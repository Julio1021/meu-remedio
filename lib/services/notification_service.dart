import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/formatters.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../domain/schedule_engine.dart';
import 'dose_service.dart';

const actionTaken = 'taken';
const actionSnooze = 'snooze';
const actionPostpone = 'postpone';
const _categoryDose = 'dose';

/// Ponto de entrada para ações tocadas com o app fechado ou em segundo plano.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  // Isolate separado: inicializa formatação de datas (pt_BR) e fuso.
  await initializeDateFormatting('pt_BR');
  await NotificationService.instance.init(background: true);
  await NotificationService.instance.handleResponse(response);
}

class DosePayload {
  final int medId;
  final DateTime scheduledAt;
  const DosePayload(this.medId, this.scheduledAt);

  String encode() => jsonEncode({'t': 'dose', 'm': medId, 's': dtKey(scheduledAt)});

  static DosePayload? decode(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      if (m['t'] != 'dose') return null;
      return DosePayload(m['m'] as int, parseDtKey(m['s'] as String));
    } catch (_) {
      return null;
    }
  }
}

class _Planned {
  final int id;
  final DateTime at;
  final String title;
  final String body;
  final Medication med;
  final DosePayload payload;
  final bool withActions;
  _Planned(this.id, this.at, this.title, this.body, this.med, this.payload, {this.withActions = true});
}

class PermissionState {
  final bool notificationsEnabled;
  final bool exactAlarmsAllowed;
  const PermissionState(this.notificationsEnabled, this.exactAlarmsAllowed);
}

