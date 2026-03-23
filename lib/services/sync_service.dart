import '../data/database/app_database.dart';
import '../data/database/daos/position_dao.dart';
import '../data/server_providers/server_provider.dart';

/// Syncs playback positions between local Drift DB and the server.
///
/// Strategy:
/// - Save locally every 10 seconds during playback
/// - Sync to server every 30 seconds when online
/// - On reconnect after offline, sync queued positions in order
/// - Conflict resolution: use furthest-ahead position; prompt if large divergence
class SyncService {
  SyncService({
    required AppDatabase database,
  }) : _positionDao = database.positionDao;

  final PositionDao _positionDao;

  /// The threshold (in seconds) beyond which we consider positions
  /// to have "large divergence" and should prompt the user.
  static const int _largeDivergenceSeconds = 300; // 5 minutes

  // ── Save Position Locally ─────────────────────────────────────────

  /// Save playback position to local database.
  /// This is called every 10 seconds during playback.
  Future<void> saveLocalPosition({
    required String bookId,
    required String serverId,
    required Duration position,
    String? chapterId,
  }) async {
    await _positionDao.savePosition(PositionEntry(
      bookId: bookId,
      serverId: serverId,
      positionMs: position.inMilliseconds,
      chapterId: chapterId,
      updatedAt: DateTime.now(),
      syncedToServer: false,
    ));
  }

  // ── Get Local Position ────────────────────────────────────────────

  /// Get the locally saved position for a book.
  Future<Duration?> getLocalPosition(String bookId, String serverId) async {
    final entry = await _positionDao.getPosition(bookId, serverId);
    if (entry == null) return null;
    return Duration(milliseconds: entry.positionMs);
  }

  // ── Sync to Server ────────────────────────────────────────────────

  /// Sync a position to the server.
  /// Called every 30 seconds during playback when online.
  Future<void> syncToServer(
    ServerProvider provider, {
    required String bookId,
    required Duration position,
  }) async {
    try {
      await provider.reportPosition(bookId, position);
      await _positionDao.markSynced(bookId, provider.serverUrl);
    } catch (_) {
      // Position remains marked as un-synced; will retry later.
    }
  }

  // ── Resolve Position on Launch ────────────────────────────────────

  /// Compare local and server positions and determine which to use.
  ///
  /// Returns a [PositionResolution] indicating the result.
  Future<PositionResolution> resolvePosition(
    ServerProvider provider, {
    required String bookId,
  }) async {
    final localPos = await getLocalPosition(bookId, provider.serverUrl);
    Duration? serverPos;

    try {
      serverPos = await provider.getServerPosition(bookId);
    } catch (_) {
      // Server unreachable — use local
      return PositionResolution(
        position: localPos ?? Duration.zero,
        source: PositionSource.local,
        conflict: false,
      );
    }

    final local = localPos ?? Duration.zero;
    final server = serverPos ?? Duration.zero;

    // Both zero — fresh start
    if (local == Duration.zero && server == Duration.zero) {
      return PositionResolution(
        position: Duration.zero,
        source: PositionSource.none,
        conflict: false,
      );
    }

    // Check for large divergence
    final diff = (local.inSeconds - server.inSeconds).abs();
    if (diff > _largeDivergenceSeconds &&
        local != Duration.zero &&
        server != Duration.zero) {
      return PositionResolution(
        position: local > server ? local : server,
        source: local > server ? PositionSource.local : PositionSource.server,
        conflict: true,
        localPosition: local,
        serverPosition: server,
      );
    }

    // Use whichever is further ahead
    if (local >= server) {
      return PositionResolution(
        position: local,
        source: PositionSource.local,
        conflict: false,
      );
    }

    return PositionResolution(
      position: server,
      source: PositionSource.server,
      conflict: false,
    );
  }

  // ── Batch Sync (Reconnect) ────────────────────────────────────────

  /// Sync all queued (un-synced) positions to the server.
  /// Called when connectivity is restored after being offline.
  Future<int> syncPendingPositions(ServerProvider provider) async {
    final unsynced = await _positionDao.getUnsyncedPositions();
    var synced = 0;

    for (final entry in unsynced) {
      try {
        await provider.reportPosition(
          entry.bookId,
          Duration(milliseconds: entry.positionMs),
        );
        await _positionDao.markSynced(entry.bookId, entry.serverId);
        synced++;
      } catch (_) {
        // Stop syncing on first failure — will retry later
        break;
      }
    }

    return synced;
  }
}

/// Result of position resolution between local and server.
class PositionResolution {
  const PositionResolution({
    required this.position,
    required this.source,
    required this.conflict,
    this.localPosition,
    this.serverPosition,
  });

  /// The resolved position to use.
  final Duration position;

  /// Where the position came from.
  final PositionSource source;

  /// Whether there was a large divergence requiring user input.
  final bool conflict;

  /// Local position (only set when conflict = true).
  final Duration? localPosition;

  /// Server position (only set when conflict = true).
  final Duration? serverPosition;
}

enum PositionSource { local, server, none }
