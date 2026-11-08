import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/dose_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'medication_form_screen.dart';

/// Medicamentos de uso eventual (quando necessário).
class PrnScreen extends StatefulWidget {
  const PrnScreen({super.key});

  @override
  State<PrnScreen> createState() => _PrnScreenState();
}

class _PrnScreenState extends State<PrnScreen> {
  Map<int, List<DoseRecord>> _uses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    final out = <int, List<DoseRecord>>{};
    for (final m in app.meds.where((m) => m.isPrn)) {
      out[m.id!] = await app.db.recordsForMed(m.id!, limit: 50);
    }
    if (mounted) setState(() => _uses = out);
  }

  Future<void> _log(Medication m, PrnCheck check) async {
    final app = context.read<AppState>();
    if (check.intervalExceeded || check.maxReached) {
      final parts = <String>[
        if (check.intervalExceeded)
          'O intervalo mínimo que você cadastrou (${fmtQty(m.prnMinIntervalHours!)} h) ainda não passou desde o último uso.',
        if (check.maxReached) 'O limite que você cadastrou (${m.prnMaxPerDay} usos em 24 h) já foi atingido.',
        'O aplicativo apenas registra o uso; em caso de dúvida, consulte o profissional de saúde.',
      ];
      final ok = await confirmDialog(context,
          title: 'Atenção aos parâmetros cadastrados', message: parts.join('\n\n'), confirm: 'Registrar mesmo assim');
      if (!ok) return;
    }
    if (!mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Horário da utilização',
    );
    if (t == null) return;
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, t.hour, t.minute);
    if (at.isAfter(now.add(const Duration(minutes: 1)))) at = at.subtract(const Duration(days: 1));
    await app.logPrn(m.id!, at);
    await _load();
    if (mounted) showSnack(context, 'Uso de ${m.displayName} registrado às ${fmtTime(at)}.');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final meds = app.meds.where((m) => m.isPrn && m.status != MedStatus.ended).toList();
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('Uso eventual')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Text('Registre aqui medicamentos usados somente quando necessário. Os limites exibidos são os que você cadastrou.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (meds.isEmpty)
          EmptyState(
            icon: Icons.back_hand_outlined,
            title: 'Nenhum medicamento de uso eventual',
            message: 'Ao cadastrar, ative "Uso eventual (quando necessário)".',
            action: FilledButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MedicationFormScreen())),
              child: const Text('Cadastrar'),
            ),
          ),
        for (final m in meds)
          Builder(builder: (context) {
            final uses = _uses[m.id] ?? const <DoseRecord>[];
            final check = PrnCheck.evaluate(m, uses, now);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      MedAvatar(m),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          Text(m.doseDescription, style: TextStyle(color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ]),
                    if ((m.instructions ?? '').isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(m.instructions!, style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 10),
                    LabeledValue('Último uso', check.lastUse == null ? 'Nenhum registro' : fmtDateTime(check.lastUse!)),
                    LabeledValue(
                        'Usos em 24 h',
                        (m.prnMaxPerDay ?? 0) > 0
                            ? '${check.usesLast24h} de ${m.prnMaxPerDay} (limite cadastrado)'
                            : '${check.usesLast24h}'),
                    if (check.nextAllowedByInterval != null && check.intervalExceeded)
                      LabeledValue('Intervalo cadastrado', 'até ${fmtTime(check.nextAllowedByInterval!)}'),
                    if (check.intervalExceeded || check.maxReached)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(children: const [
                          Icon(Icons.warning_amber_rounded, color: AppColors.pending, size: 18),
                          SizedBox(width: 6),
                          Expanded(child: Text('Fora dos parâmetros que você cadastrou.', style: TextStyle(color: AppColors.pending))),
                        ]),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () => _log(m, check),
                      icon: const Icon(Icons.add_task_rounded),
                      label: const Text('Registrar utilização'),
                    ),
                    if (uses.isNotEmpty)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Histórico'),
                        children: [
                          for (final u in uses.take(20))
                            ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.check_rounded, color: AppColors.success),
                              title: Text(fmtDateTime(parseDtKey(u.actionAt))),
                              trailing: IconButton(
                                tooltip: 'Desfazer',
                                icon: const Icon(Icons.undo_rounded),
                                onPressed: () async {
                                  await app.undoDose(m.id!, parseDtKey(u.scheduledAt));
                                  await _load();
                                },
                              ),
                            ),
                        ],
                      ),
                  ]),
                ),
              ),
            );
          }),
      ]),
    );
  }
}
