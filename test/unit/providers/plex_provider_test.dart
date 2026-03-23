import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/data/server_providers/plex_provider.dart';

void main() {
  group('PlexProvider', () {
    late PlexProvider provider;

    setUp(() {
      provider = PlexProvider(serverUrl: 'https://plex.example.com:32400');
    });

    tearDown(() {
      provider.dispose();
    });

    test('providerName is Plex', () {
      expect(provider.providerName, 'Plex');
    });

    test('serverUrl strips trailing slash', () {
      final p = PlexProvider(serverUrl: 'https://plex.example.com:32400/');
      expect(p.serverUrl, 'https://plex.example.com:32400');
      p.dispose();
    });

    test('isAuthenticated false initially', () {
      expect(provider.isAuthenticated, false);
    });

    test('restoreSession sets auth state', () {
      provider.restoreSession(token: 'plex-token', userId: 'user1');

      expect(provider.isAuthenticated, true);
      expect(provider.token, 'plex-token');
    });

    test('getCoverArtUrl includes token and dimensions', () {
      provider.restoreSession(token: 'plex-token', userId: 'user1');

      final url = provider.getCoverArtUrl('12345', maxWidth: 300);
      expect(url.toString(), contains('/library/metadata/12345/thumb'));
      expect(url.toString(), contains('width=300'));
      expect(url.toString(), contains('X-Plex-Token=plex-token'));
    });

    test('getStreamUrl uses part-based streaming', () {
      provider.restoreSession(token: 'plex-token', userId: 'user1');

      final url = provider.getStreamUrl('part42');
      expect(url.toString(), contains('/library/parts/part42/file'));
      expect(url.toString(), contains('X-Plex-Token=plex-token'));
    });

    test('logout clears auth state', () async {
      provider.restoreSession(token: 'plex-token', userId: 'user1');
      expect(provider.isAuthenticated, true);

      await provider.logout();
      expect(provider.isAuthenticated, false);
    });

    test('fetchLibrary throws when not authenticated', () {
      expect(() => provider.fetchLibrary(), throwsA(isA<Exception>()));
    });
  });

  group('PlexAuthPin', () {
    test('stores pin data correctly', () {
      const pin = PlexAuthPin(
        id: 12345,
        code: 'abc123',
        authUrl: 'https://app.plex.tv/auth#!?clientID=test&code=abc123',
      );

      expect(pin.id, 12345);
      expect(pin.code, 'abc123');
      expect(pin.authUrl, contains('clientID=test'));
    });
  });
}
