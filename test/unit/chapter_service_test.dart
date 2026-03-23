import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/data/models/unified_chapter.dart';
import 'package:libretto/core/extensions.dart';

void main() {
  group('UnifiedChapter', () {
    test('endOffset equals startOffset + duration', () {
      const chapter = UnifiedChapter(
        id: 'ch1',
        title: 'Chapter 1',
        startOffset: Duration(minutes: 5),
        duration: Duration(minutes: 30),
        trackItemId: 'item1',
      );

      expect(chapter.endOffset, const Duration(minutes: 35));
    });

    test('isSeparateTrack defaults to false', () {
      const chapter = UnifiedChapter(
        id: 'ch1',
        title: 'Chapter 1',
        startOffset: Duration.zero,
        duration: Duration(minutes: 10),
        trackItemId: 'item1',
      );

      expect(chapter.isSeparateTrack, false);
      expect(chapter.trackIndex, 0);
    });

    test('equality based on id, trackItemId, startOffset', () {
      const a = UnifiedChapter(
        id: 'ch1',
        title: 'Chapter 1',
        startOffset: Duration.zero,
        duration: Duration(minutes: 10),
        trackItemId: 'item1',
      );
      const b = UnifiedChapter(
        id: 'ch1',
        title: 'Different Title',
        startOffset: Duration.zero,
        duration: Duration(minutes: 20),
        trackItemId: 'item1',
      );

      expect(a, equals(b));
    });
  });

  group('Tick Conversion', () {
    test('Duration to ticks', () {
      const oneSecond = Duration(seconds: 1);
      expect(oneSecond.toTicks(), 10000000);
    });

    test('ticks to Duration', () {
      final duration = 10000000.ticksToDuration();
      expect(duration, const Duration(seconds: 1));
    });

    test('round-trip conversion', () {
      const original = Duration(hours: 1, minutes: 23, seconds: 45);
      final ticks = original.toTicks();
      final roundTripped = ticks.ticksToDuration();
      expect(roundTripped, original);
    });

    test('zero ticks', () {
      expect(0.ticksToDuration(), Duration.zero);
      expect(Duration.zero.toTicks(), 0);
    });
  });

  group('Duration Formatting', () {
    test('toHms with hours', () {
      const d = Duration(hours: 2, minutes: 5, seconds: 3);
      expect(d.toHms(), '02:05:03');
    });

    test('toHms without hours', () {
      const d = Duration(minutes: 45, seconds: 9);
      expect(d.toHms(), '45:09');
    });

    test('toHumanReadable hours and minutes', () {
      const d = Duration(hours: 2, minutes: 15);
      expect(d.toHumanReadable(), '2h 15m');
    });

    test('toHumanReadable hours only', () {
      const d = Duration(hours: 3);
      expect(d.toHumanReadable(), '3h');
    });

    test('toHumanReadable minutes only', () {
      const d = Duration(minutes: 45);
      expect(d.toHumanReadable(), '45m');
    });

    test('toHumanReadable seconds only', () {
      const d = Duration(seconds: 30);
      expect(d.toHumanReadable(), '30s');
    });
  });

  group('Chapter Parsing Scenarios', () {
    test('embedded chapters in M4B — sorted by startOffset', () {
      final chapters = [
        const UnifiedChapter(
          id: 'ch3',
          title: 'Chapter 3',
          startOffset: Duration(minutes: 20),
          duration: Duration(minutes: 10),
          trackItemId: 'book1',
        ),
        const UnifiedChapter(
          id: 'ch1',
          title: 'Chapter 1',
          startOffset: Duration.zero,
          duration: Duration(minutes: 10),
          trackItemId: 'book1',
        ),
        const UnifiedChapter(
          id: 'ch2',
          title: 'Chapter 2',
          startOffset: Duration(minutes: 10),
          duration: Duration(minutes: 10),
          trackItemId: 'book1',
        ),
      ];

      chapters.sort(
        (a, b) => a.startOffset.inMilliseconds.compareTo(
          b.startOffset.inMilliseconds,
        ),
      );

      expect(chapters[0].title, 'Chapter 1');
      expect(chapters[1].title, 'Chapter 2');
      expect(chapters[2].title, 'Chapter 3');
    });

    test('MP3-per-chapter — all isSeparateTrack', () {
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

      expect(chapters.length, 5);
      for (final ch in chapters) {
        expect(ch.isSeparateTrack, true);
      }
      expect(chapters.last.trackIndex, 4);
    });

    test('single file no chapters — one full-book chapter', () {
      const chapter = UnifiedChapter(
        id: 'book1_full',
        title: 'Full Book',
        startOffset: Duration.zero,
        duration: Duration(hours: 8, minutes: 30),
        trackItemId: 'book1',
      );

      expect(chapter.isSeparateTrack, false);
      expect(chapter.endOffset, const Duration(hours: 8, minutes: 30));
    });

    test('filter out zero-duration chapters', () {
      final chapters = [
        const UnifiedChapter(
          id: 'ch1',
          title: 'Chapter 1',
          startOffset: Duration.zero,
          duration: Duration(minutes: 10),
          trackItemId: 'book1',
        ),
        const UnifiedChapter(
          id: 'ch_empty',
          title: 'Empty',
          startOffset: Duration(minutes: 10),
          duration: Duration.zero,
          trackItemId: 'book1',
        ),
        const UnifiedChapter(
          id: 'ch2',
          title: 'Chapter 2',
          startOffset: Duration(minutes: 10),
          duration: Duration(minutes: 15),
          trackItemId: 'book1',
        ),
      ];

      final valid = chapters
          .where((ch) => ch.duration > Duration.zero)
          .toList();

      expect(valid.length, 2);
      expect(valid[0].title, 'Chapter 1');
      expect(valid[1].title, 'Chapter 2');
    });

    test('filter out negative duration chapters', () {
      final chapters = [
        const UnifiedChapter(
          id: 'ch1',
          title: 'Chapter 1',
          startOffset: Duration.zero,
          duration: Duration(minutes: 10),
          trackItemId: 'book1',
        ),
        const UnifiedChapter(
          id: 'ch_neg',
          title: 'Bad Chapter',
          startOffset: Duration(minutes: 10),
          duration: Duration(milliseconds: -500),
          trackItemId: 'book1',
        ),
      ];

      final valid = chapters
          .where((ch) => !ch.duration.isNegative && ch.duration > Duration.zero)
          .toList();

      expect(valid.length, 1);
    });
  });
}
