import 'package:flutter/material.dart';

const forest = Color(0xFF315943);
const coral = Color(0xFFDF815D);
const paper = Color(0xFFF5F4EC);
const ink = Color(0xFF24352D);

ThemeData appTheme({Brightness brightness = Brightness.light}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: dark ? const Color(0xFF9DD29C) : forest,
    brightness: brightness,
    surface: dark ? const Color(0xFF141D1A) : paper,
  ).copyWith(
    primary: dark ? const Color(0xFF9DD29C) : forest,
    onPrimary: dark ? const Color(0xFF122016) : Colors.white,
    surface: dark ? const Color(0xFF101A16) : paper,
    onSurface: dark ? const Color(0xFFEDF3ED) : ink,
    onSurfaceVariant: dark ? const Color(0xFFA2B1A6) : const Color(0xFF718078),
    outline: dark ? const Color(0xFF33443A) : const Color(0xFFDFE5DC),
    secondary: dark ? const Color(0xFFF09A73) : coral,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, foregroundColor: scheme.onSurface),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xFF1B2922) : const Color(0xFFFFFDF8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: scheme.outline.withValues(alpha: .7)),
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF202F27) : const Color(0xFFFFFDF8),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: scheme.outline)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF17231C) : const Color(0xFFFFFDF8),
      indicatorColor: dark ? const Color(0xFF263D2D) : const Color(0xFFDFEDDF),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: coral,
      foregroundColor: Color(0xFF2E271F),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}
