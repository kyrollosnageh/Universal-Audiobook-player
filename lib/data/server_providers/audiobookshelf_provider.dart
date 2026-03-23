import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/extensions.dart';
import '../models/auth_result.dart';
import '../models/book.dart';
import '../models/series.dart';
import '../models/server_config.dart';
import '../models/unified_chapter.dart';
import 'server_provider.dart';

/// Audiobookshelf server provider implementation.
///
/// Uses ABS REST API:
/// - Auth: `/login` for JWT token
/// - Browse: `/api/libraries/{id}/items` with pagination
/// - Detail: `/api/items/{id}` with chapters
/// - Stream: `/api/items/{id}/play` for playback session
/// - Chapters: `/api/items/{id}/chapters` (native chapter support)
/// - Series: `/api/series` (native series API)
/// - Progress: native progress sync via `/api/me/progress/{id}`
class AudiobookshelfProvider implements ServerProvider {
  AudiobookshelfProvider({required String serverUrl, Dio? dio})
    : _serverUrl = serverUrl.trimTrailing('/'),
      _dio = dio ?? Dio() {
    _configureDio();
  }

  final String _serverUrl;
  final Dio _dio;
  String? _token;
  String? _userId;
  String? _defaultLibraryId;

  void _configureDio() {
    _dio.options.baseUrl = _serverUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['Content-Type'] = 'application/json';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            _token = null;
            _userId = null;
            handler.reject(
              DioException(
                requestOptions: error.requestOptions,
                error: const TokenExpiredException(),
                type: DioExceptionType.badResponse,
                response: error.response,
              ),
            );
            return;
          }
          handler.next(error);
        },
      ),
    );
  }

  @override
  String get providerName => 'Audiobookshelf';

  @override
  String get serverUrl => _serverUrl;

  @override
  bool get isAuthenticated => _token != null;

  /// Restore a previously stored session.
  void restoreSession({
    required String token,
    required String userId,
    String? defaultLibraryId,
  }) {
    _token = token;
    _userId = userId;
    _defaultLibraryId = defaultLibraryId;
  }

  String? get token => _token;
  String? get userId => _userId;

  // ── Authentication ────────────────────────────────────────────

  @override
  Future<AuthResult> authenticate(String username, String password) async {
    try {
      final response = await _dio.post(
        AbsApiPaths.login,
        data: {'username': username, 'password': password},
      );

      final data = response.data as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;

      _token = data['token'] as String?;
      _userId = user?['id'] as String?;

      if (_token == null) {
        throw const AuthenticationException('No token received');
      }

      // Fetch default library
      await _fetchDefaultLibrary();

      return AuthResult(
        token: _token!,
        userId: _userId ?? '',
        serverName: 'Audiobookshelf',
        serverType: ServerType.audiobookshelf,
        username: user?['username'] as String?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 400) {
        throw const AuthenticationException('Invalid username or password');
      }
      throw AuthenticationException('Authentication failed: ${e.message}');
    }
  }

  Future<void> _fetchDefaultLibrary() async {
    try {
      final response = await _dio.get(AbsApiPaths.libraries);
      final data = response.data as Map<String, dynamic>;
      final libraries = data['libraries'] as List? ?? [];

      // Find first audiobook library
      for (final lib in libraries) {
        final libMap = lib as Map<String, dynamic>;
        if (libMap['mediaType'] == 'book') {
          _defaultLibraryId = libMap['id'] as String;
          break;
        }
      }

      // Fallback to first library
      _defaultLibraryId ??= libraries.isNotEmpty
          ? (libraries.first as Map<String, dynamic>)['id'] as String
          : null;
    } catch (_) {
      // Non-critical
    }
  }

  @override
  Future<void> logout() async {
    // ABS doesn't have a dedicated logout endpoint;
    // JWT just expires. Clear locally.
    _token = null;
    _userId = null;
    _defaultLibraryId = null;
  }

  // ── Library Browsing ──────────────────────────────────────────

  @override
  Future<PaginatedResult<Book>> fetchLibrary({
    int offset = 0,
    int limit = 50,
    String? searchTerm,
    String? genre,
    String? author,
    String? narrator,
    String? libraryId,
    SortOrder sort = SortOrder.titleAsc,
  }) async {
    _requireAuth();
    final libId = libraryId ?? _defaultLibraryId;
    if (libId == null) {
      throw const ServerUnreachableException('No library ID available');
    }

    try {
      // ABS uses a different endpoint for search
      if (searchTerm != null && searchTerm.isNotEmpty) {
        return _searchLibrary(libId, searchTerm, limit);
      }

      final params = <String, dynamic>{
        'limit': limit,
        'page': offset ~/ limit,
        'sort': _mapSortField(sort),
        'desc': _isSortDescending(sort) ? 1 : 0,
        'filter': _buildFilter(
          genre: genre,
          author: author,
          narrator: narrator,
        ),
      };

      // Remove null/empty filter
      params.removeWhere((k, v) => v == null || v == '');

      final response = await _dio.get(
        AbsApiPaths.libraryItems(libId),
        queryParameters: params,
      );

      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];
      final total = data['total'] as int? ?? 0;

      final books = results.map((item) => _mapToBook(item)).toList();

      return PaginatedResult<Book>(
        items: books,
        totalCount: total,
        offset: offset,
        limit: limit,
      );
    } on DioException catch (e) {
      throw ServerUnreachableException('$_serverUrl: ${e.message}');
    }
  }

  Future<PaginatedResult<Book>> _searchLibrary(
    String libraryId,
    String query,
    int limit,
  ) async {
    final response = await _dio.get(
      '/api/libraries/$libraryId/search',
      queryParameters: {'q': query, 'limit': limit},
    );

    final data = response.data as Map<String, dynamic>;
    final bookResults = data['book'] as List? ?? [];

    final books = bookResults.map((result) {
      final item = result['libraryItem'] as Map<String, dynamic>;
      return _mapToBook(item);
    }).toList();

    return PaginatedResult<Book>(
      items: books,
      totalCount: books.length,
      offset: 0,
      limit: limit,
    );
  }

  // ── Book Details ──────────────────────────────────────────────

  @override
  Future<BookDetail> getBookDetail(String bookId) async {
    _requireAuth();

    try {
      final response = await _dio.get(
        AbsApiPaths.itemDetail(bookId),
        queryParameters: {'expanded': 1},
      );

      final data = response.data as Map<String, dynamic>;
      return _mapToBookDetail(data);
    } on DioException catch (e) {
      throw ServerUnreachableException(
        'Failed to fetch book detail: ${e.message}',
      );
    }
  }

  @override
  Future<List<UnifiedChapter>> getChapters(String bookId) async {
    _requireAuth();

    try {
      final response = await _dio.get(
        AbsApiPaths.itemDetail(bookId),
        queryParameters: {'expanded': 1},
      );

      final data = response.data as Map<String, dynamic>;
      final media = data['media'] as Map<String, dynamic>? ?? {};
      final chapters = media['chapters'] as List? ?? [];

      if (chapters.isEmpty) {
        // Fall back to audio tracks
        final tracks = media['audioFiles'] as List? ?? [];
        return _tracksToChapters(tracks, bookId);
      }

      return _parseAbsChapters(chapters, bookId);
    } on DioException catch (e) {
      throw ChapterParsingException(
        'Failed to fetch chapters: ${e.message}',
        e,
      );
    }
  }

  // ── Streaming ─────────────────────────────────────────────────

  @override
  Uri getStreamUrl(String itemId, {AudioFormat? transcode}) {
    // ABS streaming via direct file access
    return Uri.parse(
      '$_serverUrl/api/items/$itemId/file',
    ).withQueryParams({'token': _token ?? ''});
  }

  @override
  Uri getCoverArtUrl(String itemId, {int maxWidth = 300}) {
    return Uri.parse(
      '$_serverUrl/api/items/$itemId/cover',
    ).withQueryParams({'width': maxWidth.toString(), 'token': _token ?? ''});
  }

  // ── Progress Sync ─────────────────────────────────────────────

  @override
  Future<void> reportPosition(String bookId, Duration position) async {
    _requireAuth();

    try {
      await _dio.patch(
        '/api/me/progress/$bookId',
        data: {
          'currentTime': position.inSeconds.toDouble(),
          'isFinished': false,
        },
      );
    } on DioException {
      // Non-critical
    }
  }

  @override
  Future<Duration?> getServerPosition(String bookId) async {
    _requireAuth();

    try {
      final response = await _dio.get('/api/me/progress/$bookId');
      final data = response.data as Map<String, dynamic>;
      final currentTime = data['currentTime'] as num?;

      if (currentTime == null || currentTime == 0) return null;
      return Duration(seconds: currentTime.toInt());
    } on DioException {
      return null;
    }
  }

  // ── Finished Status ──────────────────────────────────────────

  @override
  Future<void> reportFinished(String bookId, bool isFinished) async {
    _requireAuth();
    try {
      await _dio.patch(
        '/api/me/progress/$bookId',
        data: {'isFinished': isFinished},
      );
    } on DioException {
      // Non-critical
    }
  }

  @override
  Future<bool?> getServerFinished(String bookId) async {
    _requireAuth();
    try {
      final response = await _dio.get('/api/me/progress/$bookId');
      final data = response.data as Map<String, dynamic>;
      return data['isFinished'] as bool?;
    } on DioException {
      return null;
    }
  }

  // ── Favorites ──────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String bookId, bool isFavorite) async {
    // Audiobookshelf does not have a favorite/rating API.
    // Favorites are stored locally only for ABS users.
  }

  @override
  Future<void> setRating(String bookId, double rating) async {
    // Audiobookshelf does not have a rating API.
  }

  // ── Series ────────────────────────────────────────────────────

  @override
  Future<List<Series>> getSeries() async {
    _requireAuth();
    if (_defaultLibraryId == null) return [];

    try {
      final response = await _dio.get(
        '/api/libraries/$_defaultLibraryId/series',
        queryParameters: {'limit': 100},
      );

      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];

      return results.map((s) {
        final map = s as Map<String, dynamic>;
        return Series(
          id: map['id'] as String? ?? '',
          serverId: _serverUrl,
          name: map['name'] as String? ?? 'Unknown Series',
          totalBooks: (map['books'] as List?)?.length ?? 0,
        );
      }).toList();
    } on DioException {
      return [];
    }
  }

  @override
  Future<List<Book>> getSeriesBooks(String seriesId) async {
    _requireAuth();
    if (_defaultLibraryId == null) return [];

    try {
      final response = await _dio.get(
        AbsApiPaths.libraryItems(_defaultLibraryId!),
        queryParameters: {
          'filter': 'series.$seriesId',
          'sort': 'media.metadata.series.sequence',
          'limit': 100,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final results = data['results'] as List? ?? [];

      return results.map((item) => _mapToBook(item)).toList();
    } on DioException {
      return [];
    }
  }

  @override
  void dispose() {
    _dio.close();
  }

  // ── Private Helpers ───────────────────────────────────────────

  void _requireAuth() {
    if (!isAuthenticated) {
      throw const AuthenticationException('Not authenticated');
    }
  }

  Book _mapToBook(dynamic item) {
    final map = item as Map<String, dynamic>;
    final media = map['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};

    final durationSec = media['duration'] as num?;
    final progress = map['userMediaProgress'] as Map<String, dynamic>?;

    String? coverUrl;
    if (map['id'] != null) {
      coverUrl = getCoverArtUrl(map['id'] as String).toString();
    }

    // Extract series info
    final seriesList = metadata['series'] as List?;
    String? seriesName;
    double? seriesIndex;
    if (seriesList != null && seriesList.isNotEmpty) {
      final firstSeries = seriesList.first as Map<String, dynamic>;
      seriesName = firstSeries['name'] as String?;
      final seqStr = firstSeries['sequence'] as String?;
      if (seqStr != null) {
        seriesIndex = double.tryParse(seqStr);
      }
    }

    return Book(
      id: map['id'] as String? ?? '',
      serverId: _serverUrl,
      title: metadata['title'] as String? ?? 'Unknown',
      author: metadata['authorName'] as String?,
      narrator: metadata['narratorName'] as String?,
      coverUrl: coverUrl,
      duration: durationSec != null
          ? Duration(seconds: durationSec.toInt())
          : null,
      progress: progress?['progress'] as double?,
      seriesName: seriesName,
      seriesIndex: seriesIndex,
      genre: (metadata['genres'] as List?)?.firstOrNull as String?,
      year: metadata['publishedYear'] != null
          ? int.tryParse(metadata['publishedYear'].toString())
          : null,
      dateAdded: map['addedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['addedAt'] as num).toInt())
          : null,
    );
  }

  BookDetail _mapToBookDetail(Map<String, dynamic> data) {
    final book = _mapToBook(data);
    final media = data['media'] as Map<String, dynamic>? ?? {};
    final metadata = media['metadata'] as Map<String, dynamic>? ?? {};

    return BookDetail(
      book: book,
      description: metadata['description'] as String?,
      publisher: metadata['publisher'] as String?,
      isbn: metadata['isbn'] as String?,
      asin: metadata['asin'] as String?,
      language: metadata['language'] as String?,
      genres:
          (metadata['genres'] as List?)?.map((g) => g.toString()).toList() ??
          const [],
      tags:
          (data['tags'] as List?)?.map((t) => t.toString()).toList() ??
          const [],
    );
  }

  List<UnifiedChapter> _parseAbsChapters(
    List<dynamic> chapters,
    String bookId,
  ) {
    return chapters.asMap().entries.map((entry) {
      final ch = entry.value as Map<String, dynamic>;
      final startSec = (ch['start'] as num?)?.toDouble() ?? 0;
      final endSec = (ch['end'] as num?)?.toDouble() ?? 0;

      return UnifiedChapter(
        id: '${bookId}_ch_${entry.key}',
        title: ch['title'] as String? ?? 'Chapter ${entry.key + 1}',
        startOffset: Duration(milliseconds: (startSec * 1000).toInt()),
        duration: Duration(milliseconds: ((endSec - startSec) * 1000).toInt()),
        trackItemId: bookId,
        isSeparateTrack: false,
        trackIndex: 0,
      );
    }).toList();
  }

  List<UnifiedChapter> _tracksToChapters(List<dynamic> tracks, String bookId) {
    var cumulativeOffset = Duration.zero;

    return tracks.asMap().entries.map((entry) {
      final track = entry.value as Map<String, dynamic>;
      final durationSec = (track['duration'] as num?)?.toDouble() ?? 0;
      final duration = Duration(milliseconds: (durationSec * 1000).toInt());
      final ino = track['ino'] as String? ?? '${bookId}_track_${entry.key}';

      final chapter = UnifiedChapter(
        id: ino,
        title:
            track['metadata']?['title'] as String? ?? 'Track ${entry.key + 1}',
        startOffset: cumulativeOffset,
        duration: duration,
        trackItemId: ino,
        isSeparateTrack: true,
        trackIndex: entry.key,
      );

      cumulativeOffset += duration;
      return chapter;
    }).toList();
  }

  String _mapSortField(SortOrder sort) {
    switch (sort) {
      case SortOrder.titleAsc:
      case SortOrder.titleDesc:
        return 'media.metadata.title';
      case SortOrder.authorAsc:
      case SortOrder.authorDesc:
        return 'media.metadata.authorName';
      case SortOrder.dateAddedDesc:
      case SortOrder.dateAddedAsc:
        return 'addedAt';
      case SortOrder.datePlayedDesc:
        return 'progress';
      case SortOrder.communityRatingDesc:
        return 'media.metadata.title';
    }
  }

  bool _isSortDescending(SortOrder sort) {
    switch (sort) {
      case SortOrder.titleDesc:
      case SortOrder.authorDesc:
      case SortOrder.dateAddedDesc:
      case SortOrder.datePlayedDesc:
      case SortOrder.communityRatingDesc:
        return true;
      case SortOrder.titleAsc:
      case SortOrder.authorAsc:
      case SortOrder.dateAddedAsc:
        return false;
    }
  }

  String? _buildFilter({String? genre, String? author, String? narrator}) {
    final filters = <String>[];
    if (genre != null) filters.add('genres.$genre');
    if (author != null) filters.add('authors.$author');
    if (narrator != null) filters.add('narrators.$narrator');
    return filters.isNotEmpty ? filters.join(',') : null;
  }
}
