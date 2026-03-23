import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/servers_table.dart';

part 'server_dao.g.dart';

@DriftAccessor(tables: [ServersTable])
class ServerDao extends DatabaseAccessor<AppDatabase>
    with _$ServerDaoMixin {
  ServerDao(super.db);

  /// Get all saved servers.
  Future<List<ServerEntry>> getAllServers() {
    return (select(serversTable)
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]))
        .get();
  }

  /// Get the currently active server.
  Future<ServerEntry?> getActiveServer() {
    return (select(serversTable)
          ..where((t) => t.isActive.equals(true)))
        .getSingleOrNull();
  }

  /// Insert or update a server.
  Future<void> upsertServer(ServerEntry server) {
    return into(serversTable).insertOnConflictUpdate(server);
  }

  /// Set a server as active (deactivating all others).
  Future<void> setActiveServer(String serverId) async {
    await transaction(() async {
      // Deactivate all
      await (update(serversTable))
          .write(const ServersTableCompanion(isActive: Value(false)));
      // Activate the selected one
      await (update(serversTable)
            ..where((t) => t.id.equals(serverId)))
          .write(const ServersTableCompanion(isActive: Value(true)));
    });
  }

  /// Delete a server.
  Future<int> deleteServer(String serverId) {
    return (delete(serversTable)
          ..where((t) => t.id.equals(serverId)))
        .go();
  }

  /// Watch all servers reactively.
  Stream<List<ServerEntry>> watchAllServers() {
    return (select(serversTable)
          ..orderBy([(t) => OrderingTerm.desc(t.addedAt)]))
        .watch();
  }
}
