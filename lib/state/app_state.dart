import 'dart:async';

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../data/database.dart';
import '../data/models.dart';
import '../data/settings.dart';
import '../domain/schedule_engine.dart';
import '../services/backup_service.dart';
import '../services/dose_service.dart';
import '../services/notification_service.dart';

/// Estado global do app. Mantém o perfil ativo, seus medicamentos e as doses
/// de hoje; todas as ações gravam no SQLite e reagendam as notificações.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState({this.testMode = false});

  /// Em testes (prints automáticos) não usa notificações nem temporizadores.
  final bool testMode;
  late AppDatabase db;
  final notifications = NotificationService.instance;

  bool ready = false;
  AppSettings settings = const AppSettings();
  List<Profile> profiles = [];
  Profile? activeProfile;
  List<Medication> meds = [];
  Map<int, List<Schedule>> schedules = {};
  List<DoseView> today = [];
  PermissionState? permissions;

  /// Chamado quando o usuário toca numa notificação de dose.
  void Function(DosePayload p)? onDoseTap;
  DosePayload? _pendingTap;

  Timer? _ticker;
  StreamSubscription<void>? _changesSub;
  StreamSubscription<DosePayload>? _tapSub;
  DateTime _lastDay = dayOnly(DateTime.now());

  StatusRules get rules =>
      StatusRules(lateAfterMin: settings.lateAfterMinutes, missedAfterMin: settings.missedAfterMinutes);

  Future<void> init() async {
    db = await AppDatabase.open();
    settings = await db.loadSettings();
    if (testMode) {
      await _loadProfiles();
      await refresh(reschedule: false);
      ready = true;
      notifyListeners();
      return;
    }
    try {
      await notifications.init();
    } catch (e, st) {
      notifications.lastError = 'Falha ao iniciar as notificações: $e';
      debugPrint('Falha ao iniciar notificações: $e\n$st');
    }
    _changesSub = notifications.changes.stream.listen((_) => refresh(reschedule: false));
    _tapSub = notifications.taps.stream.listen(_handleTap);
    await _loadProfiles();
    await refresh(reschedule: true);
    final launch = await notifications.launchPayload();
    if (launch != null) _pendingTap = launch;
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    ready = true;
    notifyListeners();
  }

  void _handleTap(DosePayload p) {
    if (onDoseTap != null) {
      onDoseTap!(p);
    } else {
      _pendingTap = p;
    }
  }

  /// Entrega um toque pendente (app aberto pela notificação).
  DosePayload? takePendingTap() {
    final p = _pendingTap;
    _pendingTap = null;
    return p;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      () async {
        await notifications.refreshTimeZone();
        settings = await db.loadSettings();
        await refresh(reschedule: true);
      }();
    }
  }

  void _tick() {
    final now = DateTime.now();
    if (dayOnly(now) != _lastDay) {
      _lastDay = dayOnly(now);
      refresh(reschedule: true);
      return;
    }
    _recomputeStatuses(now);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _changesSub?.cancel();
    _tapSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // --------------------------------------------------------------- perfis
  Future<void> _loadProfiles() async {
    profiles = await db.profiles();
    if (profiles.isEmpty) {
      activeProfile = null;
      return;
    }
    activeProfile = profiles.firstWhere((p) => p.id == settings.activeProfileId, orElse: () => profiles.first);
  }

  Future<Profile> addProfile(Profile p) async {
    final id = await db.insertProfile(p);
    await _loadProfiles();
    final created = profiles.firstWhere((x) => x.id == id);
    if (activeProfile == null) await switchProfile(created);
    notifyListeners();
    return created;
  }

  Future<void> updateProfile(Profile p) async {
    await db.updateProfile(p);
    await _loadProfiles();
    notifyListeners();
  }

  Future<void> deleteProfile(Profile p) async {
    await db.deleteProfile(p.id!);
    if (activeProfile?.id == p.id) {
      settings = settings.copyWith(activeProfileId: -1);
      await db.saveSettings(settings);
    }
    await _loadProfiles();
    await refresh(reschedule: true);
  }

  Future<void> switchProfile(Profile p) async {
    activeProfile = p;
    settings = settings.copyWith(activeProfileId: p.id);
    await db.saveSettings(settings);
    await refresh(reschedule: false);
  }

  // ---------------------------------------------------------- atualização
  Future<void> refresh({bool reschedule = true}) async {
    if (activeProfile != null) {
      meds = await db.medications(activeProfile!.id!);
      schedules = await db.schedulesForProfile(activeProfile!.id!);
      final now = DateTime.now();
      final start = dayOnly(now);
      today = await dosesBetween(start, start.add(const Duration(days: 1)));
      _recomputeStatuses(now);
    } else {
      meds = [];
      schedules = {};
      today = [];
    }
    notifyListeners();
    if (reschedule && !testMode) {
      try {
        await notifications.rescheduleAll();
        permissions = await notifications.permissionState();
        notifyListeners();
      } catch (e, st) {
        notifications.lastError = 'Falha ao programar lembretes: $e';
        debugPrint('Falha ao reagendar: $e\n$st');
      }
    }
  }

  void _recomputeStatuses(DateTime now) {
    var nextMarked = false;
    for (final d in today) {
      d.status = rules.derive(d.scheduledAt, d.record, now);
      if (!nextMarked && d.status == DoseStatus.pending && !d.med.isPrn) {
        d.status = DoseStatus.next;
        nextMarked = true;
      }
    }
  }

  /// Doses (programadas + registradas) do perfil no intervalo [from, to).
  Future<List<DoseView>> dosesBetween(DateTime from, DateTime to, {int? profileId, bool includePrn = false}) async {
    final pid = profileId ?? activeProfile?.id;
    if (pid == null) return [];
    final isActive = pid == activeProfile?.id;
    final ms = isActive ? meds : await db.medications(pid);
    final sc = isActive ? schedules : await db.schedulesForProfile(pid);
    final recs = await db.recordsBetween(pid, from, to);
    final recMap = {for (final r in recs) '${r.medicationId}|${r.scheduledAt}': r};
    final medMap = {for (final m in ms) m.id!: m};
    final now = DateTime.now();
    final out = <DoseView>[];
    final seen = <String>{};
    for (final m in ms.where((m) => !m.isPrn)) {
      for (final t in ScheduleEngine.occurrencesBetween(sc[m.id] ?? const [], from, to)) {
        final key = '${m.id}|${dtKey(t)}';
        seen.add(key);
        final rec = recMap[key];
        out.add(DoseView(med: m, scheduledAt: t, record: rec, status: rules.derive(t, rec, now)));
      }
    }
    for (final r in recs) {
      final key = '${r.medicationId}|${r.scheduledAt}';
      if (seen.contains(key)) continue;
      final m = medMap[r.medicationId];
      if (m == null) continue;
      if (m.isPrn && !includePrn) continue;
      final t = parseDtKey(r.scheduledAt);
      out.add(DoseView(med: m, scheduledAt: t, record: r, status: rules.derive(t, r, now)));
    }
    out.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return out;
  }

  DoseView? get nextDose {
    for (final d in today) {
      if (d.status == DoseStatus.late || d.status == DoseStatus.snoozed || d.status == DoseStatus.next || d.status == DoseStatus.pending) {
        return d;
      }
    }
    return null;
  }

  Medication? medById(int id) {
    for (final m in meds) {
      if (m.id == id) return m;
    }
    return null;
  }

  Schedule? currentSchedule(int medId) {
    final list = schedules[medId] ?? const <Schedule>[];
    for (final s in list.reversed) {
      if (s.effectiveTo == null) return s;
    }
    return list.isEmpty ? null : list.last;
  }

  // ------------------------------------------------------------ doses
  Future<ConfirmResult> takeDose(int medId, DateTime scheduledAt, {DateTime? at}) async {
    final (res, alert) = await DoseService.confirmTaken(db, medId, scheduledAt, takenAt: at);
    await notifications.cancelDose(medId, scheduledAt);
    if (alert != null) await notifications.showStockAlert(alert, settings);
    await refresh(reschedule: true);
    return res;
  }

  Future<void> skipDose(int medId, DateTime scheduledAt) async {
    await DoseService.markSkipped(db, medId, scheduledAt);
    await notifications.cancelDose(medId, scheduledAt);
    await refresh(reschedule: true);
  }

  Future<void> cancelDose(int medId, DateTime scheduledAt) async {
    await DoseService.markCancelled(db, medId, scheduledAt);
    await notifications.cancelDose(medId, scheduledAt);
    await refresh(reschedule: true);
  }

  Future<DateTime> snoozeDose(int medId, DateTime scheduledAt, int minutes) async {
    final until = await DoseService.snooze(db, medId, scheduledAt, minutes);
    await refresh(reschedule: true);
    return until;
  }

  Future<void> undoDose(int medId, DateTime scheduledAt) async {
    await DoseService.undo(db, medId, scheduledAt);
    await refresh(reschedule: true);
  }

  Future<(ConfirmResult, StockAlert?)> logPrn(int medId, DateTime at) async {
    final r = await DoseService.logPrnUse(db, medId, at);
    if (r.$2 != null) await notifications.showStockAlert(r.$2!, settings);
    await refresh(reschedule: false);
    return r;
  }

  // ------------------------------------------------------- medicamentos
  Future<int> addMedication(Medication m, Schedule? s) async {
    final id = await db.insertMedication(m, s);
    await refresh(reschedule: true);
    await _notifyJustDue(id);
    return id;
  }

  Future<void> updateMedication(Medication m, Schedule? s) async {
    await db.updateMedication(m, s);
    await refresh(reschedule: true);
    await _notifyJustDue(m.id!);
  }

  /// Se um horário do remédio recém-salvo já chegou (até 15 min atrás) e
  /// ainda não tem registro, avisa na hora em vez de esperar a repetição.
  Future<void> _notifyJustDue(int medId) async {
    if (testMode) return;
    final now = DateTime.now();
    for (final d in today.where((d) => d.med.id == medId && d.record == null)) {
      final age = now.difference(d.scheduledAt);
      if (!age.isNegative && age.inMinutes <= 15) {
        try {
          await notifications.showDueNow(d.med, d.scheduledAt, settings);
        } catch (_) {}
      }
    }
  }

  Future<void> setMedStatus(int id, MedStatus st) async {
    await db.setMedicationStatus(id, st);
    await refresh(reschedule: true);
  }

  Future<void> toggleFavorite(Medication m) async {
    await db.setFavorite(m.id!, !m.favorite);
    await refresh(reschedule: false);
  }

  Future<void> deleteMedication(int id) async {
    await db.deleteMedication(id);
    await refresh(reschedule: true);
  }

  Future<void> stockMove(int medId, StockMoveType type, double delta, {String? note}) async {
    await db.addStockMovement(medId, type, delta, note: note);
    await refresh(reschedule: false);
  }

  Future<void> stockSet(int medId, double balance, {String? note}) async {
    await db.setStockBalance(medId, balance, note: note);
    await refresh(reschedule: false);
  }

  // ----------------------------------------------------------- ajustes
  Future<void> updateSettings(AppSettings s, {bool reschedule = false}) async {
    settings = s;
    await db.saveSettings(s);
    notifyListeners();
    if (reschedule) await refresh(reschedule: true);
  }

  Future<void> requestPermissions() async {
    await notifications.requestPermissions();
    permissions = await notifications.permissionState();
    await notifications.rescheduleAll();
    notifyListeners();
  }

  Future<void> loadDemo() async {
    final pid = await DemoData.create(db);
    settings = settings.copyWith(demoData: true, activeProfileId: pid);
    await db.saveSettings(settings);
    await _loadProfiles();
    await refresh(reschedule: true);
  }

  Future<void> removeDemo() async {
    await DemoData.remove(db);
    settings = settings.copyWith(demoData: false);
    await db.saveSettings(settings);
    await _loadProfiles();
    await refresh(reschedule: true);
  }

  Future<void> reloadAll() async {
    settings = await db.loadSettings();
    await _loadProfiles();
    await refresh(reschedule: true);
  }

  Future<void> wipeEverything() async {
    await db.wipeAll();
    await notifications.plugin.cancelAll();
    settings = const AppSettings();
    await db.saveSettings(settings);
    await _loadProfiles();
    await refresh(reschedule: false);
  }
}
