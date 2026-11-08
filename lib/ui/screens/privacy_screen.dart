import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacidade e segurança')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 40), children: [
        Card(
          child: SwitchListTile(
            value: s.privacyMode,
            onChanged: (v) => app.updateSettings(s.copyWith(privacyMode: v), reschedule: true),
            secondary: const Icon(Icons.visibility_off_outlined),
            title: const Text('Modo de privacidade'),
            subtitle: const Text('As notificações não mostram o nome do medicamento nem a dose, e ficam ocultas na tela bloqueada.'),
          ),
        ),
        const SectionTitle('Seus dados'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _p(Icons.phone_android_rounded, 'Armazenados somente neste aparelho, no armazenamento privado do aplicativo. Não há envio a servidores.'),
              _p(Icons.share_outlined, 'Relatórios e backups só saem do aparelho quando você escolhe compartilhá-los.'),
              _p(Icons.medical_information_outlined,
                  'O aplicativo não prescreve, não recomenda doses nem define intervalos: tudo é informado por você conforme orientação profissional.'),
              _p(Icons.gavel_rounded,
                  'Em conformidade com a LGPD, você pode exportar (Backup) ou excluir todos os seus dados a qualquer momento.'),
              _p(Icons.lock_outline_rounded,
                  'Recomendação: mantenha o bloqueio de tela do aparelho ativado. Arquivos de backup contêm dados de saúde: guarde-os em local seguro.'),
            ]),
          ),
        ),
        const SectionTitle('Exclusão'),
        Card(
          child: ListTile(
            leading: const Icon(Icons.delete_forever_rounded, color: AppColors.danger),
            title: const Text('Excluir todos os dados', style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
            subtitle: const Text('Apaga perfis, medicamentos, históricos, estoque e configurações deste aparelho.'),
            onTap: () async {
              final ok = await confirmDialog(context,
                  title: 'Excluir todos os dados?',
                  message: 'Esta ação é definitiva. Considere fazer um backup antes.',
                  confirm: 'Excluir tudo',
                  danger: true);
              if (!ok || !context.mounted) return;
              final again = await confirmDialog(context,
                  title: 'Tem certeza?', message: 'Todos os registros serão apagados permanentemente.', confirm: 'Sim, excluir', danger: true);
              if (!again || !context.mounted) return;
              final nav = Navigator.of(context);
              await app.wipeEverything();
              nav.popUntil((r) => r.isFirst);
            },
          ),
        ),
        const SizedBox(height: 12),
        Text('Exclusão definitiva conforme o direito do titular previsto na LGPD (Lei nº 13.709/2018).',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  Widget _p(IconData i, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(t)),
        ]),
      );
}
