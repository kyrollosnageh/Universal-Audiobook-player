import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/extensions.dart';
import '../../data/models/book.dart';
import '../../data/models/unified_chapter.dart';

/// Accessibility helpers for the player and library screens.
///
/// Ensures VoiceOver/TalkBack users can:
/// - Understand playback state at all times
/// - Navigate chapters efficiently
/// - Find and play books within 60 seconds using only screen reader
class SemanticPlayer {
  SemanticPlayer._();

  /// Build a descriptive label for the play button.
  /// "Play [Book Title] by [Author], Chapter [N], resuming at [time]"
  static String playButtonLabel({
    required Book book,
    UnifiedChapter? chapter,
    Duration? resumeAt,
  }) {
    final parts = <String>[];

    if (resumeAt != null && resumeAt != Duration.zero) {
      parts.add('Resume ${book.title}');
    } else {
      parts.add('Play ${book.title}');
    }

    if (book.author != null) {
      parts.add('by ${book.author}');
    }

    if (chapter != null) {
      parts.add('Chapter: ${chapter.title}');
    }

    if (resumeAt != null && resumeAt != Duration.zero) {
      parts.add('at ${resumeAt.toHms()}');
    }

    return parts.join(', ');
  }

  /// Announce a chapter change to screen readers.
  static void announceChapterChange(
    BuildContext context,
    UnifiedChapter chapter,
  ) {
    SemanticsService.sendAnnouncement(
      AnnounceSemanticsEvent(
        'Now playing: ${chapter.title}',
        TextDirection.ltr,
      ),
    );
  }

  /// Announce a playback state change.
  static void announcePlaybackState(
    BuildContext context, {
    required bool isPlaying,
    required String bookTitle,
  }) {
    SemanticsService.sendAnnouncement(
      AnnounceSemanticsEvent(
        isPlaying ? 'Playing $bookTitle' : 'Paused $bookTitle',
        TextDirection.ltr,
      ),
    );
  }

  /// Announce playback speed change.
  static void announceSpeedChange(BuildContext context, double speed) {
    SemanticsService.sendAnnouncement(
      AnnounceSemanticsEvent('Playback speed: ${speed}x', TextDirection.ltr),
    );
  }

  /// Announce sleep timer set.
  static void announceSleepTimer(BuildContext context, Duration? remaining) {
    if (remaining == null) {
      SemanticsService.sendAnnouncement(
        AnnounceSemanticsEvent('Sleep timer cancelled', TextDirection.ltr),
      );
    } else if (remaining.isNegative) {
      SemanticsService.sendAnnouncement(
        AnnounceSemanticsEvent(
          'Sleep timer set: end of chapter',
          TextDirection.ltr,
        ),
      );
    } else {
      SemanticsService.sendAnnouncement(
        AnnounceSemanticsEvent(
          'Sleep timer set: ${remaining.toHumanReadable()}',
          TextDirection.ltr,
        ),
      );
    }
  }

  /// Announce download progress.
  static void announceDownloadProgress(
    BuildContext context,
    String bookTitle,
    double progress,
  ) {
    SemanticsService.sendAnnouncement(
      AnnounceSemanticsEvent(
        'Downloading $bookTitle: ${(progress * 100).toInt()}%',
        TextDirection.ltr,
      ),
    );
  }

  /// Build descriptive label for a book in the library grid/list.
  static String bookLabel(Book book) {
    final parts = <String>[book.title];

    if (book.author != null) parts.add('by ${book.author}');
    if (book.duration != null) parts.add(book.duration!.toHumanReadable());
    if (book.progress != null && book.progress! > 0) {
      parts.add('${(book.progress! * 100).toInt()}% complete');
    }
    if (book.seriesName != null) {
      parts.add('Series: ${book.seriesName}');
      if (book.seriesIndex != null) {
        parts.add('Book ${book.seriesIndex!.toInt()}');
      }
    }

    return parts.join(', ');
  }

  /// Build label for chapter in the chapter list.
  static String chapterLabel(
    UnifiedChapter chapter,
    int index,
    bool isCurrent,
  ) {
    final parts = <String>[
      'Chapter ${index + 1}: ${chapter.title}',
      'Duration: ${chapter.duration.toHms()}',
    ];

    if (isCurrent) parts.add('Currently playing');

    return parts.join(', ');
  }
}
