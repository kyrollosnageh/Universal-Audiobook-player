import '../core/errors.dart';
import '../data/database/app_database.dart';
import '../data/database/daos/chapter_dao.dart';
import '../data/models/unified_chapter.dart';
import '../data/server_providers/emby_provider.dart';
import '../data/server_providers/server_provider.dart';

/// Handles format-aware chapter parsing and builds the unified chapter model.
///
/// Supports all audiobook structures:
/// 1. Single M4B/M4A with embedded chapters (isSeparateTrack = false)
/// 2. Multiple MP3s (one per chapter) — playlist entry per track
/// 3. Single MP3/FLAC with no chapter markers — time-based navigation
/// 4. Mixed formats (some M4B + some MP3)
class ChapterService {
  ChapterService({
    required AppDatabase database,
  }) : _chapterDao = database.chapterDao;

  final ChapterDao _chapterDao;

  // Custom user bookmarks per book (stored locally)
  final Map<String, List<UserBookmark>> _bookmarks = {};

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

    // If still no chapters (or only a "full book" marker with no embedded
    // chapters), detect the format and handle accordingly
    if (chapters.isEmpty) {
      chapters = _createFallbackChapters(bookId);
    }

    // Cache for next time
    await _cacheChapters(chapters, bookId, provider.serverUrl);

