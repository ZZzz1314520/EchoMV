import 'package:flutter/material.dart';

ThemeData buildEchoTheme() {
  const background = Color(0xFF111315);
  const surface = Color(0xFF1B2024);
  const teal = Color(0xFF3DD6C6);
  const coral = Color(0xFFFF6B5F);
  const amber = Color(0xFFFFC857);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: teal,
      brightness: Brightness.dark,
      primary: teal,
      secondary: coral,
      tertiary: amber,
      surface: surface,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF20262A),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      prefixIconColor: teal,
    ),
  );
}
