import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/data/models/book.dart';
import 'package:libretto/data/models/auth_result.dart';

void main() {
  group('PaginatedResult', () {
    test('hasMore is true when more items available', () {
      final result = PaginatedResult<Book>(
        items: List.generate(
          50,
          (i) => Book(id: 'book_$i', serverId: 'server1', title: 'Book $i'),
        ),
        totalCount: 200,
        offset: 0,
        limit: 50,
      );

      expect(result.hasMore, true);
      expect(result.nextOffset, 50);
    });

    test('hasMore is false at end of list', () {
      final result = PaginatedResult<Book>(
        items: List.generate(
          10,
          (i) => Book(id: 'book_$i', serverId: 'server1', title: 'Book $i'),
        ),
        totalCount: 60,
        offset: 50,
        limit: 50,
      );

      expect(result.hasMore, false);
    });

    test('empty result', () {
      const result = PaginatedResult<Book>(
        items: [],
        totalCount: 0,
        offset: 0,
        limit: 50,
      );

      expect(result.hasMore, false);
      expect(result.nextOffset, 0);
    });
  });

  group('Search Merge/Deduplicate', () {
    test('deduplication by book ID', () {
      final local = [
        const Book(id: 'b1', serverId: 's1', title: 'Local Book 1'),
        const Book(id: 'b2', serverId: 's1', title: 'Local Book 2'),
      ];
      final server = [
        const Book(id: 'b2', serverId: 's1', title: 'Server Book 2'),
        const Book(id: 'b3', serverId: 's1', title: 'Server Book 3'),
      ];

      // Server takes priority
      final seen = <String>{};
      final merged = <Book>[];
      for (final book in server) {
        if (seen.add(book.id)) merged.add(book);
      }
      for (final book in local) {
        if (seen.add(book.id)) merged.add(book);
      }

      expect(merged.length, 3);
      // b2 should be the server version
      expect(merged.firstWhere((b) => b.id == 'b2').title, 'Server Book 2');
    });
  });

  group('Book Model', () {
    test('copyWith creates a new instance', () {
      const book = Book(
        id: 'b1',
        serverId: 's1',
        title: 'Original',
        author: 'Author',
      );

      final updated = book.copyWith(title: 'Updated');
      expect(updated.title, 'Updated');
      expect(updated.author, 'Author'); // unchanged
      expect(updated.id, 'b1'); // unchanged
    });

    test('equality based on id and serverId', () {
      const a = Book(id: 'b1', serverId: 's1', title: 'Foo');
      const b = Book(id: 'b1', serverId: 's1', title: 'Bar');
      expect(a, equals(b));
    });

    test('different serverId means different book', () {
      const a = Book(id: 'b1', serverId: 's1', title: 'Foo');
      const b = Book(id: 'b1', serverId: 's2', title: 'Foo');
      expect(a, isNot(equals(b)));
    });
  });

  group('SortOrder', () {
    test('all sort orders are defined', () {
      expect(SortOrder.values.length, 8);
    });
  });
}
