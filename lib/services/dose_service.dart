import 'package:sqflite/sqflite.dart';

import '../core/formatters.dart';
import '../data/database.dart';
import '../data/models.dart';

enum ConfirmResult { ok, alreadyTaken, notFound }

class StockAlert {
  final Medication med;
  final double balance;
  final bool empty;
  const StockAlert(this.med, this.balance, this.empty);
}

/// Regras de registro de doses. Toda escrita ocorre numa transação e usa a
/// chave única (medicamento, horário programado), evitando registros
/// duplicados quando a dose é confirmada por caminhos diferentes
/// (notificação, tela inicial, agenda...).
class DoseService {
  static Future<DoseRecord?> _get(DatabaseExecutor ex, int medId, String key) async {
    final r = await ex.query('dose_records', where: 'medication_id = ? AND scheduled_at = ?', whereArgs: [medId, key]);
    return r.isEmpty ? null : DoseRecord.fromMap(r.first);
  }

  static Future<void> _upsert(DatabaseExecutor ex, DoseRecord? existing, DoseRecord rec) async {
    if (existing == null) {
      await ex.insert('dose_records', rec.toMap()..remove('id'));
    } else {
      await ex.update('dose_records', rec.toMap()..remove('id'), where: 'id = ?', whereArgs: [existing.id]);
    }
  }

  /// Registra a dose como tomada e desconta o estoque (se ativado).
  static Future<(ConfirmResult, StockAlert?)> confirmTaken(
    AppDatabase db,
    int medId,
    DateTime scheduledAt, {
    String source = 'aplicativo',
    DateTime? takenAt,
  }) async {
    return db.db.transaction((txn) async {
      final mr = await txn.query('medications', where: 'id = ?', whereArgs: [medId]);
      if (mr.isEmpty) return (ConfirmResult.notFound, null);
      final med = Medication.fromMap(mr.first);
      final key = dtKey(scheduledAt);
      final existing = await _get(txn, medId, key);
      if (existing?.status == RecordStatus.taken) return (ConfirmResult.alreadyTaken, null);

      await _upsert(
        txn,
        existing,
        DoseRecord(
          profileId: med.profileId,
          medicationId: medId,
          medName: med.displayName,
          doseDesc: med.doseDescription,
          scheduledAt: key,
          status: RecordStatus.taken,
          actionAt: dtKey(takenAt ?? DateTime.now()),
          source: source,
        ),
      );

      StockAlert? alert;
      if (med.stockEnabled) {
        final bal = await AppDatabase.applyStock(txn, medId, StockMoveType.dose, -med.doseQty,
            note: 'Dose de ${fmtDateTime(scheduledAt)}');
        if (bal <= 0) {
          alert = StockAlert(med, bal, true);
        } else if (med.stockMin > 0 && bal <= med.stockMin) {
          alert = StockAlert(med, bal, false);
        }
      }
      return (ConfirmResult.ok, alert);
    });
  }

  /// Marca como não tomada (confirmação explícita do usuário).
  static Future<void> markSkipped(AppDatabase db, int medId, DateTime scheduledAt, {String? note}) =>
      _setStatus(db, medId, scheduledAt, RecordStatus.skipped, note: note);

  static Future<void> markCancelled(AppDatabase db, int medId, DateTime scheduledAt) =>
      _setStatus(db, medId, scheduledAt, RecordStatus.cancelled);

  /// Adia a dose. Ela continua pendente — nunca vira "tomada" sozinha.
  static Future<DateTime> snooze(AppDatabase db, int medId, DateTime scheduledAt, int minutes,
      {String source = 'aplicativo'}) async {
    final until = DateTime.now().add(Duration(minutes: minutes));
    await _setStatus(db, medId, scheduledAt, RecordStatus.snoozed, snoozedUntil: until, source: source);
    return until;
  }

