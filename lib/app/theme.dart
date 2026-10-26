import 'package:flutter/material.dart';

/// Grimoire's default dark palette (the web app's `--p-*` tokens).
abstract final class GrimoireColors {
  static const bgDeep = Color(0xFF0D0B0A);
  static const panel = Color(0xFF1A1614);
  static const card = Color(0xFF231F1B);
  static const cardHover = Color(0xFF2D2721);
  static const input = Color(0xFF151210);
  static const border = Color(0xFF3A322A);
  static const accent = Color(0xFFC9A84C);
  static const accentBright = Color(0xFFE8C95A);
  static const onAccent = Color(0xFF1A1209);
  static const text = Color(0xFFE8E0D4);
  static const textDim = Color(0xFFB8AB9B);
  static const textMuted = Color(0xFF968879);
  static const danger = Color(0xFFE07070);
}

ThemeData grimoireTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: GrimoireColors.accent,
    onPrimary: GrimoireColors.onAccent,
    primaryContainer: Color(0xFF3B3120),
    onPrimaryContainer: GrimoireColors.accentBright,
    secondary: Color(0xFFD4913A),
    onSecondary: GrimoireColors.onAccent,
    error: GrimoireColors.danger,
    onError: Color(0xFF1A0A08),
    errorContainer: Color(0xFF5A2620),
    onErrorContainer: Color(0xFFFDF6F4),
    surface: GrimoireColors.bgDeep,
    onSurface: GrimoireColors.text,
    onSurfaceVariant: GrimoireColors.textDim,
    surfaceContainerLowest: GrimoireColors.bgDeep,
    surfaceContainerLow: Color(0xFF141110),
    surfaceContainer: GrimoireColors.panel,
    surfaceContainerHigh: GrimoireColors.card,
    surfaceContainerHighest: GrimoireColors.cardHover,
    outline: GrimoireColors.border,
    outlineVariant: Color(0xFF2A241F),
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: GrimoireColors.bgDeep,
    appBarTheme: const AppBarTheme(
      backgroundColor: GrimoireColors.bgDeep,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GrimoireColors.panel,
      indicatorColor: scheme.primaryContainer,
      labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelSmall),
    ),
    cardTheme: const CardThemeData(
      color: GrimoireColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: GrimoireColors.input,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: GrimoireColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: GrimoireColors.border),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    textTheme: base.textTheme.apply(
      bodyColor: GrimoireColors.text,
      displayColor: GrimoireColors.text,
    ),
  );
}
