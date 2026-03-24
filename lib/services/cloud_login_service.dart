import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../data/models/server_config.dart';

/// A server discovered from a cloud account.
class CloudServer {
  const CloudServer({
    required this.name,
    required this.url,
    required this.type,
    this.version,
    this.isOnline = false,
  });

  final String name;
  final String url;
  final ServerType type;
  final String? version;
  final bool isOnline;
}

/// Handles cloud account login for Plex and Emby Connect.
class CloudLoginService {
  CloudLoginService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  // ── Plex Cloud Login ──────────────────────────────────────────

  /// Step 1: Request a PIN from Plex.tv.
  /// Returns a map with 'id' (pin ID) and 'code' (user-facing code).
  Future<Map<String, dynamic>> requestPlexPin() async {
    final response = await _dio.post(
      'https://plex.tv/api/v2/pins',
      options: Options(
        headers: {
          'Accept': 'application/json',
          'X-Plex-Client-Identifier': 'libretto-audiobook-player',
          'X-Plex-Product': 'Libretto',
          'X-Plex-Version': '1.0.0',
        },
        contentType: 'application/x-www-form-urlencoded',
      ),
      data: 'strong=true',
    );

    final data = response.data as Map<String, dynamic>;
    return {
      'id': data['id'] as int,
      'code': data['code'] as String,
    };
  }

  /// Get the Plex auth URL the user should open in their browser.
  String getPlexAuthUrl(String code) {
    return 'https://app.plex.tv/auth#?clientID=libretto-audiobook-player'
        '&code=$code'
        '&context%5Bdevice%5D%5Bproduct%5D=Libretto';
  }

  /// Step 2: Poll for PIN completion. Returns the auth token when the user
  /// completes auth, or null if not yet completed.
  Future<String?> checkPlexPin(int pinId) async {
    try {
      final response = await _dio.get(
        'https://plex.tv/api/v2/pins/$pinId',
        options: Options(
          headers: {
            'Accept': 'application/json',
            'X-Plex-Client-Identifier': 'libretto-audiobook-player',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final token = data['authToken'] as String?;
      return (token != null && token.isNotEmpty) ? token : null;
    } catch (_) {
      return null;
    }
  }

  /// Step 3: Fetch all servers linked to the Plex account.
  Future<List<CloudServer>> fetchPlexServers(String authToken) async {
    final response = await _dio.get(
      'https://plex.tv/api/v2/resources',
      options: Options(
        headers: {
          'Accept': 'application/json',
          'X-Plex-Client-Identifier': 'libretto-audiobook-player',
          'X-Plex-Token': authToken,
        },
      ),
      queryParameters: {
        'includeHttps': '1',
        'includeRelay': '0',
      },
    );

    final resources = response.data as List<dynamic>;
    final servers = <CloudServer>[];

    for (final resource in resources) {
      if (resource is! Map<String, dynamic>) continue;
      // Only include Plex Media Server devices
      if (resource['provides'] != 'server') continue;

      final connections = resource['connections'] as List<dynamic>? ?? [];
      // Prefer local connection, fallback to remote
      String? bestUrl;
      for (final conn in connections) {
        if (conn is! Map<String, dynamic>) continue;
        final uri = conn['uri'] as String?;
        if (uri == null) continue;
        final isLocal = conn['local'] == true;
        if (isLocal || bestUrl == null) bestUrl = uri;
      }

      if (bestUrl != null) {
        servers.add(CloudServer(
          name: resource['name'] as String? ?? 'Plex Server',
          url: bestUrl,
          type: ServerType.plex,
          version: resource['productVersion'] as String?,
          isOnline: resource['presence'] == true,
        ));
      }
    }

    return servers;
  }

  // ── Emby Connect Login ────────────────────────────────────────

  /// Login to Emby Connect with username/email and password.
  /// Returns the connect token and user ID.
  Future<Map<String, String>> loginEmbyConnect({
    required String username,
    required String password,
  }) async {
    final response = await _dio.post(
      'https://connect.emby.media/service/user/authenticate',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'X-Application': 'Libretto/1.0.0',
        },
      ),
      data: {
        'nameOrEmail': username,
        'rawpw': password,
      },
    );

    final data = response.data as Map<String, dynamic>;
    return {
      'accessToken': data['AccessToken'] as String,
      'userId': data['User']?['Id'] as String? ?? '',
    };
  }

  /// Fetch all servers linked to the Emby Connect account.
  Future<List<CloudServer>> fetchEmbyServers({
    required String connectToken,
    required String userId,
  }) async {
    final response = await _dio.get(
      'https://connect.emby.media/service/servers',
      options: Options(
        headers: {
          'X-Connect-UserToken': connectToken,
          'X-Application': 'Libretto/1.0.0',
        },
        validateStatus: (status) => status != null && status < 500,
      ),
      queryParameters: {'userId': userId},
    );

    if (response.statusCode != 200 || response.data is! List) {
      return [];
    }

    final serverList = response.data as List<dynamic>;
    final servers = <CloudServer>[];

    for (final entry in serverList) {
      if (entry is! Map<String, dynamic>) continue;
      final url = entry['Url'] as String? ?? entry['LocalAddress'] as String?;
      if (url == null || url.isEmpty) continue;

      servers.add(CloudServer(
        name: entry['Name'] as String? ?? 'Emby Server',
        url: url,
        type: ServerType.emby,
      ));
    }

    return servers;
  }

  void dispose() {
    _dio.close();
  }
}
