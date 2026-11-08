import 'package:flutter/material.dart';

import '../domain/schedule_engine.dart';

class AppColors {
  // Identidade: verde‑petróleo profundo com acento turquesa.
  static const primary = Color(0xFF0A5C5C);
  static const primaryDark = Color(0xFF063F40);
  static const accent = Color(0xFF12A39A);
  static const info = Color(0xFF2F6FD6);
  static const success = Color(0xFF1B9A57);
  static const pending = Color(0xFFEA8A00);
  static const danger = Color(0xFFD64040);
  static const neutral = Color(0xFF7A878C);
  static const lightBg = Color(0xFFE9F0EF);
  static const darkBg = Color(0xFF0C1414);
  static const darkSurface = Color(0xFF162222);

  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF063F40), Color(0xFF0A5C5C), Color(0xFF12857F)],
  );

  static const medPalette = <int>[
    0xFF0A5C5C,
    0xFF2F6FD6,
    0xFF7B4FC4,
    0xFFD0503C,
    0xFFE5A100,
    0xFF1B9A57,
    0xFFD24A86,
    0xFF4E5D66,
  ];

  static Color forStatus(DoseStatus s) => switch (s) {
        DoseStatus.taken => success,
        DoseStatus.pending => info,
        DoseStatus.next => accent,
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
  final light = brightness == Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
    primary: light ? AppColors.primary : const Color(0xFF5FD3C8),
    onPrimary: light ? Colors.white : const Color(0xFF00201E),
    secondary: AppColors.accent,
    surface: light ? Colors.white : AppColors.darkSurface,
    onSurface: light ? const Color(0xFF13201F) : const Color(0xFFE3ECEB),
    onSurfaceVariant: light ? const Color(0xFF4F5F5E) : const Color(0xFFA6B6B4),
    outlineVariant: light ? const Color(0xFFD3DEDC) : const Color(0xFF2A3A39),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: brightness);
  final text = base.textTheme.apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor: light ? AppColors.lightBg : AppColors.darkBg,
    appBarTheme: AppBarTheme(
      backgroundColor: light ? AppColors.lightBg : AppColors.darkBg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: scheme.onSurface),
      foregroundColor: scheme.onSurface,
    ),
    cardTheme: CardThemeData(
      elevation: light ? 1.5 : 0,
      shadowColor: AppColors.primaryDark.withValues(alpha: 0.18),
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: light ? BorderSide.none : BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 52),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: light ? AppColors.accent : scheme.primary,
      foregroundColor: light ? Colors.white : scheme.onPrimary,
      elevation: 3,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: light ? Colors.white : const Color(0xFF1C2A2A),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.primary, width: 2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      selectedColor: scheme.primary.withValues(alpha: light ? 0.16 : 0.32),
      checkmarkColor: scheme.primary,
      labelStyle: WidgetStateTextStyle.resolveWith((st) => TextStyle(
            fontWeight: st.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: st.contains(WidgetState.selected) ? scheme.primary : scheme.onSurface,
          )),
      side: WidgetStateBorderSide.resolveWith((st) =>
          BorderSide(color: st.contains(WidgetState.selected) ? scheme.primary : scheme.outlineVariant)),
      backgroundColor: scheme.surface,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurface),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w700)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 70,
      elevation: 3,
      shadowColor: Colors.black26,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary,
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? scheme.onPrimary : scheme.onSurfaceVariant)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 12,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
          )),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: scheme.primary,
      unselectedLabelColor: scheme.onSurfaceVariant,
      indicatorColor: scheme.primary,
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2)),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: light ? AppColors.primaryDark : const Color(0xFF2B3B3A),
      contentTextStyle: const TextStyle(color: Colors.white),
      actionTextColor: const Color(0xFF7FE6DC),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
