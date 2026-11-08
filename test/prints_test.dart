// Gera imagens (prints) das principais telas com dados de demonstração.
// Executado no GitHub Actions com:
//   flutter test --update-goldens --dart-define=PRINTS=true --dart-define=FLUTTER_ROOT=$FLUTTER_ROOT test/prints_test.dart
// Sem PRINTS=true os testes são ignorados.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:meu_remedio/app.dart';
import 'package:meu_remedio/core/theme.dart';
import 'package:meu_remedio/data/database.dart';
import 'package:meu_remedio/data/models.dart';
import 'package:meu_remedio/data/settings.dart';
import 'package:meu_remedio/services/backup_service.dart';
import 'package:meu_remedio/services/dose_service.dart';
import 'package:meu_remedio/state/app_state.dart';
import 'package:meu_remedio/ui/screens/medication_detail_screen.dart';
import 'package:meu_remedio/ui/screens/medication_form_screen.dart';
import 'package:meu_remedio/ui/screens/notification_center_screen.dart';
import 'package:meu_remedio/ui/screens/onboarding_screen.dart';
import 'package:meu_remedio/ui/screens/prn_screen.dart';
import 'package:meu_remedio/ui/screens/reports_screen.dart';
import 'package:meu_remedio/ui/screens/settings_screen.dart';
import 'package:meu_remedio/ui/screens/stock_detail_screen.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _enabled = bool.fromEnvironment('PRINTS');
const _flutterRoot = String.fromEnvironment('FLUTTER_ROOT');

Future<void> _loadFonts() async {
  final dir = Directory('$_flutterRoot/bin/cache/artifacts/material_fonts');
  if (!dir.existsSync()) return;
  final roboto = FontLoader('Roboto');
  final icons = FontLoader('MaterialIcons');
  for (final f in dir.listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    final data = f.readAsBytes().then((b) => ByteData.view(b.buffer));
    if (name.startsWith('Roboto-') && name.endsWith('.ttf') && !name.contains('Italic')) roboto.addFont(data);
    if (name.startsWith('MaterialIcons')) icons.addFont(data);
  }
  await roboto.load();
  await icons.load();
}

var _dbCounter = 0;

Future<AppState> _makeState(WidgetTester tester) async {
  late AppState app;
  await tester.runAsync(() async {
    final path = '${Directory.systemTemp.path}/prints_${pid}_${_dbCounter++}.db';
    if (File(path).existsSync()) File(path).deleteSync();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, v) => AppDatabase.createSchema(d),
      ),
    );
    final adb = AppDatabase.forTesting(db);
    final profileId = await DemoData.create(adb);
    await adb.updateProfile(const Profile(name: 'Júlio César', relation: 'Eu', color: 0xFF0A5C5C).copyWith(id: profileId));
    await adb.insertProfile(const Profile(name: 'Mãe', relation: 'Mãe', color: 0xFFD24A86));
    await adb.saveSettings(AppSettings(onboardingDone: true, activeProfileId: profileId));
    // Primeira dose de hoje registrada, para mostrar situações diferentes.
    final meds = await adb.medications(profileId);
    final now = DateTime.now();
    final los = meds.firstWhere((m) => m.name == 'Losartana');
    final t = DateTime(now.year, now.month, now.day, 8);
    if (now.isAfter(t)) await DoseService.confirmTaken(adb, los.id!, t, takenAt: t.add(const Duration(minutes: 4)));
    app = AppState(testMode: true);
    await app.init();
  });
  return app;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump(const Duration(milliseconds: 120));
  }
}

Widget _wrap(AppState app, Widget home, {ThemeMode mode = ThemeMode.light, double textScale = 1}) =>
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: mode,
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );

Future<void> _shot(WidgetTester tester, String name, {double height = 844}) async {
  tester.view.physicalSize = Size(390 * 2.0, height * 2.0);
  tester.view.devicePixelRatio = 2.0;
  await _settle(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('prints/$name.png'));
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    await initializeDateFormatting('pt_BR');
    if (_enabled) await _loadFonts();
  });

  Future<void> tab(WidgetTester tester, String label) async {
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
    await _settle(tester);
  }

  testWidgets('01 início', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell()));
    await _shot(tester, '01-inicio', height: 1500);
  }, skip: !_enabled);

  testWidgets('02 início escuro', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell(), mode: ThemeMode.dark));
    await _shot(tester, '02-inicio-escuro', height: 1500);
  }, skip: !_enabled);

  testWidgets('03 início fonte grande', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell(), textScale: 1.3));
    await _shot(tester, '03-inicio-fonte-130', height: 1700);
  }, skip: !_enabled);

  testWidgets('04 remédios', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell()));
    await _settle(tester);
    await tab(tester, 'Remédios');
    await _shot(tester, '04-remedios');
  }, skip: !_enabled);

  testWidgets('05 agenda', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell()));
    await _settle(tester);
    await tab(tester, 'Agenda');
    await _shot(tester, '05-agenda');
  }, skip: !_enabled);

  testWidgets('06 histórico', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell()));
    await _settle(tester);
    await tab(tester, 'Histórico');
    await _shot(tester, '06-historico-calendario', height: 1300);
    await tester.tap(find.text('Registros'));
    await _shot(tester, '07-historico-registros');
  }, skip: !_enabled);

  testWidgets('08 perfil', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MainShell()));
    await _settle(tester);
    await tab(tester, 'Perfil');
    await _shot(tester, '08-perfil');
  }, skip: !_enabled);

  testWidgets('09 relatórios', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const ReportsScreen()));
    await _shot(tester, '09-relatorios', height: 1900);
  }, skip: !_enabled);

  testWidgets('10 cadastro', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const MedicationFormScreen()));
    await _shot(tester, '10-cadastro-1', height: 1300);
    await tester.enterText(find.byType(TextField).first, 'Metformina');
    await tester.tap(find.text('Continuar'));
    await _shot(tester, '11-cadastro-2-horarios', height: 1500);
    await tester.tap(find.text('Continuar'));
    await _shot(tester, '12-cadastro-3-estoque');
    await tester.tap(find.text('Continuar'));
    await _shot(tester, '13-cadastro-4-detalhes', height: 1300);
  }, skip: !_enabled);

  testWidgets('14 detalhes', (tester) async {
    final app = await _makeState(tester);
    final m = app.meds.firstWhere((m) => m.name == 'Losartana');
    await tester.pumpWidget(_wrap(app, MedicationDetailScreen(medId: m.id!)));
    await _shot(tester, '14-detalhes', height: 1600);
  }, skip: !_enabled);

  testWidgets('15 estoque', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const StockScreen()));
    await _shot(tester, '15-estoque');
    final m = app.meds.firstWhere((m) => m.name == 'Losartana');
    await tester.pumpWidget(_wrap(app, StockDetailScreen(medId: m.id!)));
    await _shot(tester, '16-estoque-detalhe');
  }, skip: !_enabled);

  testWidgets('17 uso eventual', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const PrnScreen()));
    await _shot(tester, '17-uso-eventual');
  }, skip: !_enabled);

  testWidgets('18 configurações', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const SettingsScreen()));
    await _shot(tester, '18-configuracoes', height: 1900);
  }, skip: !_enabled);

  testWidgets('19 notificações', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const NotificationCenterScreen()));
    await _shot(tester, '19-central-notificacoes', height: 1200);
  }, skip: !_enabled);

  testWidgets('20 apresentação', (tester) async {
    final app = await _makeState(tester);
    await tester.pumpWidget(_wrap(app, const OnboardingFlow()));
    await _shot(tester, '20-apresentacao');
  }, skip: !_enabled);
}
