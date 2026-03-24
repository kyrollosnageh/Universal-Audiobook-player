import 'package:flutter/widgets.dart';

/// Responsive layout breakpoints for Libretto.
///
/// Usage:
/// ```dart
/// final layout = ResponsiveLayout.of(context);
/// if (layout.isTablet) { ... }
/// ```
class ResponsiveLayout {
  const ResponsiveLayout._({
    required this.screenWidth,
    required this.isLandscape,
  });

  final double screenWidth;
  final bool isLandscape;

  /// Phone: < 600dp, Tablet: >= 600dp (Material Design breakpoint)
  bool get isTablet => screenWidth >= 600;

  /// Large tablet or desktop: >= 900dp
  bool get isLargeTablet => screenWidth >= 900;

  /// Max cross-axis extent for book grid items.
  double get gridMaxExtent {
    if (isTablet) return 220;
    return 180;
  }

  /// Cover art size for the player screen.
  double get playerCoverSize {
    if (isLargeTablet) return 400;
    if (isTablet) return 340;
    return 280;
  }

  /// Read from the nearest MediaQuery.
  static ResponsiveLayout of(BuildContext context) {
    final mq = MediaQuery.of(context);
    return ResponsiveLayout._(
      screenWidth: mq.size.shortestSide >= 600 ? mq.size.width : mq.size.width,
      isLandscape: mq.orientation == Orientation.landscape,
    );
  }
}
