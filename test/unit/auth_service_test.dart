import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/core/errors.dart';
import 'package:libretto/core/extensions.dart';
import 'package:libretto/core/constants.dart';

void main() {
  group('URL Security Validation', () {
    test('localhost is local network', () {
      expect('http://localhost:8096'.isLocalNetwork, true);
    });

    test('127.0.0.1 is local network', () {
      expect('http://127.0.0.1:8096'.isLocalNetwork, true);
    });

    test('192.168.x.x is local network', () {
      expect('http://192.168.1.100:8096'.isLocalNetwork, true);
    });

    test('10.x.x.x is local network', () {
      expect('http://10.0.0.5:8096'.isLocalNetwork, true);
    });

    test('.local domain is local network', () {
      expect('http://myserver.local:8096'.isLocalNetwork, true);
    });

    test('public URL is not local network', () {
      expect('https://emby.example.com:8096'.isLocalNetwork, false);
    });

    test('172.16.x.x is local network', () {
      expect('http://172.16.0.1:8096'.isLocalNetwork, true);
    });
  });

  group('Storage Keys', () {
    test('token key is namespaced per server', () {
      final key = StorageKeys.serverToken('https://server1.example.com');
      expect(key, 'server:https://server1.example.com:token');
    });

    test('different servers get different keys', () {
      final key1 = StorageKeys.serverToken('https://server1.com');
      final key2 = StorageKeys.serverToken('https://server2.com');
      expect(key1, isNot(equals(key2)));
    });

    test('userId key is namespaced per server', () {
      final key = StorageKeys.serverUserId('https://emby.local');
      expect(key, 'server:https://emby.local:userId');
    });
  });

  group('Custom Exceptions', () {
    test('AuthenticationException has message', () {
      const e = AuthenticationException('test');
      expect(e.message, 'test');
      expect(e.toString(), contains('AuthenticationException'));
    });

    test('TokenExpiredException has descriptive message', () {
      const e = TokenExpiredException();
      expect(e.message, contains('expired'));
    });

    test('InsecureConnectionException message', () {
      const e = InsecureConnectionException();
      expect(e.message, contains('HTTPS'));
    });

    test('ChapterParsingException preserves cause', () {
      final cause = Exception('bad data');
      final e = ChapterParsingException('parse failed', cause);
      expect(e.message, 'parse failed');
      expect(e.cause, cause);
    });

    test('SyncConflictException carries both positions', () {
      const e = SyncConflictException(
        localPosition: Duration(minutes: 10),
        serverPosition: Duration(minutes: 45),
      );
      expect(e.localPosition, const Duration(minutes: 10));
      expect(e.serverPosition, const Duration(minutes: 45));
    });
  });
}
