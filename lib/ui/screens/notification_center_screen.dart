import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../domain/schedule_engine.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'permissions_screen.dart';

/// Central de notificações: doses em aberto, diagnóstico de permissões e
/// lembretes já programados no sistema.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() => _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<PendingNotificationRequest> _pending = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final app = context.read<AppState>();
    try {
      app.permissions = await app.notifications.permissionState();
      final p = await app.notifications.pending();
      if (mounted) setState(() => _pending = p);
    } catch (e) {
      app.notifications.lastError = 'Não foi possível consultar as notificações: $e';
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final open = app.today.where((d) => d.status == DoseStatus.late || d.status == DoseStatus.missed || d.status == DoseStatus.snoozed).toList();
    final perm = app.permissions;
    final doseReqs = _pending.where((r) => DosePayload.decode(r.payload) != null).toList();
    final nextReqs = doseReqs
        .map((r) => (r, DosePayload.decode(r.payload)!))
        .toList()
      ..sort((a, b) => a.$2.scheduledAt.compareTo(b.$2.scheduledAt));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Central de notificações'),
        actions: [IconButton(tooltip: 'Atualizar', onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
          Card(
            child: ListTile(
              leading: Icon(
                (perm?.notificationsEnabled ?? false) ? Icons.notifications_active_rounded : Icons.notifications_off_rounded,
                color: (perm?.notificationsEnabled ?? false) ? AppColors.success : AppColors.danger,
              ),
              title: Text((perm?.notificationsEnabled ?? false) ? 'Notificações ativadas' : 'Notificações desativadas'),
              subtitle: Text(perm != null && !perm.exactAlarmsAllowed
                  ? 'Horário exato não permitido: avisos podem atrasar.'
                  : '${doseReqs.length} lembrete(s) programado(s) no aparelho'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const PermissionsScreen()));
                _load();
              },
            ),
          ),
          if (app.notifications.lastError != null) ...[
            const SizedBox(height: 10),
            Card(
              color: AppColors.pending.withValues(alpha: 0.12),
              child: ListTile(
                leading: const Icon(Icons.report_problem_rounded, color: AppColors.pending),
                title: const Text('Último problema detectado'),
                subtitle: Text(app.notifications.lastError!),
              ),
            ),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () async {
              final at = await app.notifications.scheduleTest(minutes: 1);
              await _load();
              if (context.mounted) {
                showSnack(context, 'Lembrete de teste agendado para ${fmtTime(at)}. Pode fechar o app e aguardar.');
              }
            },
            icon: const Icon(Icons.alarm_add_rounded),
            label: const Text('Testar lembrete em 1 minuto'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await app.notifications.showTest();
                  if (context.mounted) showSnack(context, 'Notificação de teste enviada agora.');
                },
                icon: const Icon(Icons.notification_add_rounded),
                label: const Text('Testar agora'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await app.notifications.rescheduleAll();
                  await _load();
                  if (context.mounted) {
                    showSnack(context, '${app.notifications.lastScheduledCount} lembrete(s) reprogramado(s).');
                  }
                },
                icon: const Icon(Icons.sync_rounded),
                label: const Text('Reprogramar'),
              ),
            ),
          ]),
          const SectionTitle('Aguardando registro hoje'),
          if (open.isEmpty)
            Text('Nenhuma dose em aberto.', style: TextStyle(color: cs.onSurfaceVariant))
          else
            for (final d in open) Padding(padding: const EdgeInsets.only(bottom: 8), child: DoseTile(d)),
          const SectionTitle('Próximos lembretes programados'),
          if (nextReqs.isEmpty)
            Text('Nenhum lembrete programado.', style: TextStyle(color: cs.onSurfaceVariant))
          else
            Card(
              child: Column(children: [
                for (final (r, p) in nextReqs.take(30))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.alarm_rounded),
                    title: Text(app.settings.privacyMode ? (r.title ?? 'Lembrete') : (app.medById(p.medId)?.displayName ?? r.title ?? 'Lembrete')),
                    subtitle: Text('Dose de ${fmtDate(p.scheduledAt)} às ${fmtTime(p.scheduledAt)}${(r.id % 8) != 0 ? ' (repetição/adiamento)' : ''}'),
                  ),
              ]),
            ),
          const SizedBox(height: 12),
          Text(
            'Os lembretes são locais e funcionam sem internet. O sistema operacional pode atrasá-los ou bloqueá-los '
            '(economia de bateria, modo não perturbe, permissões).',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ]),
      ),
    );
  }
}