  static Future<void> _setStatus(AppDatabase db, int medId, DateTime scheduledAt, RecordStatus status,
      {DateTime? snoozedUntil, String source = 'aplicativo', String? note}) async {
    await db.db.transaction((txn) async {
      final mr = await txn.query('medications', where: 'id = ?', whereArgs: [medId]);
      if (mr.isEmpty) return;
      final med = Medication.fromMap(mr.first);
      final key = dtKey(scheduledAt);
      final existing = await _get(txn, medId, key);
      if (existing?.status == RecordStatus.taken && med.stockEnabled) {
        await AppDatabase.applyStock(txn, medId, StockMoveType.doseUndo, med.doseQty, note: 'Registro alterado');
      }
      await _upsert(
        txn,
        existing,
        DoseRecord(
          profileId: med.profileId,
          medicationId: medId,
          medName: med.displayName,
          doseDesc: med.doseDescription,
          scheduledAt: key,
          status: status,
          actionAt: AppDatabase.nowKey(),
          snoozedUntil: snoozedUntil == null ? null : dtKey(snoozedUntil),
          source: source,
          note: note,
        ),
      );
    });
  }

  /// Desfaz qualquer registro da dose, devolvendo o estoque se necessário.
  static Future<void> undo(AppDatabase db, int medId, DateTime scheduledAt) async {
    await db.db.transaction((txn) async {
      final key = dtKey(scheduledAt);
      final existing = await _get(txn, medId, key);
      if (existing == null) return;
      final mr = await txn.query('medications', where: 'id = ?', whereArgs: [medId]);
      if (mr.isNotEmpty) {
        final med = Medication.fromMap(mr.first);
        if (existing.status == RecordStatus.taken && med.stockEnabled) {
          await AppDatabase.applyStock(txn, medId, StockMoveType.doseUndo, med.doseQty, note: 'Registro desfeito');
        }
      }
      await txn.delete('dose_records', where: 'id = ?', whereArgs: [existing.id]);
    });
  }

  /// Registra uma utilização de medicamento de uso eventual.
  static Future<(ConfirmResult, StockAlert?)> logPrnUse(AppDatabase db, int medId, DateTime at) async {
    var t = DateTime(at.year, at.month, at.day, at.hour, at.minute);
    // Garante horário único (precisão de minuto).
    for (var i = 0; i < 60; i++) {
      final ex = await _get(db.db, medId, dtKey(t));
      if (ex == null) break;
      t = t.add(const Duration(minutes: 1));
    }
    return confirmTaken(db, medId, t, source: 'eventual', takenAt: at);
  }
}

/// Avaliação dos parâmetros informados pelo usuário para uso eventual.
/// O aplicativo apenas informa; não autoriza nem recomenda doses.
class PrnCheck {
  final int usesLast24h;
  final DateTime? lastUse;
  final DateTime? nextAllowedByInterval;
  final bool intervalExceeded;
  final bool maxReached;

  const PrnCheck({
    required this.usesLast24h,
    required this.lastUse,
    required this.nextAllowedByInterval,
    required this.intervalExceeded,
    required this.maxReached,
  });

  static PrnCheck evaluate(Medication med, List<DoseRecord> uses, DateTime now) {
    final taken = uses.where((u) => u.status == RecordStatus.taken).map((u) => parseDtKey(u.actionAt)).toList()..sort();
    final last = taken.isEmpty ? null : taken.last;
    final dayAgo = now.subtract(const Duration(hours: 24));
    final count = taken.where((t) => t.isAfter(dayAgo)).length;
    DateTime? next;
    var intervalHit = false;
    if (last != null && med.prnMinIntervalHours != null && med.prnMinIntervalHours! > 0) {
      next = last.add(Duration(minutes: (med.prnMinIntervalHours! * 60).round()));
      intervalHit = now.isBefore(next);
    }
    final maxHit = med.prnMaxPerDay != null && med.prnMaxPerDay! > 0 && count >= med.prnMaxPerDay!;
    return PrnCheck(
      usesLast24h: count,
      lastUse: last,
      nextAllowedByInterval: next,
      intervalExceeded: intervalHit,
      maxReached: maxHit,
    );
  }
}
