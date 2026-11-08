import 'package:flutter/material.dart';

import '../domain/schedule_engine.dart';

class AppColors {
  static const primary = Color(0xFF0F6E6E); // verde-petróleo
  static const info = Color(0xFF4F7CAC); // azul suave
  static const success = Color(0xFF2E8B57);
  static const pending = Color(0xFFE08A1E);
  static const danger = Color(0xFFC0392B);
  static const neutral = Color(0xFF8A9499);
  static const lightBg = Color(0xFFF6F8F7);

  static const medPalette = <int>[
    0xFF0F6E6E,
    0xFF4F7CAC,
    0xFF7A5BA6,
    0xFFB55A4A,
    0xFFE0A030,
    0xFF3F8F5A,
    0xFFC2577F,
    0xFF5C6B73,
  ];

  static Color forStatus(DoseStatus s) => switch (s) {
        DoseStatus.taken => success,
        DoseStatus.pending => neutral,
        DoseStatus.next => primary,
        DoseStatus.snoozed => pending,
        DoseStatus.late => pending,
        DoseStatus.missed => danger,
        DoseStatus.skipped => danger,
        DoseStatus.cancelled => neutral,
      };

  static IconData iconForStatus(DoseStatus s) => switch (s) {
        DoseStatus.taken => Icons.check_circle_rounded,
        DoseStatus.pending => Icons.schedule_rounded,
        DoseStatus.next => Icons.notifications_active_rounded,
        DoseStatus.snoozed => Icons.snooze_rounded,
        DoseStatus.late => Icons.error_outline_rounded,
        DoseStatus.missed => Icons.help_outline_rounded,
        DoseStatus.skipped => Icons.do_not_disturb_on_outlined,
        DoseStatus.cancelled => Icons.block_rounded,
      };
}

IconData iconForForm(String form) => switch (form) {
      'Comprimido' => Icons.medication_rounded,
      'Cápsula' => Icons.medication_liquid_rounded,
      'Gotas' => Icons.water_drop_rounded,
      'Solução' || 'Xarope' => Icons.local_drink_rounded,
      'Pomada' => Icons.healing_rounded,
      'Spray' || 'Inalador' => Icons.air_rounded,
      'Injetável' => Icons.vaccines_rounded,
      'Adesivo' => Icons.crop_square_rounded,
      _ => Icons.medical_services_rounded,
    };

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
    primary: brightness == Brightness.light ? AppColors.primary : const Color(0xFF7FCFCB),
    surface: brightness == Brightness.light ? Colors.white : const Color(0xFF151A1A),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final radius = BorderRadius.circular(20);
  return base.copyWith(
    scaffoldBackgroundColor: brightness == Brightness.light ? AppColors.lightBg : const Color(0xFF0E1212),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: scheme.onSurface),
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: brightness == Brightness.light ? const Color(0xFFF1F4F3) : const Color(0xFF1E2525),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    chipTheme: base.chipTheme.copyWith(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    navigationBarTheme: NavigationBarThemeData(
      height: 72,
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2)),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
