import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/formatters.dart';
import '../../data/settings.dart';
import '../../state/app_state.dart';
import '../widgets/common.dart';
import 'backup_screen.dart';
import 'notification_center_screen.dart';
import 'privacy_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    void set(AppSettings n, {bool resched = false}) => app.updateSettings(n, reschedule: resched);

    Widget minutes(String title, int value, List<int> options, void Function(int) onChanged, {String suffix = 'min'}) => ListTile(
          title: Text(title),
          trailing: DropdownButton<int>(
            value: options.contains(value) ? value : options.first,
            underline: const SizedBox(),
            items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o == 0 ? 'Desligado' : '$o $suffix'))],
            onChanged: (v) => onChanged(v!),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 40), children: [
        const SectionTitle('Aparência'),
        Card(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(value: ThemeMode.light, label: Text('Claro'), icon: Icon(Icons.light_mode_rounded)),
                  ButtonSegment(value: ThemeMode.dark, label: Text('Escuro'), icon: Icon(Icons.dark_mode_rounded)),
                  ButtonSegment(value: ThemeMode.system, label: Text('Auto'), icon: Icon(Icons.brightness_auto_rounded)),
                ],
                selected: {s.themeMode},
                onSelectionChanged: (v) => set(s.copyWith(themeMode: v.first)),
              ),
            ),
            ListTile(
              title: const Text('Tamanho do texto'),
              subtitle: Slider(
                value: s.textScale,
                min: 0.9,
                max: 1.5,
                divisions: 6,
                label: '${(s.textScale * 100).round()}%',
                onChanged: (v) => set(s.copyWith(textScale: v)),
              ),
              trailing: Text('${(s.textScale * 100).round()}%'),
            ),
            SwitchListTile(
              value: s.reduceMotion,
              onChanged: (v) => set(s.copyWith(reduceMotion: v)),
              title: const Text('Reduzir animações'),
            ),
          ]),
        ),
        const SectionTitle('Lembretes'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.notifications_rounded),
              title: const Text('Central de notificações e permissões'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationCenterScreen())),
            ),
            SwitchListTile(
              value: s.vibration,
              onChanged: (v) => set(s.copyWith(vibration: v), resched: true),
              title: const Text('Vibração'),
              subtitle: const Text('Som e toque: ajuste nas configurações de notificação do sistema'),
            ),
            minutes('"Lembrar em" (botão da notificação)', s.snoozeMinutes, const [5, 10, 15, 20, 30],
                (v) => set(s.copyWith(snoozeMinutes: v), resched: true)),
            minutes('"Adiar" (botão da notificação)', s.postponeMinutes, const [15, 30, 45, 60, 90, 120],
                (v) => set(s.copyWith(postponeMinutes: v), resched: true)),
            minutes('Repetir se não houver resposta a cada', s.repeatEveryMinutes, const [5, 10, 15, 20, 30],
                (v) => set(s.copyWith(repeatEveryMinutes: v), resched: true)),
            ListTile(
              title: const Text('Quantidade de repetições'),
              trailing: DropdownButton<int>(
                value: s.maxRepeats.clamp(0, 3),
                underline: const SizedBox(),
                items: [for (var i = 0; i <= 3; i++) DropdownMenuItem(value: i, child: Text(i == 0 ? 'Nenhuma' : '$i'))],
                onChanged: (v) => set(s.copyWith(maxRepeats: v), resched: true),
              ),
            ),
            minutes('Aviso antecipado', s.advanceMinutes, const [0, 5, 10, 15, 30],
                (v) => set(s.copyWith(advanceMinutes: v), resched: true)),
            minutes('Considerar atrasada após', s.lateAfterMinutes, const [5, 10, 15, 30, 60],
                (v) => set(s.copyWith(lateAfterMinutes: v))),
            ListTile(
              title: const Text('Marcar "não registrada" após'),
              trailing: DropdownButton<int>(
                value: const [60, 120, 240, 480, 720].contains(s.missedAfterMinutes) ? s.missedAfterMinutes : 240,
                underline: const SizedBox(),
                items: [for (final m in const [60, 120, 240, 480, 720]) DropdownMenuItem(value: m, child: Text('${m ~/ 60} h'))],
                onChanged: (v) => set(s.copyWith(missedAfterMinutes: v)),
              ),
            ),
            SwitchListTile(
              value: s.dailySummary,
              onChanged: (v) => set(s.copyWith(dailySummary: v), resched: true),
              title: const Text('Resumo diário'),
              subtitle: Text('Todos os dias às ${s.dailySummaryTime}'),
              secondary: IconButton(
                tooltip: 'Alterar horário do resumo',
                icon: const Icon(Icons.schedule_rounded),
                onPressed: () async {
                  final (h, m) = parseHm(s.dailySummaryTime);
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: h, minute: m));
                  if (t != null) set(s.copyWith(dailySummaryTime: hm(t.hour, t.minute)), resched: true);
                },
              ),
            ),
          ]),
        ),
        const SectionTitle('Dados'),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Privacidade e segurança'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup e restauração'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupScreen())),
            ),
            if (!s.demoData)
              ListTile(
                leading: const Icon(Icons.science_outlined),
                title: const Text('Carregar dados de demonstração'),
                subtitle: const Text('Cria um perfil "Demonstração" separado'),
                onTap: () async {
                  await app.loadDemo();
                  if (context.mounted) showSnack(context, 'Perfil de demonstração criado e ativado.');
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('Remover dados de demonstração'),
                onTap: () async {
                  await app.removeDemo();
                  if (context.mounted) showSnack(context, 'Dados de demonstração removidos.');
                },
              ),
          ]),
        ),
        const SizedBox(height: 20),
        Center(
          child: Text('Meu Remédio 1.0 • Não substitui orientação profissional.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
      ]),
    );
  }
}
