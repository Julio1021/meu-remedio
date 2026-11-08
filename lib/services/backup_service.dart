import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../data/database.dart';
import '../data/models.dart';

/// Backup e restauração em arquivo JSON local (sem nuvem obrigatória).
class BackupService {
  static Future<File> createBackupFile(AppDatabase db) async {
    final data = await db.exportAll();
    final dir = await getApplicationDocumentsDirectory();
    final stamp = dtKey(DateTime.now()).replaceAll(RegExp('[-:T]'), '');
    final f = File('${dir.path}/backup_meu_remedio_$stamp.json');
    await f.writeAsString(const JsonEncoder.withIndent(' ').convert(data));
    return f;
  }

  static Future<void> shareBackup(AppDatabase db) async {
    final f = await createBackupFile(db);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(f.path, mimeType: 'application/json')],
      text: 'Backup do Meu Remédio. Guarde em local seguro: contém dados de saúde.',
    ));
  }

  /// Retorna false se o usuário cancelou a seleção.
  static Future<bool> pickAndRestore(AppDatabase db) async {
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return false;
    final bytes = await file.readAsBytes();
    final data = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    await db.importAll(data);
    return true;
  }
}

/// Dados fictícios para demonstração inicial. Ficam num perfil próprio
/// ("Demonstração") e podem ser removidos com um toque.
class DemoData {
  static const profileName = 'Demonstração';

  static Future<int> create(AppDatabase db) async {
    final pid = await db.insertProfile(const Profile(name: profileName, relation: 'Familiar', color: 0xFF3A6EA5));
    final today = DateTime.now();
    final start = dateKey(DateTime(today.year, today.month, today.day - 10));
    final eff = '${start}T00:00';

    final losartana = await db.insertMedication(
      Medication(
        profileId: pid,
        name: 'Losartana',
        strength: '50 mg',
        form: 'Comprimido',
        doseQty: 1,
        doseUnit: 'comprimido(s)',
        instructions: 'Exemplo: conforme orientação do seu médico.',
        color: 0xFF0F6E6E,
        stockEnabled: true,
        stockQty: 24,
        stockUnit: 'comprimido(s)',
        stockMin: 7,
      ),
      Schedule(medicationId: 0, times: const ['08:00', '20:00'], startDate: start, effectiveFrom: eff),
    );
    await db.insertMedication(
      Medication(
        profileId: pid,
        name: 'Vitamina D',
        strength: '2.000 UI',
        form: 'Gotas',
        doseQty: 4,
        doseUnit: 'gota(s)',
        color: 0xFFE0A030,
      ),
      Schedule(medicationId: 0, times: const ['12:30'], startDate: start, effectiveFrom: eff),
    );
    await db.insertMedication(
      Medication(
        profileId: pid,
        name: 'Antibiótico (exemplo)',
        form: 'Cápsula',
        doseQty: 1,
        doseUnit: 'cápsula(s)',
        color: 0xFF7A5BA6,
        stockEnabled: true,
        stockQty: 6,
        stockUnit: 'cápsula(s)',
        stockMin: 2,
      ),
      Schedule(
        medicationId: 0,
        kind: ScheduleKind.interval,
        intervalHours: 8,
        intervalStart: '07:00',
        startDate: dateKey(DateTime(today.year, today.month, today.day - 2)),
        endDate: dateKey(DateTime(today.year, today.month, today.day + 4)),
        effectiveFrom: '${dateKey(DateTime(today.year, today.month, today.day - 2))}T00:00',
      ),
    );
    await db.insertMedication(
      Medication(
        profileId: pid,
        name: 'Analgésico (exemplo)',
        form: 'Comprimido',
        doseQty: 1,
        isPrn: true,
        prnMinIntervalHours: 6,
        prnMaxPerDay: 4,
        instructions: 'Exemplo: somente se houver dor, conforme orientação profissional.',
        color: 0xFFB55A4A,
      ),
      null,
    );

    // Alguns registros passados para ilustrar histórico e relatórios.
    final b = db.db.batch();
    for (var i = 1; i <= 9; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      for (final t in const ['08:00', '20:00']) {
        final (h, m) = parseHm(t);
        final sched = DateTime(d.year, d.month, d.day, h, m);
        if (i == 3 && t == '20:00') continue; // fica "não registrada"
        b.insert('dose_records', {
          'profile_id': pid,
          'medication_id': losartana,
          'med_name': 'Losartana 50 mg',
          'dose_desc': '1 comprimido(s)',
          'scheduled_at': dtKey(sched),
          'status': (i == 5 && t == '08:00') ? 'skipped' : 'taken',
          'action_at': dtKey(sched.add(Duration(minutes: 3 + i))),
          'source': i.isEven ? 'notificacao' : 'aplicativo',
        });
      }
    }
    await b.commit(noResult: true);
    return pid;
  }

  static Future<void> remove(AppDatabase db) async {
    await db.db.delete('profiles', where: 'name = ?', whereArgs: [profileName]);
  }
}
