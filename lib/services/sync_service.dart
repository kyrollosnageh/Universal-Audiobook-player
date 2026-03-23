import '../data/database/app_database.dart';
import '../data/database/daos/book_dao.dart';
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
  SyncService({required AppDatabase database})
    : _positionDao = database.positionDao,
      _bookDao = database.bookDao;

  final PositionDao _positionDao;
  final BookDao _bookDao;

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
    await _positionDao.savePosition(
      PositionEntry(
        bookId: bookId,
        serverId: serverId,
        positionMs: position.inMilliseconds,
        chapterId: chapterId,
        updatedAt: DateTime.now(),
        syncedToServer: false,
      ),
    );
  }

  // ── Get Local Position ────────────────────────────────────────────

  /// Get the locally saved position for a book, including chapter info.
  Future<SavedPosition?> getLocalPosition(
    String bookId,
    String serverId,
  ) async {
    final entry = await _positionDao.getPosition(bookId, serverId);
    if (entry == null) return null;
    return SavedPosition(
      position: Duration(milliseconds: entry.positionMs),
      chapterId: entry.chapterId,
    );
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
    final saved = await getLocalPosition(bookId, provider.serverUrl);
    final localPos = saved?.position ?? Duration.zero;
    Duration? serverPos;

    try {
      serverPos = await provider.getServerPosition(bookId);
    } catch (_) {
      // Server unreachable — use local
      return PositionResolution(
        position: localPos,
        chapterId: saved?.chapterId,
        source: PositionSource.local,
        conflict: false,
      );
    }

    final server = serverPos ?? Duration.zero;

    // Both zero — fresh start
    if (localPos == Duration.zero && server == Duration.zero) {
      return const PositionResolution(
        position: Duration.zero,
        source: PositionSource.none,
        conflict: false,
      );
    }

    // Check for large divergence
    final diff = (localPos.inSeconds - server.inSeconds).abs();
    if (diff > _largeDivergenceSeconds &&
        localPos != Duration.zero &&
        server != Duration.zero) {
      final useLocal = localPos > server;
      return PositionResolution(
        position: useLocal ? localPos : server,
        chapterId: useLocal ? saved?.chapterId : null,
        source: useLocal ? PositionSource.local : PositionSource.server,
        conflict: true,
        localPosition: localPos,
        serverPosition: server,
      );
    }

    // Use whichever is further ahead
    if (localPos >= server) {
      return PositionResolution(
        position: localPos,
        chapterId: saved?.chapterId,
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

  // ── Finished Status ───────────────────────────────────────────────

  /// Mark a book as finished locally and sync to server.
  Future<void> markFinished(
    ServerProvider provider, {
    required String bookId,
    required String serverId,
    required bool isFinished,
  }) async {
    await _bookDao.setFinished(bookId, serverId, isFinished);
    try {
      await provider.reportFinished(bookId, isFinished);
    } catch (_) {
      // Local state is updated regardless
    }
  }

  // ── Favorites ─────────────────────────────────────────────────────

  /// Toggle a book's favorite status locally and sync to server.
  Future<void> toggleFavorite(
    ServerProvider provider, {
    required String bookId,
    required String serverId,
    required bool isFavorite,
  }) async {
    await _bookDao.setFavorite(bookId, serverId, isFavorite);
    try {
      await provider.setFavorite(bookId, isFavorite);
    } catch (_) {
      // Local state is updated regardless
    }
  }

  /// Set a book's rating locally and sync to server.
  Future<void> rateBook(
    ServerProvider provider, {
    required String bookId,
    required String serverId,
    required double rating,
  }) async {
    await _bookDao.setRating(bookId, serverId, rating);
    try {
      await provider.setRating(bookId, rating);
    } catch (_) {
      // Local state is updated regardless
    }
  }
}

/// A locally saved position with optional chapter info.
class SavedPosition {
  const SavedPosition({required this.position, this.chapterId});

  final Duration position;
  final String? chapterId;
}

/// Result of position resolution between local and server.
class PositionResolution {
  const PositionResolution({
    required this.position,
    required this.source,
    required this.conflict,
    this.chapterId,
    this.localPosition,
    this.serverPosition,
  });

  /// The resolved position to use.
  final Duration position;

  /// The chapter ID associated with the resolved position.
  final String? chapterId;

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
