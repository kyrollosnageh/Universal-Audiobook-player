import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'tables/books_table.dart';
import 'tables/chapters_table.dart';
import 'tables/downloads_table.dart';
import 'tables/positions_table.dart';
import 'tables/series_table.dart';
import 'tables/servers_table.dart';
import 'daos/book_dao.dart';
import 'daos/chapter_dao.dart';
import 'daos/position_dao.dart';
import 'daos/server_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    BooksTable,
    ChaptersTable,
    PositionsTable,
    ServersTable,
    SeriesTableDef,
    DownloadsTable,
  ],
  daos: [BookDao, ChapterDao, PositionDao, ServerDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Constructor for testing with an in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Future migrations will go here.
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'libretto.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
