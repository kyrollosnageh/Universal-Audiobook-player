import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../data/database/app_database.dart';
import '../data/models/server_config.dart';
import '../data/server_providers/server_detector.dart';
import '../data/server_providers/server_provider.dart';
import '../services/auth_service.dart';

/// Database provider — single instance.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Auth service provider.
final authServiceProvider = Provider<AuthService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = AuthService(database: db);
  ref.onDispose(() => service.dispose());
  return service;
});

/// Currently active server provider (the API abstraction, not Riverpod provider).
final activeServerProvider = Provider<ServerProvider?>((ref) {
  return ref.watch(authServiceProvider).currentProvider;
});

/// Saved servers list.
final savedServersProvider = FutureProvider<List<ServerEntry>>((ref) async {
  final auth = ref.watch(authServiceProvider);
  return auth.getSavedServers();
});

/// Server detection state.
final serverDetectionProvider =
    FutureProvider.family<ServerDetectionResult, String>((ref, url) async {
      final auth = ref.watch(authServiceProvider);
      return auth.detectServer(url);
    });

/// Authentication state notifier.
class AuthState {
  const AuthState({
    this.isLoading = false,
    this.isAuthenticated = false,
    this.error,
    this.activeServer,
  });

  final bool isLoading;
  final bool isAuthenticated;
  final String? error;
  final ServerConfig? activeServer;

  AuthState copyWith({
    bool? isLoading,
    bool? isAuthenticated,
    String? error,
    ServerConfig? activeServer,
    bool clearActiveServer = false,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: error,
      activeServer: clearActiveServer ? null : (activeServer ?? this.activeServer),
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  late AuthService _authService;

  @override
  AuthState build() {
    _authService = ref.read(authServiceProvider);
    return const AuthState();
  }

  /// Directly set state (used by server hub for session restoration).
  set state(AuthState newState) => super.state = newState;

  Future<void> login({
    required String url,
    required String username,
    required String password,
    required ServerType serverType,
    String? serverName,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final config = await _authService.login(
        url: url,
        username: username,
        password: password,
        serverType: serverType,
        serverName: serverName,
      );

      state = AuthState(isAuthenticated: true, activeServer: config);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _sanitizeError(e));
    }
  }

  Future<void> logout(String serverUrl) async {
    await _authService.logout(serverUrl);
    state = const AuthState();
  }

  Future<void> restoreSession() async {
    state = state.copyWith(isLoading: true);

    try {
      final servers = await _authService.getSavedServers();
      final activeEntry = servers.where((s) => s.isActive).firstOrNull;

      if (activeEntry != null) {
        final config = ServerConfig(
          id: activeEntry.id,
          name: activeEntry.name,
          url: activeEntry.url,
          type: ServerType.values.byName(activeEntry.type),
          userId: activeEntry.userId,
          isActive: true,
        );

        final provider = await _authService.restoreSession(config);
        if (provider != null) {
          state = AuthState(isAuthenticated: true, activeServer: config);
          return;
        }
      }

      state = const AuthState();
    } catch (e) {
      state = state.copyWith(isLoading: false, error: _sanitizeError(e));
    }
  }

  String _sanitizeError(Object e) {
    if (e is LibrettoException) return e.message;
    // Strip server URLs and tokens from generic exceptions
    return 'An unexpected error occurred. Please try again.';
  }
}

final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
