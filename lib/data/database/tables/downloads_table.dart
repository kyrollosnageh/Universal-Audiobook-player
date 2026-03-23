import 'package:drift/drift.dart';

/// Download queue and state tracking.
@DataClassName('DownloadEntry')
class DownloadsTable extends Table {
  @override
  String get tableName => 'downloads';

  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get serverId => text()();
  TextColumn get itemId => text()();
  TextColumn get title => text()();
  TextColumn get filePath => text().nullable()();
  IntColumn get totalBytes => integer().nullable()();
  IntColumn get downloadedBytes => integer().withDefault(const Constant(0))();
  TextColumn get status => text()(); // queued, downloading, complete, error
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
