import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/extensions.dart';
import '../../data/models/book.dart';
import '../../data/models/unified_chapter.dart';

/// Accessibility helpers for the player.
class SemanticPlayer {
  SemanticPlayer._();

  /// Build a descriptive label for the play button.
  static String playButtonLabel({
    required Book book,
    UnifiedChapter? chapter,
    Duration? resumeAt,
  }) {
    final parts = <String>['Play ${book.title}'];

    if (book.author != null) {
      parts.add('by ${book.author}');
    }

    if (chapter != null) {
      parts.add('Chapter: ${chapter.title}');
    }

    if (resumeAt != null && resumeAt != Duration.zero) {
      parts.add('resuming at ${resumeAt.toHms()}');
    }

    return parts.join(', ');
  }

  /// Announce a chapter change to screen readers.
  static void announceChapterChange(
    BuildContext context,
    UnifiedChapter chapter,
  ) {
    SemanticsService.announce(
      'Now playing: ${chapter.title}',
      TextDirection.ltr,
    );
  }

  /// Announce a playback state change.
  static void announcePlaybackState(
    BuildContext context, {
    required bool isPlaying,
    required String bookTitle,
  }) {
    SemanticsService.announce(
      isPlaying ? 'Playing $bookTitle' : 'Paused $bookTitle',
      TextDirection.ltr,
    );
  }
}
