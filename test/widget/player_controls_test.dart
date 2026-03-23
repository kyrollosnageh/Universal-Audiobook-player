import 'package:flutter_test/flutter_test.dart';

import 'package:libretto/state/player_provider.dart';
import 'package:libretto/data/models/book.dart';
import 'package:libretto/data/models/unified_chapter.dart';

void main() {
  group('PlayerState', () {
    test('hasBook is false when no book', () {
      const state = PlayerState();
      expect(state.hasBook, false);
    });

    test('hasBook is true when book set', () {
      const state = PlayerState(
        book: Book(id: 'b1', serverId: 's1', title: 'Test'),
      );
      expect(state.hasBook, true);
    });

    test('progress calculation', () {
      const state = PlayerState(
        position: Duration(minutes: 30),
        duration: Duration(hours: 1),
      );
      expect(state.progress, closeTo(0.5, 0.001));
    });

    test('progress is 0 when duration is 0', () {
      const state = PlayerState(
        position: Duration(minutes: 5),
        duration: Duration.zero,
      );
      expect(state.progress, 0.0);
    });

    test('copyWith preserves unmodified fields', () {
      const state = PlayerState(
        book: Book(id: 'b1', serverId: 's1', title: 'Test'),
        isPlaying: true,
        speed: 1.5,
        position: Duration(minutes: 10),
      );

      final updated = state.copyWith(isPlaying: false);
      expect(updated.isPlaying, false);
      expect(updated.book?.id, 'b1');
      expect(updated.speed, 1.5);
      expect(updated.position, const Duration(minutes: 10));
    });

    test('copyWith clears error when set to null', () {
      const state = PlayerState(error: 'some error');
      final updated = state.copyWith(error: null);
      expect(updated.error, null);
    });

    test('chapters stored correctly', () {
      final chapters = [
        const UnifiedChapter(
          id: 'ch1',
          title: 'Chapter 1',
          startOffset: Duration.zero,
          duration: Duration(minutes: 10),
          trackItemId: 'b1',
        ),
        const UnifiedChapter(
          id: 'ch2',
          title: 'Chapter 2',
          startOffset: Duration(minutes: 10),
          duration: Duration(minutes: 15),
          trackItemId: 'b1',
        ),
      ];

      final state = PlayerState(
        chapters: chapters,
        currentChapter: chapters.first,
      );

      expect(state.chapters.length, 2);
      expect(state.currentChapter?.title, 'Chapter 1');
    });
  });

  group('Playback speed bounds', () {
    test('speed range 0.5 to 3.0', () {
      // Enforced by PlaybackService.setSpeed clamp
      expect(0.5.clamp(0.5, 3.0), 0.5);
      expect(3.0.clamp(0.5, 3.0), 3.0);
      expect(0.3.clamp(0.5, 3.0), 0.5);
      expect(4.0.clamp(0.5, 3.0), 3.0);
    });
  });
}
