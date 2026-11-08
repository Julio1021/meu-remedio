import 'package:flutter/material.dart';

/// Preferências do aplicativo, gravadas na tabela `settings` do SQLite para
/// que o tratador de notificações em segundo plano também consiga lê-las.
class AppSettings {
  final ThemeMode themeMode;
  final double textScale;
  final bool reduceMotion;
  final bool privacyMode; // notificações sem nome do medicamento
  final bool vibration;
  final int snoozeMinutes; // "Lembrar em X min"
  final int postponeMinutes; // "Adiar"
  final int repeatEveryMinutes; // repetição quando não há resposta
  final int maxRepeats;
  final int advanceMinutes; // aviso antecipado (0 = desligado)
  final int lateAfterMinutes;
  final int missedAfterMinutes;
  final bool dailySummary;
  final String dailySummaryTime; // HH:mm
  final bool onboardingDone;
  final int? activeProfileId;
  final bool demoData;

  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.textScale = 1.0,
    this.reduceMotion = false,
    this.privacyMode = false,
    this.vibration = true,
    this.snoozeMinutes = 10,
    this.postponeMinutes = 30,
    this.repeatEveryMinutes = 10,
    this.maxRepeats = 2,
    this.advanceMinutes = 0,
    this.lateAfterMinutes = 15,
    this.missedAfterMinutes = 240,
    this.dailySummary = false,
    this.dailySummaryTime = '07:00',
    this.onboardingDone = false,
    this.activeProfileId,
    this.demoData = false,
  });

  AppSettings copyWith({
    ThemeMode? themeMode,
    double? textScale,
    bool? reduceMotion,
    bool? privacyMode,
    bool? vibration,
    int? snoozeMinutes,
    int? postponeMinutes,
    int? repeatEveryMinutes,
    int? maxRepeats,
    int? advanceMinutes,
    int? lateAfterMinutes,
    int? missedAfterMinutes,
    bool? dailySummary,
    String? dailySummaryTime,
    bool? onboardingDone,
    int? activeProfileId,
    bool? demoData,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        textScale: textScale ?? this.textScale,
        reduceMotion: reduceMotion ?? this.reduceMotion,
        privacyMode: privacyMode ?? this.privacyMode,
        vibration: vibration ?? this.vibration,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        postponeMinutes: postponeMinutes ?? this.postponeMinutes,
        repeatEveryMinutes: repeatEveryMinutes ?? this.repeatEveryMinutes,
        maxRepeats: maxRepeats ?? this.maxRepeats,
        advanceMinutes: advanceMinutes ?? this.advanceMinutes,
        lateAfterMinutes: lateAfterMinutes ?? this.lateAfterMinutes,
        missedAfterMinutes: missedAfterMinutes ?? this.missedAfterMinutes,
        dailySummary: dailySummary ?? this.dailySummary,
        dailySummaryTime: dailySummaryTime ?? this.dailySummaryTime,
        onboardingDone: onboardingDone ?? this.onboardingDone,
        activeProfileId: activeProfileId ?? this.activeProfileId,
        demoData: demoData ?? this.demoData,
      );

  Map<String, String> toKv() => {
        'themeMode': themeMode.name,
        'textScale': '$textScale',
        'reduceMotion': '$reduceMotion',
        'privacyMode': '$privacyMode',
        'vibration': '$vibration',
        'snoozeMinutes': '$snoozeMinutes',
        'postponeMinutes': '$postponeMinutes',
        'repeatEveryMinutes': '$repeatEveryMinutes',
        'maxRepeats': '$maxRepeats',
        'advanceMinutes': '$advanceMinutes',
        'lateAfterMinutes': '$lateAfterMinutes',
        'missedAfterMinutes': '$missedAfterMinutes',
        'dailySummary': '$dailySummary',
        'dailySummaryTime': dailySummaryTime,
        'onboardingDone': '$onboardingDone',
        'activeProfileId': activeProfileId?.toString() ?? '',
        'demoData': '$demoData',
      };

  factory AppSettings.fromKv(Map<String, String> kv) {
    const d = AppSettings();
    bool b(String k, bool def) => kv[k] == null ? def : kv[k] == 'true';
    int i(String k, int def) => int.tryParse(kv[k] ?? '') ?? def;
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((t) => t.name == kv['themeMode'], orElse: () => d.themeMode),
      textScale: double.tryParse(kv['textScale'] ?? '') ?? d.textScale,
      reduceMotion: b('reduceMotion', d.reduceMotion),
      privacyMode: b('privacyMode', d.privacyMode),
      vibration: b('vibration', d.vibration),
      snoozeMinutes: i('snoozeMinutes', d.snoozeMinutes),
      postponeMinutes: i('postponeMinutes', d.postponeMinutes),
      repeatEveryMinutes: i('repeatEveryMinutes', d.repeatEveryMinutes),
      maxRepeats: i('maxRepeats', d.maxRepeats),
      advanceMinutes: i('advanceMinutes', d.advanceMinutes),
      lateAfterMinutes: i('lateAfterMinutes', d.lateAfterMinutes),
      missedAfterMinutes: i('missedAfterMinutes', d.missedAfterMinutes),
      dailySummary: b('dailySummary', d.dailySummary),
      dailySummaryTime: kv['dailySummaryTime'] ?? d.dailySummaryTime,
      onboardingDone: b('onboardingDone', d.onboardingDone),
      activeProfileId: int.tryParse(kv['activeProfileId'] ?? ''),
      demoData: b('demoData', d.demoData),
    );
  }
}
