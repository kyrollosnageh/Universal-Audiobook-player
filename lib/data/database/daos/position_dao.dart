import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/positions_table.dart';

part 'position_dao.g.dart';

@DriftAccessor(tables: [PositionsTable])
class PositionDao extends DatabaseAccessor<AppDatabase>
    with _$PositionDaoMixin {
  PositionDao(super.db);

  /// Save or update a playback position.
  Future<void> savePosition(PositionEntry position) {
    return into(positionsTable).insertOnConflictUpdate(position);
  }

  /// Get the saved position for a book.
  Future<PositionEntry?> getPosition(String bookId, String serverId) {
    return (select(positionsTable)
          ..where(
              (t) => t.bookId.equals(bookId) & t.serverId.equals(serverId)))
        .getSingleOrNull();
  }

  /// Get all un-synced positions (for batch sync on reconnect).
  Future<List<PositionEntry>> getUnsyncedPositions() {
    return (select(positionsTable)
          ..where((t) => t.syncedToServer.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.updatedAt)]))
        .get();
  }

  /// Mark a position as synced to the server.
  Future<void> markSynced(String bookId, String serverId) {
    return (update(positionsTable)
          ..where(
              (t) => t.bookId.equals(bookId) & t.serverId.equals(serverId)))
        .write(const PositionsTableCompanion(
      syncedToServer: Value(true),
    ));
  }

  /// Delete position for a book (on logout/clear).
  Future<int> clearPosition(String bookId, String serverId) {
    return (delete(positionsTable)
          ..where(
              (t) => t.bookId.equals(bookId) & t.serverId.equals(serverId)))
        .go();
  }
}
