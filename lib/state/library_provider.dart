import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/models/auth_result.dart';
import '../data/models/book.dart';
import '../services/library_service.dart';
import '../services/sync_service.dart';
import 'auth_provider.dart';

/// Library service provider.
final libraryServiceProvider = Provider<LibraryService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = LibraryService(database: db);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Sync service provider.
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(databaseProvider);
  return SyncService(database: db);
});

/// Filter for the library drawer navigation.
enum LibraryFilter { all, recentlyAdded, currentlyReading, favorites, finished }

/// Library state.
class LibraryState {
  const LibraryState({
    this.books = const [],
    this.continueListening = const [],
    this.favoriteBooks = const [],
    this.finishedBooks = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.totalCount = 0,
    this.error,
    this.searchQuery,
    this.sort = SortOrder.titleAsc,
    this.filterGenre,
    this.filterAuthor,
    this.activeFilter = LibraryFilter.all,
    this.isSyncing = false,
    this.syncProgress = 0.0,
    this.syncedCount = 0,
  });

  final List<Book> books;
  final List<Book> continueListening;
  final List<Book> favoriteBooks;
  final List<Book> finishedBooks;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int totalCount;
  final String? error;
  final String? searchQuery;
  final SortOrder sort;
  final String? filterGenre;
  final String? filterAuthor;
  final LibraryFilter activeFilter;
  final bool isSyncing;
  final double syncProgress;
  final int syncedCount;

  LibraryState copyWith({
    List<Book>? books,
    List<Book>? continueListening,
    List<Book>? favoriteBooks,
    List<Book>? finishedBooks,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? totalCount,
    String? error,
    String? searchQuery,
    SortOrder? sort,
    String? filterGenre,
    String? filterAuthor,
    LibraryFilter? activeFilter,
    bool clearSearch = false,
    bool clearGenre = false,
    bool clearAuthor = false,
    bool? isSyncing,
    double? syncProgress,
    int? syncedCount,
  }) {
    return LibraryState(
      books: books ?? this.books,
      continueListening: continueListening ?? this.continueListening,
      favoriteBooks: favoriteBooks ?? this.favoriteBooks,
      finishedBooks: finishedBooks ?? this.finishedBooks,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      totalCount: totalCount ?? this.totalCount,
      error: error,
      searchQuery: clearSearch ? null : (searchQuery ?? this.searchQuery),
      sort: sort ?? this.sort,
      filterGenre: clearGenre ? null : (filterGenre ?? this.filterGenre),
      filterAuthor: clearAuthor ? null : (filterAuthor ?? this.filterAuthor),
      activeFilter: activeFilter ?? this.activeFilter,
      isSyncing: isSyncing ?? this.isSyncing,
      syncProgress: syncProgress ?? this.syncProgress,
      syncedCount: syncedCount ?? this.syncedCount,
    );
  }

  /// Books filtered by the active drawer filter.
  List<Book> get displayedBooks {
    return switch (activeFilter) {
      LibraryFilter.all => books,
      LibraryFilter.recentlyAdded => books,
      LibraryFilter.currentlyReading => continueListening,
      LibraryFilter.favorites => favoriteBooks,
      LibraryFilter.finished => finishedBooks,
    };
  }
}

class LibraryNotifier extends Notifier<LibraryState> {
  late LibraryService _libraryService;
  late SyncService _syncService;
  Timer? _searchDebounce;

  @override
  LibraryState build() {
    _libraryService = ref.read(libraryServiceProvider);
    _syncService = ref.read(syncServiceProvider);
    ref.onDispose(() {
      _searchDebounce?.cancel();
    });
    return const LibraryState();
  }

