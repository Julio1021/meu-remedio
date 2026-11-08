import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Agenda: doses de qualquer dia, com navegação rápida pelos próximos dias.
class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});

  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  DateTime _day = dayOnly(DateTime.now());
  Future<List<DoseView>>? _future;
  final _scroll = ScrollController();

  static const _pastDays = 7;
  static const _futureDays = 30;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    final app = context.read<AppState>();
    _future = app.dosesBetween(_day, _day.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final today = dayOnly(DateTime.now());
    // Recarrega sempre que o estado global mudar (ex.: dose registrada).
    _future = app.dosesBetween(_day, _day.add(const Duration(days: 1)));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agenda'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _day = today),
            child: const Text('Hoje'),
          ),
          IconButton(
            tooltip: 'Escolher data',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: () async {
              final d = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime(2000), lastDate: DateTime(2100));
              if (d != null) setState(() => _day = dayOnly(d));
            },
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 84,
          child: ListView.builder(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            itemCount: _pastDays + _futureDays,
            itemBuilder: (c, i) {
              final d = DateTime(today.year, today.month, today.day - _pastDays + i);
              final sel = d == _day;
              final isToday = d == today;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Semantics(
                  selected: sel,
                  button: true,
                  label: fmtLongDate(d),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => setState(() => _day = d),
                    child: Container(
                      width: 56,
                      decoration: BoxDecoration(
                        color: sel ? cs.primary : cs.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: isToday && !sel ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(fmtWeekdayShort(d), style: TextStyle(fontSize: 12, color: sel ? cs.onPrimary : cs.onSurfaceVariant)),
                        const SizedBox(height: 4),
                        Text('${d.day}',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: sel ? cs.onPrimary : cs.onSurface)),
                      ]),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(_day == today ? 'Hoje, ${fmtDate(_day)}' : fmtLongDate(_day),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<DoseView>>(
            future: _future,
            builder: (c, snap) {
              if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('Não foi possível carregar a agenda.\n${snap.error}', textAlign: TextAlign.center));
              }
              final list = snap.data ?? const [];
              if (list.isEmpty) {
                return ListView(children: const [
                  EmptyState(
                    icon: Icons.event_available_rounded,
                    title: 'Nenhuma dose neste dia',
                    message: 'Escolha outro dia ou cadastre um medicamento.',
                  ),
                ]);
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (c, i) => DoseTile(list[i]),
              );
            },
          ),
        ),
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo((_pastDays * 64.0) - 14);
    });
  }
}
