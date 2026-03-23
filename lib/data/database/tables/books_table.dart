import 'package:drift/drift.dart';

/// Cached book metadata table.
@DataClassName('BookEntry')
class BooksTable extends Table {
  @override
  String get tableName => 'books';

  TextColumn get id => text()();
  TextColumn get serverId => text()();
  TextColumn get title => text()();
  TextColumn get author => text().nullable()();
  TextColumn get narrator => text().nullable()();
  TextColumn get coverUrl => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  RealColumn get progress => real().nullable()();
  TextColumn get seriesName => text().nullable()();
  RealColumn get seriesIndex => real().nullable()();
  TextColumn get genre => text().nullable()();
  IntColumn get year => integer().nullable()();
  DateTimeColumn get dateAdded => dateTime().nullable()();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  BoolColumn get isDownloaded =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id, serverId};
}
