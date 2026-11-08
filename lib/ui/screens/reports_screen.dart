import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/analytics.dart';
import '../../domain/schedule_engine.dart';
import '../../services/report_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'history_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  Period _p = Period.month;
  DateTimeRange? _custom;
  bool _exporting = false;

  Future<List<DoseView>> _load(AppState app) async {
    final (from, to) = periodRange(_p, _custom);
    final now = DateTime.now();
    final end = to.isAfter(now) ? now.add(const Duration(minutes: 1)) : to;
    return app.dosesBetween(from, end);
  }

  Future<void> _export(bool pdf) async {
    final app = context.read<AppState>();
    setState(() => _exporting = true);
    try {
      final (from, to) = periodRange(_p, _custom);
      final doses = await _load(app);
      final f = pdf
          ? await ReportService.adherencePdf(profile: app.activeProfile!, doses: doses, from: from, to: to)
          : await ReportService.dosesCsv(app.activeProfile!, doses, from, to);
      await ReportService.share(f, 'Relatório de doses — ${app.activeProfile!.name}');
    } catch (e) {
      if (mounted) showSnack(context, 'Não foi possível gerar o relatório: $e');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Relatórios')),
      body: FutureBuilder<List<DoseView>>(
        future: _load(app),
        builder: (c, snap) {
          final doses = snap.data ?? const <DoseView>[];
          final st = AdherenceStats.from(doses);
          final byMed = <String, List<DoseView>>{};
          for (final d in doses) {
            byMed.putIfAbsent(d.record?.medName ?? d.med.displayName, () => []).add(d);
          }
          // Evolução semanal (últimas 4-5 semanas do período).
          final weeks = <DateTime, List<DoseView>>{};
          for (final d in doses) {
            final day = dayOnly(d.scheduledAt);
            final monday = DateTime(day.year, day.month, day.day - (day.weekday - 1));
            weeks.putIfAbsent(monday, () => []).add(d);
          }
          final weekKeys = weeks.keys.toList()..sort();
          // Dias da semana com mais pendências.
          final pendByWeekday = List<int>.filled(7, 0);
          for (final d in doses) {
            if (d.status == DoseStatus.missed || d.status == DoseStatus.skipped) pendByWeekday[d.scheduledAt.weekday - 1]++;
          }
          final maxPend = pendByWeekday.reduce((a, b) => a > b ? a : b);

          return ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in Period.values.where((p) => p != Period.today && p != Period.yesterday))
                ChoiceChip(
                  label: Text(periodLabels[p]!),
                  selected: _p == p,
                  onSelected: (_) async {
                    if (p == Period.custom) {
                      final r = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime.now());
                      if (r == null) return;
                      _custom = r;
                    }
                    setState(() => _p = p);
                  },
                ),
            ]),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  SizedBox(
                    width: 96,
                    height: 96,
                    child: Stack(fit: StackFit.expand, children: [
                      CircularProgressIndicator(
                        value: st.adherence ?? 0,
                        strokeWidth: 10,
                        backgroundColor: cs.outlineVariant.withValues(alpha: 0.4),
                        color: AppColors.success,
                      ),
                      Center(
                        child: Text(st.adherence == null ? '–' : '${(st.adherence! * 100).round()}%',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Doses registradas como tomadas', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('${st.taken} de ${st.taken + st.skipped + st.missed + st.snoozedOrLate} doses já vencidas',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.6,
              children: [
                StatCard(label: 'Programadas', value: '${st.scheduled}', color: AppColors.info, icon: Icons.event_note_rounded),
                StatCard(label: 'Confirmadas', value: '${st.taken}', color: AppColors.success, icon: Icons.check_circle_rounded),
                StatCard(label: 'Não tomadas (confirmado)', value: '${st.skipped}', color: AppColors.danger, icon: Icons.do_not_disturb_on_outlined),
                StatCard(label: 'Não registradas', value: '${st.missed}', color: AppColors.pending, icon: Icons.help_outline_rounded),
              ],
            ),
            const SizedBox(height: 8),
            Text('"Não registrada" é uma dose sem resposta ao lembrete; "não tomada" foi confirmada por você.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            if (weekKeys.isNotEmpty) ...[
              const SectionTitle('Evolução semanal'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (final w in weekKeys)
                      _Bar(
                        label: 'Sem. ${fmtDate(w).substring(0, 5)}',
                        value: AdherenceStats.from(weeks[w]!).adherence,
                      ),
                  ]),
                ),
              ),
            ],
            if (maxPend > 0) ...[
              const SectionTitle('Dias com mais pendências'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    for (var i = 0; i < 7; i++)
                      _Bar(
                        label: weekdayNames[i],
                        value: pendByWeekday[i] / maxPend,
                        text: '${pendByWeekday[i]}',
                        color: AppColors.pending,
                      ),
                  ]),
                ),
              ),
            ],
            if (byMed.isNotEmpty) ...[
              const SectionTitle('Por medicamento'),
              Card(
                child: Column(children: [
                  for (final e in byMed.entries)
                    () {
                      final s = AdherenceStats.from(e.value);
                      return ListTile(
                        title: Text(e.key),
                        subtitle: Text('${s.taken} tomadas • ${s.skipped} não tomadas • ${s.missed} não registradas'),
                        trailing: Text(s.adherence == null ? '–' : '${(s.adherence! * 100).round()}%',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      );
                    }(),
                ]),
              ),
            ],
            const SectionTitle('Exportar'),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _exporting ? null : () => _export(true),
                  icon: const Icon(Icons.picture_as_pdf_rounded),
                  label: const Text('PDF'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exporting ? null : () => _export(false),
                  icon: const Icon(Icons.table_chart_rounded),
                  label: const Text('CSV'),
                ),
              ),
            ]),
          ]);
        },
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String label;
  final double? value;
  final String? text;
  final Color color;
  const _Bar({required this.label, required this.value, this.text, this.color = AppColors.success});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shown = text ?? (value == null ? '–' : '${(value! * 100).round()}%');
    return Semantics(
      label: '$label: $shown',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          SizedBox(width: 92, child: Text(label, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: value ?? 0,
                minHeight: 12,
                backgroundColor: cs.outlineVariant.withValues(alpha: 0.35),
                color: color,
              ),
            ),
          ),
          SizedBox(width: 48, child: Text(shown, textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}
