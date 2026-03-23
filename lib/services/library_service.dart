import 'package:dio/dio.dart';

import '../core/constants.dart';
import '../data/database/app_database.dart';
import '../data/database/daos/book_dao.dart';
import '../data/models/auth_result.dart';
import '../data/models/book.dart';
import '../data/server_providers/server_provider.dart';

/// Manages library browsing with pagination, caching, and hybrid search.
///
/// Strategy:
/// - Always uses server-side pagination (never fetches full library)
/// - Caches book metadata in Drift for instant local search
/// - On first launch, prefetches library in background batches of 200
/// - Deduplicates search results (local + server)
class LibraryService {
  LibraryService({
    required AppDatabase database,
  }) : _bookDao = database.bookDao;

  final BookDao _bookDao;

  CancelToken? _searchCancelToken;

  // ── Library Fetching ──────────────────────────────────────────────

  /// Fetch a page of books from the server and cache them.
  Future<PaginatedResult<Book>> fetchLibrary(
    ServerProvider provider, {
    int offset = 0,
    int limit = AppConstants.defaultPageSize,
    String? searchTerm,
    String? genre,
    String? author,
    String? narrator,
    String? libraryId,
    SortOrder sort = SortOrder.titleAsc,
  }) async {
    final result = await provider.fetchLibrary(
      offset: offset,
      limit: limit,
      searchTerm: searchTerm,
      genre: genre,
      author: author,
      narrator: narrator,
      libraryId: libraryId,
      sort: sort,
    );

    // Cache results in background
    _cacheBooks(result.items, provider.serverUrl);

    return result;
  }

  // ── Hybrid Search ─────────────────────────────────────────────────

  /// Search locally first (instant), then fire server request after debounce.
  ///
  /// Returns local results immediately. Call [searchServer] separately
  /// after the debounce period for server results.
  Future<List<Book>> searchLocal(String query, String serverId) async {
    if (query.isEmpty) return [];

    final entries = await _bookDao.searchBooks(query, serverId);
    return entries.map(_bookEntryToBook).toList();
  }

  /// Search the server (call after 300ms debounce).
  /// Cancels any previous in-flight search request.
  Future<PaginatedResult<Book>> searchServer(
    ServerProvider provider,
    String query,
  ) async {
    // Cancel previous search
    _searchCancelToken?.cancel();
    _searchCancelToken = CancelToken();

    final result = await provider.fetchLibrary(
      searchTerm: query,
      limit: AppConstants.searchResultLimit,
    );

    // Cache new results
    _cacheBooks(result.items, provider.serverUrl);

    return result;
  }

  /// Merge and deduplicate local + server search results.
  List<Book> mergeResults(List<Book> local, List<Book> server) {
    final seen = <String>{};
    final merged = <Book>[];

    // Server results take priority (fresher data)
    for (final book in server) {
      if (seen.add(book.id)) {
        merged.add(book);
      }
    }

    // Add local results not already present
    for (final book in local) {
      if (seen.add(book.id)) {
        merged.add(book);
      }
    }

    return merged;
  }

  // ── Continue Listening ────────────────────────────────────────────

  /// Get books the user is currently reading (progress > 0 and < 1).
  Future<List<Book>> getContinueListening(String serverId) async {
    final entries = await _bookDao.getContinueListening(serverId);
    return entries.map(_bookEntryToBook).toList();
  }

  // ── Cached Data ───────────────────────────────────────────────────

  /// Get cached books (for instant display on app launch).
  Future<List<Book>> getCachedBooks(
    String serverId, {
    int offset = 0,
    int limit = AppConstants.defaultPageSize,
  }) async {
    final entries = await _bookDao.getBooks(
      serverId,
      offset: offset,
      limit: limit,
    );
    return entries.map(_bookEntryToBook).toList();
  }

  /// Get the number of cached books.
  Future<int> getCachedBookCount(String serverId) {
    return _bookDao.getBookCount(serverId);
  }

  // ── Background Prefetch ───────────────────────────────────────────

  /// Prefetch the library in background batches to fill the local cache.
  ///
  /// Called on first launch or when cache is empty.
  /// Yields progress as (fetched, total) for UI feedback.
  Stream<(int, int)> prefetchLibrary(ServerProvider provider) async* {
    var offset = 0;
    const batchSize = AppConstants.backgroundPrefetchBatchSize;
    int? totalCount;

    while (true) {
      final result = await provider.fetchLibrary(
        offset: offset,
        limit: batchSize,
      );

      totalCount ??= result.totalCount;
      _cacheBooks(result.items, provider.serverUrl);

      offset += result.items.length;
      yield (offset, totalCount);

      if (!result.hasMore) break;
    }
  }

  // ── Cache Management ──────────────────────────────────────────────

  Future<void> _cacheBooks(List<Book> books, String serverId) async {
    final entries = books.map((b) => _bookToEntry(b, serverId)).toList();
    await _bookDao.upsertBooks(entries);
  }

  /// Clear the cached library for a server.
  Future<void> clearCache(String serverId) {
    return _bookDao.clearServerBooks(serverId);
  }

  void dispose() {
    _searchCancelToken?.cancel();
  }

  // ── Mapping ───────────────────────────────────────────────────────

  Book _bookEntryToBook(BookEntry entry) {
    return Book(
      id: entry.id,
      serverId: entry.serverId,
      title: entry.title,
      author: entry.author,
      narrator: entry.narrator,
      coverUrl: entry.coverUrl,
      duration: entry.durationMs != null
          ? Duration(milliseconds: entry.durationMs!)
          : null,
      progress: entry.progress,
      seriesName: entry.seriesName,
      seriesIndex: entry.seriesIndex,
      genre: entry.genre,
      year: entry.year,
      dateAdded: entry.dateAdded,
      lastPlayedAt: entry.lastPlayedAt,
      isDownloaded: entry.isDownloaded,
    );
  }

  BookEntry _bookToEntry(Book book, String serverId) {
    return BookEntry(
      id: book.id,
      serverId: serverId,
      title: book.title,
      author: book.author,
      narrator: book.narrator,
      coverUrl: book.coverUrl,
      durationMs: book.duration?.inMilliseconds,
      progress: book.progress,
      seriesName: book.seriesName,
      seriesIndex: book.seriesIndex,
      genre: book.genre,
      year: book.year,
      dateAdded: book.dateAdded,
      lastPlayedAt: book.lastPlayedAt,
      isDownloaded: book.isDownloaded,
      cachedAt: DateTime.now(),
    );
  }
}
