import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/extensions.dart';
import '../models/auth_result.dart';
import '../models/book.dart';
import '../models/series.dart';
import '../models/server_config.dart';
import '../models/unified_chapter.dart';
import 'server_provider.dart';

/// Emby server provider implementation.
///
/// Uses Emby's REST API:
/// - Auth: `/Users/AuthenticateByName`
/// - Browse: `/Users/{UserId}/Items` with pagination
/// - Detail: `/Items/{ItemId}`
/// - Stream: `/Audio/{ItemId}/stream`
/// - Chapters: embedded in item detail response
class EmbyProvider implements ServerProvider {
  EmbyProvider({required String serverUrl, Dio? dio})
    : _serverUrl = serverUrl.trimTrailing('/'),
      _dio = dio ?? Dio() {
    _configureDio();
  }

  final String _serverUrl;
  final Dio _dio;
  String? _token;
  String? _userId;
  String? _serverId;

  static const String _clientName = 'Libretto';
  static const String _deviceName = 'Flutter';
  static String _deviceId = '';
  static const String _clientVersion = '1.0.0';

  static Future<void> initDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('libretto_device_id') ?? '';
    if (_deviceId.isEmpty) {
      _deviceId = 'libretto-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      await prefs.setString('libretto_device_id', _deviceId);
    }
  }

  void _configureDio() {
    _dio.options.baseUrl = _serverUrl;
    _dio.options.connectTimeout = const Duration(seconds: 5);
    _dio.options.receiveTimeout = const Duration(seconds: 10);
    _dio.options.headers['Content-Type'] = 'application/json';
    _dio.options.headers['Accept-Encoding'] = 'gzip';

    // Add auth interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.headers['X-Emby-Authorization'] = _buildAuthHeader();
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

  String _buildAuthHeader() {
    final parts = [
      'MediaBrowser Client="$_clientName"',
      'Device="$_deviceName"',
      'DeviceId="$_deviceId"',
      'Version="$_clientVersion"',
    ];
    if (_token != null) {
      parts.add('Token="$_token"');
    }
    return parts.join(', ');
  }

  @override
  String get providerName => 'Emby';

  @override
  String get serverUrl => _serverUrl;

  @override
  bool get isAuthenticated => _token != null && _userId != null;

  /// Restore a previously stored auth session.
  void restoreSession({
    required String token,
    required String userId,
    String? serverId,
  }) {
    _token = token;
    _userId = userId;
    _serverId = serverId;
  }

  String? get userId => _userId;
  String? get token => _token;

  // ── Authentication ────────────────────────────────────────────────

  @override
  Future<AuthResult> authenticate(String username, String password) async {
    try {
      final response = await _dio.post(
        EmbyApiPaths.authenticateByName,
        data: {'Username': username, 'Pw': password},
      );

      final data = response.data as Map<String, dynamic>;
      _token = data['AccessToken'] as String;
      _userId = data['User']?['Id'] as String?;
      _serverId = data['ServerId'] as String?;

      final serverName =
          data['User']?['ServerName'] as String? ?? 'Emby Server';

      // Password is now out of scope and will be GC'd.
      return AuthResult(
        token: _token!,
        userId: _userId!,
        serverName: serverName,
        serverType: ServerType.emby,
        serverId: _serverId,
        username: data['User']?['Name'] as String?,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const AuthenticationException('Invalid username or password');
      }
      throw AuthenticationException('Authentication failed: ${e.message}');
    }
  }

  @override
  Future<void> logout() async {
    if (_token != null) {
      try {
        await _dio.post(EmbyApiPaths.sessionsLogout);
      } catch (_) {
        // Best-effort server-side logout; always clear locally.
      }
    }
    _token = null;
    _userId = null;
    _serverId = null;
  }

  // ── Library Browsing ──────────────────────────────────────────────

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

    final params = <String, dynamic>{
      'IncludeItemTypes': 'AudioBook',
      'Recursive': true,
      'StartIndex': offset,
      'Limit': limit,
      'Fields':
          'Genres,DateCreated,RunTimeTicks,'
          'SeriesName,IndexNumber',
      'EnableUserData': true,
      'ImageTypeLimit': 1,
      'EnableImageTypes': 'Primary',
      'SortBy': _mapSortBy(sort),
      'SortOrder': _mapSortOrder(sort),
    };

    if (searchTerm != null && searchTerm.isNotEmpty) {
      params['SearchTerm'] = searchTerm;
    }
    if (genre != null) params['Genres'] = genre;
    if (author != null) params['Artists'] = author;
    if (libraryId != null) params['ParentId'] = libraryId;

    try {
      final response = await _dio.get(
        EmbyApiPaths.userItems(_userId!),
        queryParameters: params,
      );

      final data = response.data as Map<String, dynamic>;
      final items = (data['Items'] as List<dynamic>?) ?? [];
      final totalCount = data['TotalRecordCount'] as int? ?? 0;

      final books = items.map((item) => _mapItemToBook(item)).toList();

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

  // ── Book Details ──────────────────────────────────────────────────

  /// Cache for the last fetched detail response, keyed by bookId.
  /// Avoids duplicate API calls when detail + chapters are requested
  /// for the same book.
  final Map<String, Map<String, dynamic>> _detailCache = {};

  Future<Map<String, dynamic>> _fetchDetailData(String bookId) async {
    if (_detailCache.containsKey(bookId)) return _detailCache[bookId]!;

    final response = await _dio.get(
      EmbyApiPaths.userItemDetail(_userId!, bookId),
      queryParameters: {
        'Fields':
            'Overview,Genres,Studios,DateCreated,RunTimeTicks,'
            'MediaSources,Chapters,People,Tags,'
            'SeriesName,IndexNumber',
        'EnableUserData': true,
      },
    );

    final data = response.data as Map<String, dynamic>;
    _detailCache[bookId] = data;
    return data;
  }

  @override
  Future<BookDetail> getBookDetail(String bookId) async {
    _requireAuth();

    try {
      final data = await _fetchDetailData(bookId);
      return _mapItemToBookDetail(data);
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
      final data = await _fetchDetailData(bookId);
      return _parseChapters(data, bookId);
    } on DioException catch (e) {
      throw ChapterParsingException(
        'Failed to fetch chapters: ${e.message}',
        e,
      );
    }
  }

  // ── Streaming ─────────────────────────────────────────────────────

  @override
  Uri getStreamUrl(String itemId, {AudioFormat? transcode}) {
    final uri = Uri.parse('$_serverUrl${EmbyApiPaths.audioStream(itemId)}');
    final params = <String, String>{
      'Static': transcode == null || transcode == AudioFormat.original
          ? 'true'
          : 'false',
      'api_key': _token ?? '',
    };

    if (transcode != null && transcode != AudioFormat.original) {
      params['AudioCodec'] = _mapAudioFormat(transcode);
    }

    return uri.withQueryParams(params);
  }

  @override
  Uri getCoverArtUrl(String itemId, {int maxWidth = 200}) {
    final uri = Uri.parse('$_serverUrl${EmbyApiPaths.itemImage(itemId)}');
    return uri.withQueryParams({
      'maxWidth': maxWidth.toString(),
      'quality': '80',
      'api_key': _token ?? '',
    });
  }

  // ── Progress Sync ─────────────────────────────────────────────────

  @override
  Future<void> reportPosition(String bookId, Duration position) async {
    _requireAuth();

    try {
      await _dio.post(
        '/Users/$_userId/PlayingItems/$bookId/Progress',
        queryParameters: {'PositionTicks': position.toTicks()},
      );
    } on DioException {
      // Non-critical — position saved locally regardless.
    }
  }

  @override
  Future<Duration?> getServerPosition(String bookId) async {
    _requireAuth();

    try {
      final response = await _dio.get(
        EmbyApiPaths.userItems(_userId!),
        queryParameters: {'Ids': bookId, 'Fields': 'UserData'},
      );

      final data = response.data as Map<String, dynamic>;
      final items = (data['Items'] as List<dynamic>?) ?? [];
      if (items.isEmpty) return null;

      final item = items.first as Map<String, dynamic>;
      final userData = item['UserData'] as Map<String, dynamic>?;
      final ticks = userData?['PlaybackPositionTicks'] as int?;

      if (ticks == null || ticks == 0) return null;
      return ticks.ticksToDuration();
    } on DioException {
      return null;
    }
  }

  // ── Finished Status ──────────────────────────────────────────────

  @override
  Future<void> reportFinished(String bookId, bool isFinished) async {
    _requireAuth();
    try {
      if (isFinished) {
        await _dio.post('/Users/$_userId/PlayedItems/$bookId');
      } else {
        await _dio.delete('/Users/$_userId/PlayedItems/$bookId');
      }
    } on DioException {
      // Non-critical
    }
  }

  @override
  Future<bool?> getServerFinished(String bookId) async {
    _requireAuth();
    try {
      final response = await _dio.get(
        EmbyApiPaths.userItems(_userId!),
        queryParameters: {'Ids': bookId, 'Fields': 'UserData'},
      );
      final data = response.data as Map<String, dynamic>;
      final items = (data['Items'] as List<dynamic>?) ?? [];
      if (items.isEmpty) return null;
      final item = items.first as Map<String, dynamic>;
      final userData = item['UserData'] as Map<String, dynamic>?;
      return userData?['Played'] as bool?;
    } on DioException {
      return null;
    }
  }

  // ── Favorites ──────────────────────────────────────────────────────

  @override
  Future<void> setFavorite(String bookId, bool isFavorite) async {
    _requireAuth();
    try {
      if (isFavorite) {
        await _dio.post('/Users/$_userId/FavoriteItems/$bookId');
      } else {
        await _dio.delete('/Users/$_userId/FavoriteItems/$bookId');
      }
    } on DioException {
      // Non-critical
    }
  }

  @override
  Future<void> setRating(String bookId, double rating) async {
    _requireAuth();
    try {
      await _dio.post(
        '/Users/$_userId/Items/$bookId/Rating',
        queryParameters: {'likes': rating >= 0.5},
      );
    } on DioException {
      // Non-critical
    }
  }

  // ── Series ────────────────────────────────────────────────────────

  @override
  Future<List<Series>> getSeries() async {
    _requireAuth();

    try {
      // Emby doesn't have a native series API for audiobooks.
      // We group by SeriesName from book metadata.
      await _dio.get(
        EmbyApiPaths.userItems(_userId!),
        queryParameters: {
          'IncludeItemTypes': 'AudioBook',
          'Recursive': true,
          'Fields': 'SeriesName,IndexNumber,RunTimeTicks',
          'Limit': 0, // We just need the grouping metadata
          'GroupItemsIntoCollections': true,
        },
      );

      // For now, return empty — full series detection in Phase 5.
      return [];
    } on DioException {
      return [];
    }
  }

  @override
  Future<List<Book>> getSeriesBooks(String seriesId) async {
    _requireAuth();

    try {
      final response = await _dio.get(
        EmbyApiPaths.userItems(_userId!),
        queryParameters: {
          'IncludeItemTypes': 'AudioBook',
          'Recursive': true,
          'Fields': 'SeriesName,IndexNumber,RunTimeTicks,Overview',
          'SortBy': 'IndexNumber',
          'SortOrder': 'Ascending',
          // seriesId is the series name for Emby
          'NameStartsWith': seriesId,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final items = (data['Items'] as List<dynamic>?) ?? [];
      return items.map((item) => _mapItemToBook(item)).toList();
    } on DioException {
      return [];
    }
  }

  @override
  void dispose() {
    _dio.close();
  }

  // ── Private Helpers ───────────────────────────────────────────────

  void _requireAuth() {
    if (!isAuthenticated) {
      throw const AuthenticationException('Not authenticated');
    }
  }

  Book _mapItemToBook(dynamic item) {
    final map = item as Map<String, dynamic>;
    final userData = map['UserData'] as Map<String, dynamic>?;
    final ticks = map['RunTimeTicks'] as int?;
    final playbackTicks = userData?['PlaybackPositionTicks'] as int?;

    double? progress;
    if (ticks != null && ticks > 0 && playbackTicks != null) {
      progress = playbackTicks / ticks;
    }

    return Book(
      id: map['Id'] as String,
      serverId: _serverId ?? _serverUrl,
      title: map['Name'] as String? ?? 'Unknown',
      author: _extractPerson(map, 'Author') ?? (map['AlbumArtist'] as String?),
      narrator: _extractPerson(map, 'Narrator'),
      coverUrl:
          map['ImageTags'] != null &&
              (map['ImageTags'] as Map).containsKey('Primary')
          ? getCoverArtUrl(map['Id'] as String).toString()
          : null,
      duration: ticks?.ticksToDuration(),
      progress: progress,
      seriesName: map['SeriesName'] as String?,
      seriesIndex: (map['IndexNumber'] as num?)?.toDouble(),
      genre: (map['Genres'] as List?)?.firstOrNull as String?,
      year: map['ProductionYear'] as int?,
      dateAdded: map['DateCreated'] != null
          ? DateTime.tryParse(map['DateCreated'] as String)
          : null,
      lastPlayedAt: userData?['LastPlayedDate'] != null
          ? DateTime.tryParse(userData!['LastPlayedDate'] as String)
          : null,
      isFavorite: userData?['IsFavorite'] as bool? ?? false,
      isFinished: userData?['Played'] as bool? ?? false,
    );
  }

  BookDetail _mapItemToBookDetail(Map<String, dynamic> data) {
    final book = _mapItemToBook(data);
    final mediaSources = data['MediaSources'] as List?;
    final firstSource = mediaSources?.firstOrNull as Map<String, dynamic>?;

    return BookDetail(
      book: book,
      description: data['Overview'] as String?,
      publisher: (data['Studios'] as List?)?.firstOrNull?['Name'] as String?,
      language: data['Language'] as String?,
      fileSize: firstSource?['Size'] as int?,
      audioFormat: firstSource?['Container'] as String?,
      bitrate: firstSource?['Bitrate'] as int?,
      communityRating: (data['CommunityRating'] as num?)?.toDouble(),
      parentId: data['ParentId'] as String?,
      genres:
          (data['Genres'] as List?)?.map((g) => g as String).toList() ??
          const [],
      tags:
          (data['Tags'] as List?)?.map((t) => t as String).toList() ?? const [],
    );
  }

  List<UnifiedChapter> _parseChapters(
    Map<String, dynamic> data,
    String bookId,
  ) {
    final chapters = data['Chapters'] as List?;

    // Case 1: Embedded chapters in a single file (M4B/M4A)
    if (chapters != null && chapters.isNotEmpty) {
      return _parseEmbeddedChapters(chapters, bookId, data);
    }

    // Case 2: Multiple child tracks (MP3-per-chapter)
    // This is detected by having child items — handled via separate call
    // in ChapterService.

    // Case 3: No chapters — return a single "chapter" spanning the whole file
    final ticks = data['RunTimeTicks'] as int?;
    final duration = ticks != null
        ? ticks.ticksToDuration()
        : const Duration(hours: 1);

    return [
      UnifiedChapter(
        id: '${bookId}_full',
        title: data['Name'] as String? ?? 'Full Book',
        startOffset: Duration.zero,
        duration: duration,
        trackItemId: bookId,
      ),
    ];
  }

  List<UnifiedChapter> _parseEmbeddedChapters(
    List<dynamic> chapters,
    String bookId,
    Map<String, dynamic> parentData,
  ) {
    final totalTicks = parentData['RunTimeTicks'] as int? ?? 0;
    final totalDuration = totalTicks.ticksToDuration();
    final result = <UnifiedChapter>[];

    for (var i = 0; i < chapters.length; i++) {
      final ch = chapters[i] as Map<String, dynamic>;
      final startTicks = ch['StartPositionTicks'] as int? ?? 0;
      final startOffset = startTicks.ticksToDuration();

      // Duration = next chapter start - this chapter start
      // (or total duration - start for last chapter)
      Duration chapterDuration;
      if (i < chapters.length - 1) {
        final nextStart =
            (chapters[i + 1] as Map<String, dynamic>)['StartPositionTicks']
                as int? ??
            0;
        chapterDuration = nextStart.ticksToDuration() - startOffset;
      } else {
        chapterDuration = totalDuration - startOffset;
      }

      // Validate: skip chapters with non-positive duration
      if (chapterDuration.inMilliseconds <= 0) continue;

      // Validate: skip chapters that start beyond file duration
      if (startOffset > totalDuration) continue;

      final name = ch['Name'] as String? ?? 'Chapter ${i + 1}';

      result.add(
        UnifiedChapter(
          id: '${bookId}_ch_$i',
          title: name,
          startOffset: startOffset,
          duration: chapterDuration,
          trackItemId: bookId,
          isSeparateTrack: false,
          trackIndex: 0,
        ),
      );
    }

    return result;
  }

  /// Fetch child items (for MP3-per-chapter books).
  Future<List<UnifiedChapter>> fetchChildTracks(String parentId) async {
    _requireAuth();

    final response = await _dio.get(
      EmbyApiPaths.userItems(_userId!),
      queryParameters: {
        'ParentId': parentId,
        'IncludeItemTypes': 'Audio',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Fields': 'RunTimeTicks,SortName',
      },
    );

    final data = response.data as Map<String, dynamic>;
    final items = (data['Items'] as List<dynamic>?) ?? [];

    var cumulativeOffset = Duration.zero;
    final chapters = <UnifiedChapter>[];

    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final ticks = item['RunTimeTicks'] as int? ?? 0;
      final duration = ticks.ticksToDuration();

      chapters.add(
        UnifiedChapter(
          id: item['Id'] as String,
          title: item['Name'] as String? ?? 'Track ${i + 1}',
          startOffset: cumulativeOffset,
          duration: duration,
          trackItemId: item['Id'] as String,
          isSeparateTrack: true,
          trackIndex: i,
        ),
      );

      cumulativeOffset += duration;
    }

    return chapters;
  }

  String? _extractPerson(Map<String, dynamic> item, String type) {
    final people = item['People'] as List?;
    if (people == null) return null;
    for (final person in people) {
      final p = person as Map<String, dynamic>;
      if (p['Type'] == type) return p['Name'] as String?;
    }
    return null;
  }

  String _mapSortBy(SortOrder sort) {
    switch (sort) {
      case SortOrder.titleAsc:
      case SortOrder.titleDesc:
        return 'SortName';
      case SortOrder.authorAsc:
      case SortOrder.authorDesc:
        return 'AlbumArtist,SortName';
      case SortOrder.dateAddedDesc:
      case SortOrder.dateAddedAsc:
        return 'DateCreated';
      case SortOrder.datePlayedDesc:
        return 'DatePlayed';
      case SortOrder.communityRatingDesc:
        return 'CommunityRating';
    }
  }

  String _mapSortOrder(SortOrder sort) {
    switch (sort) {
      case SortOrder.titleDesc:
      case SortOrder.authorDesc:
      case SortOrder.dateAddedDesc:
      case SortOrder.datePlayedDesc:
      case SortOrder.communityRatingDesc:
        return 'Descending';
      case SortOrder.titleAsc:
      case SortOrder.authorAsc:
      case SortOrder.dateAddedAsc:
        return 'Ascending';
    }
  }

  String _mapAudioFormat(AudioFormat format) {
    switch (format) {
      case AudioFormat.aac:
        return 'aac';
      case AudioFormat.mp3:
        return 'mp3';
      case AudioFormat.opus:
        return 'opus';
      case AudioFormat.flac:
        return 'flac';
      case AudioFormat.original:
        return '';
    }
  }
}
