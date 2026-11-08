import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import 'backup_screen.dart';
import 'notification_center_screen.dart';
import 'prn_screen.dart';
import 'privacy_screen.dart';
import 'profiles_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'stock_detail_screen.dart';

/// Aba "Perfil": acesso às demais áreas do app.
class ProfileHubScreen extends StatelessWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = app.activeProfile!;
    final cs = Theme.of(context).colorScheme;
    Widget item(IconData i, String t, String s, Widget page) => ListTile(
          leading: Icon(i, color: cs.primary),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(s),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 0, 20, 40), children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: Color(p.color).withValues(alpha: 0.18),
              child: Text(p.name.characters.first.toUpperCase(),
                  style: TextStyle(color: Color(p.color), fontWeight: FontWeight.w800, fontSize: 22)),
            ),
            title: Text(p.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            subtitle: Text('${p.relation} • ${app.meds.length} medicamento(s)'),
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfilesScreen())),
              child: Text(app.profiles.length > 1 ? 'Trocar' : 'Perfis'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            item(Icons.inventory_2_rounded, 'Controle de estoque', 'Quantidades, compras e estimativas', const StockScreen()),
            item(Icons.back_hand_rounded, 'Uso eventual', 'Medicamentos quando necessário', const PrnScreen()),
            item(Icons.bar_chart_rounded, 'Relatórios', 'Adesão, evolução e exportação PDF/CSV', const ReportsScreen()),
            item(Icons.group_rounded, 'Compartilhamento e cuidadores', 'Lista de medicamentos para familiares', const SharingScreen()),
          ]),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(children: [
            item(Icons.people_alt_rounded, 'Gerenciar perfis', 'Família e pessoas cuidadas', const ProfilesScreen()),
            item(Icons.notifications_rounded, 'Central de notificações', 'Permissões e lembretes programados', const NotificationCenterScreen()),
            item(Icons.settings_rounded, 'Configurações', 'Tema, fonte, sons e repetições', const SettingsScreen()),
            item(Icons.shield_rounded, 'Privacidade e segurança', 'Modo privado e exclusão de dados', const PrivacyScreen()),
            item(Icons.backup_rounded, 'Backup e restauração', 'Exportar e importar seus dados', const BackupScreen()),
          ]),
        ),
      ]),
    );
  }
}
