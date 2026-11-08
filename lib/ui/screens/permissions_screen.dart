import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';

class PermissionsScreen extends StatelessWidget {
  const PermissionsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Permissões')),
        body: const PermissionsBody(),
      );
}

/// Solicitação e diagnóstico das permissões necessárias aos lembretes.
class PermissionsBody extends StatefulWidget {
  const PermissionsBody({super.key});

  @override
  State<PermissionsBody> createState() => _PermissionsBodyState();
}

class _PermissionsBodyState extends State<PermissionsBody> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final app = context.read<AppState>();
      app.permissions = await app.notifications.permissionState();
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.permissions;
    final cs = Theme.of(context).colorScheme;

    Widget row(bool ok, String title, String desc) => Card(
          child: ListTile(
            leading: Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: ok ? AppColors.success : AppColors.pending),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(ok ? 'Ativado' : desc),
          ),
        );

    return ListView(padding: const EdgeInsets.all(24), children: [
      Icon(Icons.notifications_active_rounded, size: 56, color: cs.primary),
      const SizedBox(height: 16),
      Text('Permita os lembretes',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
        'Para avisar no horário das doses, o aplicativo precisa enviar notificações. '
        'Elas são geradas no próprio aparelho e funcionam sem internet.',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurfaceVariant),
      ),
      const SizedBox(height: 20),
      row(p?.notificationsEnabled ?? false, 'Notificações', 'Desativadas — os lembretes não aparecerão.'),
      const SizedBox(height: 8),
      if (Platform.isAndroid)
        row(p?.exactAlarmsAllowed ?? false, 'Alarmes e lembretes (horário exato)',
            'Sem esta permissão o Android pode atrasar alguns minutos os avisos.'),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: () => app.requestPermissions(),
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('Permitir notificações'),
      ),
      const SizedBox(height: 24),
      Card(
        color: AppColors.info.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.info_outline_rounded, color: AppColors.info),
              const SizedBox(width: 8),
              Text('Importante', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 8),
            Text(Platform.isIOS
                ? 'O iOS limita a quantidade de lembretes agendados. Abra o aplicativo ao menos uma vez a cada dois dias para manter os próximos lembretes programados.'
                : 'Alguns aparelhos economizam bateria encerrando aplicativos. Em Configurações > Apps > Meu Remédio > Bateria, escolha "Sem restrições" para maior confiabilidade. '
                    'Os lembretes são reprogramados após reiniciar o aparelho.'),
            const SizedBox(height: 8),
            const Text('Nenhum sistema de notificação é infalível: o sistema operacional pode atrasar ou bloquear avisos.',
                style: TextStyle(fontSize: 12.5)),
          ]),
        ),
      ),
    ]);
  }
}
