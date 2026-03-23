import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/services/sync_service.dart';

void main() {
  group('PositionResolution', () {
    test('both zero — fresh start', () {
      const resolution = PositionResolution(
        position: Duration.zero,
        source: PositionSource.none,
        conflict: false,
      );

      expect(resolution.position, Duration.zero);
      expect(resolution.source, PositionSource.none);
      expect(resolution.conflict, false);
    });

    test('local ahead — uses local', () {
      const resolution = PositionResolution(
        position: Duration(minutes: 30),
        source: PositionSource.local,
        conflict: false,
      );

      expect(resolution.position, const Duration(minutes: 30));
      expect(resolution.source, PositionSource.local);
      expect(resolution.conflict, false);
    });

    test('server ahead — uses server', () {
      const resolution = PositionResolution(
        position: Duration(minutes: 45),
        source: PositionSource.server,
        conflict: false,
      );

      expect(resolution.position, const Duration(minutes: 45));
      expect(resolution.source, PositionSource.server);
    });

    test('identical positions — no conflict', () {
      const resolution = PositionResolution(
        position: Duration(minutes: 20),
        source: PositionSource.local,
        conflict: false,
      );

      expect(resolution.conflict, false);
    });

    test('large divergence — conflict flagged', () {
      const resolution = PositionResolution(
        position: Duration(minutes: 45),
        source: PositionSource.server,
        conflict: true,
        localPosition: Duration(minutes: 10),
        serverPosition: Duration(minutes: 45),
      );

      expect(resolution.conflict, true);
      expect(resolution.localPosition, const Duration(minutes: 10));
      expect(resolution.serverPosition, const Duration(minutes: 45));
    });
  });

  group('PositionSource', () {
    test('all enum values exist', () {
      expect(PositionSource.values.length, 3);
      expect(PositionSource.values, contains(PositionSource.local));
      expect(PositionSource.values, contains(PositionSource.server));
      expect(PositionSource.values, contains(PositionSource.none));
    });
  });
}
