import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/analytics.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'reports_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Histórico'),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
                icon: const Icon(Icons.bar_chart_rounded),
                label: const Text('Relatórios'),
              ),
            ],
            bottom: const TabBar(tabs: [Tab(text: 'Calendário'), Tab(text: 'Registros')]),
          ),
          body: const TabBarView(children: [CalendarView(), RecordsView()]),
        ),
      );
}

// --------------------------------------------------------------- calendário
class CalendarView extends StatefulWidget {
  const CalendarView({super.key});

  @override
  State<CalendarView> createState() => _CalendarViewState();
}

class _CalendarViewState extends State<CalendarView> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selected = dayOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final first = _month;
    final next = DateTime(_month.year, _month.month + 1);
    final future = app.dosesBetween(first, next);
    final now = DateTime.now();
    final mn = DateFormat('MMMM', 'pt_BR').format(first);
    final monthName = mn[0].toUpperCase() + mn.substring(1);

    return FutureBuilder<List<DoseView>>(
      future: future,
      builder: (c, snap) {
        final doses = snap.data ?? const <DoseView>[];
        final byDay = <DateTime, List<DoseView>>{};
        for (final d in doses) {
          byDay.putIfAbsent(dayOnly(d.scheduledAt), () => []).add(d);
        }
        final lead = first.weekday - 1; // semana começa na segunda
        final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
        final cells = lead + daysInMonth;
        final rows = (cells / 7).ceil();
        final sel = _selected;
        final selDoses = sel == null ? const <DoseView>[] : (byDay[sel] ?? const <DoseView>[]);

        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
          Row(children: [
            IconButton(
              tooltip: 'Mês anterior',
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text('$monthName ${first.year}',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
            IconButton(
              tooltip: 'Próximo mês',
              onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final l in weekdayLetters)
              Expanded(child: Center(child: Text(l, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)))),
          ]),
          const SizedBox(height: 6),
          for (var r = 0; r < rows; r++)
            Row(children: [
              for (var col = 0; col < 7; col++)
                Expanded(child: _cell(context, r * 7 + col - lead + 1, daysInMonth, byDay, now)),
            ]),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 6, children: const [
            _Legend(AppColors.success, 'Tudo tomado'),
            _Legend(AppColors.pending, 'Pendente/adiado'),
            _Legend(AppColors.danger, 'Não registrado / não tomado'),
            _Legend(AppColors.neutral, 'Sem doses / futuro'),
          ]),
          if (sel != null) ...[
            SectionTitle(fmtLongDate(sel)),
            if (selDoses.isEmpty)
              Text('Sem administração programada.', style: TextStyle(color: cs.onSurfaceVariant))
            else
              for (final d in selDoses) Padding(padding: const EdgeInsets.only(bottom: 8), child: DoseTile(d)),
          ],
        ]);
      },
    );
  }

  Widget _cell(BuildContext context, int day, int daysInMonth, Map<DateTime, List<DoseView>> byDay, DateTime now) {
    if (day < 1 || day > daysInMonth) return const SizedBox(height: 52);
    final cs = Theme.of(context).colorScheme;
    final d = DateTime(_month.year, _month.month, day);
    final doses = byDay[d] ?? const <DoseView>[];
    final mark = markForDay(doses, d, now);
    final color = switch (mark) {
      DayMark.allTaken => AppColors.success,
      DayMark.partial => AppColors.pending,
      DayMark.missed => AppColors.danger,
      DayMark.future || DayMark.none => AppColors.neutral,
    };
    final label = switch (mark) {
      DayMark.allTaken => 'todas tomadas',
      DayMark.partial => 'com pendências',
      DayMark.missed => 'com doses não registradas ou não tomadas',
      DayMark.future => 'doses programadas',
      DayMark.none => 'sem doses',
    };
    final sel = _selected == d;
    final isToday = d == dayOnly(now);
    return Semantics(
      button: true,
      selected: sel,
      label: '${fmtDate(d)}, $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => setState(() => _selected = d),
        child: Container(
          height: 52,
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: sel ? cs.primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(14),
            border: isToday ? Border.all(color: cs.primary, width: 1.5) : null,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$day', style: TextStyle(fontWeight: isToday ? FontWeight.w800 : FontWeight.w500)),
            const SizedBox(height: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: mark == DayMark.none ? Colors.transparent : color,
                shape: BoxShape.circle,
                border: mark == DayMark.future ? Border.all(color: color) : null,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final Color c;
  final String t;
  const _Legend(this.c, this.t);

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12)),
      ]);
}

// ---------------------------------------------------------------- registros
enum Period { today, yesterday, week, month, custom }

const periodLabels = {
  Period.today: 'Hoje',
  Period.yesterday: 'Ontem',
  Period.week: '7 dias',
  Period.month: '30 dias',
  Period.custom: 'Personalizado',
};

(DateTime, DateTime) periodRange(Period p, DateTimeRange? custom) {
  final t = dayOnly(DateTime.now());
  final tomorrow = DateTime(t.year, t.month, t.day + 1);
  return switch (p) {
    Period.today => (t, tomorrow),
    Period.yesterday => (DateTime(t.year, t.month, t.day - 1), t),
    Period.week => (DateTime(t.year, t.month, t.day - 6), tomorrow),
    Period.month => (DateTime(t.year, t.month, t.day - 29), tomorrow),
    Period.custom => custom == null
        ? (t, tomorrow)
        : (dayOnly(custom.start), DateTime(custom.end.year, custom.end.month, custom.end.day + 1)),
  };
}

class RecordsView extends StatefulWidget {
  const RecordsView({super.key});

  @override
  State<RecordsView> createState() => _RecordsViewState();
}

class _RecordsViewState extends State<RecordsView> {
  Period _p = Period.week;
  DateTimeRange? _custom;
  DoseStatus? _status;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final (from, to) = periodRange(_p, _custom);
    final now = DateTime.now();
    final effectiveTo = to.isAfter(now) ? now.add(const Duration(minutes: 1)) : to;
    return FutureBuilder<List<DoseView>>(
      future: app.dosesBetween(from, effectiveTo, includePrn: true),
      builder: (c, snap) {
        final all = (snap.data ?? const <DoseView>[]).reversed.toList();
        final list = _status == null ? all : all.where((d) => d.status == _status).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 40), children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in Period.values)
              ChoiceChip(
                label: Text(p == Period.custom && _custom != null && _p == Period.custom
                    ? '${fmtDate(_custom!.start).substring(0, 5)}–${fmtDate(_custom!.end).substring(0, 5)}'
                    : periodLabels[p]!),
                selected: _p == p,
                onSelected: (_) async {
                  if (p == Period.custom) {
                    final r = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2000),
                      lastDate: DateTime.now(),
                      initialDateRange: _custom,
                    );
                    if (r == null) return;
                    _custom = r;
                  }
                  setState(() => _p = p);
                },
              ),
          ]),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              FilterChip(label: const Text('Todas'), selected: _status == null, onSelected: (_) => setState(() => _status = null)),
              for (final s in [DoseStatus.taken, DoseStatus.snoozed, DoseStatus.late, DoseStatus.missed, DoseStatus.skipped, DoseStatus.cancelled])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: FilterChip(
                    label: Text(doseStatusLabels[s]!),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (list.isEmpty)
            const EmptyState(icon: Icons.history_rounded, title: 'Sem registros', message: 'Não há doses neste período com o filtro escolhido.')
          else
            for (final d in list) Padding(padding: const EdgeInsets.only(bottom: 8), child: DoseTile(d, showDate: true)),
        ]);
      },
    );
  }
}
