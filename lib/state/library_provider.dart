import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants.dart';
import '../data/models/auth_result.dart';
import '../data/models/book.dart';
import '../services/library_service.dart';
import 'auth_provider.dart';

/// Library service provider.
final libraryServiceProvider = Provider<LibraryService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = LibraryService(database: db);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Library state.
class LibraryState {
  const LibraryState({
    this.books = const [],
    this.continueListening = const [],
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.totalCount = 0,
    this.error,
    this.searchQuery,
    this.sort = SortOrder.titleAsc,
    this.filterGenre,
    this.filterAuthor,
  });

  final List<Book> books;
  final List<Book> continueListening;
  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final int totalCount;
  final String? error;
  final String? searchQuery;
  final SortOrder sort;
  final String? filterGenre;
  final String? filterAuthor;

  LibraryState copyWith({
    List<Book>? books,
    List<Book>? continueListening,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? totalCount,
    String? error,
    String? searchQuery,
    SortOrder? sort,
    String? filterGenre,
    String? filterAuthor,
  }) {
    return LibraryState(
      books: books ?? this.books,
      continueListening: continueListening ?? this.continueListening,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      totalCount: totalCount ?? this.totalCount,
      error: error,
      searchQuery: searchQuery ?? this.searchQuery,
      sort: sort ?? this.sort,
      filterGenre: filterGenre,
      filterAuthor: filterAuthor,
    );
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  LibraryNotifier(this._libraryService, this._ref)
      : super(const LibraryState());

  final LibraryService _libraryService;
  final Ref _ref;
  Timer? _searchDebounce;

  /// Load the initial library page + continue listening.
  Future<void> loadLibrary() async {
    final provider = _ref.read(activeServerProvider);
    if (provider == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      // Show cached data instantly
      final serverId = provider.serverUrl;
      final cached = await _libraryService.getCachedBooks(serverId);
      final continueListening =
          await _libraryService.getContinueListening(serverId);

      if (cached.isNotEmpty) {
        state = state.copyWith(
          books: cached,
          continueListening: continueListening,
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

      // Refresh continue listening
      final freshContinue =
          await _libraryService.getContinueListening(serverId);
      state = state.copyWith(continueListening: freshContinue);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// Load the next page (infinite scroll).
  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore) return;

    final provider = _ref.read(activeServerProvider);
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
    final provider = _ref.read(activeServerProvider);
    if (provider == null) return;

    final local = await _libraryService.searchLocal(
      query,
      provider.serverUrl,
    );

    if (state.searchQuery == query) {
      state = state.copyWith(books: local);
    }
  }

  Future<void> _searchServer(String query) async {
    final provider = _ref.read(activeServerProvider);
    if (provider == null) return;

    try {
      final serverResult =
          await _libraryService.searchServer(provider, query);

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

  /// Change sort order.
  void setSort(SortOrder sort) {
    state = state.copyWith(sort: sort);
    loadLibrary();
  }

  /// Set genre filter.
  void setGenreFilter(String? genre) {
    state = state.copyWith(filterGenre: genre);
    loadLibrary();
  }

  /// Set author filter.
  void setAuthorFilter(String? author) {
    state = state.copyWith(filterAuthor: author);
    loadLibrary();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}

final libraryNotifierProvider =
    StateNotifierProvider<LibraryNotifier, LibraryState>((ref) {
  final libraryService = ref.watch(libraryServiceProvider);
  return LibraryNotifier(libraryService, ref);
});
