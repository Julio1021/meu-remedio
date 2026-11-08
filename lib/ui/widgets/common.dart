import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../domain/schedule_engine.dart';
import '../../services/dose_service.dart';
import '../../state/app_state.dart';

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
          child: Icon(icon, size: 40, color: cs.primary),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ]),
    );
  }
}

/// Status sempre com texto e ícone — nunca apenas cor.
class StatusChip extends StatelessWidget {
  final DoseStatus status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.forStatus(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(AppColors.iconForStatus(status), size: 14, color: c),
        const SizedBox(width: 4),
        Text(doseStatusLabels[status]!, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class MedAvatar extends StatelessWidget {
  final Medication med;
  final double size;
  const MedAvatar(this.med, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final c = Color(med.color);
    final photo = med.photoPath;
    if (photo != null && File(photo).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 3),
        child: Image.file(File(photo), width: size, height: size, fit: BoxFit.cover, semanticLabel: 'Foto de ${med.name}'),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size / 3)),
      child: Icon(iconForForm(med.form), color: c, size: size * 0.55, semanticLabel: med.form),
    );
  }
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const StatCard({super.key, required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 10),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
          ]),
        ),
      );
}

Future<bool> confirmDialog(BuildContext context,
    {required String title, required String message, String confirm = 'Confirmar', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String msg, {VoidCallback? onUndo}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(msg),
    duration: const Duration(seconds: 4),
    action: onUndo == null ? null : SnackBarAction(label: 'DESFAZER', onPressed: onUndo),
  ));
}

/// Registra a dose como tomada com opção de desfazer.
Future<void> quickTake(BuildContext context, DoseView d) async {
  final app = context.read<AppState>();
  final res = await app.takeDose(d.med.id!, d.scheduledAt);
  if (!context.mounted) return;
  if (res == ConfirmResult.alreadyTaken) {
    showSnack(context, 'Esta dose já estava registrada como tomada.');
  } else {
    showSnack(context, '${d.med.displayName} registrado como tomado às ${fmtTime(DateTime.now())}.',
        onUndo: () => app.undoDose(d.med.id!, d.scheduledAt));
  }
}

/// Lista de doses (agenda) com botão de confirmação.
class DoseTile extends StatelessWidget {
  final DoseView dose;
  final bool showDate;
  const DoseTile(this.dose, {super.key, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = dose;
    final done = d.status == DoseStatus.taken;
    final canAct = d.status != DoseStatus.taken && d.status != DoseStatus.cancelled && d.status != DoseStatus.skipped;
    final name = d.record?.medName ?? d.med.displayName;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => showDoseSheet(context, d),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(children: [
            SizedBox(
              width: 56,
              child: Column(children: [
                Text(fmtTime(d.scheduledAt),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17, color: done ? cs.onSurfaceVariant : cs.onSurface)),
                if (showDate) Text(fmtDate(d.scheduledAt).substring(0, 5), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
            const SizedBox(width: 6),
            MedAvatar(d.med, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                      decoration: done ? TextDecoration.lineThrough : null,
                      decorationColor: cs.onSurfaceVariant,
                    )),
                const SizedBox(height: 2),
                Text(d.record?.doseDesc ?? d.med.doseDescription, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(height: 6),
                Row(children: [
                  StatusChip(d.status),
                  if (d.status == DoseStatus.taken && d.record != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('às ${fmtTime(parseDtKey(d.record!.actionAt))}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ],
                  if (d.status == DoseStatus.snoozed && d.record?.snoozedUntil != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('até ${fmtTime(parseDtKey(d.record!.snoozedUntil!))}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ],
                ]),
              ]),
            ),
            if (canAct)
              IconButton.filledTonal(
                tooltip: 'Registrar como tomado',
                iconSize: 26,
                onPressed: () => quickTake(context, d),
                icon: const Icon(Icons.check_rounded),
              )
            else
              const SizedBox(width: 8),
          ]),
        ),
      ),
    );
  }
}

/// Folha de ações de uma dose (também usada ao tocar numa notificação).
Future<void> showDoseSheet(BuildContext context, DoseView d) async {
  final app = context.read<AppState>();
  final s = app.settings;
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) {
      final cs = Theme.of(c).colorScheme;
      Widget action(IconData i, String label, Future<void> Function() fn, {Color? color}) => ListTile(
            leading: Icon(i, color: color ?? cs.primary),
            title: Text(label),
            onTap: () async {
              Navigator.pop(c);
              await fn();
            },
          );
      final open = d.status != DoseStatus.taken && d.status != DoseStatus.cancelled && d.status != DoseStatus.skipped;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              leading: MedAvatar(d.med),
              title: Text(d.record?.medName ?? d.med.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              subtitle: Text('${d.record?.doseDesc ?? d.med.doseDescription} • ${fmtDate(d.scheduledAt)} às ${fmtTime(d.scheduledAt)}'),
              trailing: StatusChip(d.status),
            ),
            if ((d.med.instructions ?? '').trim().isNotEmpty || (d.med.foodNote ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text([d.med.instructions, d.med.foodNote].whereType<String>().where((x) => x.trim().isNotEmpty).join('\n'),
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            if (d.record != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text('Registrado em ${fmtDateTime(parseDtKey(d.record!.actionAt))} • origem: ${d.record!.source}',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
              ),
            const Divider(),
            if (open) ...[
              action(Icons.check_circle_rounded, 'Registrar como tomado agora', () => quickTake(context, d), color: AppColors.success),
              action(Icons.edit_calendar_rounded, 'Tomei em outro horário…', () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(d.scheduledAt));
                if (t == null) return;
                final at = DateTime(d.scheduledAt.year, d.scheduledAt.month, d.scheduledAt.day, t.hour, t.minute);
                await app.takeDose(d.med.id!, d.scheduledAt, at: at);
                if (context.mounted) showSnack(context, 'Registrado como tomado às ${fmtTime(at)}.');
              }),
              for (final m in ({s.snoozeMinutes, 15, 30, 60}.toList()..sort()))
                action(Icons.snooze_rounded, 'Adiar $m minutos', () async {
                  final until = await app.snoozeDose(d.med.id!, d.scheduledAt, m);
                  if (context.mounted) showSnack(context, 'Lembrete adiado para ${fmtTime(until)}.');
                }, color: AppColors.pending),
              action(Icons.do_not_disturb_on_outlined, 'Não tomei (confirmar)', () async {
                await app.skipDose(d.med.id!, d.scheduledAt);
                if (context.mounted) {
                  showSnack(context, 'Dose registrada como não tomada.', onUndo: () => app.undoDose(d.med.id!, d.scheduledAt));
                }
              }, color: AppColors.danger),
              action(Icons.block_rounded, 'Cancelar esta dose', () async {
                await app.cancelDose(d.med.id!, d.scheduledAt);
                if (context.mounted) {
                  showSnack(context, 'Dose cancelada.', onUndo: () => app.undoDose(d.med.id!, d.scheduledAt));
                }
              }, color: AppColors.neutral),
            ],
            if (d.record != null)
              action(Icons.undo_rounded, 'Desfazer registro', () async {
                await app.undoDose(d.med.id!, d.scheduledAt);
                if (context.mounted) showSnack(context, 'Registro desfeito. A dose voltou a ficar pendente.');
              }),
          ]),
        ),
      );
    },
  );
}

class LabeledValue extends StatelessWidget {
  final String label;
  final String value;
  const LabeledValue(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 130,
            child: Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}