    return chapters;
  }

  /// Detect the chapter format of a book.
  ChapterFormat detectFormat(List<UnifiedChapter> chapters) {
    if (chapters.isEmpty) return ChapterFormat.noChapters;
    if (chapters.length == 1 && !chapters.first.isSeparateTrack) {
      return ChapterFormat.noChapters;
    }
    if (chapters.every((ch) => ch.isSeparateTrack)) {
      return ChapterFormat.mp3PerChapter;
    }
    if (chapters.every((ch) => !ch.isSeparateTrack)) {
      return ChapterFormat.embeddedChapters;
    }
    return ChapterFormat.mixed;
  }

  /// Build a flat, unified chapter list for mixed-format books.
  ///
  /// For books that have some M4B files with sub-chapters and some MP3
  /// tracks, this creates a single flat list abstracting both.
  List<UnifiedChapter> flattenMixedChapters(
    List<UnifiedChapter> chapters,
  ) {
    final flat = <UnifiedChapter>[];
    var globalOffset = Duration.zero;

    for (final ch in chapters) {
      flat.add(UnifiedChapter(
        id: ch.id,
        title: ch.title,
        startOffset: globalOffset,
        duration: ch.duration,
        trackItemId: ch.trackItemId,
        imageUrl: ch.imageUrl,
        isSeparateTrack: ch.isSeparateTrack,
        trackIndex: ch.trackIndex,
      ));
      globalOffset += ch.duration;
    }

    return flat;
  }

  /// Calculate the total duration across all chapters.
  Duration totalDuration(List<UnifiedChapter> chapters) {
    if (chapters.isEmpty) return Duration.zero;

    final format = detectFormat(chapters);
    if (format == ChapterFormat.mp3PerChapter) {
      // Sum of individual tracks
      return chapters.fold(
        Duration.zero,
        (sum, ch) => sum + ch.duration,
      );
    }

    // For embedded chapters: last chapter end offset
    final last = chapters.last;
    return last.startOffset + last.duration;
  }

  /// Get chapter boundary positions (for scrubber tick marks).
  List<double> getChapterBoundaries(
    List<UnifiedChapter> chapters,
    Duration totalDuration,
  ) {
    if (chapters.length <= 1 || totalDuration == Duration.zero) {
      return [];
    }

    final totalMs = totalDuration.inMilliseconds.toDouble();
    return chapters.skip(1).map((ch) {
      return ch.startOffset.inMilliseconds / totalMs;
    }).toList();
  }

  // ── Chapter-aware Seeking ─────────────────────────────────────

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

  /// Calculate remaining time in the current chapter.
  Duration remainingInChapter(
    UnifiedChapter chapter,
    Duration currentPosition,
  ) {
    final chapterEnd = chapter.startOffset + chapter.duration;
    final remaining = chapterEnd - currentPosition;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Calculate time elapsed in the current chapter.
  Duration elapsedInChapter(
    UnifiedChapter chapter,
    Duration currentPosition,
  ) {
    final elapsed = currentPosition - chapter.startOffset;
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  /// Progress within the current chapter (0.0 - 1.0).
  double chapterProgress(
    UnifiedChapter chapter,
    Duration currentPosition,
  ) {
    if (chapter.duration == Duration.zero) return 0.0;
    final elapsed = elapsedInChapter(chapter, currentPosition);
    return (elapsed.inMilliseconds / chapter.duration.inMilliseconds)
        .clamp(0.0, 1.0);
  }

  // ── User Bookmarks ────────────────────────────────────────────

  /// Add a user-created bookmark at the current position.
  void addBookmark({
    required String bookId,
    required Duration position,
    String? note,
    String? chapterId,
  }) {
    _bookmarks.putIfAbsent(bookId, () => []);
    _bookmarks[bookId]!.add(UserBookmark(
      position: position,
      note: note,
      chapterId: chapterId,
      createdAt: DateTime.now(),
    ));
  }

  /// Get all bookmarks for a book.
  List<UserBookmark> getBookmarks(String bookId) {
    return List.unmodifiable(_bookmarks[bookId] ?? []);
  }

  /// Remove a bookmark.
  void removeBookmark(String bookId, int index) {
    _bookmarks[bookId]?.removeAt(index);
  }

  // ── Validation ────────────────────────────────────────────────

  /// Validate chapters: ensure non-negative offsets, sorted order,
  /// within file duration. Filter out invalid entries.
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

    // Ensure sorted by start offset (for embedded) or track index (for separate)
    if (validated.any((ch) => ch.isSeparateTrack)) {
      validated.sort((a, b) => a.trackIndex.compareTo(b.trackIndex));
    } else {
      validated.sort(
          (a, b) => a.startOffset.inMilliseconds.compareTo(
              b.startOffset.inMilliseconds));
    }

    // Remove overlapping chapters (keep the first one)
    final deduped = <UnifiedChapter>[];
    for (final ch in validated) {
      if (deduped.isEmpty) {
        deduped.add(ch);
        continue;
      }
      final prev = deduped.last;
      // For embedded: check overlap
      if (!ch.isSeparateTrack && !prev.isSeparateTrack) {
        if (ch.startOffset < prev.endOffset) {
          // Overlapping — adjust the previous chapter's duration
          final adjustedDuration = ch.startOffset - prev.startOffset;
          if (adjustedDuration > Duration.zero) {
            deduped[deduped.length - 1] = UnifiedChapter(
              id: prev.id,
              title: prev.title,
              startOffset: prev.startOffset,
              duration: adjustedDuration,
              trackItemId: prev.trackItemId,
              imageUrl: prev.imageUrl,
              isSeparateTrack: prev.isSeparateTrack,
              trackIndex: prev.trackIndex,
            );
          }
        }
      }
      deduped.add(ch);
    }

    return deduped;
  }

  /// Create fallback "chapters" for books with no chapter data.
  /// Returns a single chapter spanning the estimated duration.
  List<UnifiedChapter> _createFallbackChapters(String bookId) {
    return [
      UnifiedChapter(
        id: '${bookId}_fallback',
        title: 'Full Book',
        startOffset: Duration.zero,
        duration: const Duration(hours: 1), // Placeholder; updated on load
        trackItemId: bookId,
      ),
    ];
  }

  // ── Caching ───────────────────────────────────────────────────

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

/// The detected chapter format of a book.
enum ChapterFormat {
  /// M4B/M4A with embedded chapter markers.
  embeddedChapters,
  /// Multiple MP3 files, one per chapter.
  mp3PerChapter,
  /// Single file with no chapter markers.
  noChapters,
  /// Mixed: some files with embedded chapters, some separate tracks.
  mixed,
}

/// A user-created bookmark.
class UserBookmark {
  const UserBookmark({
    required this.position,
    required this.createdAt,
    this.note,
    this.chapterId,
  });

  final Duration position;
  final String? note;
  final String? chapterId;
  final DateTime createdAt;
}
