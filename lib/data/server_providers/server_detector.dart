import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../models/server_config.dart';

/// Probes a URL to auto-detect the server type.
///
/// Checks endpoints in order:
/// 1. `/System/Info/Public` → Emby or Jellyfin
/// 2. `/api/status` → Audiobookshelf
/// 3. `/identity` → Plex
class ServerDetector {
  ServerDetector({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// Attempt to detect the server type at the given URL.
  ///
  /// Returns [ServerType] on success.
  /// Throws [ServerDetectionException] if no known server is found.
  Future<ServerDetectionResult> detect(String url) async {
    final baseUrl = url.trimRight('/');

    // Try Emby/Jellyfin first (they share the endpoint)
    try {
      final result = await _probeEmbyJellyfin(baseUrl);
      if (result != null) return result;
    } catch (_) {}

    // Try Audiobookshelf
    try {
      final result = await _probeAudiobookshelf(baseUrl);
      if (result != null) return result;
    } catch (_) {}

    // Try Plex
    try {
      final result = await _probePlex(baseUrl);
      if (result != null) return result;
    } catch (_) {}

    throw ServerDetectionException(url);
  }

  Future<ServerDetectionResult?> _probeEmbyJellyfin(String baseUrl) async {
    final response = await _dio.get(
      '$baseUrl${EmbyApiPaths.systemInfoPublic}',
      options: Options(
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      final serverName = data['ServerName'] as String? ?? 'Media Server';
      final productName = (data['ProductName'] as String? ?? '').toLowerCase();

      // Jellyfin identifies itself in ProductName
      if (productName.contains('jellyfin')) {
        return ServerDetectionResult(
          type: ServerType.jellyfin,
          serverName: serverName,
          version: data['Version'] as String?,
        );
      }

      // Otherwise it's Emby
      return ServerDetectionResult(
        type: ServerType.emby,
        serverName: serverName,
        version: data['Version'] as String?,
      );
    }

    return null;
  }

  Future<ServerDetectionResult?> _probeAudiobookshelf(String baseUrl) async {
    final response = await _dio.get(
      '$baseUrl${AbsApiPaths.status}',
      options: Options(
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map<String, dynamic>;
      // ABS returns { isInit, authMethods, serverVersion, ... }
      if (data.containsKey('isInit') || data.containsKey('serverVersion')) {
        return ServerDetectionResult(
          type: ServerType.audiobookshelf,
          serverName: 'Audiobookshelf',
          version: data['serverVersion'] as String?,
        );
      }
    }

    return null;
  }

  Future<ServerDetectionResult?> _probePlex(String baseUrl) async {
    final response = await _dio.get(
      '$baseUrl${PlexApiPaths.identity}',
      options: Options(
        receiveTimeout: const Duration(seconds: 5),
        validateStatus: (status) => status != null && status < 500),
      ),
    );

    if (response.statusCode == 200) {
      // Plex returns XML by default, but we can check for
      // MediaContainer in JSON mode
      final data = response.data;
      if (data is Map && data.containsKey('MediaContainer')) {
        final mc = data['MediaContainer'] as Map<String, dynamic>;
        return ServerDetectionResult(
          type: ServerType.plex,
          serverName: mc['friendlyName'] as String? ?? 'Plex Server',
          version: mc['version'] as String?,
        );
      }

      // Try string-based detection for XML responses
      if (data is String && data.contains('MediaContainer')) {
        return ServerDetectionResult(
          type: ServerType.plex,
          serverName: 'Plex Server',
        );
      }
    }

    return null;
  }

  void dispose() {
    _dio.close();
  }
}

/// Result of a server detection probe.
class ServerDetectionResult {
  const ServerDetectionResult({
    required this.type,
    required this.serverName,
    this.version,
  });

  final ServerType type;
  final String serverName;
  final String? version;
}

extension on String {
  String trimRight(String char) {
    var s = this;
    while (s.endsWith(char)) {
      s = s.substring(0, s.length - char.length);
    }
    return s;
  }
}
