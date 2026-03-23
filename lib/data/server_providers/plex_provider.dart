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

/// Plex server provider — the most complex implementation.
///
/// Key differences from other providers:
/// - Auth is OAuth via plex.tv (not username/password to the server)
/// - Audiobooks stored as "music" — needs heuristics to detect audiobooks
/// - Chapters come as track listings (albums -> tracks)
/// - Series mapped via collections
/// - Uses X-Plex-Token for all requests
class PlexProvider implements ServerProvider {
  PlexProvider({required String serverUrl, Dio? dio})
    : _serverUrl = serverUrl.trimTrailing('/'),
      _dio = dio ?? Dio(),
      _plexTvDio = Dio() {
    _configureDio();
  }

  final String _serverUrl;
  final Dio _dio;
  final Dio _plexTvDio;
  String? _token;
  String? _userId;
  String? _audioLibrarySectionId;

  static const String _clientId = 'libretto-audiobook-player';
  static const String _product = 'Libretto';
  static const String _version = '1.0.0';

  void _configureDio() {
    _dio.options.baseUrl = _serverUrl;
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
    _dio.options.headers['Accept'] = 'application/json';

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.queryParameters['X-Plex-Token'] = _token;
          }
          options.queryParameters.addAll({
            'X-Plex-Client-Identifier': _clientId,
            'X-Plex-Product': _product,
            'X-Plex-Version': _version,
          });
          handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            _token = null;
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
  String get providerName => 'Plex';

  @override
  String get serverUrl => _serverUrl;

  @override
  bool get isAuthenticated => _token != null;

  /// Restore a previously stored auth session.
  void restoreSession({
    required String token,
    required String userId,
    String? audioLibrarySectionId,
  }) {
    _token = token;
    _userId = userId;
    _audioLibrarySectionId = audioLibrarySectionId;
  }

  String? get token => _token;

  // ── Authentication (OAuth via plex.tv) ────────────────────────

