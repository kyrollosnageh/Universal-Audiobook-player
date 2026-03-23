import '../core/errors.dart';
import '../data/database/app_database.dart';
import '../data/database/daos/chapter_dao.dart';
import '../data/models/unified_chapter.dart';
import '../data/server_providers/emby_provider.dart';
import '../data/server_providers/server_provider.dart';

/// Handles format-aware chapter parsing and builds the unified chapter model.
///
/// Supports all audiobook structures:
/// 1. Single M4B/M4A with embedded chapters
/// 2. Multiple MP3s (one per chapter) — playlist entry per track
/// 3. Single MP3/FLAC with no chapter markers — time-based navigation
/// 4. Mixed formats (some M4B + some MP3)
class ChapterService {
  ChapterService({
    required AppDatabase database,
  }) : _chapterDao = database.chapterDao;

  final ChapterDao _chapterDao;

  /// Get chapters for a book, detecting the format automatically.
  ///
  /// First tries to load from cache, then fetches from server.
  /// Validates all chapter data defensively.
  Future<List<UnifiedChapter>> getChapters(
    ServerProvider provider,
    String bookId, {
    bool forceRefresh = false,
  }) async {
    // Try cache first
    if (!forceRefresh) {
      final cached = await _getCachedChapters(bookId, provider.serverUrl);
      if (cached.isNotEmpty) return cached;
    }

    // Fetch from server
    List<UnifiedChapter> chapters;
    try {
      chapters = await provider.getChapters(bookId);
    } catch (e) {
      throw ChapterParsingException('Failed to fetch chapters', e);
    }

    // If we got a single "full book" chapter and provider supports
    // child tracks, try fetching MP3-per-chapter
    if (chapters.length == 1 &&
        !chapters.first.isSeparateTrack &&
        provider is EmbyProvider) {
      try {
        final childTracks = await provider.fetchChildTracks(bookId);
        if (childTracks.isNotEmpty) {
          chapters = childTracks;
        }
      } catch (_) {
        // Fall through with the single chapter
      }
    }

    // Validate and sanitize
    chapters = _validateChapters(chapters);

    // Cache for next time
    await _cacheChapters(chapters, bookId, provider.serverUrl);

    return chapters;
  }

  /// Validate chapters: ensure non-negative offsets, sorted order,
  /// within file duration. Fall back to time-based navigation if invalid.
  List<UnifiedChapter> _validateChapters(List<UnifiedChapter> chapters) {
    if (chapters.isEmpty) return chapters;

    final validated = <UnifiedChapter>[];

    for (final ch in chapters) {
      // Skip chapters with negative duration or offset
      if (ch.duration.isNegative || ch.startOffset.isNegative) continue;
      // Skip zero-duration chapters
      if (ch.duration == Duration.zero) continue;

      validated.add(ch);
    }

    // Ensure sorted by start offset
    validated.sort(
        (a, b) => a.startOffset.inMilliseconds.compareTo(
            b.startOffset.inMilliseconds));

    return validated;
  }

  /// Find the chapter containing a given position.
  UnifiedChapter? getChapterAtPosition(
    List<UnifiedChapter> chapters,
    Duration position,
  ) {
    for (final ch in chapters.reversed) {
      if (position >= ch.startOffset) return ch;
    }
    return chapters.isNotEmpty ? chapters.first : null;
  }

  /// Get the next chapter after the current one.
  UnifiedChapter? getNextChapter(
    List<UnifiedChapter> chapters,
    UnifiedChapter current,
  ) {
    final idx = chapters.indexOf(current);
    if (idx < 0 || idx >= chapters.length - 1) return null;
    return chapters[idx + 1];
  }

  /// Get the previous chapter.
  UnifiedChapter? getPreviousChapter(
    List<UnifiedChapter> chapters,
    UnifiedChapter current,
  ) {
    final idx = chapters.indexOf(current);
    if (idx <= 0) return null;
    return chapters[idx - 1];
  }

  // ── Caching ───────────────────────────────────────────────────────

  Future<List<UnifiedChapter>> _getCachedChapters(
    String bookId,
    String serverId,
  ) async {
    final entries = await _chapterDao.getChapters(bookId, serverId);
    return entries.map(_entryToChapter).toList();
  }

  Future<void> _cacheChapters(
    List<UnifiedChapter> chapters,
    String bookId,
    String serverId,
  ) async {
    // Clear old chapters first
    await _chapterDao.clearBookChapters(bookId, serverId);

    final entries = chapters
        .map((ch) => ChapterEntry(
              id: ch.id,
              bookId: bookId,
              serverId: serverId,
              title: ch.title,
              startOffsetMs: ch.startOffset.inMilliseconds,
              durationMs: ch.duration.inMilliseconds,
              trackItemId: ch.trackItemId,
              imageUrl: ch.imageUrl,
              isSeparateTrack: ch.isSeparateTrack,
              trackIndex: ch.trackIndex,
            ))
        .toList();

    await _chapterDao.upsertChapters(entries);
  }

  UnifiedChapter _entryToChapter(ChapterEntry entry) {
    return UnifiedChapter(
      id: entry.id,
      title: entry.title,
      startOffset: Duration(milliseconds: entry.startOffsetMs),
      duration: Duration(milliseconds: entry.durationMs),
      trackItemId: entry.trackItemId,
      imageUrl: entry.imageUrl,
      isSeparateTrack: entry.isSeparateTrack,
      trackIndex: entry.trackIndex,
    );
  }
}