/// Notificações locais nativas com agendamento persistente.
///
/// Estratégia: mantém uma "janela" de lembretes já agendados no sistema
/// (7 dias no Android; no iOS, limitada a ~60 pendentes pelo sistema).
/// A janela é recalculada ao abrir o app, ao voltar do segundo plano, a cada
/// alteração de tratamento ou registro de dose e quando o fuso muda. O plugin
/// restaura os agendamentos após reiniciar o aparelho (Android).
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  String _tzName = 'America/Sao_Paulo';

  /// Último problema encontrado (exibido na Central de notificações).
  String? lastError;

  /// Quantidade de lembretes agendados na última reprogramação.
  int lastScheduledCount = 0;
  DateTime? lastRescheduleAt;

  /// Disparado quando uma ação da notificação alterou dados.
  final changes = StreamController<void>.broadcast();

  /// Disparado quando o usuário toca no corpo de uma notificação de dose.
  final taps = StreamController<DosePayload>.broadcast();

  static final _chDefault = AndroidNotificationChannel('doses_v1', 'Lembretes de doses',
      description: 'Horários dos medicamentos', importance: Importance.max);
  static final _chNoVib = AndroidNotificationChannel('doses_novib_v1', 'Lembretes de doses (sem vibração)',
      description: 'Horários dos medicamentos sem vibração', importance: Importance.max, enableVibration: false);
  static final _chSilent = AndroidNotificationChannel('doses_silent_v1', 'Lembretes discretos',
      description: 'Lembretes sem som', importance: Importance.high, playSound: false, enableVibration: false);
  static final _chAlerts = AndroidNotificationChannel('alerts_v1', 'Avisos de estoque e tratamento',
      description: 'Estoque baixo, vencimento e término de tratamento', importance: Importance.defaultImportance);
  static final _chSummary = AndroidNotificationChannel('summary_v1', 'Resumo diário',
      description: 'Resumo das doses do dia', importance: Importance.low);

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  Future<void> init({bool background = false}) async {
    tzdata.initializeTimeZones();
    await refreshTimeZone();
    if (_ready) return;

    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(_categoryDose, actions: [
          DarwinNotificationAction.plain(actionTaken, 'TOMADO'),
          DarwinNotificationAction.plain(actionSnooze, 'LEMBRAR MAIS TARDE'),
          DarwinNotificationAction.plain(actionPostpone, 'ADIAR'),
        ]),
      ],
    );
    Future<void> doInit(String icon) => plugin.initialize(
          InitializationSettings(android: AndroidInitializationSettings(icon), iOS: darwin),
          onDidReceiveNotificationResponse: background ? null : handleResponse,
          onDidReceiveBackgroundNotificationResponse: background ? null : notificationTapBackground,
        );
    try {
      await doInit('ic_stat_pill');
    } catch (e) {
      // Se o ícone próprio não estiver disponível, usa o ícone do app.
      lastError = 'Ícone de notificação indisponível ($e). Usando o ícone do app.';
      await doInit('@mipmap/ic_launcher');
    }
    final a = _android;
    if (a != null) {
      for (final ch in [_chDefault, _chNoVib, _chSilent, _chAlerts, _chSummary]) {
        await a.createNotificationChannel(ch);
      }
    }
    _ready = true;
  }

  /// Atualiza o fuso local. Retorna true se mudou.
  Future<bool> refreshTimeZone() async {
    String name;
    try {
      name = await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      name = _tzName;
    }
    final changed = name != _tzName;
    try {
      tz.setLocalLocation(tz.getLocation(name));
      _tzName = name;
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    }
    return changed;
  }

  /// Verifica se o app foi aberto pelo toque numa notificação.
  Future<DosePayload?> launchPayload() async {
    final d = await plugin.getNotificationAppLaunchDetails();
    if (d == null || !d.didNotificationLaunchApp) return null;
    final r = d.notificationResponse;
    if (r == null) return null;
    if (r.actionId != null && r.actionId!.isNotEmpty) return null;
    return DosePayload.decode(r.payload);
  }

  // ------------------------------------------------------------ permissões
  Future<PermissionState> permissionState() async {
    if (Platform.isAndroid) {
      final a = _android;
      final enabled = await a?.areNotificationsEnabled() ?? false;
      final exact = await a?.canScheduleExactNotifications() ?? true;
      return PermissionState(enabled, exact);
    }
    if (Platform.isIOS) {
      final opts = await _ios?.checkPermissions();
      return PermissionState(opts?.isEnabled ?? false, true);
    }
    return const PermissionState(false, false);
  }

  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      await _android?.requestNotificationsPermission();
      final exact = await _android?.canScheduleExactNotifications() ?? true;
      if (!exact) await _android?.requestExactAlarmsPermission();
    } else if (Platform.isIOS) {
      await _ios?.requestPermissions(alert: true, badge: true, sound: true);
    }
  }

  // ------------------------------------------------------------- respostas
  Future<void> handleResponse(NotificationResponse r) async {
    final p = DosePayload.decode(r.payload);
    if (p == null) return;
    final action = r.actionId ?? '';
    if (action.isEmpty) {
      taps.add(p);
      return;
    }
    final db = await AppDatabase.open();
    final s = await db.loadSettings();
    if (action == actionTaken) {
      final (_, alert) = await DoseService.confirmTaken(db, p.medId, p.scheduledAt, source: 'notificacao');
      await cancelDose(p.medId, p.scheduledAt);
      if (alert != null) await showStockAlert(alert, s);
    } else if (action == actionSnooze || action == actionPostpone) {
      final min = action == actionSnooze ? s.snoozeMinutes : s.postponeMinutes;
      final until = await DoseService.snooze(db, p.medId, p.scheduledAt, min, source: 'notificacao');
      await cancelDose(p.medId, p.scheduledAt);
      final med = await db.medication(p.medId);
      if (med != null) await scheduleSnooze(med, p.scheduledAt, until, s);
    }
    if (!changes.isClosed) changes.add(null);
  }

  // ------------------------------------------------------------------ ids
  static int _key(int medId, DateTime scheduledAt) {
    final minutes = DateTime.utc(scheduledAt.year, scheduledAt.month, scheduledAt.day, scheduledAt.hour, scheduledAt.minute)
            .millisecondsSinceEpoch ~/
        60000;
    return ((medId * 1000003) ^ minutes) & 0x00FFFFFF;
  }

  /// Slots: 0 principal, 1-3 repetições, 4 adiamento, 5 aviso antecipado.
  static int doseId(int medId, DateTime scheduledAt, int slot) => _key(medId, scheduledAt) * 8 + slot;

  static const _summaryId = 1400000000;
  static int _alertId(int medId, int kind) => 1500000000 + medId * 4 + kind; // 0 venc., 1 término, 2 estoque

  Future<void> cancelDose(int medId, DateTime scheduledAt) async {
    for (var slot = 0; slot < 6; slot++) {
      await plugin.cancel(doseId(medId, scheduledAt, slot));
    }
  }

  // ---------------------------------------------------------- detalhes
  NotificationDetails _doseDetails(Medication med, AppSettings s, String body, {bool actions = true}) {
    final ch = med.silent ? _chSilent : (s.vibration ? _chDefault : _chNoVib);
    return NotificationDetails(
      android: AndroidNotificationDetails(
        ch.id,
        ch.name,
        channelDescription: ch.description,
        importance: ch.importance,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        visibility: s.privacyMode ? NotificationVisibility.secret : NotificationVisibility.private,
        color: Color(med.color),
        styleInformation: BigTextStyleInformation(body),
        ticker: 'Lembrete de medicamento',
        actions: actions
            ? [
                AndroidNotificationAction(actionTaken, 'TOMADO', cancelNotification: true),
                AndroidNotificationAction(actionSnooze, 'LEMBRAR EM ${s.snoozeMinutes} MIN', cancelNotification: true),
                AndroidNotificationAction(actionPostpone, 'ADIAR', cancelNotification: true),
              ]
            : null,
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: actions ? _categoryDose : null,
        presentSound: !med.silent,
        interruptionLevel: InterruptionLevel.active,
      ),
    );
  }

  (String, String) _texts(Medication med, DateTime scheduledAt, AppSettings s, {String kind = 'main'}) {
    if (s.privacyMode) {
      final t = kind == 'repeat' ? 'Lembrete pendente' : 'Lembrete';
      return (t, 'Você tem um lembrete agendado para ${fmtTime(scheduledAt)}. Toque para ver.');
    }
    final title = switch (kind) {
      'repeat' => 'Dose ainda não registrada',
      'snooze' => 'Lembrete adiado: hora do seu medicamento',
      'advance' => 'Em breve: ${med.displayName}',
      _ => 'Hora do seu medicamento',
    };
    final lines = <String>[
      med.displayName,
      'Quantidade: ${med.doseDescription}',
      'Horário programado: ${fmtTime(scheduledAt)}',
      if (med.instructions != null && med.instructions!.trim().isNotEmpty) med.instructions!.trim(),
      if (med.foodNote != null && med.foodNote!.trim().isNotEmpty) med.foodNote!.trim(),
    ];
    return (title, lines.join('\n'));
  }

  bool _exact = true;

  /// Agenda uma notificação. Lembretes de dose usam o modo "despertador"
  /// (setAlarmClock), o mais confiável do Android mesmo com economia de
  /// bateria; os demais avisos usam alarme exato comum.
  Future<bool> _zoned(int id, DateTime at, String title, String body, NotificationDetails details,
      {String? payload, DateTimeComponents? match, bool alarm = false}) async {
    final when = tz.TZDateTime.from(at, tz.local);
    final mode = !_exact
        ? AndroidScheduleMode.inexactAllowWhileIdle
        : (alarm ? AndroidScheduleMode.alarmClock : AndroidScheduleMode.exactAllowWhileIdle);
    try {
      await plugin.zonedSchedule(id, title, body, when, details,
          androidScheduleMode: mode, payload: payload, matchDateTimeComponents: match);
      return true;
    } on PlatformException catch (e) {
      // Sem permissão de alarme exato: tenta o modo inexato.
      lastError = 'Alarme exato recusado pelo sistema (${e.code}). Os avisos podem atrasar.';
      _exact = false;
      try {
        await plugin.zonedSchedule(id, title, body, when, details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle, payload: payload, matchDateTimeComponents: match);
        return true;
      } catch (e2) {
        lastError = 'Falha ao agendar lembrete: $e2';
        return false;
      }
    } catch (e) {
      lastError = 'Falha ao agendar lembrete: $e';
      return false;
    }
  }

  /// Agenda um lembrete de teste para daqui a [minutes] minuto(s).
  Future<DateTime> scheduleTest({int minutes = 1}) async {
    final at = DateTime.now().add(Duration(minutes: minutes));
    final ch = _chDefault;
    await _zoned(
      1399999998,
      at,
      'Teste de lembrete agendado',
      'Se você está vendo esta mensagem, os lembretes agendados estão funcionando.',
      NotificationDetails(
        android: AndroidNotificationDetails(ch.id, ch.name,
            channelDescription: ch.description, importance: Importance.max, priority: Priority.high,
            category: AndroidNotificationCategory.reminder),
        iOS: const DarwinNotificationDetails(),
      ),
      alarm: true,
    );
    return at;
  }

  Future<void> scheduleSnooze(Medication med, DateTime scheduledAt, DateTime until, AppSettings s) async {
    final (title, body) = _texts(med, scheduledAt, s, kind: 'snooze');
    await _zoned(doseId(med.id!, scheduledAt, 4), until, title, body, _doseDetails(med, s, body),
        payload: DosePayload(med.id!, scheduledAt).encode(), alarm: true);
  }

  Future<void> showStockAlert(StockAlert a, AppSettings s) async {
    final name = s.privacyMode ? 'um medicamento' : a.med.displayName;
    final title = a.empty ? 'Estoque esgotado' : 'Estoque baixo';
    final body = a.empty
        ? 'O estoque de $name chegou a zero.'
        : 'Restam ${fmtQty(a.balance)} ${a.med.stockUnit} de $name.';
    await plugin.show(_alertId(a.med.id!, 2), title, body, _alertDetails());
  }

  NotificationDetails _alertDetails() => NotificationDetails(
        android: AndroidNotificationDetails(_chAlerts.id, _chAlerts.name, channelDescription: _chAlerts.description),
        iOS: const DarwinNotificationDetails(),
      );

  Future<void> showTest() async {
    await plugin.show(
      1399999999,
      'Notificações funcionando',
      'Este é um teste. Os lembretes de doses aparecerão assim.',
      _alertDetails(),
    );
  }

  Future<List<PendingNotificationRequest>> pending() => plugin.pendingNotificationRequests();

  // ---------------------------------------------------------- reagendamento
  bool _busy = false;
  bool _again = false;

  /// Recalcula todos os lembretes a partir do banco de dados.
  Future<void> rescheduleAll() async {
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      do {
        _again = false;
        await _rescheduleOnce();
      } while (_again);
    } finally {
      _busy = false;
    }
  }

  Future<void> _rescheduleOnce() async {
    final db = await AppDatabase.open();
    final s = await db.loadSettings();
    if (Platform.isAndroid) {
      _exact = await _android?.canScheduleExactNotifications() ?? true;
    }
    final meds = (await db.allMedications()).where((m) => m.status == MedStatus.active).toList();
    final schedules = await db.allSchedules();
    final now = DateTime.now();
    final windowDays = Platform.isIOS ? 2 : 7;
    final cap = Platform.isIOS ? 56 : 400;
    final from = now.subtract(const Duration(days: 1));
    final to = DateTime(now.year, now.month, now.day + windowDays + 1);
    final records = {
      for (final r in await db.allRecordsBetween(from, to)) '${r.medicationId}|${r.scheduledAt}': r,
    };

    final planned = <_Planned>[];
    for (final med in meds.where((m) => !m.isPrn)) {
      final occ = ScheduleEngine.occurrencesBetween(schedules[med.id] ?? const [], from, to);
      for (final t in occ) {
        final rec = records['${med.id}|${dtKey(t)}'];
        final payload = DosePayload(med.id!, t);
        if (rec != null) {
          if (rec.status == RecordStatus.snoozed && rec.snoozedUntil != null) {
            final until = parseDtKey(rec.snoozedUntil!);
            if (until.isAfter(now)) {
              final (title, body) = _texts(med, t, s, kind: 'snooze');
              planned.add(_Planned(doseId(med.id!, t, 4), until, title, body, med, payload));
            }
          }
          continue;
        }
        if (s.advanceMinutes > 0) {
          final a = t.subtract(Duration(minutes: s.advanceMinutes));
          if (a.isAfter(now)) {
            final (title, body) = _texts(med, t, s, kind: 'advance');
            planned.add(_Planned(doseId(med.id!, t, 5), a, title, body, med, payload));
          }
        }
        if (t.isAfter(now)) {
          final (title, body) = _texts(med, t, s);
          planned.add(_Planned(doseId(med.id!, t, 0), t, title, body, med, payload));
        }
        final repeats = s.maxRepeats.clamp(0, 3);
        for (var k = 1; k <= repeats; k++) {
          final rt = t.add(Duration(minutes: s.repeatEveryMinutes * k));
          if (rt.isAfter(now)) {
            final (title, body) = _texts(med, t, s, kind: 'repeat');
            planned.add(_Planned(doseId(med.id!, t, k), rt, title, body, med, payload));
          }
        }
      }
    }
    planned.sort((a, b) => a.at.compareTo(b.at));

    // Preserva o teste agendado, se houver.
    final pendingNow = await plugin.pendingNotificationRequests();
    for (final r in pendingNow) {
      if (r.id != 1399999998) await plugin.cancel(r.id);
    }
    var ok = 0;
    for (final p in planned.take(cap)) {
      final done = await _zoned(p.id, p.at, p.title, p.body, _doseDetails(p.med, s, p.body, actions: p.withActions),
          payload: p.payload.encode(), alarm: true);
      if (done) ok++;
    }
    lastScheduledCount = ok;
    lastRescheduleAt = DateTime.now();

    // Avisos de vencimento e de término de tratamento (09:00 local).
    for (final med in meds) {
      if (med.expiryDate != null) {
        final exp = parseDateKey(med.expiryDate!);
        final at = DateTime(exp.year, exp.month, exp.day - 7, 9);
        if (at.isAfter(now)) {
          final name = s.privacyMode ? 'Um medicamento' : med.displayName;
          await _zoned(_alertId(med.id!, 0), at, 'Medicamento próximo do vencimento',
              '$name vence em ${fmtDate(exp)}. Confira a embalagem.', _alertDetails());
        }
      }
      final list = schedules[med.id] ?? const <Schedule>[];
      final current = list.where((x) => x.effectiveTo == null).toList();
      if (current.isNotEmpty && current.last.endDate != null) {
        final end = parseDateKey(current.last.endDate!);
        final at = DateTime(end.year, end.month, end.day - 2, 9);
        if (at.isAfter(now)) {
          final name = s.privacyMode ? 'Um tratamento' : 'O tratamento com ${med.displayName}';
          await _zoned(_alertId(med.id!, 1), at, 'Tratamento próximo do encerramento',
              '$name termina em ${fmtDate(end)}.', _alertDetails());
        }
      }
    }

    if (s.dailySummary) {
      final (h, m) = parseHm(s.dailySummaryTime);
      var at = DateTime(now.year, now.month, now.day, h, m);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _zoned(
        _summaryId,
        at,
        'Resumo do dia',
        'Toque para ver os medicamentos programados para hoje.',
        NotificationDetails(
          android: AndroidNotificationDetails(_chSummary.id, _chSummary.name, channelDescription: _chSummary.description),
          iOS: const DarwinNotificationDetails(),
        ),
        match: DateTimeComponents.time,
      );
    }
  }
}
