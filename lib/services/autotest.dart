import 'package:flutter/foundation.dart';

import '../core/formatters.dart';
import '../data/models.dart';
import '../state/app_state.dart';

/// Autoteste usado somente em builds de diagnóstico
/// (`--dart-define=AUTOTEST=true`), executado num emulador no GitHub Actions.
class AutoTest {
  static const enabled = bool.fromEnvironment('AUTOTEST');

  static void log(String s) => debugPrint('AUTOTEST $s');

  static Future<void> run(AppState app) async {
    try {
      log('inicio');
      if (app.activeProfile == null) {
        final p = await app.addProfile(const Profile(name: 'Teste'));
        await app.switchProfile(p);
      }
      await app.updateSettings(app.settings.copyWith(onboardingDone: true));
      final perm = await app.notifications.permissionState();
      log('permissoes notif=${perm.notificationsEnabled} exato=${perm.exactAlarmsAllowed}');
      final now = DateTime.now();
      final t = now.add(const Duration(minutes: 2));
      await app.addMedication(
        Medication(profileId: app.activeProfile!.id!, name: 'Remedio Teste', strength: '10 mg'),
        Schedule(medicationId: 0, times: [hm(t.hour, t.minute)], startDate: dateKey(now), effectiveFrom: '${dateKey(now)}T00:00'),
      );
      log('remedio criado para ${hm(t.hour, t.minute)}');
      await app.notifications.showTest();
      log('showTest ok');
      final at = await app.notifications.scheduleTest(minutes: 1);
      log('scheduleTest para ${fmtTime(at)}');
      await app.notifications.rescheduleAll();
      final pend = await app.notifications.pending();
      log('pendentes=${pend.length} agendados=${app.notifications.lastScheduledCount}');
      for (final p in pend.take(10)) {
        log('  id=${p.id} titulo=${p.title}');
      }
      log('ultimoErro=${app.notifications.lastError}');
    } catch (e, st) {
      log('ERRO $e\n$st');
    }
  }
}
