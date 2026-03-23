import '../../core/errors.dart';
import '../models/auth_result.dart';
import '../models/server_config.dart';
import 'emby_provider.dart';

/// Jellyfin server provider — extends EmbyProvider.
///
/// Jellyfin shares ~80% of the Emby API but diverges in:
/// - Auth token format (no MediaBrowser prefix needed in some versions)
/// - Some endpoint paths differ slightly
/// - ProductName identifies as "Jellyfin" in /System/Info
/// - Auth response structure may differ
///
/// All browsing, chapter, streaming, and progress APIs are identical.
class JellyfinProvider extends EmbyProvider {
  JellyfinProvider({required super.serverUrl, super.dio});

  @override
  String get providerName => 'Jellyfin';

  /// Override authentication to handle Jellyfin-specific differences.
  @override
  Future<AuthResult> authenticate(String username, String password) async {
    try {
      final result = await super.authenticate(username, password);

      // Re-wrap the result with the correct server type
      return AuthResult(
        token: result.token,
        userId: result.userId,
        serverName: result.serverName,
        serverType: ServerType.jellyfin,
        serverId: result.serverId,
        username: result.username,
      );
    } on AuthenticationException {
      rethrow;
    }
  }

  /// Jellyfin uses the same stream URL format but may require
  /// different transcoding params in some deployments.
  @override
  Uri getStreamUrl(String itemId, {AudioFormat? transcode}) {
    // Jellyfin's streaming endpoint is identical to Emby's
    return super.getStreamUrl(itemId, transcode: transcode);
  }

  /// Jellyfin's logout endpoint.
  @override
  Future<void> logout() async {
    // Jellyfin uses the same /Sessions/Logout endpoint
    await super.logout();
  }
}
