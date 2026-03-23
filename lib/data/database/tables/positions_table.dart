import 'package:drift/drift.dart';

/// Playback position tracking table.
@DataClassName('PositionEntry')
class PositionsTable extends Table {
  @override
  String get tableName => 'positions';

  TextColumn get bookId => text()();
  TextColumn get serverId => text()();
  IntColumn get positionMs => integer()();
  TextColumn get chapterId => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get syncedToServer =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {bookId, serverId};
}