  /// Plex uses OAuth — this method handles the token exchange.
  ///
  /// For mobile apps, the flow is:
  /// 1. Create a PIN at plex.tv/api/v2/pins
  /// 2. Open browser to plex.tv auth URL with PIN
  /// 3. Poll for PIN completion
  /// 4. Extract token from completed PIN
  ///
  /// [username] and [password] are used for direct sign-in as fallback.
  @override
  Future<AuthResult> authenticate(String username, String password) async {
    try {
      // Try direct sign-in via plex.tv
      final response = await _plexTvDio.post(
        'https://plex.tv/users/sign_in.json',
        data: {
          'user': {'login': username, 'password': password},
        },
        options: Options(
          headers: {
            'X-Plex-Client-Identifier': _clientId,
            'X-Plex-Product': _product,
            'X-Plex-Version': _version,
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;

      _token = user?['authToken'] as String?;
      _userId = user?['id']?.toString();

      if (_token == null) {
        throw const AuthenticationException('No token received from Plex');
      }

      // Detect the audio/music library
      await _detectAudioLibrary();

      return AuthResult(
        token: _token!,
        userId: _userId ?? '',
        serverName: 'Plex Server',
        serverType: ServerType.plex,
        username: user?['username'] as String?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthenticationException('Invalid Plex credentials');
      }
      throw AuthenticationException('Plex authentication failed: ${e.message}');
    }
  }

  /// Generate a Plex OAuth PIN for browser-based auth.
  Future<PlexAuthPin> createAuthPin() async {
    final response = await _plexTvDio.post(
      PlexApiPaths.plexTvPins,
      queryParameters: {
        'strong': true,
        'X-Plex-Client-Identifier': _clientId,
        'X-Plex-Product': _product,
      },
      options: Options(headers: {'Accept': 'application/json'}),
    );

    final data = response.data as Map<String, dynamic>;
    final pinId = data['id'] as int;
    final code = data['code'] as String;

    final authUrl =
        '${PlexApiPaths.plexTvAuth}'
        '#!?clientID=$_clientId&code=$code';

    return PlexAuthPin(id: pinId, code: code, authUrl: authUrl);
  }

  /// Poll for PIN completion after user authenticates in browser.
  Future<AuthResult?> checkAuthPin(int pinId) async {
    final response = await _plexTvDio.get(
      '${PlexApiPaths.plexTvPins}/$pinId',
      queryParameters: {'X-Plex-Client-Identifier': _clientId},
      options: Options(headers: {'Accept': 'application/json'}),
    );

    final data = response.data as Map<String, dynamic>;
    final authToken = data['authToken'] as String?;

    if (authToken == null) return null; // Not yet authenticated

    _token = authToken;
    await _detectAudioLibrary();

    return AuthResult(
      token: _token!,
      userId: '',
      serverName: 'Plex Server',
      serverType: ServerType.plex,
    );
  }

  Future<void> _detectAudioLibrary() async {
    try {
      final response = await _dio.get('/library/sections');
      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final directories = mc['Directory'] as List? ?? [];

      for (final dir in directories) {
        final dirMap = dir as Map<String, dynamic>;
        final type = dirMap['type'] as String?;
        final title = (dirMap['title'] as String? ?? '').toLowerCase();

        // Audiobooks in Plex are stored as "artist" (music) type
        // Look for libraries with audiobook-related names
        if (type == 'artist' &&
            (title.contains('audiobook') ||
                title.contains('audio book') ||
                title.contains('book'))) {
          _audioLibrarySectionId = dirMap['key'] as String?;
          return;
        }
      }

      // Fallback: use first music library
      for (final dir in directories) {
        final dirMap = dir as Map<String, dynamic>;
        if (dirMap['type'] == 'artist') {
          _audioLibrarySectionId = dirMap['key'] as String?;
          return;
        }
      }
    } catch (_) {}
  }

  @override
  Future<void> logout() async {
    // Revoke token via plex.tv (if possible)
    if (_token != null) {
      try {
        await _plexTvDio.delete(
          'https://plex.tv/api/v2/tokens/$_token',
          options: Options(
            headers: {
              'X-Plex-Client-Identifier': _clientId,
              'X-Plex-Token': _token,
            },
          ),
        );
      } catch (_) {}
    }

    _token = null;
    _userId = null;
    _audioLibrarySectionId = null;
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
    final sectionId = libraryId ?? _audioLibrarySectionId;
    if (sectionId == null) {
      return const PaginatedResult(
        items: [],
        totalCount: 0,
        offset: 0,
        limit: 50,
      );
    }

    try {
      final params = <String, dynamic>{
        'type': 9, // album type
        'X-Plex-Container-Start': offset,
        'X-Plex-Container-Size': limit,
        'sort': _mapPlexSort(sort),
      };

      if (searchTerm != null && searchTerm.isNotEmpty) {
        params['title'] = searchTerm;
      }
      if (genre != null) params['genre'] = genre;
      if (author != null) params['artist.title'] = author;

      final response = await _dio.get(
        PlexApiPaths.librarySections(sectionId),
        queryParameters: params,
      );

      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final items = mc['Metadata'] as List? ?? [];
      final totalCount =
          mc['totalSize'] as int? ?? mc['size'] as int? ?? items.length;

      // Heuristic: filter to only items that look like audiobooks
      final books = items
          .map((item) => _mapPlexAlbumToBook(item))
          .where((book) => _looksLikeAudiobook(book))
          .toList();

      return PaginatedResult<Book>(
        items: books,
        totalCount: totalCount,
        offset: offset,
        limit: limit,
      );
    } on DioException catch (e) {
      throw ServerUnreachableException('$_serverUrl: ${e.message}');
    }
  }

  // ── Book Details ──────────────────────────────────────────────

  @override
  Future<BookDetail> getBookDetail(String bookId) async {
    _requireAuth();

    try {
      final response = await _dio.get(PlexApiPaths.metadata(bookId));

      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final items = mc['Metadata'] as List? ?? [];

      if (items.isEmpty) {
        throw ServerUnreachableException('Book not found: $bookId');
      }

      return _mapPlexAlbumToBookDetail(items.first);
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
      // Plex audiobook chapters are tracks within an album
      final response = await _dio.get(PlexApiPaths.children(bookId));

      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final tracks = mc['Metadata'] as List? ?? [];

      if (tracks.isEmpty) return [];

      return _tracksToChapters(tracks, bookId);
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
    // Plex direct stream
    return Uri.parse(
      '$_serverUrl/library/parts/$itemId/file',
    ).withQueryParams({'X-Plex-Token': _token ?? ''});
  }

  @override
  Uri getCoverArtUrl(String itemId, {int maxWidth = 300}) {
    return Uri.parse(
      '$_serverUrl/library/metadata/$itemId/thumb',
    ).withQueryParams({
      'width': maxWidth.toString(),
      'height': maxWidth.toString(),
      'X-Plex-Token': _token ?? '',
    });
  }

  // ── Progress Sync ─────────────────────────────────────────────

  @override
  Future<void> reportPosition(String bookId, Duration position) async {
    _requireAuth();

    try {
      await _dio.get(
        '/:/timeline',
        queryParameters: {
          'ratingKey': bookId,
          'key': '/library/metadata/$bookId',
          'state': 'playing',
          'time': position.inMilliseconds,
          'duration': 0,
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
      final response = await _dio.get(PlexApiPaths.metadata(bookId));

      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final items = mc['Metadata'] as List? ?? [];

      if (items.isEmpty) return null;

      final item = items.first as Map<String, dynamic>;
      final viewOffset = item['viewOffset'] as int?;

      if (viewOffset == null || viewOffset == 0) return null;
      return Duration(milliseconds: viewOffset);
    } on DioException {
      return null;
    }
  }

  // ── Finished Status ──────────────────────────────────────────

  @override
  Future<void> reportFinished(String bookId, bool isFinished) async {
    _requireAuth();
    try {
      if (isFinished) {
        await _dio.get(
          '/:/scrobble',
          queryParameters: {
            'identifier': 'com.plexapp.plugins.library',
            'key': '/library/metadata/$bookId',
          },
        );
      } else {
        await _dio.get(
          '/:/unscrobble',
          queryParameters: {
            'identifier': 'com.plexapp.plugins.library',
            'key': '/library/metadata/$bookId',
          },
        );
      }
    } on DioException {
      // Non-critical
    }
  }

  @override
  Future<bool?> getServerFinished(String bookId) async {
    _requireAuth();
    try {
      final response = await _dio.get(PlexApiPaths.metadata(bookId));
      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final items = mc['Metadata'] as List? ?? [];
      if (items.isEmpty) return null;
      final item = items.first as Map<String, dynamic>;
      final viewCount = item['viewCount'] as int?;
      return viewCount != null && viewCount > 0;
    } on DioException {
      return null;
    }
  }

  // ── Favorites ──────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String bookId, bool isFavorite) async {
    _requireAuth();
    try {
      // Plex uses rating=10 as "loved"
      await _dio.put(
        '/:/rate',
        queryParameters: {
          'key': '/library/metadata/$bookId',
          'identifier': 'com.plexapp.plugins.library',
          'rating': isFavorite ? 10 : 0,
        },
      );
    } on DioException {
      // Non-critical
    }
  }

  @override
  Future<void> setRating(String bookId, double rating) async {
    _requireAuth();
    try {
      // Plex uses 0-10 scale, we normalize from 0.0-1.0
      await _dio.put(
        '/:/rate',
        queryParameters: {
          'key': '/library/metadata/$bookId',
          'identifier': 'com.plexapp.plugins.library',
          'rating': (rating * 10).round(),
        },
      );
    } on DioException {
      // Non-critical
    }
  }

  // ── Series (via Collections) ──────────────────────────────────

  @override
  Future<List<Series>> getSeries() async {
    _requireAuth();
    if (_audioLibrarySectionId == null) return [];

    try {
      final response = await _dio.get(
        '/library/sections/$_audioLibrarySectionId/collections',
      );

      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final collections = mc['Metadata'] as List? ?? [];

      return collections.map((c) {
        final map = c as Map<String, dynamic>;
        return Series(
          id: map['ratingKey'] as String? ?? '',
          serverId: _serverUrl,
          name: map['title'] as String? ?? 'Unknown Collection',
          totalBooks: map['childCount'] as int? ?? 0,
        );
      }).toList();
    } on DioException {
      return [];
    }
  }

  @override
  Future<List<Book>> getSeriesBooks(String seriesId) async {
    _requireAuth();

    try {
      final response = await _dio.get(PlexApiPaths.children(seriesId));

      final data = response.data as Map<String, dynamic>;
      final mc = data['MediaContainer'] as Map<String, dynamic>? ?? {};
      final items = mc['Metadata'] as List? ?? [];

      return items.map((item) => _mapPlexAlbumToBook(item)).toList();
    } on DioException {
      return [];
    }
  }

  @override
  void dispose() {
    _dio.close();
    _plexTvDio.close();
  }

  // ── Private Helpers ───────────────────────────────────────────

  void _requireAuth() {
    if (!isAuthenticated) {
      throw const AuthenticationException('Not authenticated');
    }
  }

  Book _mapPlexAlbumToBook(dynamic item) {
    final map = item as Map<String, dynamic>;
    final ratingKey = map['ratingKey'] as String? ?? '';
    final durationMs = map['duration'] as int?;
    final viewOffset = map['viewOffset'] as int?;

    double? progress;
    if (durationMs != null && durationMs > 0 && viewOffset != null) {
      progress = viewOffset / durationMs;
    }

    return Book(
      id: ratingKey,
      serverId: _serverUrl,
      title: map['title'] as String? ?? 'Unknown',
      author: map['parentTitle'] as String?, // Artist = Author
      coverUrl: ratingKey.isNotEmpty
          ? getCoverArtUrl(ratingKey).toString()
          : null,
      duration: durationMs != null ? Duration(milliseconds: durationMs) : null,
      progress: progress,
      genre: map['genre'] as String?,
      year: map['year'] as int?,
      dateAdded: map['addedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['addedAt'] as int) * 1000)
          : null,
    );
  }

  BookDetail _mapPlexAlbumToBookDetail(dynamic item) {
    final book = _mapPlexAlbumToBook(item);
    final map = item as Map<String, dynamic>;

    return BookDetail(
      book: book,
      description: map['summary'] as String?,
      publisher: map['studio'] as String?,
      genres:
          (map['Genre'] as List?)
              ?.map((g) => (g as Map)['tag'] as String? ?? '')
              .toList() ??
          const [],
    );
  }

  List<UnifiedChapter> _tracksToChapters(List<dynamic> tracks, String albumId) {
    var cumulativeOffset = Duration.zero;

    return tracks.asMap().entries.map((entry) {
      final track = entry.value as Map<String, dynamic>;
      final durationMs = track['duration'] as int? ?? 0;
      final duration = Duration(milliseconds: durationMs);
      final ratingKey =
          track['ratingKey'] as String? ?? '${albumId}_track_${entry.key}';

      // Get the media part key for streaming
      final mediaList = track['Media'] as List?;
      String partKey = ratingKey;
      if (mediaList != null && mediaList.isNotEmpty) {
        final parts =
            (mediaList.first as Map<String, dynamic>)['Part'] as List?;
        if (parts != null && parts.isNotEmpty) {
          partKey =
              (parts.first as Map<String, dynamic>)['id']?.toString() ??
              ratingKey;
        }
      }

      final chapter = UnifiedChapter(
        id: ratingKey,
        title: track['title'] as String? ?? 'Track ${entry.key + 1}',
        startOffset: cumulativeOffset,
        duration: duration,
        trackItemId: partKey,
        isSeparateTrack: true,
        trackIndex: entry.key,
      );

      cumulativeOffset += duration;
      return chapter;
    }).toList();
  }

  /// Heuristic: determine if a Plex album looks like an audiobook.
  bool _looksLikeAudiobook(Book book) {
    // In a dedicated audiobook library, everything is an audiobook
    // This heuristic is for mixed music/audiobook libraries
    final title = book.title.toLowerCase();

    // Long duration suggests audiobook (> 1 hour)
    if (book.duration != null && book.duration!.inHours >= 1) {
      return true;
    }

    // Check for audiobook-related keywords
    if (title.contains('unabridged') ||
        title.contains('audiobook') ||
        title.contains('narrated')) {
      return true;
    }

    // If the library is detected as audiobook-specific, include all
    return true;
  }

  String _mapPlexSort(SortOrder sort) {
    switch (sort) {
      case SortOrder.titleAsc:
        return 'titleSort:asc';
      case SortOrder.titleDesc:
        return 'titleSort:desc';
      case SortOrder.authorAsc:
        return 'artist.titleSort:asc';
      case SortOrder.authorDesc:
        return 'artist.titleSort:desc';
      case SortOrder.dateAddedDesc:
        return 'addedAt:desc';
      case SortOrder.dateAddedAsc:
        return 'addedAt:asc';
      case SortOrder.datePlayedDesc:
        return 'lastViewedAt:desc';
      case SortOrder.communityRatingDesc:
        return 'rating:desc';
    }
  }
}

/// Plex OAuth PIN for browser-based authentication.
class PlexAuthPin {
  const PlexAuthPin({
    required this.id,
    required this.code,
    required this.authUrl,
  });

  final int id;
  final String code;
  final String authUrl;
}
