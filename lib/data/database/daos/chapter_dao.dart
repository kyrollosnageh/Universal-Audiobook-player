import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/chapters_table.dart';

part 'chapter_dao.g.dart';

@DriftAccessor(tables: [ChaptersTable])
class ChapterDao extends DatabaseAccessor<AppDatabase>
    with _$ChapterDaoMixin {
  ChapterDao(super.db);

  /// Insert or update a chapter.
  Future<void> upsertChapter(ChapterEntry chapter) {
    return into(chaptersTable).insertOnConflictUpdate(chapter);
  }

  /// Batch upsert chapters for a book.
  Future<void> upsertChapters(List<ChapterEntry> chapters) {
    return batch((b) {
      b.insertAllOnConflictUpdate(chaptersTable, chapters);
    });
  }

  /// Get all chapters for a book, ordered by start offset.
  Future<List<ChapterEntry>> getChapters(String bookId, String serverId) {
    return (select(chaptersTable)
          ..where(
              (t) => t.bookId.equals(bookId) & t.serverId.equals(serverId))
          ..orderBy([(t) => OrderingTerm.asc(t.startOffsetMs)]))
        .get();
  }

  /// Delete all chapters for a book.
  Future<int> clearBookChapters(String bookId, String serverId) {
    return (delete(chaptersTable)
          ..where(
              (t) => t.bookId.equals(bookId) & t.serverId.equals(serverId)))
        .go();
  }
}
