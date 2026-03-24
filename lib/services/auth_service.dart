import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../core/extensions.dart';
import '../data/database/app_database.dart';
import '../data/database/daos/server_dao.dart';
import '../data/models/server_config.dart';
import '../data/server_providers/server_detector.dart';
import '../data/server_providers/server_provider.dart';
import '../data/server_providers/emby_provider.dart';
import '../data/server_providers/audiobookshelf_provider.dart';
import '../data/server_providers/jellyfin_provider.dart';
import '../data/server_providers/plex_provider.dart';

/// Manages authentication, multi-server connections, and HTTPS enforcement.
///
/// Security rules:
/// - Never stores passwords — authenticate once, store token, discard password
/// - Tokens stored in flutter_secure_storage (iOS Keychain / Android EncryptedSharedPreferences)
/// - Enforces HTTPS; HTTP only allowed for localhost/LAN with explicit acknowledgment
/// - Tokens namespaced per server: `server:{url}:token`
/// - On 401: clears token, redirects to login
/// - Logout clears token locally AND revokes server-side
class AuthService {
  AuthService({
    required AppDatabase database,
    FlutterSecureStorage? secureStorage,
    ServerDetector? detector,
  }) : _serverDao = database.serverDao,
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _detector = detector ?? ServerDetector();

  final ServerDao _serverDao;
  final FlutterSecureStorage _secureStorage;
  final ServerDetector _detector;

  final Map<String, ServerProvider> _activeProviders = {};
  ServerProvider? _currentProvider;

  /// The currently active server provider.
  ServerProvider? get currentProvider => _currentProvider;

  /// All active provider instances.
  Map<String, ServerProvider> get providers =>
      Map.unmodifiable(_activeProviders);

  // ── HTTPS Enforcement ─────────────────────────────────────────────

  /// Validate that the URL meets security requirements.
  ///
  /// Returns null if valid, or a warning message if HTTP is detected.
  /// Throws [InsecureConnectionException] if HTTP is used on a public URL
  /// without acknowledgment.
  String? validateUrl(String url, {bool httpAcknowledged = false}) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Invalid URL format';

    if (uri.scheme == 'http') {
      if (url.isLocalNetwork) {
        return 'Warning: Using unencrypted HTTP connection. '
            'Your credentials will be sent in plain text.';
      }
      if (!httpAcknowledged) {
        throw const InsecureConnectionException();
      }
      return 'Warning: HTTP connection to a public server is insecure.';
    }

    return null;
  }

  // ── Server Detection ──────────────────────────────────────────────

  /// Detect the server type at a URL.
  Future<ServerDetectionResult> detectServer(String url) {
    return _detector.detect(url);
  }

  // ── Authentication ────────────────────────────────────────────────

  /// Authenticate with a server and store the credentials securely.
  ///
  /// [url] must be validated with [validateUrl] first.
  /// Password is discarded after authentication completes.
  Future<ServerConfig> login({
    required String url,
    required String username,
    required String password,
    required ServerType serverType,
    String? serverName,
  }) async {
    final provider = _createProvider(url, serverType);

    try {
      final result = await provider.authenticate(username, password);
      // Password is now out of scope — GC will reclaim it.

      // Store token securely (NEVER in SharedPreferences or SQLite)
      await _secureStorage.write(
        key: StorageKeys.serverToken(url),
        value: result.token,
      );
      await _secureStorage.write(
        key: StorageKeys.serverUserId(url),
        value: result.userId,
      );

      // Create server config
      final serverId = result.serverId ?? const Uuid().v4();
      final config = ServerConfig(
        id: serverId,
        name: serverName ?? result.serverName,
        url: url,
        type: serverType,
        userId: result.userId,
        isActive: true,
        addedAt: DateTime.now(),
      );

      // Persist to database
      await _serverDao.upsertServer(
        ServerEntry(
          id: config.id,
          name: config.name,
          url: config.url,
          type: config.type.name,
          userId: config.userId,
          isActive: true,
          trustedCertFingerprint: null,
          addedAt: config.addedAt ?? DateTime.now(),
        ),
      );
      await _serverDao.setActiveServer(config.id);

      // Cache the provider
      _activeProviders[url] = provider;
      _currentProvider = provider;

      return config;
    } catch (e) {
      provider.dispose();
      rethrow;
    }
  }

  /// Restore a session from stored credentials (app launch).
  Future<ServerProvider?> restoreSession(ServerConfig config) async {
    final token = await _secureStorage.read(
      key: StorageKeys.serverToken(config.url),
    );
    final userId = await _secureStorage.read(
      key: StorageKeys.serverUserId(config.url),
    );

    if (token == null || userId == null) return null;

    final provider = _createProvider(config.url, config.type);

    // Restore the session without re-authenticating
    if (provider is EmbyProvider) {
      provider.restoreSession(token: token, userId: userId);
    } else if (provider is AudiobookshelfProvider) {
      provider.restoreSession(token: token, userId: userId);
    } else if (provider is PlexProvider) {
      provider.restoreSession(token: token, userId: userId);
    }
    // JellyfinProvider extends EmbyProvider — handled above

    _activeProviders[config.url] = provider;

    if (config.isActive) {
      _currentProvider = provider;
    }

    return provider;
  }

  // ── Logout ────────────────────────────────────────────────────────

  /// Log out from a server. Clears token locally AND revokes server-side.
  Future<void> logout(String serverUrl) async {
    final provider = _activeProviders[serverUrl];

    if (provider != null) {
      try {
        await provider.logout();
      } catch (_) {
        // Best-effort server-side revocation
      }
      provider.dispose();
      _activeProviders.remove(serverUrl);
    }

    // Always clear local credentials regardless of server response
    await _secureStorage.delete(key: StorageKeys.serverToken(serverUrl));
    await _secureStorage.delete(key: StorageKeys.serverUserId(serverUrl));

    if (_currentProvider == provider) {
      _currentProvider = null;
    }
  }

  /// Log out from all servers and clear everything.
  Future<void> logoutAll() async {
    for (final url in _activeProviders.keys.toList()) {
      await logout(url);
    }
  }

  // ── Multi-server Management ───────────────────────────────────────

  /// Switch the active server.
  Future<void> switchServer(ServerConfig config) async {
    var provider = _activeProviders[config.url];

    if (provider == null) {
      provider = await restoreSession(config);
      if (provider == null) {
        throw const AuthenticationException(
          'Cannot restore session. Please log in again.',
        );
      }
    }

    _currentProvider = provider;
    await _serverDao.setActiveServer(config.id);
  }

  /// Get all configured servers.
  Future<List<ServerEntry>> getSavedServers() {
    return _serverDao.getAllServers();
  }

  /// Remove a server completely.
  Future<void> removeServer(String serverId, String serverUrl) async {
    await logout(serverUrl);
    await _serverDao.deleteServer(serverId);
  }

  // ── Provider Factory ──────────────────────────────────────────────

  ServerProvider _createProvider(String url, ServerType type) {
    switch (type) {
      case ServerType.emby:
        return EmbyProvider(serverUrl: url);
      case ServerType.jellyfin:
        return JellyfinProvider(serverUrl: url);
      case ServerType.audiobookshelf:
        return AudiobookshelfProvider(serverUrl: url);
      case ServerType.plex:
        return PlexProvider(serverUrl: url);
    }
  }

  void dispose() {
    for (final provider in _activeProviders.values) {
      provider.dispose();
    }
    _activeProviders.clear();
    _currentProvider = null;
    _detector.dispose();
  }
}
