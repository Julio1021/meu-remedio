import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../services/backup_service.dart';
import '../widgets/common.dart';

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup e restauração')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Text('O backup gera um arquivo com todos os perfis, medicamentos, horários, histórico, estoque e configurações. '
            'Salve-o no Google Drive, e-mail ou outro local de sua escolha.',
            style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    await BackupService.shareBackup(app.db);
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Falha ao gerar backup: $e');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.cloud_upload_outlined),
          label: const Text('Fazer backup agora'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () async {
                  final ok = await confirmDialog(context,
                      title: 'Restaurar backup?',
                      message: 'Os dados atuais deste aparelho serão substituídos pelos do arquivo escolhido.',
                      confirm: 'Escolher arquivo');
                  if (!ok) return;
                  setState(() => _busy = true);
                  try {
                    final done = await BackupService.pickAndRestore(app.db);
                    if (done) {
                      await app.reloadAll();
                      if (context.mounted) showSnack(context, 'Backup restaurado. Lembretes reprogramados.');
                    }
                  } catch (e) {
                    if (context.mounted) showSnack(context, 'Arquivo inválido ou corrompido. Nenhum dado foi alterado.');
                  } finally {
                    if (mounted) setState(() => _busy = false);
                  }
                },
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Restaurar de um arquivo'),
        ),
        const SizedBox(height: 20),
        Text('A restauração é feita numa única transação: se o arquivo for inválido, nada é alterado.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}