  /// Load the initial library page + continue listening.
  Future<void> loadLibrary() async {
    final provider = ref.read(activeServerProvider);
    if (provider == null) return;

    state = state.copyWith(isLoading: true, error: null, hasMore: true);

    try {
      final serverId = provider.serverUrl;

      // Show cached data instantly (parallel DB reads)
      final cachedFutures = await Future.wait([
        _libraryService.getCachedBooks(serverId),
        _libraryService.getContinueListening(serverId),
        _libraryService.getFavoriteBooks(serverId),
        _libraryService.getFinishedBooks(serverId),
      ]);

      final cached = cachedFutures[0];
      if (cached.isNotEmpty) {
        state = state.copyWith(
          books: cached,
          continueListening: cachedFutures[1],
          favoriteBooks: cachedFutures[2],
          finishedBooks: cachedFutures[3],
          isLoading: false,
        );
      }

      // Fetch ALL books from server (paginated)
      final allBooks = <Book>[];
      var offset = 0;
      const pageSize = 10000;
      int totalCount = 0;

      while (true) {
        final result = await _libraryService.fetchLibrary(
          provider,
          offset: offset,
          limit: pageSize,
          sort: state.sort,
          genre: state.filterGenre,
          author: state.filterAuthor,
        );

        debugPrint(
          'Library fetch: got ${result.items.length} items, '
          'total=${result.totalCount}, offset=$offset, '
          'hasMore=${result.hasMore}',
        );

        allBooks.addAll(result.items);
        totalCount = result.totalCount;

        // Update UI progressively
        state = state.copyWith(
          books: allBooks,
          totalCount: totalCount,
          isLoading: allBooks.isEmpty,
        );

        // Stop if: got fewer than requested, or no items, or we have them all
        if (result.items.length < pageSize || result.items.isEmpty) break;
        offset += pageSize;
      }

      state = state.copyWith(
        books: allBooks,
        totalCount: allBooks.length > totalCount ? allBooks.length : totalCount,
        hasMore: false,
        isLoading: false,
      );

      // Save book count to server entry for display on hub
      final activeServer = ref.read(authNotifierProvider).activeServer;
      if (activeServer != null) {
        try {
          final db = ref.read(databaseProvider);
          await db.serverDao.updateServerMeta(
            activeServer.id,
            bookCount: totalCount,
            lastConnectedAt: DateTime.now(),
          );
          // Invalidate so hub re-reads from DB next time
          ref.invalidate(savedServersProvider);
        } catch (e) {
          debugPrint('Failed to save book count: $e');
        }
      }

      // Refresh shelves in background (parallel DB reads)
      final freshShelves = await Future.wait([
        _libraryService.getContinueListening(serverId),
        _libraryService.getFavoriteBooks(serverId),
        _libraryService.getFinishedBooks(serverId),
      ]);
      state = state.copyWith(
        continueListening: freshShelves[0],
        favoriteBooks: freshShelves[1],
        finishedBooks: freshShelves[2],
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load the next page (infinite scroll).
  /// Only applies to server-paginated filters (all, recentlyAdded).
  Future<void> loadMore() async {
    if (state.activeFilter != LibraryFilter.all &&
        state.activeFilter != LibraryFilter.recentlyAdded)
      return;
    if (state.isLoadingMore || !state.hasMore) return;

    final provider = ref.read(activeServerProvider);
    if (provider == null) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final result = await _libraryService.fetchLibrary(
        provider,
        offset: state.books.length,
        searchTerm: state.searchQuery,
        sort: state.sort,
        genre: state.filterGenre,
        author: state.filterAuthor,
      );

      state = state.copyWith(
        books: [...state.books, ...result.items],
        totalCount: result.totalCount,
        hasMore: result.hasMore,
        isLoadingMore: false,
      );
    } catch (e) {
      state = state.copyWith(isLoadingMore: false);
    }
  }

  /// Search with hybrid local-first + server strategy.
  void search(String query) {
    if (query.isEmpty) {
      state = state.copyWith(clearSearch: true);
    } else {
      state = state.copyWith(searchQuery: query);
    }

    if (query.isEmpty) {
      loadLibrary();
      return;
    }

    // Immediately search local cache
    _searchLocal(query);

    // Debounce server search
    _searchDebounce?.cancel();
    _searchDebounce = Timer(AppConstants.searchDebounce, () {
      _searchServer(query);
    });
  }

  Future<void> _searchLocal(String query) async {
    final provider = ref.read(activeServerProvider);
    if (provider == null) return;

    final local = await _libraryService.searchLocal(query, provider.serverUrl);

    if (state.searchQuery == query) {
      state = state.copyWith(books: local);
    }
  }

  Future<void> _searchServer(String query) async {
    final provider = ref.read(activeServerProvider);
    if (provider == null) return;

    try {
      final serverResult = await _libraryService.searchServer(provider, query);

      // Merge with current local results
      if (state.searchQuery == query) {
        final merged = _libraryService.mergeResults(
          state.books,
          serverResult.items,
        );
        state = state.copyWith(
          books: merged,
          totalCount: serverResult.totalCount,
          hasMore: serverResult.hasMore,
        );
      }
    } catch (_) {
      // Server search failed; local results remain
    }
  }

  /// Toggle a book's favorite status and sync to server.
  Future<void> toggleFavorite(Book book) async {
    final provider = ref.read(activeServerProvider);
    if (provider == null) return;

    final newValue = !book.isFavorite;
    await _syncService.toggleFavorite(
      provider,
      bookId: book.id,
      serverId: book.serverId,
      isFavorite: newValue,
    );

    // Update local state
    _updateBookInState(book.id, (b) => b.copyWith(isFavorite: newValue));
    final favorites = await _libraryService.getFavoriteBooks(book.serverId);
    state = state.copyWith(favoriteBooks: favorites);
  }

  /// Toggle a book's finished status and sync to server.
  Future<void> toggleFinished(Book book) async {
    final provider = ref.read(activeServerProvider);
    if (provider == null) return;

    final newValue = !book.isFinished;
    await _syncService.markFinished(
      provider,
      bookId: book.id,
      serverId: book.serverId,
      isFinished: newValue,
    );

    // Update local state
    _updateBookInState(book.id, (b) => b.copyWith(isFinished: newValue));
    final serverId = book.serverId;
    final continueListening = await _libraryService.getContinueListening(
      serverId,
    );
    final finished = await _libraryService.getFinishedBooks(serverId);
    state = state.copyWith(
      continueListening: continueListening,
      finishedBooks: finished,
    );
  }

  /// Helper: update a book in all lists in state.
  void _updateBookInState(String bookId, Book Function(Book) updater) {
    state = state.copyWith(
      books: state.books.map((b) => b.id == bookId ? updater(b) : b).toList(),
      continueListening: state.continueListening
          .map((b) => b.id == bookId ? updater(b) : b)
          .toList(),
      favoriteBooks: state.favoriteBooks
          .map((b) => b.id == bookId ? updater(b) : b)
          .toList(),
      finishedBooks: state.finishedBooks
          .map((b) => b.id == bookId ? updater(b) : b)
          .toList(),
    );
  }

  /// Change sort order.
  void setSort(SortOrder sort) {
    state = state.copyWith(sort: sort);
    loadLibrary();
  }

  /// Set genre filter. Resets active filter to "all" so the grid shows
  /// the server-filtered results.
  void setGenreFilter(String? genre) {
    if (genre == null) {
      state = state.copyWith(clearGenre: true, activeFilter: LibraryFilter.all);
    } else {
      state = state.copyWith(
        filterGenre: genre,
        activeFilter: LibraryFilter.all,
      );
    }
    loadLibrary();
  }

  /// Set author filter.
  void setAuthorFilter(String? author) {
    if (author == null) {
      state = state.copyWith(clearAuthor: true);
    } else {
      state = state.copyWith(filterAuthor: author);
    }
    loadLibrary();
  }

  /// Set the drawer filter.
  /// Client-side filters (favorites, finished, currentlyReading) don't
  /// need a server round-trip — the data is already loaded.
  void setFilter(LibraryFilter filter) {
    if (filter == LibraryFilter.recentlyAdded) {
      state = state.copyWith(
        activeFilter: filter,
        sort: SortOrder.dateAddedDesc,
      );
      loadLibrary();
    } else if (filter == LibraryFilter.all) {
      state = state.copyWith(activeFilter: filter);
      loadLibrary();
    } else {
      // currentlyReading, favorites, finished — data already in state
      state = state.copyWith(activeFilter: filter);
    }
  }

  /// Sync all books from the server by fetching every page.
  Future<void> syncAll() async {
    final provider = ref.read(activeServerProvider);
    if (provider == null) return;
    if (state.isSyncing) return; // Prevent double-sync

    // Use smaller batches so progress is visible
    const batchSize = 10000;

    // Show syncing state immediately with indeterminate progress
    state = state.copyWith(
      error: null,
      hasMore: true,
      isSyncing: true,
      syncProgress: 0.0,
      syncedCount: 0,
    );

    try {
      final allBooks = <Book>[];
      var offset = 0;

      // First fetch to get totalCount
      final firstResult = await _libraryService.fetchLibrary(
        provider,
        offset: 0,
        limit: batchSize,
        sort: state.sort,
      );
      allBooks.addAll(firstResult.items);
      // Use the larger of totalCount or what we'll accumulate
      var total = firstResult.totalCount;
      if (total == 0) total = firstResult.items.length;

      debugPrint(
        'Sync first batch: got ${firstResult.items.length}, '
        'totalCount=$total',
      );

      // Update with real numbers
      state = state.copyWith(
        books: allBooks,
        totalCount: total,
        syncProgress: total > 0 ? allBooks.length / total : 0.0,
        syncedCount: allBooks.length,
      );

      // Fetch remaining pages — stop when we get fewer than requested
      if (firstResult.items.length >= batchSize) {
        offset += batchSize;

        while (true) {
          final result = await _libraryService.fetchLibrary(
            provider,
            offset: offset,
            limit: batchSize,
            sort: state.sort,
          );

          debugPrint(
            'Sync batch: got ${result.items.length}, offset=$offset',
          );

          if (result.items.isEmpty) break;
          allBooks.addAll(result.items);
          if (result.totalCount > total) total = result.totalCount;

          state = state.copyWith(
            books: allBooks,
            totalCount: total,
            syncProgress: total > 0 ? allBooks.length / total : 1.0,
            syncedCount: allBooks.length,
          );

          if (result.items.length < batchSize) break;
          offset += batchSize;
        }
      }

      // Show completed state briefly
      state = state.copyWith(
        books: allBooks,
        hasMore: false,
        syncProgress: 1.0,
        syncedCount: allBooks.length,
        totalCount: total,
      );

      // Refresh shelves
      final serverId = provider.serverUrl;
      final shelves = await Future.wait([
        _libraryService.getContinueListening(serverId),
        _libraryService.getFavoriteBooks(serverId),
        _libraryService.getFinishedBooks(serverId),
      ]);
      state = state.copyWith(
        continueListening: shelves[0],
        favoriteBooks: shelves[1],
        finishedBooks: shelves[2],
      );

      // Keep bar visible for 1.5s so user sees completion
      await Future.delayed(const Duration(milliseconds: 1500));
      state = state.copyWith(isSyncing: false);
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncProgress: 0.0,
        error: e.toString(),
      );
    }
  }
}

final libraryNotifierProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
