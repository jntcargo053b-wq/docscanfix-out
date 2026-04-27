import 'package:flutter/material.dart';

class AppTheme {
  // Color Palette
  static const Color primary = Color(0xFF00D4AA);
  static const Color primaryDark = Color(0xFF00A88A);
  static const Color background = Color(0xFF0D0F14);
  static const Color surface = Color(0xFF161B26);
  static const Color surfaceLight = Color(0xFF1E2535);
  static const Color textPrimary = Color(0xFFF0F4FF);
  static const Color textSecondary = Color(0xFF8892A4);
  static const Color error = Color(0xFFFF5E5E);
  static const Color success = Color(0xFF00D4AA);
  static const Color warning = Color(0xFFFFB547);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        secondary: primaryDark,
        surface: surface,
        error: error,
        onPrimary: Colors.black,
        onSecondary: Colors.black,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      cardTheme: CardThemeData(        // ← FIXED: was CardTheme
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.black,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32, fontWeight: FontWeight.w800,
          color: textPrimary, letterSpacing: -1,
        ),
        displayMedium: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w700,
          color: textPrimary, letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w700,
          color: textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: TextStyle(fontSize: 15, color: textPrimary, height: 1.5),
        bodyMedium: TextStyle(fontSize: 13, color: textSecondary, height: 1.5),
        labelLarge: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600,
          color: textSecondary, letterSpacing: 0.5,
        ),
      ),
      iconTheme: const IconThemeData(color: textSecondary),
      dividerTheme: const DividerThemeData(
        color: surfaceLight,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceLight,
        contentTextStyle: const TextStyle(color: textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
