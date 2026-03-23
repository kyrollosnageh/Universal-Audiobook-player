import 'package:drift/drift.dart';

/// Configured server connections table.
@DataClassName('ServerEntry')
class ServersTable extends Table {
  @override
  String get tableName => 'servers';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get url => text()();
  TextColumn get type => text()(); // emby, jellyfin, audiobookshelf, plex
  TextColumn get userId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  TextColumn get trustedCertFingerprint => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
