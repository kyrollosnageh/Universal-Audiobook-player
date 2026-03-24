import 'dart:async';

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
    bool clearGenre = false,
    bool clearAuthor = false,
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
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      filterGenre: clearGenre ? null : (filterGenre ?? this.filterGenre),
      filterAuthor: clearAuthor ? null : (filterAuthor ?? this.filterAuthor),
      activeFilter: activeFilter ?? this.activeFilter,
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

      // Fetch fresh data from server
      final result = await _libraryService.fetchLibrary(
        provider,
        sort: state.sort,
        genre: state.filterGenre,
        author: state.filterAuthor,
      );

      state = state.copyWith(
        books: result.items,
        totalCount: result.totalCount,
        hasMore: result.hasMore,
        isLoading: false,
      );

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
    state = state.copyWith(searchQuery: query.isEmpty ? null : query);

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

    state = state.copyWith(isLoading: true, error: null, hasMore: true);

    try {
      final allBooks = <Book>[];
      var offset = 0;
      const batchSize = AppConstants.backgroundPrefetchBatchSize;

      while (true) {
        final result = await _libraryService.fetchLibrary(
          provider,
          offset: offset,
          limit: batchSize,
          sort: state.sort,
        );
        allBooks.addAll(result.items);

        // Update UI progressively
        state = state.copyWith(
          books: allBooks,
          totalCount: result.totalCount,
          isLoading: false,
        );

        if (!result.hasMore) break;
        offset += batchSize;
      }

      state = state.copyWith(books: allBooks, hasMore: false, isLoading: false);

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
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void dispose() {
    _searchDebounce?.cancel();
  }
}

final libraryNotifierProvider = NotifierProvider<LibraryNotifier, LibraryState>(
  LibraryNotifier.new,
);
