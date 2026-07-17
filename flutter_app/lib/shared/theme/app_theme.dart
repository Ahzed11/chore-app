import 'package:flutter/material.dart';

/// The "Outfit" font (TASK-067 F-26) is bundled as a variable font at
/// `assets/fonts/Outfit-Variable.ttf` and registered under this family name
/// via `pubspec.yaml`'s `flutter.fonts` — see that file. Flutter maps the
/// requested `TextStyle.fontWeight` onto the font's `wght` variation axis
/// automatically, so a single asset covers every weight used below without
/// any runtime network fetch (the app used to pull each weight from Google
/// Fonts' CDN via the `google_fonts` package on first run, which meant
/// LAN-only/offline installs rendered with the system fallback font).
const _outfit = 'Outfit';

class AppTheme {
  AppTheme._();

  static const Color primary = Color(0xFF0D9488);
  static const Color _primaryDark = Color(0xFF0F766E);
  static const Color _error = Color(0xFFDC2626);
  static const Color _background = Color(0xFFF8FAFA);
  static const Color _surface = Color(0xFFFFFFFF);
  static const Color _darkText = Color(0xFF0F2E2C);

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      error: _error,
      surface: _surface,
      brightness: Brightness.light,
    );

    final base = ThemeData(brightness: Brightness.light).textTheme
        .apply(fontFamily: _outfit)
        .copyWith(
      displayLarge: const TextStyle(
        fontFamily: _outfit,
        fontSize: 32,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.5,
        color: _darkText,
      ),
      displayMedium: const TextStyle(
        fontFamily: _outfit,
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: _darkText,
      ),
      headlineLarge: const TextStyle(
        fontFamily: _outfit,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: _darkText,
      ),
      headlineMedium: const TextStyle(
        fontFamily: _outfit,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: _darkText,
      ),
      headlineSmall: const TextStyle(
        fontFamily: _outfit,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: _darkText,
      ),
      titleLarge: const TextStyle(
        fontFamily: _outfit,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
        color: _darkText,
      ),
      titleMedium: const TextStyle(
        fontFamily: _outfit,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: _darkText,
      ),
      bodyLarge: const TextStyle(
        fontFamily: _outfit,
        fontSize: 16,
        color: _darkText,
      ),
      bodyMedium: const TextStyle(
        fontFamily: _outfit,
        fontSize: 14,
        color: _darkText,
      ),
      bodySmall: const TextStyle(
        fontFamily: _outfit,
        fontSize: 12,
        color: Color(0xFF7F9794),
      ),
      labelLarge: const TextStyle(
        fontFamily: _outfit,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: _darkText,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _background,
      textTheme: base,

      // AppBar — white, no elevation, dark text
      appBarTheme: const AppBarTheme(
        backgroundColor: _surface,
        foregroundColor: _darkText,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _outfit,
          color: _darkText,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
        iconTheme: IconThemeData(color: _darkText),
      ),

      // Elevated button
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: _outfit,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Filled button
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: _outfit,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: primary),
          textStyle: const TextStyle(
            fontFamily: _outfit,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(
            fontFamily: _outfit,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      // Input decoration
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE6EDEC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _error),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        labelStyle: const TextStyle(
          fontFamily: _outfit,
          color: Color(0xFF7F9794),
        ),
        hintStyle: const TextStyle(
          fontFamily: _outfit,
          color: Color(0xFFA8BCB9),
        ),
      ),

      // Card — no elevation, 18px radius, cards own their margin
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        color: _surface,
        margin: EdgeInsets.zero,
      ),

      // FAB — teal
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: CircleBorder(),
      ),

      // Bottom nav bar
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primary,
        unselectedItemColor: Color(0xFFA8BCB9),
        backgroundColor: _surface,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: const Color(0xFFF1F5F5),
        labelStyle: const TextStyle(fontFamily: _outfit, fontSize: 13),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide.none,
      ),

      // Divider
      dividerTheme: const DividerThemeData(
        color: Color(0xFFEEF3F2),
        thickness: 1,
        space: 1,
      ),

      // Primary color (legacy)
      primaryColor: primary,
      primaryColorDark: _primaryDark,
    );
  }
}
