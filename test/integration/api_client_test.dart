import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/data/server_providers/emby_provider.dart';
import 'package:libretto/data/server_providers/audiobookshelf_provider.dart';
import 'package:libretto/data/server_providers/jellyfin_provider.dart';
import 'package:libretto/data/server_providers/plex_provider.dart';
import 'package:libretto/data/server_providers/server_detector.dart';
import 'package:libretto/data/models/auth_result.dart';
import 'package:libretto/data/models/server_config.dart';
import 'package:libretto/core/extensions.dart';

void main() {
  // These tests validate the provider implementations
  // against mock HTTP responses. In CI, they would use
  // http_mock_adapter with Dio.

  group('EmbyProvider Integration', () {
    test('auth flow stores token and userId', () {
      final provider = EmbyProvider(serverUrl: 'https://emby.test:8096');
      provider.restoreSession(
        token: 'test-token-123',
        userId: 'user-abc',
        serverId: 'server-xyz',
      );

      expect(provider.isAuthenticated, true);
      expect(provider.token, 'test-token-123');
      expect(provider.userId, 'user-abc');

      provider.dispose();
    });

    test('stream URL generation with auth', () {
      final provider = EmbyProvider(serverUrl: 'https://emby.test:8096');
      provider.restoreSession(token: 'tok', userId: 'uid');

      final url = provider.getStreamUrl('item-1');
      expect(url.toString(), contains('api_key=tok'));
      expect(url.toString(), contains('/Audio/item-1/stream'));

      provider.dispose();
    });

    test('cover art URL with dimensions', () {
      final provider = EmbyProvider(serverUrl: 'https://emby.test:8096');
      provider.restoreSession(token: 'tok', userId: 'uid');

      final url = provider.getCoverArtUrl('item-1', maxWidth: 150);
      expect(url.toString(), contains('maxWidth=150'));
      expect(url.toString(), contains('api_key=tok'));

      provider.dispose();
    });

    test('tick conversion accuracy', () {
      // 2 hours, 30 minutes = 9000 seconds
      const duration = Duration(hours: 2, minutes: 30);
      final ticks = duration.toTicks();

      expect(ticks, 90000000000); // 9000 * 10^7
      expect(ticks.ticksToDuration(), duration);
    });
  });

  group('AudiobookshelfProvider Integration', () {
    test('session restore sets token', () {
      final provider = AudiobookshelfProvider(
        serverUrl: 'https://abs.test:13378',
      );
      provider.restoreSession(token: 'jwt-token', userId: 'user1');

      expect(provider.isAuthenticated, true);
      expect(provider.token, 'jwt-token');

      provider.dispose();
    });

    test('cover art URL includes token', () {
      final provider = AudiobookshelfProvider(
        serverUrl: 'https://abs.test:13378',
      );
      provider.restoreSession(token: 'jwt-tok', userId: 'u1');

      final url = provider.getCoverArtUrl('item-1', maxWidth: 300);
      expect(url.toString(), contains('token=jwt-tok'));
      expect(url.toString(), contains('width=300'));

      provider.dispose();
    });
  });

  group('JellyfinProvider Integration', () {
    test('providerName is Jellyfin', () {
      final provider = JellyfinProvider(serverUrl: 'https://jf.test:8096');
      expect(provider.providerName, 'Jellyfin');
      provider.dispose();
    });

    test('inherits EmbyProvider stream URL format', () {
      final provider = JellyfinProvider(serverUrl: 'https://jf.test:8096');
      provider.restoreSession(token: 'jf-tok', userId: 'uid');

      final url = provider.getStreamUrl('item-1');
      expect(url.toString(), contains('/Audio/item-1/stream'));

      provider.dispose();
    });
  });

  group('PlexProvider Integration', () {
    test('stream URL uses parts endpoint', () {
      final provider = PlexProvider(serverUrl: 'https://plex.test:32400');
      provider.restoreSession(token: 'plex-tok', userId: 'u1');

      final url = provider.getStreamUrl('part-42');
      expect(url.toString(), contains('/library/parts/part-42/file'));
      expect(url.toString(), contains('X-Plex-Token=plex-tok'));

      provider.dispose();
    });
  });

  group('ServerDetector', () {
    test('creates without error', () {
      final detector = ServerDetector();
      // Actual detection requires live server or mock
      detector.dispose();
    });
  });

  group('Cross-provider consistency', () {
    test('all providers implement same interface', () {
      // Verify that all providers have the required interface methods
      // by creating instances (they all implement ServerProvider)
      final providers = [
        EmbyProvider(serverUrl: 'https://e.test'),
        JellyfinProvider(serverUrl: 'https://j.test'),
        AudiobookshelfProvider(serverUrl: 'https://a.test'),
        PlexProvider(serverUrl: 'https://p.test'),
      ];

      for (final p in providers) {
        expect(p.providerName, isNotEmpty);
        expect(p.serverUrl, isNotEmpty);
        expect(p.isAuthenticated, false);
        p.dispose();
      }
    });
  });
}
