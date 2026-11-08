import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme.dart';
import 'domain/schedule_engine.dart';
import 'services/notification_service.dart';
import 'state/app_state.dart';
import 'ui/screens/agenda_screen.dart';
import 'ui/screens/history_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/medication_form_screen.dart';
import 'ui/screens/medications_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/profile_hub_screen.dart';
import 'ui/widgets/common.dart';

final navigatorKey = GlobalKey<NavigatorState>();

class MeuRemedioApp extends StatelessWidget {
  const MeuRemedioApp({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Meu Remédio',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: s.themeMode,
      themeAnimationDuration: s.reduceMotion ? Duration.zero : const Duration(milliseconds: 250),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // Respeita a fonte do sistema e aplica o ajuste do app por cima.
        final system = mq.textScaler.scale(1);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear((system * s.textScale).clamp(0.8, 2.0)),
            disableAnimations: s.reduceMotion || mq.disableAnimations,
          ),
          child: child!,
        );
      },
      home: const RootGate(),
    );
  }
}

class RootGate extends StatelessWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.ready) return const SplashScreen();
    if (!app.settings.onboardingDone || app.activeProfile == null) return const OnboardingFlow();
    return const MainShell();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(32)),
            child: const Icon(Icons.medication_rounded, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 20),
          const Text('Meu Remédio',
              style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
          const SizedBox(height: 6),
          Text('Seu cuidado, no horário certo.', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85))),
          const SizedBox(height: 32),
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
        ]),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    final app = _app = context.read<AppState>();
    app.onDoseTap = _openDose;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = app.takePendingTap();
      if (p != null) _openDose(p);
    });
  }

  @override
  void dispose() {
    _app.onDoseTap = null;
    super.dispose();
  }

  Future<void> _openDose(DosePayload p) async {
    final app = context.read<AppState>();
    await app.refresh(reschedule: false);
    final med = app.medById(p.medId);
    final ctx = navigatorKey.currentContext;
    if (med == null || ctx == null || !ctx.mounted) return;
    setState(() => _index = 0);
    final views = await app.dosesBetween(p.scheduledAt, p.scheduledAt.add(const Duration(minutes: 1)));
    final view = views.where((v) => v.med.id == med.id).firstOrNull ??
        DoseView(med: med, scheduledAt: p.scheduledAt, record: null, status: DoseStatus.late);
    if (ctx.mounted) await showDoseSheet(ctx, view);
  }

  void _add() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MedicationFormScreen()));

  @override
  Widget build(BuildContext context) {
    const pages = [HomeScreen(), MedicationsScreen(), AgendaScreen(), HistoryScreen(), ProfileHubScreen()];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      floatingActionButton: _index <= 2
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Novo remédio'),
              tooltip: 'Adicionar medicamento',
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Início'),
          NavigationDestination(icon: Icon(Icons.medication_outlined), selectedIcon: Icon(Icons.medication_rounded), label: 'Remédios'),
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today_rounded), label: 'Agenda'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Histórico'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Perfil'),
        ],
      ),
    );
  }
}
