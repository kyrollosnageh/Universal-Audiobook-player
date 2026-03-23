import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/books_table.dart';

part 'book_dao.g.dart';

@DriftAccessor(tables: [BooksTable])
class BookDao extends DatabaseAccessor<AppDatabase> with _$BookDaoMixin {
  BookDao(super.db);

  /// Insert or update a book in the cache.
  Future<void> upsertBook(BookEntry book) {
    return into(booksTable).insertOnConflictUpdate(book);
  }

  /// Batch upsert books.
  Future<void> upsertBooks(List<BookEntry> books) {
    return batch((b) {
      b.insertAllOnConflictUpdate(booksTable, books);
    });
  }

  /// Get a single book by ID and server.
  Future<BookEntry?> getBook(String id, String serverId) {
    return (select(booksTable)
          ..where((t) => t.id.equals(id) & t.serverId.equals(serverId)))
        .getSingleOrNull();
  }

  /// Search books locally by title, author, or narrator.
  Future<List<BookEntry>> searchBooks(String query, String serverId) {
    final pattern = '%$query%';
    return (select(booksTable)
          ..where(
            (t) =>
                t.serverId.equals(serverId) &
                (t.title.like(pattern) |
                    t.author.like(pattern) |
                    t.narrator.like(pattern)),
          )
          ..limit(50))
        .get();
  }

  /// Get paginated books for a server.
  Future<List<BookEntry>> getBooks(
    String serverId, {
    int offset = 0,
    int limit = 50,
    String? genre,
    String? author,
  }) {
    final query = select(booksTable)
      ..where((t) {
        var condition = t.serverId.equals(serverId);
        if (genre != null) {
          condition = condition & t.genre.equals(genre);
        }
        if (author != null) {
          condition = condition & t.author.equals(author);
        }
        return condition;
      })
      ..orderBy([(t) => OrderingTerm.asc(t.title)])
      ..limit(limit, offset: offset);

    return query.get();
  }

  /// Get books currently in progress (have a non-zero progress).
  Future<List<BookEntry>> getContinueListening(String serverId) {
    return (select(booksTable)
          ..where(
            (t) =>
                t.serverId.equals(serverId) &
                t.progress.isBiggerThanValue(0.0) &
                t.progress.isSmallerThanValue(1.0),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.lastPlayedAt)])
          ..limit(20))
        .get();
  }

  /// Get total number of cached books for a server.
  Future<int> getBookCount(String serverId) async {
    final count = booksTable.id.count();
    final query = selectOnly(booksTable)
      ..addColumns([count])
      ..where(booksTable.serverId.equals(serverId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  /// Delete all cached books for a server.
  Future<int> clearServerBooks(String serverId) {
    return (delete(booksTable)..where((t) => t.serverId.equals(serverId))).go();
  }
}
