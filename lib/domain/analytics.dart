// Cálculos de adesão e estoque (Dart puro).

import '../core/formatters.dart';
import 'schedule_engine.dart';

class AdherenceStats {
  final int scheduled; // doses programadas no período (já vencidas)
  final int taken;
  final int skipped; // confirmadas como não tomadas
  final int missed; // sem registro após o prazo
  final int snoozedOrLate; // ainda em aberto
  final int cancelled;
  final int upcoming; // ainda não chegaram

  const AdherenceStats({
    required this.scheduled,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.snoozedOrLate,
    required this.cancelled,
    required this.upcoming,
  });

  /// Percentual de doses registradas como tomadas sobre as que já venceram
  /// (exclui canceladas e futuras). Nulo quando não há base de cálculo.
  double? get adherence {
    final base = taken + skipped + missed + snoozedOrLate;
    if (base == 0) return null;
    return taken / base;
  }

  static AdherenceStats from(Iterable<DoseView> doses) {
    var taken = 0, skipped = 0, missed = 0, open = 0, cancelled = 0, upcoming = 0;
    for (final d in doses) {
      switch (d.status) {
        case DoseStatus.taken:
          taken++;
        case DoseStatus.skipped:
          skipped++;
        case DoseStatus.missed:
          missed++;
        case DoseStatus.late:
        case DoseStatus.snoozed:
          open++;
        case DoseStatus.cancelled:
          cancelled++;
        case DoseStatus.pending:
        case DoseStatus.next:
          upcoming++;
      }
    }
    return AdherenceStats(
      scheduled: taken + skipped + missed + open + cancelled,
      taken: taken,
      skipped: skipped,
      missed: missed,
      snoozedOrLate: open,
      cancelled: cancelled,
      upcoming: upcoming,
    );
  }
}

/// Resumo de um dia para o calendário.
enum DayMark { none, allTaken, partial, missed, future }

DayMark markForDay(List<DoseView> doses, DateTime day, DateTime now) {
  if (doses.isEmpty) return DayMark.none;
  final hasMissed = doses.any((d) => d.status == DoseStatus.missed || d.status == DoseStatus.skipped);
  final allTaken = doses.every((d) => d.status == DoseStatus.taken || d.status == DoseStatus.cancelled);
  if (allTaken) return DayMark.allTaken;
  if (hasMissed) return DayMark.missed;
  if (dayOnly(day).isAfter(dayOnly(now))) return DayMark.future;
  return DayMark.partial;
}

class StockEstimate {
  final double? daysLeft; // nulo: sem consumo programado
  final DateTime? runOutDate;
  const StockEstimate(this.daysLeft, this.runOutDate);

  static StockEstimate compute({
    required double stockQty,
    required double doseQty,
    required double dosesPerDay,
    required DateTime now,
  }) {
    final perDay = doseQty * dosesPerDay;
    if (perDay <= 0) return const StockEstimate(null, null);
    final days = stockQty <= 0 ? 0.0 : stockQty / perDay;
    return StockEstimate(days, now.add(Duration(minutes: (days * 24 * 60).floor())));
  }
}
