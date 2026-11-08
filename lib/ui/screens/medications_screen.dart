import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/schedule_engine.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'medication_detail_screen.dart';
import 'medication_form_screen.dart';

enum _Filter { active, prn, paused, ended, all }

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  String _q = '';
  _Filter _filter = _Filter.active;

  static const _labels = {
    _Filter.active: 'Ativos',
    _Filter.prn: 'Uso eventual',
    _Filter.paused: 'Pausados',
    _Filter.ended: 'Encerrados',
    _Filter.all: 'Todos',
  };

  bool _match(Medication m) {
    final okFilter = switch (_filter) {
      _Filter.active => m.status == MedStatus.active && !m.isPrn,
      _Filter.prn => m.isPrn && m.status != MedStatus.ended,
      _Filter.paused => m.status == MedStatus.paused,
      _Filter.ended => m.status == MedStatus.ended,
      _Filter.all => true,
    };
    if (!okFilter) return false;
    if (_q.isEmpty) return true;
    final q = _q.toLowerCase();
    return m.name.toLowerCase().contains(q) || (m.activeIngredient ?? '').toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final list = app.meds.where(_match).toList()
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return Scaffold(
      appBar: AppBar(title: const Text('Medicamentos')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: TextField(
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Pesquisar por nome'),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            for (final f in _Filter.values)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(_labels[f]!), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
              ),
          ]),
        ),
        Expanded(
          child: list.isEmpty
              ? ListView(children: [
                  EmptyState(
                    icon: Icons.medication_outlined,
                    title: app.meds.isEmpty ? 'Nenhum medicamento cadastrado' : 'Nada encontrado',
                    message: app.meds.isEmpty
                        ? 'Toque em "Medicamento" para cadastrar o primeiro.'
                        : 'Tente outro filtro ou termo de pesquisa.',
                    action: app.meds.isEmpty
                        ? FilledButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicationFormScreen())),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Cadastrar'),
                          )
                        : null,
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (c, i) => _MedCard(list[i]),
                ),
        ),
      ]),
    );
  }
}

class _MedCard extends StatelessWidget {
  final Medication m;
  const _MedCard(this.m);

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final cs = Theme.of(context).colorScheme;
    final s = app.currentSchedule(m.id!);
    final sub = m.isPrn
        ? 'Uso eventual • ${m.doseDescription}'
        : (s == null ? m.doseDescription : '${m.doseDescription} • ${ScheduleEngine.describe(s)}');
    final statusLabel = switch (m.status) {
      MedStatus.active => null,
      MedStatus.paused => 'Pausado',
      MedStatus.ended => 'Encerrado',
    };
    final low = m.stockEnabled && m.stockQty <= m.stockMin;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicationDetailScreen(medId: m.id!))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            MedAvatar(m, size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(m.displayName,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                  if (m.favorite) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.star_rounded, size: 18, color: AppColors.pending)),
                ]),
                const SizedBox(height: 2),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                if (statusLabel != null || m.stockEnabled) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, children: [
                    if (statusLabel != null) _tag(statusLabel, AppColors.neutral),
                    if (m.stockEnabled)
                      _tag('Estoque: ${fmtQty(m.stockQty)}', low ? AppColors.danger : AppColors.info),
                  ]),
                ],
              ]),
            ),
            IconButton(
              tooltip: 'Editar',
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MedicationFormScreen(editing: m))),
              icon: const Icon(Icons.edit_outlined),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _tag(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}
