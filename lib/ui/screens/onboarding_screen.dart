import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import 'permissions_screen.dart';

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final _pc = PageController();
  int _page = 0;
  final _name = TextEditingController();
  bool _demo = false;
  bool _saving = false;

  static const _intro = [
    (Icons.notifications_active_rounded, 'Lembretes que funcionam',
        'Receba o aviso no horário certo e registre a dose direto na notificação, sem abrir o app.'),
    (Icons.fact_check_rounded, 'Tudo registrado',
        'Veja o que foi tomado, adiado ou ficou sem registro. Histórico, calendário e relatórios em PDF.'),
    (Icons.inventory_2_rounded, 'Estoque sob controle',
        'Saiba quantas unidades restam e quando será preciso comprar mais. Funciona sem internet.'),
  ];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    if (app.activeProfile != null) _name.text = app.activeProfile!.name;
  }

  @override
  void dispose() {
    _pc.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(int p) {
    final app = context.read<AppState>();
    if (app.settings.reduceMotion) {
      _pc.jumpToPage(p);
    } else {
      _pc.animateToPage(p, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    }
  }

  Future<void> _saveProfile() async {
    final n = _name.text.trim();
    if (n.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe como devemos chamar você.')));
      return;
    }
    setState(() => _saving = true);
    final app = context.read<AppState>();
    if (app.activeProfile == null) {
      final p = await app.addProfile(Profile(name: n, relation: 'Eu'));
      await app.switchProfile(p);
    } else {
      await app.updateProfile(app.activeProfile!.copyWith(name: n));
    }
    if (_demo && !app.settings.demoData) {
      final mine = app.activeProfile!;
      await app.loadDemo();
      await app.switchProfile(mine);
    }
    setState(() => _saving = false);
    _go(_intro.length + 1);
  }

  Future<void> _finish() async {
    final app = context.read<AppState>();
    // Garante o pedido de permissão mesmo se o botão não foi tocado.
    if (!(app.permissions?.notificationsEnabled ?? false)) {
      try {
        await app.requestPermissions();
      } catch (_) {}
    }
    await app.updateSettings(app.settings.copyWith(onboardingDone: true), reschedule: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _intro.length + 2;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(children: [
              for (var i = 0; i < total; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: i <= _page ? cs.primary : cs.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: PageView(
              controller: _pc,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (p) => setState(() => _page = p),
              children: [
                for (final (icon, title, text) in _intro)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(icon, size: 72, color: cs.primary),
                      ),
                      const SizedBox(height: 36),
                      Text(title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 14),
                      Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: cs.onSurfaceVariant, height: 1.4)),
                    ]),
                  ),
                ListView(padding: const EdgeInsets.all(28), children: [
                  const SizedBox(height: 24),
                  Text('Como podemos chamar você?',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text('Este será o seu perfil. Depois você pode adicionar familiares.',
                      style: TextStyle(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Seu nome', prefixIcon: Icon(Icons.person_rounded)),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _demo,
                    onChanged: (v) => setState(() => _demo = v),
                    title: const Text('Incluir perfil de demonstração'),
                    subtitle: const Text('Dados fictícios em um perfil separado, para conhecer o app. Podem ser removidos depois.'),
                  ),
                ]),
                const PermissionsBody(),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Row(children: [
              if (_page > 0)
                TextButton(onPressed: () => _go(_page - 1), child: const Text('Voltar'))
              else
                TextButton(onPressed: () => _go(_intro.length), child: const Text('Pular')),
              const Spacer(),
              FilledButton(
                onPressed: _saving
                    ? null
                    : () {
                        if (_page < _intro.length) {
                          _go(_page + 1);
                        } else if (_page == _intro.length) {
                          _saveProfile();
                        } else {
                          _finish();
                        }
                      },
                child: Text(_page == total - 1 ? 'Começar' : 'Continuar'),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
