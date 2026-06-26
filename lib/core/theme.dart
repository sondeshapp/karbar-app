import 'package:flutter/material.dart';

final ThemeData appDarkTheme = ThemeData(
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF8B5CF6),
    error: Color(0xFFEF4444),
    surface: Color(0xFF1E293B),
    onSurface: Color(0xFFF1F5F9),
  ),
  scaffoldBackgroundColor: const Color(0xFF0F172A),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFF1E293B),
    foregroundColor: Color(0xFFF1F5F9),
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      color: Color(0xFFF1F5F9),
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF3B82F6),
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF334155)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  ),
  cardColor: const Color(0xFF1E293B),
  dividerColor: const Color(0xFF334155),
  useMaterial3: true,
);

final ThemeData appTheme = ThemeData(
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF2563EB),
    error: Color(0xFFEF4444),
    surface: Color(0xFFFFFFFF),
    onSurface: Color(0xFF1A1A1A),
  ),
  scaffoldBackgroundColor: const Color(0xFFFFFFFF),
  appBarTheme: const AppBarTheme(
    backgroundColor: Color(0xFFFFFFFF),
    foregroundColor: Color(0xFF1A1A1A),
    elevation: 0,
    scrolledUnderElevation: 0,
    titleTextStyle: TextStyle(
      color: Color(0xFF1A1A1A),
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
    shadowColor: Color(0xFFE5E7EB),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF2563EB),
      foregroundColor: Colors.white,
      minimumSize: const Size(double.infinity, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
  ),
  dividerColor: const Color(0xFFE5E7EB),
  useMaterial3: true,
);
