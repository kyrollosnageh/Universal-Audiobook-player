import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Libretto's dark-first theme with accessibility considerations.
class LibrettoTheme {
  LibrettoTheme._();

  // Brand colors
  static const Color primary = Color(0xFFE91E80); // Magenta / berry
  static const Color primaryVariant = Color(0xFFC4176B);
  static const Color secondary = Color(
    0xFFA8E824,
  ); // Lime green accent
  static const Color surface = Color(0xFF232340);
  static const Color background = Color(0xFF1A1A2E);
  static const Color cardColor = Color(0xFF2D2B55);
  static const Color error = Color(0xFFFF6B6B); // Soft coral
  static const Color onPrimary = Colors.white;
  static const Color onSurface = Color(0xFFF5F0FF); // Warm white
  static const Color onSurfaceVariant = Color(0xFF9B95B8); // Muted lavender
  static const Color divider = Color(0xFF3D3A66);

  // Spacing system (4dp base grid)
  static const double spacingXs = 4;
  static const double spacingSm = 8;
  static const double spacingMd = 12;
  static const double spacingLg = 16;
  static const double spacingXl = 24;
  static const double spacingXxl = 32;
  static const double spacingXxxl = 48;

  // Border radii
  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  // Component sizes
  static const double coverSmall = 48;
  static const double coverMedium = 130;
  static const double coverLarge = 200;
  static const double coverPlayer = 280;
  static const double miniPlayerHeight = 72;
  static const double heroCardRadius = 20;

  // Server type colors
  static const Color jellyfinColor = Color(0xFF00A4DC);
  static const Color embyColor = Color(0xFF4CAF50);
  static const Color audiobookshelfColor = Color(0xFFE8A87C);
  static const Color plexColor = Color(0xFFE5A00D);
  static const Color successColor = Color(0xFF4CAF50);

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
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          minimumSize: const Size(48, 48), // a11y: min touch target
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(48, 48), // a11y: min touch target
          side: const BorderSide(color: primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: const TextStyle(color: onSurfaceVariant),
      ),
      textTheme: TextTheme(
        headlineLarge: GoogleFonts.nunito(
          color: textOnSurface,
          fontSize: 28,
          fontWeight: FontWeight.bold,
        ),
        headlineMedium: GoogleFonts.nunito(
          color: textOnSurface,
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
        titleLarge: GoogleFonts.nunito(
          color: textOnSurface,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: GoogleFonts.nunito(
          color: textOnSurface,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: textOnSurface, fontSize: 16),
        bodyMedium: TextStyle(color: textOnSurface, fontSize: 14),
        bodySmall: const TextStyle(color: onSurfaceVariant, fontSize: 12),
        labelLarge: TextStyle(
          color: textOnSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardColor,
        contentTextStyle: TextStyle(color: textOnSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: secondary,
        inactiveTrackColor: divider,
        thumbColor: secondary,
        overlayColor: secondary.withValues(alpha: 0.2),
        trackHeight: 6,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: secondary,
        linearTrackColor: divider,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: divider),
        ),
        textStyle: TextStyle(color: textOnSurface, fontSize: 12),
      ),
    );
  }
}
