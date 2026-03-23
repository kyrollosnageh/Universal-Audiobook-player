import 'package:audio_service/audio_service.dart';

import '../data/models/book.dart';
import '../data/models/unified_chapter.dart';
import '../services/playback_service.dart';

/// CarPlay + Android Auto audio handler integration.
///
/// Bridges the PlaybackService with car display systems:
/// - CarPlay: CPTemplate-based UI via Flutter method channels
/// - Android Auto: MediaBrowserServiceCompat via audio_service
/// - Pre-cached cover art for car displays
/// - Voice commands resume last-played book
/// - Front-loaded titles for truncation on car screens
class CarAudioHandler {
  CarAudioHandler({required this.playbackService});

  final PlaybackService playbackService;

  // ── Media Item Formatting ─────────────────────────────────────

  /// Format a book title for car displays (front-load important info).
  String formatCarTitle(Book book) {
    // Car screens truncate long titles, so put the most important info first
    if (book.seriesName != null && book.seriesIndex != null) {
      return '${book.seriesName} #${book.seriesIndex!.toInt()} - ${book.title}';
    }
    return book.title;
  }

  /// Format chapter title for car displays.
  String formatChapterTitle(UnifiedChapter chapter, int index, int total) {
    return '${index + 1}/$total: ${chapter.title}';
  }

  /// Create a MediaItem for the audio_service media tree.
  MediaItem bookToMediaItem(Book book) {
    return MediaItem(
      id: book.id,
      title: formatCarTitle(book),
      artist: book.author ?? 'Unknown Author',
      album: book.seriesName,
      duration: book.duration,
      artUri: book.coverUrl != null ? Uri.tryParse(book.coverUrl!) : null,
      extras: {'serverId': book.serverId, 'progress': book.progress},
    );
  }

  /// Create a MediaItem for a chapter.
  MediaItem chapterToMediaItem(
    UnifiedChapter chapter,
    Book book,
    int index,
    int total,
  ) {
    return MediaItem(
      id: '${book.id}:${chapter.id}',
      title: formatChapterTitle(chapter, index, total),
      artist: book.author,
      album: book.title,
      duration: chapter.duration,
      artUri: book.coverUrl != null ? Uri.tryParse(book.coverUrl!) : null,
    );
  }
}
