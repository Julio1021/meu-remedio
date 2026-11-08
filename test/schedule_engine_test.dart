import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meu_remedio/core/formatters.dart';
import 'package:meu_remedio/data/models.dart';
import 'package:meu_remedio/domain/analytics.dart';
import 'package:meu_remedio/domain/schedule_engine.dart';

Schedule fixed(List<String> times,
        {DaysMode mode = DaysMode.daily, List<int> weekdays = const [1, 2, 3, 4, 5, 6, 7], int everyN = 2, String start = '2026-11-02', String? end, String eff = '2026-11-02T00:00', String? effTo}) =>
    Schedule(
      medicationId: 1,
      times: times,
      daysMode: mode,
      weekdays: weekdays,
      everyN: everyN,
      startDate: start,
      endDate: end,
      effectiveFrom: eff,
      effectiveTo: effTo,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  group('Horários fixos', () {
    test('gera horários ordenados no dia', () {
      final s = fixed(['20:00', '08:00', '13:00']);
      final r = ScheduleEngine.occurrencesOnDay(s, DateTime(2026, 11, 5));
      expect(r.map(fmtTime), ['08:00', '13:00', '20:00']);
    });

    test('respeita data de início e término (inclusive)', () {
      final s = fixed(['08:00'], end: '2026-11-04');
      expect(ScheduleEngine.occurrencesOnDay(s, DateTime(2026, 11, 1)), isEmpty);
      expect(ScheduleEngine.occurrencesOnDay(s, DateTime(2026, 11, 4)), hasLength(1));
      expect(ScheduleEngine.occurrencesOnDay(s, DateTime(2026, 11, 5)), isEmpty);
    });

    test('dias específicos da semana', () {
      // 02/11/2026 é segunda-feira.
      final s = fixed(['09:00'], mode: DaysMode.weekdays, weekdays: [1, 3, 5]);
      final days = ScheduleEngine.occurrencesBetween([s], DateTime(2026, 11, 2), DateTime(2026, 11, 9));
      expect(days.map((d) => d.weekday), [1, 3, 5]);
    });

    test('dias alternados contam a partir do início', () {
      final s = fixed(['09:00'], mode: DaysMode.everyN, everyN: 2);
      final r = ScheduleEngine.occurrencesBetween([s], DateTime(2026, 11, 2), DateTime(2026, 11, 8));
      expect(r.map((d) => d.day), [2, 4, 6]);
    });

    test('vigência: regra antiga e nova não se sobrepõem', () {
      final old = fixed(['08:00', '20:00'], effTo: '2026-11-05T12:00');
      final neu = fixed(['09:00', '21:00'], eff: '2026-11-05T12:00');
      final r = ScheduleEngine.occurrencesOnDay(old, DateTime(2026, 11, 5)) + ScheduleEngine.occurrencesOnDay(neu, DateTime(2026, 11, 5));
      expect(r.map(fmtTime).toList()..sort(), ['08:00', '21:00']);
    });
  });

  group('Intervalos', () {
    test('a cada 8 h atravessando a meia-noite', () {
      final s = Schedule(
        medicationId: 1,
        kind: ScheduleKind.interval,
        intervalHours: 8,
        intervalStart: '22:00',
        startDate: '2026-11-02',
        effectiveFrom: '2026-11-02T00:00',
      );
      expect(ScheduleEngine.occurrencesOnDay(s, DateTime(2026, 11, 2)).map(fmtTime), ['22:00']);
      expect(ScheduleEngine.occurrencesOnDay(s, DateTime(2026, 11, 3)).map(fmtTime), ['06:00', '14:00', '22:00']);
    });

    test('a cada 36 h', () {
      final s = Schedule(
        medicationId: 1,
        kind: ScheduleKind.interval,
        intervalHours: 36,
        intervalStart: '08:00',
        startDate: '2026-11-02',
        effectiveFrom: '2026-11-02T00:00',
      );
      final r = ScheduleEngine.occurrencesBetween([s], DateTime(2026, 11, 2), DateTime(2026, 11, 6));
      expect(r.map(dtKey), ['2026-11-02T08:00', '2026-11-03T20:00', '2026-11-05T08:00']);
    });
  });

  group('Situação das doses', () {
    const rules = StatusRules(lateAfterMin: 15, missedAfterMin: 240);
    final t = DateTime(2026, 11, 5, 8);

    test('sem registro: pendente → atrasada → não registrada', () {
      expect(rules.derive(t, null, DateTime(2026, 11, 5, 7)), DoseStatus.pending);
      expect(rules.derive(t, null, DateTime(2026, 11, 5, 8, 10)), DoseStatus.pending);
      expect(rules.derive(t, null, DateTime(2026, 11, 5, 9)), DoseStatus.late);
      expect(rules.derive(t, null, DateTime(2026, 11, 5, 13)), DoseStatus.missed);
    });

    test('dose pendente nunca vira tomada sozinha', () {
      expect(rules.derive(t, null, DateTime(2026, 12, 1)), isNot(DoseStatus.taken));
    });

    test('adiada até o horário combinado', () {
      final rec = DoseRecord(
        profileId: 1,
        medicationId: 1,
        medName: 'X',
        doseDesc: '1',
        scheduledAt: dtKey(t),
        status: RecordStatus.snoozed,
        actionAt: '2026-11-05T08:01',
        snoozedUntil: '2026-11-05T08:30',
      );
      expect(rules.derive(t, rec, DateTime(2026, 11, 5, 8, 20)), DoseStatus.snoozed);
      expect(rules.derive(t, rec, DateTime(2026, 11, 5, 8, 40)), DoseStatus.late);
    });
  });

  group('Estoque', () {
    test('estimativa de duração', () {
      final e = StockEstimate.compute(stockQty: 20, doseQty: 1, dosesPerDay: 2, now: DateTime(2026, 11, 1));
      expect(e.daysLeft, 10);
      expect(dateKey(e.runOutDate!), '2026-11-11');
    });

    test('sem consumo programado', () {
      expect(StockEstimate.compute(stockQty: 5, doseQty: 1, dosesPerDay: 0, now: DateTime.now()).daysLeft, isNull);
    });

    test('média de doses por dia', () {
      final s = fixed(['08:00', '20:00'], start: '2026-01-01', eff: '2026-01-01T00:00');
      expect(ScheduleEngine.averageDosesPerDay([s], DateTime(2026, 11, 1)), 2);
    });
  });
}
