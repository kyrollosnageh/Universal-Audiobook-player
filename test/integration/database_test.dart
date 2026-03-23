import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/data/models/book.dart';
import 'package:libretto/data/models/unified_chapter.dart';
import 'package:libretto/data/models/series.dart';
import 'package:libretto/data/models/auth_result.dart';

void main() {
  // Database integration tests would use an in-memory Drift database.
  // These tests verify the data model layer without requiring SQLite.

  group('Book Model Persistence', () {
    test('book with all fields', () {
      final book = Book(
        id: 'book-123',
        serverId: 'server-1',
        title: 'The Hitchhiker\'s Guide to the Galaxy',
        author: 'Douglas Adams',
        narrator: 'Stephen Fry',
        duration: const Duration(hours: 5, minutes: 51),
        progress: 0.42,
        seriesName: 'Hitchhiker\'s Guide',
        seriesIndex: 1,
        genre: 'Science Fiction',
        year: 1979,
        dateAdded: DateTime(2024, 1, 15),
        isDownloaded: true,
      );

      expect(book.id, 'book-123');
      expect(book.title, contains('Hitchhiker'));
      expect(book.duration!.inHours, 5);
      expect(book.progress, 0.42);
      expect(book.isDownloaded, true);
    });

    test('book equality by id + serverId', () {
      const a = Book(id: 'b1', serverId: 's1', title: 'A');
      const b = Book(id: 'b1', serverId: 's1', title: 'B');
      const c = Book(id: 'b1', serverId: 's2', title: 'A');

      expect(a, equals(b)); // Same id + serverId
      expect(a, isNot(equals(c))); // Different serverId
    });
  });

  group('Chapter Model Persistence', () {
    test('M4B chapters have correct structure', () {
      final chapters = List.generate(10, (i) {
        return UnifiedChapter(
          id: 'ch_$i',
          title: 'Chapter ${i + 1}',
          startOffset: Duration(minutes: i * 30),
          duration: const Duration(minutes: 30),
          trackItemId: 'book-1',
          isSeparateTrack: false,
          trackIndex: 0,
        );
      });

      expect(chapters.length, 10);
      expect(chapters.first.startOffset, Duration.zero);
      expect(chapters.last.startOffset, const Duration(minutes: 270));
      expect(chapters.every((c) => !c.isSeparateTrack), true);
    });

    test('MP3-per-chapter has unique trackItemIds', () {
      final chapters = List.generate(5, (i) {
        return UnifiedChapter(
          id: 'track_$i',
          title: 'Track ${i + 1}',
          startOffset: Duration(minutes: i * 10),
          duration: const Duration(minutes: 10),
          trackItemId: 'track_$i',
          isSeparateTrack: true,
          trackIndex: i,
        );
      });

      final trackIds = chapters.map((c) => c.trackItemId).toSet();
      expect(trackIds.length, 5); // All unique
    });
  });

  group('Position Tracking', () {
    test('position conflicts with large divergence', () {
      const localPos = Duration(hours: 1, minutes: 10);
      const serverPos = Duration(hours: 2, minutes: 30);

      final diff = (localPos.inSeconds - serverPos.inSeconds).abs();
      expect(diff, greaterThan(300)); // > 5 minutes = conflict
    });

    test('position within threshold', () {
      const localPos = Duration(hours: 1, minutes: 10);
      const serverPos = Duration(hours: 1, minutes: 12);

      final diff = (localPos.inSeconds - serverPos.inSeconds).abs();
      expect(diff, lessThan(300)); // < 5 minutes = auto-resolve
    });
  });

  group('Series Model', () {
    test('completion fraction calculation', () {
      const series = Series(
        id: 's1',
        serverId: 'srv1',
        name: 'Lord of the Rings',
        totalBooks: 3,
        completedBooks: 2,
      );

      expect(series.completionFraction, closeTo(0.667, 0.001));
    });

    test('empty series has zero completion', () {
      const series = Series(
        id: 's1',
        serverId: 'srv1',
        name: 'Empty',
        totalBooks: 0,
        completedBooks: 0,
      );

      expect(series.completionFraction, 0.0);
    });
  });

  group('Paginated Results', () {
    test('hasMore with partial page', () {
      const result = PaginatedResult<Book>(
        items: [],
        totalCount: 150,
        offset: 100,
        limit: 50,
      );

      // offset(100) + items(0) < total(150) = hasMore
      expect(result.hasMore, true);
    });

    test('hasMore false at end', () {
      final result = PaginatedResult<Book>(
        items: List.generate(
          25,
          (i) => Book(id: '$i', serverId: 's', title: '$i'),
        ),
        totalCount: 125,
        offset: 100,
        limit: 50,
      );

      // offset(100) + items(25) = 125 = total(125) = no more
      expect(result.hasMore, false);
    });
  });

  group('Server Config', () {
    test('copyWith creates modified copy', () {
      const config = ServerConfig(
        id: 'srv1',
        name: 'My Server',
        url: 'https://emby.local',
        type: ServerType.emby,
        isActive: false,
      );

      final active = config.copyWith(isActive: true);
      expect(active.isActive, true);
      expect(active.name, 'My Server');
      expect(active.type, ServerType.emby);
    });

    test('all server types exist', () {
      expect(ServerType.values.length, 4);
      expect(ServerType.values, contains(ServerType.emby));
      expect(ServerType.values, contains(ServerType.jellyfin));
      expect(ServerType.values, contains(ServerType.audiobookshelf));
      expect(ServerType.values, contains(ServerType.plex));
    });
  });
}
