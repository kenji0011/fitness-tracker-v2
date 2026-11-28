import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/liquid_glass_surface.dart';

class AppTheme {
  static const Color tempoOrangeLight = Color(0xFFFF6A24);
  static const Color tempoOrangeDark = Color(0xFFFF7A33);

  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF2F2F7),
    primaryColor: tempoOrangeLight,
    splashFactory: const TempoTouchLightSplashFactory(isDark: false),
    highlightColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF2F2F7),
      foregroundColor: Color(0xFF1C1C1E),
      iconTheme: IconThemeData(color: Color(0xFF1C1C1E)),
      titleTextStyle: TextStyle(
        color: Color(0xFF1C1C1E),
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
    ),
    colorScheme: const ColorScheme.light(
      primary: tempoOrangeLight,
      onPrimary: Colors.white,
      secondary: tempoOrangeLight,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE9E9EE),
      onSecondaryContainer: Color(0xFF1C1C1E),
      surface: Colors.white,
      onSurface: Color(0xFF1C1C1E),
      error: Color(0xFFFF3B30),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tempoOrangeLight,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardColor: Colors.white,
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),
    dividerColor: const Color(0x14000000),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: Color(0xFF1C1C1E),
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: Color(0xFF1C1C1E),
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: Color(0xFF1C1C1E),
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      bodyLarge: TextStyle(color: Color(0xFF1C1C1E)),
      bodyMedium: TextStyle(color: Color(0xFF1C1C1E)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFE9E9EE),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: tempoOrangeLight, width: 1.5),
      ),
    ),
  );

  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF000000),
    primaryColor: tempoOrangeDark,
    splashFactory: const TempoTouchLightSplashFactory(isDark: true),
    highlightColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF000000),
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    colorScheme: const ColorScheme.dark(
      primary: tempoOrangeDark,
      onPrimary: Colors.white,
      secondary: tempoOrangeDark,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFF2C2C2E),
      onSecondaryContainer: Colors.white,
      surface: Color(0xFF1C1C1E),
      onSurface: Colors.white,
      error: Color(0xFFFF453A),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: tempoOrangeDark,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    cardColor: const Color(0xFF1C1C1E),
    cardTheme: CardThemeData(
      color: const Color(0xFF1C1C1E),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
    ),
    dividerColor: const Color(0x1AFFFFFF),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
      ),
      headlineMedium: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      titleLarge: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF2C2C2E),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: tempoOrangeDark, width: 1.5),
      ),
    ),
  );
}
