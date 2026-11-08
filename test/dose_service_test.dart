import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meu_remedio/data/database.dart';
import 'package:meu_remedio/data/models.dart';
import 'package:meu_remedio/domain/analytics.dart';
import 'package:meu_remedio/domain/schedule_engine.dart';
import 'package:meu_remedio/services/dose_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<AppDatabase> memoryDb() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: (d, v) => AppDatabase.createSchema(d),
    ),
  );
  return AppDatabase.forTesting(db);
}

void main() {
  late AppDatabase db;
  late int pid;
  late int medId;
  final t = DateTime(2026, 11, 5, 8);

  setUpAll(() => initializeDateFormatting('pt_BR'));

  setUp(() async {
    db = await memoryDb();
    pid = await db.insertProfile(const Profile(name: 'Teste'));
    medId = await db.insertMedication(
      Medication(profileId: pid, name: 'Losartana', strength: '50 mg', stockEnabled: true, stockQty: 10, stockMin: 9),
      const Schedule(medicationId: 0, times: ['08:00', '20:00'], startDate: '2026-11-01', effectiveFrom: '2026-11-01T00:00'),
    );
  });

  tearDown(() => db.db.close());

  test('confirmar desconta estoque e alerta estoque baixo', () async {
    final (res, alert) = await DoseService.confirmTaken(db, medId, t, source: 'notificacao');
    expect(res, ConfirmResult.ok);
    expect((await db.medication(medId))!.stockQty, 9);
    expect(alert, isNotNull);
  });

  test('confirmação por dois caminhos não duplica registro nem estoque', () async {
    await DoseService.confirmTaken(db, medId, t, source: 'notificacao');
    final (res, _) = await DoseService.confirmTaken(db, medId, t, source: 'aplicativo');
    expect(res, ConfirmResult.alreadyTaken);
    final recs = await db.recordsForMed(medId);
    expect(recs, hasLength(1));
    expect(recs.single.source, 'notificacao');
    expect((await db.medication(medId))!.stockQty, 9);
  });

  test('desfazer devolve o estoque', () async {
    await DoseService.confirmTaken(db, medId, t);
    await DoseService.undo(db, medId, t);
    expect(await db.recordsForMed(medId), isEmpty);
    expect((await db.medication(medId))!.stockQty, 10);
  });

  test('adiar não consome estoque e mantém dose em aberto', () async {
    await DoseService.snooze(db, medId, t, 10);
    final r = (await db.recordsForMed(medId)).single;
    expect(r.status, RecordStatus.snoozed);
    expect((await db.medication(medId))!.stockQty, 10);
  });

  test('alterar horários preserva histórico e encerra a regra anterior', () async {
    await DoseService.confirmTaken(db, medId, t);
    final med = (await db.medication(medId))!;
    await db.updateMedication(
      med,
      const Schedule(medicationId: 0, times: ['09:00'], startDate: '2026-11-01', effectiveFrom: '2026-11-01T00:00'),
    );
    final scheds = await db.schedulesFor(medId);
    expect(scheds, hasLength(2));
    expect(scheds.first.effectiveTo, isNotNull);
    expect(scheds.last.effectiveTo, isNull);
    expect(await db.recordsForMed(medId), hasLength(1));
  });

  test('pausar e retomar', () async {
    await db.setMedicationStatus(medId, MedStatus.paused);
    var s = await db.schedulesFor(medId);
    expect(s.every((x) => x.effectiveTo != null), isTrue);
    await db.setMedicationStatus(medId, MedStatus.active);
    s = await db.schedulesFor(medId);
    expect(s.last.effectiveTo, isNull);
  });

  test('adesão distingue não registrada de não tomada', () {
    final med = Medication(profileId: 1, name: 'X', id: 1);
    DoseView v(DoseStatus s) => DoseView(med: med, scheduledAt: t, record: null, status: s);
    final st = AdherenceStats.from([v(DoseStatus.taken), v(DoseStatus.taken), v(DoseStatus.skipped), v(DoseStatus.missed), v(DoseStatus.pending)]);
    expect(st.taken, 2);
    expect(st.skipped, 1);
    expect(st.missed, 1);
    expect(st.upcoming, 1);
    expect(st.adherence, 0.5);
  });

  test('backup e restauração', () async {
    await DoseService.confirmTaken(db, medId, t);
    final dump = await db.exportAll();
    await db.wipeAll();
    expect(await db.profiles(), isEmpty);
    await db.importAll(dump);
    expect(await db.profiles(), hasLength(1));
    expect(await db.recordsForMed(medId), hasLength(1));
  });

  test('uso eventual respeita apenas os limites informados', () {
    final med = Medication(profileId: 1, name: 'Dipirona', id: 2, isPrn: true, prnMinIntervalHours: 6, prnMaxPerDay: 2);
    final now = DateTime(2026, 11, 5, 12);
    DoseRecord use(String at) => DoseRecord(
        profileId: 1, medicationId: 2, medName: 'D', doseDesc: '1', scheduledAt: at, status: RecordStatus.taken, actionAt: at);
    final c = PrnCheck.evaluate(med, [use('2026-11-05T02:00'), use('2026-11-05T09:00')], now);
    expect(c.usesLast24h, 2);
    expect(c.intervalExceeded, isTrue);
    expect(c.maxReached, isTrue);
  });
}
