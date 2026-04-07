import 'package:flutter/material.dart';

class AppTheme {
  static const primaryRed = Color(0xFFD32F2F);
  static const darkGrey = Color(0xFF2B2B2B);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const warningAmber = Color(0xFFFFC107);
  static const successGreen = Color(0xFF2E7D32);

  static ThemeData get urgentTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary: primaryRed,
        onPrimary: white,
        secondary: warningAmber,
        onSecondary: black,
        surface: black,
        onSurface: white,
        error: primaryRed,
        onError: white,
      ),
      scaffoldBackgroundColor: black,
      appBarTheme: const AppBarTheme(
        backgroundColor: black,
        foregroundColor: white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: white,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkGrey,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: white,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          elevation: 6,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: white),
        headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: white),
        bodyLarge: TextStyle(fontSize: 18, color: white),
        bodyMedium: TextStyle(fontSize: 16, color: white),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white70),
      ),
    );
  }
}
