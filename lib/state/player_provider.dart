import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/book.dart';
import '../data/models/unified_chapter.dart';

/// Playback state — full implementation in Phase 2.
class PlayerState {
  const PlayerState({
    this.book,
    this.chapters = const [],
    this.currentChapter,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.speed = 1.0,
    this.sleepTimerRemaining,
    this.error,
  });

  final Book? book;
  final List<UnifiedChapter> chapters;
  final UnifiedChapter? currentChapter;
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool isBuffering;
  final double speed;
  final Duration? sleepTimerRemaining;
  final String? error;

  bool get hasBook => book != null;
  double get progress =>
      duration.inMilliseconds > 0
          ? position.inMilliseconds / duration.inMilliseconds
          : 0.0;

  PlayerState copyWith({
    Book? book,
    List<UnifiedChapter>? chapters,
    UnifiedChapter? currentChapter,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    bool? isBuffering,
    double? speed,
    Duration? sleepTimerRemaining,
    String? error,
  }) {
    return PlayerState(
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
      currentChapter: currentChapter ?? this.currentChapter,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      speed: speed ?? this.speed,
      sleepTimerRemaining: sleepTimerRemaining ?? this.sleepTimerRemaining,
      error: error,
    );
  }
}

/// Player state notifier — Phase 2 will add full playback control.
class PlayerNotifier extends StateNotifier<PlayerState> {
  PlayerNotifier() : super(const PlayerState());

  void setBook(Book book, List<UnifiedChapter> chapters) {
    state = state.copyWith(
      book: book,
      chapters: chapters,
      currentChapter: chapters.isNotEmpty ? chapters.first : null,
    );
  }

  void clear() {
    state = const PlayerState();
  }
}

final playerNotifierProvider =
    StateNotifierProvider<PlayerNotifier, PlayerState>((ref) {
  return PlayerNotifier();
});
