// Motor de horários: gera as doses programadas a partir das regras
// cadastradas pelo usuário. Código Dart puro (testável sem Flutter).
//
// Toda a aritmética é feita em "horário de parede" usando DateTime.utc como
// relógio neutro, para que mudanças de horário de verão/fuso não desloquem os
// horários configurados (08:00 continua 08:00).

import '../core/formatters.dart';
import '../data/models.dart';

DateTime _wall(int y, int mo, int d, [int h = 0, int mi = 0]) => DateTime.utc(y, mo, d, h, mi);
DateTime _toLocal(DateTime w) => DateTime(w.year, w.month, w.day, w.hour, w.minute);
DateTime _fromLocal(DateTime l) => DateTime.utc(l.year, l.month, l.day, l.hour, l.minute);

class ScheduleEngine {
  /// Horários (locais) de uma regra num dia específico.
  static List<DateTime> occurrencesOnDay(Schedule s, DateTime day) {
    final d = _wall(day.year, day.month, day.day);
    final start = _fromLocal(parseDateKey(s.startDate));
    if (d.isBefore(start)) return const [];
    if (s.endDate != null && d.isAfter(_fromLocal(parseDateKey(s.endDate!)))) return const [];

    final out = <DateTime>[];
    if (s.kind == ScheduleKind.fixed) {
      if (!_dayMatches(s, d, start)) return const [];
      final times = [...s.times]..sort();
      for (final t in times) {
        final (h, m) = parseHm(t);
        out.add(_wall(d.year, d.month, d.day, h, m));
      }
    } else {
      // Intervalo contínuo a partir do primeiro horário do dia de início.
      final stepMin = (s.intervalHours * 60).round();
      if (stepMin <= 0) return const [];
      final (h0, m0) = parseHm(s.intervalStart);
      final origin = _wall(start.year, start.month, start.day, h0, m0);
      final dayStart = d;
      final dayEnd = d.add(const Duration(days: 1));
      final diff = dayStart.difference(origin).inMinutes;
      var k = diff <= 0 ? 0 : (diff / stepMin).ceil();
      while (true) {
        final t = origin.add(Duration(minutes: k * stepMin));
        if (!t.isBefore(dayEnd)) break;
        if (!t.isBefore(dayStart)) out.add(t);
        k++;
      }
    }

    final effFrom = _fromLocal(parseDtKey(s.effectiveFrom));
    final effTo = s.effectiveTo == null ? null : _fromLocal(parseDtKey(s.effectiveTo!));
    return out
        .where((t) => !t.isBefore(effFrom) && (effTo == null || t.isBefore(effTo)))
        .map(_toLocal)
        .toList();
  }

  static bool _dayMatches(Schedule s, DateTime d, DateTime start) {
    switch (s.daysMode) {
      case DaysMode.daily:
        return true;
      case DaysMode.weekdays:
        return s.weekdays.contains(d.weekday);
      case DaysMode.everyN:
        final n = s.everyN < 1 ? 1 : s.everyN;
        final days = d.difference(start).inDays;
        return days % n == 0;
    }
  }

  /// Todas as ocorrências de várias regras entre [from] (inclusive) e [to]
  /// (exclusive), em ordem cronológica e sem duplicidade.
  static List<DateTime> occurrencesBetween(List<Schedule> schedules, DateTime from, DateTime to) {
    final set = <String, DateTime>{};
    var day = dayOnly(from);
    final lastDay = dayOnly(to);
    while (!day.isAfter(lastDay)) {
      for (final s in schedules) {
        for (final t in occurrencesOnDay(s, day)) {
          if (!t.isBefore(from) && t.isBefore(to)) set[dtKey(t)] = t;
        }
      }
      day = DateTime(day.year, day.month, day.day + 1);
    }
    final list = set.values.toList()..sort();
    return list;
  }

  /// Quantidade média de doses por dia nos próximos [days] dias.
  static double averageDosesPerDay(List<Schedule> schedules, DateTime from, {int days = 28}) {
    final to = DateTime(from.year, from.month, from.day + days, from.hour, from.minute);
    final n = occurrencesBetween(schedules, from, to).length;
    return n / days;
  }

  /// Descrição legível da regra.
  static String describe(Schedule s) {
    final b = StringBuffer();
    if (s.kind == ScheduleKind.fixed) {
      final times = [...s.times]..sort();
      final n = times.length;
      b.write(n == 1 ? '1 vez ao dia' : '$n vezes ao dia');
      b.write(' • ${times.join(', ')}');
      switch (s.daysMode) {
        case DaysMode.daily:
          break;
        case DaysMode.weekdays:
          final sorted = [...s.weekdays]..sort();
          if (sorted.length == 7) break;
          b.write(' • ${sorted.map((w) => weekdayNames[w - 1].substring(0, 3)).join(', ')}');
        case DaysMode.everyN:
          b.write(s.everyN == 2 ? ' • dias alternados' : ' • a cada ${s.everyN} dias');
      }
    } else {
      b.write('A cada ${fmtQty(s.intervalHours)} h a partir das ${s.intervalStart}');
    }
    if (s.endDate != null) b.write(' • até ${fmtDate(parseDateKey(s.endDate!))}');
    return b.toString();
  }
}

/// Situação exibida para uma dose.
enum DoseStatus { pending, next, taken, snoozed, late, missed, skipped, cancelled }

const doseStatusLabels = {
  DoseStatus.pending: 'Pendente',
  DoseStatus.next: 'Próximo horário',
  DoseStatus.taken: 'Tomado',
  DoseStatus.snoozed: 'Adiado',
  DoseStatus.late: 'Atrasado',
  DoseStatus.missed: 'Não registrado',
  DoseStatus.skipped: 'Não tomado',
  DoseStatus.cancelled: 'Cancelado',
};

class StatusRules {
  /// Minutos após o horário em que a dose passa a ser "Atrasada".
  final int lateAfterMin;

  /// Minutos após o horário em que a dose sem resposta vira "Não registrada".
  final int missedAfterMin;

  const StatusRules({this.lateAfterMin = 15, this.missedAfterMin = 240});

  /// Deriva a situação. Nunca transforma dose pendente em tomada.
  DoseStatus derive(DateTime scheduled, DoseRecord? record, DateTime now) {
    if (record != null) {
      switch (record.status) {
        case RecordStatus.taken:
          return DoseStatus.taken;
        case RecordStatus.skipped:
          return DoseStatus.skipped;
        case RecordStatus.cancelled:
          return DoseStatus.cancelled;
        case RecordStatus.snoozed:
          final until = record.snoozedUntil == null ? scheduled : parseDtKey(record.snoozedUntil!);
          if (now.isBefore(until)) return DoseStatus.snoozed;
          if (now.isBefore(until.add(Duration(minutes: missedAfterMin)))) return DoseStatus.late;
          return DoseStatus.missed;
      }
    }
    if (now.isBefore(scheduled.add(Duration(minutes: lateAfterMin)))) return DoseStatus.pending;
    if (now.isBefore(scheduled.add(Duration(minutes: missedAfterMin)))) return DoseStatus.late;
    return DoseStatus.missed;
  }
}

/// Uma dose programada (ou registrada) já combinada com seu registro.
class DoseView {
  final Medication med;
  final DateTime scheduledAt;
  final DoseRecord? record;
  DoseStatus status;

  DoseView({required this.med, required this.scheduledAt, required this.record, required this.status});

  String get key => '${med.id}|${dtKey(scheduledAt)}';
  bool get isOpen => status == DoseStatus.pending || status == DoseStatus.next || status == DoseStatus.late || status == DoseStatus.snoozed || status == DoseStatus.missed;
}
