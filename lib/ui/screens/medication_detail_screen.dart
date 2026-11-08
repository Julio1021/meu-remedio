import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/analytics.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'medication_form_screen.dart';
import 'stock_detail_screen.dart';

class MedicationDetailScreen extends StatefulWidget {
  final int medId;
  const MedicationDetailScreen({super.key, required this.medId});

  @override
  State<MedicationDetailScreen> createState() => _MedicationDetailScreenState();
}

class _MedicationDetailScreenState extends State<MedicationDetailScreen> {
  List<DoseRecord> _records = [];
  List<ChangeLogEntry> _log = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppState>().db;
    final r = await db.recordsForMed(widget.medId, limit: 30);
    final l = await db.changeLog(widget.medId);
    if (mounted) {
      setState(() {
        _records = r;
        _log = l;
      });
    }
  }

  Future<void> _setStatus(MedStatus st) async {
    final app = context.read<AppState>();
    const msgs = {
      MedStatus.paused: ('Pausar tratamento?', 'Os lembretes serão suspensos até você retomar. O histórico é preservado.', 'Pausar'),
      MedStatus.ended: ('Encerrar tratamento?', 'Os lembretes futuros serão removidos. O histórico é preservado.', 'Encerrar'),
      MedStatus.active: ('Retomar tratamento?', 'Os lembretes voltarão a partir de agora.', 'Retomar'),
    };
    final (t, m, c) = msgs[st]!;
    if (!await confirmDialog(context, title: t, message: m, confirm: c)) return;
    await app.setMedStatus(widget.medId, st);
    await _load();
    if (mounted) showSnack(context, st == MedStatus.active ? 'Tratamento retomado.' : (st == MedStatus.paused ? 'Tratamento pausado.' : 'Tratamento encerrado.'));
  }

  Future<void> _delete(Medication m) async {
    final ok = await confirmDialog(
      context,
      title: 'Excluir ${m.displayName}?',
      message: 'Isto apaga o medicamento, seu histórico de doses e de estoque. Esta ação não pode ser desfeita. '
          'Se quiser apenas parar, prefira "Encerrar tratamento".',
      confirm: 'Excluir',
      danger: true,
    );
    if (!ok || !mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await context.read<AppState>().deleteMedication(m.id!);
    nav.pop();
    messenger.showSnackBar(SnackBar(content: Text('${m.displayName} excluído.')));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final m = app.medById(widget.medId);
    if (m == null) return const Scaffold(body: Center(child: Text('Medicamento não encontrado.')));
    final cs = Theme.of(context).colorScheme;
    final s = app.currentSchedule(m.id!);
    final allSched = app.schedules[m.id] ?? const <Schedule>[];
    final active = allSched.where((x) => x.effectiveTo == null).toList();
    final perDay = active.isEmpty ? 0.0 : ScheduleEngine.averageDosesPerDay(active, DateTime.now());
    final est = StockEstimate.compute(stockQty: m.stockQty, doseQty: m.doseQty, dosesPerDay: perDay, now: DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalhes'),
        actions: [
          IconButton(
            tooltip: m.favorite ? 'Remover dos favoritos' : 'Marcar como favorito',
            onPressed: () => app.toggleFavorite(m),
            icon: Icon(m.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: m.favorite ? AppColors.pending : null),
          ),
          IconButton(
            tooltip: 'Editar',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => MedicationFormScreen(editing: m)));
              _load();
            },
            icon: const Icon(Icons.edit_outlined),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'pause') _setStatus(MedStatus.paused);
              if (v == 'resume') _setStatus(MedStatus.active);
              if (v == 'end') _setStatus(MedStatus.ended);
              if (v == 'delete') _delete(m);
            },
            itemBuilder: (_) => [
              if (m.status == MedStatus.active && !m.isPrn) const PopupMenuItem(value: 'pause', child: Text('Pausar tratamento')),
              if (m.status != MedStatus.active) const PopupMenuItem(value: 'resume', child: Text('Retomar tratamento')),
              if (m.status != MedStatus.ended) const PopupMenuItem(value: 'end', child: Text('Encerrar tratamento')),
              const PopupMenuItem(value: 'delete', child: Text('Excluir')),
            ],
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Row(children: [
          MedAvatar(m, size: 72),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(m.displayName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              if ((m.activeIngredient ?? '').isNotEmpty) Text(m.activeIngredient!, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(switch (m.status) {
                MedStatus.active => m.isPrn ? 'Uso eventual' : 'Em uso',
                MedStatus.paused => 'Pausado',
                MedStatus.ended => 'Encerrado',
              }, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SectionTitle('Uso'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              LabeledValue('Apresentação', m.form),
              LabeledValue('Quantidade', m.doseDescription),
              if (!m.isPrn) LabeledValue('Horários', s == null ? 'Sem horários vigentes' : ScheduleEngine.describe(s)),
              if (!m.isPrn && s != null) LabeledValue('Início', fmtDate(parseDateKey(s.startDate))),
              if (m.isPrn && (m.prnMinIntervalHours ?? 0) > 0) LabeledValue('Intervalo mínimo', '${fmtQty(m.prnMinIntervalHours!)} h'),
              if (m.isPrn && (m.prnMaxPerDay ?? 0) > 0) LabeledValue('Limite em 24 h', '${m.prnMaxPerDay}'),
              if ((m.instructions ?? '').isNotEmpty) LabeledValue('Instruções', m.instructions!),
              if ((m.foodNote ?? '').isNotEmpty) LabeledValue('Alimentação', m.foodNote!),
              if ((m.notes ?? '').isNotEmpty) LabeledValue('Anotações', m.notes!),
            ]),
          ),
        ),
        if (m.stockEnabled) ...[
          const SectionTitle('Estoque'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_rounded),
              title: Text('${fmtQty(m.stockQty)} ${m.stockUnit}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(est.daysLeft == null
                  ? 'Sem consumo programado'
                  : 'Estimativa: dura cerca de ${est.daysLeft!.floor()} dia(s), até ${fmtDate(est.runOutDate!)}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockDetailScreen(medId: m.id!))),
            ),
          ),
        ],
        if (m.expiryDate != null) ...[
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_rounded),
              title: Text('Validade: ${fmtDate(parseDateKey(m.expiryDate!))}'),
            ),
          ),
        ],
        const SectionTitle('Últimos registros'),
        if (_records.isEmpty)
          Text('Ainda não há registros.', style: TextStyle(color: cs.onSurfaceVariant))
        else
          Card(
            child: Column(children: [
              for (final r in _records.take(10))
                ListTile(
                  dense: true,
                  leading: Icon(_iconFor(r.status), color: _colorFor(r.status)),
                  title: Text('${fmtDate(parseDtKey(r.scheduledAt))} • ${fmtTime(parseDtKey(r.scheduledAt))}'),
                  subtitle: Text('${_labelFor(r.status)} • registrado ${fmtDateTime(parseDtKey(r.actionAt))} (${r.source})'),
                ),
            ]),
          ),
        const SectionTitle('Alterações no tratamento'),
        Card(
          child: Column(children: [
            for (final l in _log)
              ListTile(
                dense: true,
                leading: const Icon(Icons.history_rounded),
                title: Text(l.description),
                subtitle: Text(fmtDateTime(parseDtKey(l.createdAt))),
              ),
            if (allSched.length > 1)
              ExpansionTile(
                title: const Text('Regras de horário anteriores'),
                children: [
                  for (final x in allSched.reversed.where((x) => x.effectiveTo != null))
                    ListTile(
                      dense: true,
                      title: Text(ScheduleEngine.describe(x)),
                      subtitle: Text('Vigente de ${fmtDateTime(parseDtKey(x.effectiveFrom))} até ${fmtDateTime(parseDtKey(x.effectiveTo!))}'),
                    ),
                ],
              ),
          ]),
        ),
      ]),
    );
  }

  static IconData _iconFor(RecordStatus s) => switch (s) {
        RecordStatus.taken => Icons.check_circle_rounded,
        RecordStatus.skipped => Icons.do_not_disturb_on_outlined,
        RecordStatus.snoozed => Icons.snooze_rounded,
        RecordStatus.cancelled => Icons.block_rounded,
      };
  static Color _colorFor(RecordStatus s) => switch (s) {
        RecordStatus.taken => AppColors.success,
        RecordStatus.skipped => AppColors.danger,
        RecordStatus.snoozed => AppColors.pending,
        RecordStatus.cancelled => AppColors.neutral,
      };
  static String _labelFor(RecordStatus s) => switch (s) {
        RecordStatus.taken => 'Tomado',
        RecordStatus.skipped => 'Não tomado',
        RecordStatus.snoozed => 'Adiado',
        RecordStatus.cancelled => 'Cancelado',
      };
}
