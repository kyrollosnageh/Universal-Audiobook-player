import 'dart:ui';

import 'package:flutter/material.dart';

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

  static FlutterView get _defaultView =>
      WidgetsBinding.instance.platformDispatcher.views.first;

  static void _announce(String message) {
    SemanticsService.sendAnnouncement(
      _defaultView,
      AnnounceSemanticsEvent(message, TextDirection.ltr, Assertiveness.polite),
    );
  }

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
    _announce('Now playing: ${chapter.title}');
  }

  /// Announce a playback state change.
  static void announcePlaybackState(
    BuildContext context, {
    required bool isPlaying,
    required String bookTitle,
  }) {
    _announce(isPlaying ? 'Playing $bookTitle' : 'Paused $bookTitle');
  }

  /// Announce playback speed change.
  static void announceSpeedChange(BuildContext context, double speed) {
    _announce('Playback speed: ${speed}x');
  }

  /// Announce sleep timer set.
  static void announceSleepTimer(BuildContext context, Duration? remaining) {
    if (remaining == null) {
      _announce('Sleep timer cancelled');
    } else if (remaining.isNegative) {
      _announce('Sleep timer set: end of chapter');
    } else {
      _announce('Sleep timer set: ${remaining.toHumanReadable()}');
    }
  }

  /// Announce download progress.
  static void announceDownloadProgress(
    BuildContext context,
    String bookTitle,
    double progress,
  ) {
    _announce('Downloading $bookTitle: ${(progress * 100).toInt()}%');
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
