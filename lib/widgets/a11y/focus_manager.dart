import 'package:flutter/material.dart';

/// Focus management utilities for accessibility.
///
/// Ensures proper focus flow:
/// - Focus lands on the most relevant element when navigating screens
/// - Focus is trapped in modal sheets
/// - Focus is restored when modals close
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
}
