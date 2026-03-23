import 'package:flutter/material.dart';

/// Libretto's dark-first theme with accessibility considerations.
class LibrettoTheme {
  LibrettoTheme._();

  // Brand colors
  static const Color primary = Color(0xFF7B68EE); // Medium slate blue
  static const Color primaryVariant = Color(0xFF5B4ACF);
  static const Color secondary = Color(0xFFFF8C42); // Warm orange
  static const Color surface = Color(0xFF1E1E2E);
  static const Color background = Color(0xFF13131A);
  static const Color cardColor = Color(0xFF252536);
  static const Color error = Color(0xFFCF6679);
  static const Color onPrimary = Colors.white;
  static const Color onSurface = Color(0xFFE0E0E6);
  static const Color onSurfaceVariant = Color(0xFF9999AA);
  static const Color divider = Color(0xFF333344);

  // High contrast colors (WCAG AAA — 7:1 ratio)
  static const Color highContrastOnSurface = Colors.white;
  static const Color highContrastOnBackground = Colors.white;

  static ThemeData darkTheme({bool highContrast = false}) {
    final textOnSurface = highContrast ? highContrastOnSurface : onSurface;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        surface: surface,
        error: error,
        onPrimary: onPrimary,
        onSurface: textOnSurface,
      ),
      scaffoldBackgroundColor: background,
      cardColor: cardColor,
      dividerColor: divider,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: textOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textOnSurface,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardTheme(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(48, 48), // a11y: min touch target
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48), // a11y: min touch target
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: onSurfaceVariant),
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          color: textOnSurface,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: TextStyle(
          color: textOnSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: TextStyle(
          color: textOnSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: textOnSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(
          color: textOnSurface,
          fontSize: 16,
        ),
        bodyMedium: TextStyle(
          color: textOnSurface,
          fontSize: 14,
        ),
        bodySmall: TextStyle(
          color: onSurfaceVariant,
          fontSize: 12,
        ),
        labelLarge: TextStyle(
          color: textOnSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: TextStyle(color: textOnSurface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: divider,
        thumbColor: primary,
        overlayColor: primary.withOpacity(0.2),
        trackHeight: 4,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: divider,
      ),
    );
  }
}
