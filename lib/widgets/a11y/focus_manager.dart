import 'package:flutter/material.dart';

/// Focus management utilities for accessibility.
///
/// Ensures proper focus flow for VoiceOver/TalkBack:
/// - Focus lands on the most relevant element when navigating screens
/// - Focus is trapped in modal sheets
/// - Focus is restored when modals close
/// - Dynamic text scaling handled gracefully
class LibrettoFocusManager {
  LibrettoFocusManager._();

  /// Request focus on a specific node after navigation.
  static void requestFocusAfterBuild(
    BuildContext context,
    FocusNode node,
  ) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        node.requestFocus();
      }
    });
  }

  /// Create a focus scope that traps focus within a modal.
  static Widget focusTrap({required Widget child}) {
    return FocusScope(
      autofocus: true,
      child: child,
    );
  }

  /// Determine if we should use list layout based on text scale.
  /// At text scale > 1.5x, grid items become too small — switch to list.
  static bool shouldUseListLayout(BuildContext context) {
    return MediaQuery.textScaleFactorOf(context) > 1.5;
  }

  /// Check if animations should be disabled.
  static bool shouldDisableAnimations(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  /// Get the appropriate cover art size for the current text scale.
  static double coverArtSize(BuildContext context, {double base = 130}) {
    final scale = MediaQuery.textScaleFactorOf(context);
    if (scale > 2.0) return base * 0.7;
    if (scale > 1.5) return base * 0.85;
    return base;
  }
}

/// A widget that adapts its layout based on accessibility settings.
class AdaptiveLayout extends StatelessWidget {
  const AdaptiveLayout({
    super.key,
    required this.gridChild,
    required this.listChild,
  });

  final Widget gridChild;
  final Widget listChild;

  @override
  Widget build(BuildContext context) {
    if (LibrettoFocusManager.shouldUseListLayout(context)) {
      return listChild;
    }
    return gridChild;
  }
}

/// Wrapper that respects reduced motion preferences.
class MotionSafeWidget extends StatelessWidget {
  const MotionSafeWidget({
    super.key,
    required this.child,
    required this.reducedChild,
  });

  /// The animated version.
  final Widget child;

  /// The static version shown when reduced motion is enabled.
  final Widget reducedChild;

  @override
  Widget build(BuildContext context) {
    if (LibrettoFocusManager.shouldDisableAnimations(context)) {
      return reducedChild;
    }
    return child;
  }
}

/// Ensures all touch targets meet the 48x48dp minimum.
class AccessibleTapTarget extends StatelessWidget {
  const AccessibleTapTarget({
    super.key,
    required this.child,
    required this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 48,
            minHeight: 48,
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
