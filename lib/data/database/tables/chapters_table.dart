import 'package:drift/drift.dart';

/// Cached chapter data table.
@DataClassName('ChapterEntry')
class ChaptersTable extends Table {
  @override
  String get tableName => 'chapters';

  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get serverId => text()();
  TextColumn get title => text()();
  IntColumn get startOffsetMs => integer()();
  IntColumn get durationMs => integer()();
  TextColumn get trackItemId => text()();
  TextColumn get imageUrl => text().nullable()();
  BoolColumn get isSeparateTrack =>
      boolean().withDefault(const Constant(false))();
  IntColumn get trackIndex => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id, bookId, serverId};
}
