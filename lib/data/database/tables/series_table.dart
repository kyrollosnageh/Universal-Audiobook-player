import 'package:drift/drift.dart';

/// Series tracking table.
@DataClassName('SeriesEntry')
class SeriesTableDef extends Table {
  @override
  String get tableName => 'series';

  TextColumn get id => text()();
  TextColumn get serverId => text()();
  TextColumn get name => text()();
  TextColumn get coverUrl => text().nullable()();
  IntColumn get totalBooks => integer().withDefault(const Constant(0))();
  IntColumn get completedBooks => integer().withDefault(const Constant(0))();
  IntColumn get totalDurationMs => integer().nullable()();
  IntColumn get remainingDurationMs => integer().nullable()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, serverId};
}
