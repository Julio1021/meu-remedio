import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/analytics.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

/// Visão geral do estoque de todos os medicamentos do perfil.
class StockScreen extends StatelessWidget {
  const StockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final list = app.meds.where((m) => m.stockEnabled && m.status != MedStatus.ended).toList();
    final without = app.meds.where((m) => !m.stockEnabled && m.status != MedStatus.ended).toList();
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Controle de estoque')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Nenhum estoque controlado',
            message: 'Ative o controle de estoque na edição de um medicamento para acompanhar quanto resta.',
          ),
        for (final m in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Builder(builder: (context) {
              final active = (app.schedules[m.id] ?? const <Schedule>[]).where((s) => s.effectiveTo == null).toList();
              final perDay = m.status == MedStatus.active && active.isNotEmpty ? ScheduleEngine.averageDosesPerDay(active, now) : 0.0;
              final est = StockEstimate.compute(stockQty: m.stockQty, doseQty: m.doseQty, dosesPerDay: perDay, now: now);
              final empty = m.stockQty <= 0;
              final low = !empty && m.stockQty <= m.stockMin;
              final color = empty ? AppColors.danger : (low ? AppColors.pending : AppColors.success);
              final expSoon = m.expiryDate != null && parseDateKey(m.expiryDate!).difference(now).inDays <= 30;
              return Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StockDetailScreen(medId: m.id!))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      MedAvatar(m),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            est.daysLeft == null ? 'Sem consumo programado' : 'Estimativa: ~${est.daysLeft!.floor()} dia(s)',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                          ),
                          if (expSoon)
                            Text('Validade: ${fmtDate(parseDateKey(m.expiryDate!))}',
                                style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fmtQty(m.stockQty), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                        Text(empty ? 'Esgotado' : (low ? 'Baixo' : m.stockUnit),
                            style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
                      ]),
                    ]),
                  ),
                ),
              );
            }),
          ),
        if (without.isNotEmpty) ...[
          const SectionTitle('Sem controle de estoque'),
          Text(without.map((m) => m.displayName).join(', '), style: TextStyle(color: cs.onSurfaceVariant)),
        ],
        const SizedBox(height: 16),
        Text('As estimativas consideram a programação atual e as doses confirmadas. Doses não confirmadas não são descontadas.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class StockDetailScreen extends StatefulWidget {
  final int medId;
  const StockDetailScreen({super.key, required this.medId});

  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<StockMovement> _moves = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final m = await context.read<AppState>().db.movements(widget.medId);
    if (mounted) setState(() => _moves = m);
  }

  Future<void> _movement(Medication m, StockMoveType type) async {
    final qty = TextEditingController();
    final note = TextEditingController();
    final title = switch (type) {
      StockMoveType.purchase => 'Registrar compra / entrada',
      StockMoveType.loss => 'Registrar perda ou descarte',
      _ => 'Ajuste manual (saldo atual)',
    };
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: type == StockMoveType.adjust ? 'Novo saldo' : 'Quantidade',
              suffixText: m.stockUnit,
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'Observação (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Salvar')),
        ],
      ),
    );
    final v = parseQty(qty.text);
    final n = note.text.trim().isEmpty ? null : note.text.trim();
    if (ok != true || !mounted) return;
    if (v == null || v < 0) {
      showSnack(context, 'Quantidade inválida.');
      return;
    }
    final app = context.read<AppState>();
    if (type == StockMoveType.adjust) {
      await app.stockSet(m.id!, v, note: n);
    } else {
      await app.stockMove(m.id!, type, type == StockMoveType.loss ? -v : v, note: n);
    }
    await _load();
    if (mounted) showSnack(context, 'Estoque atualizado.');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final m = app.medById(widget.medId);
    if (m == null) return const Scaffold(body: Center(child: Text('Medicamento não encontrado.')));
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final active = (app.schedules[m.id] ?? const <Schedule>[]).where((s) => s.effectiveTo == null).toList();
    final perDay = m.status == MedStatus.active && active.isNotEmpty ? ScheduleEngine.averageDosesPerDay(active, now) : 0.0;
    final est = StockEstimate.compute(stockQty: m.stockQty, doseQty: m.doseQty, dosesPerDay: perDay, now: now);

    return Scaffold(
      appBar: AppBar(title: Text(m.displayName)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text(fmtQty(m.stockQty), style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800)),
              Text(m.stockUnit, style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              Text(
                est.daysLeft == null
                    ? 'Sem consumo programado no momento.'
                    : 'Estimativa: dura cerca de ${est.daysLeft!.floor()} dia(s), até ${fmtDate(est.runOutDate!)}.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text('Estimativa baseada na programação atual (${fmtQty(perDay * m.doseQty)} ${m.stockUnit}/dia).',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              if (m.stockMin > 0) ...[
                const SizedBox(height: 4),
                Text('Aviso de estoque baixo: ${fmtQty(m.stockMin)} ${m.stockUnit}',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: () => _movement(m, StockMoveType.purchase),
            icon: const Icon(Icons.add_shopping_cart_rounded),
            label: const Text('Compra'),
          ),
          OutlinedButton.icon(
            onPressed: () => _movement(m, StockMoveType.adjust),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Ajustar'),
          ),
          OutlinedButton.icon(
            onPressed: () => _movement(m, StockMoveType.loss),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Perda/descarte'),
          ),
        ]),
        const SectionTitle('Movimentações'),
        if (_moves.isEmpty)
          Text('Nenhuma movimentação.', style: TextStyle(color: cs.onSurfaceVariant))
        else
          Card(
            child: Column(children: [
              for (final mv in _moves)
                ListTile(
                  dense: true,
                  leading: Icon(mv.qty >= 0 ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                      color: mv.qty >= 0 ? AppColors.success : AppColors.pending),
                  title: Text('${stockMoveLabels[mv.type]} • ${mv.qty >= 0 ? '+' : ''}${fmtQty(mv.qty)}'),
                  subtitle: Text('${fmtDateTime(parseDtKey(mv.createdAt))}${mv.note == null ? '' : ' • ${mv.note}'}'),
                  trailing: Text('Saldo ${fmtQty(mv.balance)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
      ]),
    );
  }
}
