import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/core/extensions.dart';
import 'package:libretto/data/server_providers/emby_provider.dart';
import 'package:libretto/data/models/auth_result.dart';

void main() {
  group('EmbyProvider', () {
    late EmbyProvider provider;

    setUp(() {
      provider = EmbyProvider(serverUrl: 'https://emby.example.com:8096');
    });

    tearDown(() {
      provider.dispose();
    });

    test('providerName is Emby', () {
      expect(provider.providerName, 'Emby');
    });

    test('serverUrl strips trailing slash', () {
      final p = EmbyProvider(serverUrl: 'https://emby.example.com:8096/');
      expect(p.serverUrl, 'https://emby.example.com:8096');
      p.dispose();
    });

    test('isAuthenticated false initially', () {
      expect(provider.isAuthenticated, false);
    });

    test('restoreSession sets auth state', () {
      provider.restoreSession(
        token: 'test-token',
        userId: 'test-user',
        serverId: 'server1',
      );

      expect(provider.isAuthenticated, true);
      expect(provider.token, 'test-token');
      expect(provider.userId, 'test-user');
    });

    test('getStreamUrl generates correct URL', () {
      provider.restoreSession(token: 'abc123', userId: 'user1');

      final url = provider.getStreamUrl('item42');
      expect(url.toString(), contains('/Audio/item42/stream'));
      expect(url.toString(), contains('api_key=abc123'));
      expect(url.toString(), contains('Static=true'));
    });

    test('getStreamUrl with transcode sets correct params', () {
      provider.restoreSession(token: 'abc123', userId: 'user1');

      final url = provider.getStreamUrl('item42', transcode: AudioFormat.aac);
      expect(url.toString(), contains('Static=false'));
      expect(url.toString(), contains('AudioCodec=aac'));
    });

    test('getCoverArtUrl includes dimensions and auth', () {
      provider.restoreSession(token: 'abc123', userId: 'user1');

      final url = provider.getCoverArtUrl('item42', maxWidth: 300);
      expect(url.toString(), contains('/Items/item42/Images/Primary'));
      expect(url.toString(), contains('maxWidth=300'));
      expect(url.toString(), contains('api_key=abc123'));
    });

    test('logout clears auth state', () async {
      provider.restoreSession(token: 'test-token', userId: 'test-user');
      expect(provider.isAuthenticated, true);

      await provider.logout();
      expect(provider.isAuthenticated, false);
    });

    test('requireAuth throws when not authenticated', () {
      expect(() => provider.fetchLibrary(), throwsA(isA<Exception>()));
    });
  });

  group('Emby Tick Conversions', () {
    test('1 second = 10,000,000 ticks', () {
      expect(const Duration(seconds: 1).toTicks(), 10000000);
    });

    test('1 hour = 36,000,000,000 ticks', () {
      expect(const Duration(hours: 1).toTicks(), 36000000000);
    });

    test('typical audiobook position (2h 15m 30s)', () {
      const position = Duration(hours: 2, minutes: 15, seconds: 30);
      final ticks = position.toTicks();
      expect(ticks, 81300000000);
      expect(ticks.ticksToDuration(), position);
    });
  });
}
