import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/constants.dart';
import '../data/models/book.dart';
import '../data/models/unified_chapter.dart';
import '../data/server_providers/server_provider.dart';
import '../services/playback_service.dart';
import 'auth_provider.dart';
import 'library_provider.dart';

/// Playback service provider.
final playbackServiceProvider = Provider<PlaybackService>((ref) {
  final service = PlaybackService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Playback state.
class PlayerState {
  const PlayerState({
    this.book,
    this.chapters = const [],
    this.currentChapter,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedPosition = Duration.zero,
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
  final Duration bufferedPosition;
  final bool isPlaying;
  final bool isBuffering;
  final double speed;
  final Duration? sleepTimerRemaining;
  final String? error;

  bool get hasBook => book != null;
  double get progress => duration.inMilliseconds > 0
      ? position.inMilliseconds / duration.inMilliseconds
      : 0.0;

  PlayerState copyWith({
    Book? book,
    List<UnifiedChapter>? chapters,
    UnifiedChapter? currentChapter,
    Duration? position,
    Duration? duration,
    Duration? bufferedPosition,
    bool? isPlaying,
    bool? isBuffering,
    double? speed,
    Duration? sleepTimerRemaining,
    bool clearSleepTimer = false,
    String? error,
  }) {
    return PlayerState(
      book: book ?? this.book,
      chapters: chapters ?? this.chapters,
      currentChapter: currentChapter ?? this.currentChapter,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedPosition: bufferedPosition ?? this.bufferedPosition,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      speed: speed ?? this.speed,
      sleepTimerRemaining: clearSleepTimer
          ? null
          : (sleepTimerRemaining ?? this.sleepTimerRemaining),
      error: error,
    );
  }
}

/// Player state notifier — manages playback via PlaybackService.
class PlayerNotifier extends Notifier<PlayerState> {
  late PlaybackService _playbackService;
  late SyncService _syncService;

  @override
  PlayerState build() {
    _playbackService = ref.read(playbackServiceProvider);
    _syncService = ref.read(syncServiceProvider);
    ref.onDispose(() {
      _positionSub?.cancel();
      _durationSub?.cancel();
      _bufferedSub?.cancel();
      _playerStateSub?.cancel();
      _processingSub?.cancel();
      _stopPositionTracking();
      _savePositionImmediately();
    });
    return const PlayerState();
  }

  StreamSubscription? _positionSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _bufferedSub;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _processingSub;
  Timer? _positionSaveTimer;
  Timer? _positionSyncTimer;
  Timer? _sleepTimerPollTimer;
  ServerProvider? _provider;

  /// Initialize the playback service.
  Future<void> initialize() async {
    await _playbackService.initialize();
    _subscribeToStreams();
  }

  /// Load and start playing a book.
  Future<void> playBook({
    required Book book,
    required List<UnifiedChapter> chapters,
    required ServerProvider provider,
    Duration startPosition = Duration.zero,
  }) async {
    _provider = provider;

    try {
      await _playbackService.loadBook(
        book: book,
        chapters: chapters,
        provider: provider,
        startPosition: startPosition,
      );

      state = state.copyWith(
        book: book,
        chapters: chapters,
        currentChapter: _playbackService.currentChapter,
        error: null,
      );

      await _playbackService.play();
      _startPositionTracking();
    } catch (e) {
      // Save position before handling error
      await _savePositionImmediately();
      state = state.copyWith(error: e.toString());
    }
  }

  void setBook(Book book, List<UnifiedChapter> chapters) {
    state = state.copyWith(
      book: book,
      chapters: chapters,
      currentChapter: chapters.isNotEmpty ? chapters.first : null,
    );
  }

  Future<void> togglePlayPause() async {
    await _playbackService.togglePlayPause();
  }

  Future<void> play() async => _playbackService.play();
  Future<void> pause() async => _playbackService.pause();

  Future<void> seek(Duration position) async {
    await _playbackService.seek(position);
    state = state.copyWith(currentChapter: _playbackService.currentChapter);
  }

  Future<void> skipForward() async => _playbackService.skipForward();
  Future<void> skipBackward() async => _playbackService.skipBackward();
  Future<void> nextChapter() async {
    await _playbackService.nextChapter();
    state = state.copyWith(currentChapter: _playbackService.currentChapter);
  }

  Future<void> previousChapter() async {
    await _playbackService.previousChapter();
    state = state.copyWith(currentChapter: _playbackService.currentChapter);
  }

  Future<void> seekToChapter(int index) async {
    await _playbackService.seekToChapter(index);
    state = state.copyWith(currentChapter: _playbackService.currentChapter);
  }

  Future<void> setSpeed(double speed) async {
    await _playbackService.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  void setSleepTimer(Duration duration) {
    _playbackService.setSleepTimer(duration);
    _startSleepTimerPolling();
  }

  void cancelSleepTimer() {
    _playbackService.cancelSleepTimer();
    _sleepTimerPollTimer?.cancel();
    state = state.copyWith(clearSleepTimer: true);
  }

  Future<void> stop() async {
    await _savePositionImmediately();
    await _playbackService.stop();
    _stopPositionTracking();
  }

  void clear() {
    _stopPositionTracking();
    state = const PlayerState();
  }

  // ── Position Tracking ─────────────────────────────────────────

  void _startPositionTracking() {
    // Save to Drift every 10 seconds
    _positionSaveTimer?.cancel();
    _positionSaveTimer = Timer.periodic(
      AppConstants.positionSaveInterval,
      (_) => _savePositionImmediately(),
    );

    // Sync to server every 30 seconds
    _positionSyncTimer?.cancel();
    _positionSyncTimer = Timer.periodic(
      AppConstants.positionSyncInterval,
      (_) => _syncPositionToServer(),
    );
  }

  void _stopPositionTracking() {
    _positionSaveTimer?.cancel();
    _positionSyncTimer?.cancel();
    _sleepTimerPollTimer?.cancel();
  }

  Future<void> _savePositionImmediately() async {
    if (state.book == null || _provider == null) return;

    await _syncService.saveLocalPosition(
      bookId: state.book!.id,
      serverId: _provider!.serverUrl,
      position: state.position,
      chapterId: state.currentChapter?.id,
    );
  }

  Future<void> _syncPositionToServer() async {
    if (state.book == null || _provider == null) return;

    await _syncService.syncToServer(
      _provider!,
      bookId: state.book!.id,
      position: state.position,
    );
  }

  // ── Stream Subscriptions ──────────────────────────────────────

  void _subscribeToStreams() {
    _positionSub = _playbackService.positionStream.listen((pos) {
      state = state.copyWith(position: pos);

      // Update current chapter based on position
      final chapter = _playbackService.currentChapter;
      if (chapter != null && chapter != state.currentChapter) {
        state = state.copyWith(currentChapter: chapter);
      }
    });

    _durationSub = _playbackService.durationStream.listen((dur) {
      if (dur != null) {
        state = state.copyWith(duration: dur);
      }
    });

    _bufferedSub = _playbackService.bufferedPositionStream.listen((buf) {
      state = state.copyWith(bufferedPosition: buf);
    });

    _playerStateSub = _playbackService.playerStateStream.listen((ps) {
      state = state.copyWith(isPlaying: ps.playing);
    });

    _processingSub = _playbackService.processingStateStream.listen((ps) {
      state = state.copyWith(
        isBuffering:
            ps == ProcessingState.buffering || ps == ProcessingState.loading,
      );

      if (ps == ProcessingState.completed) {
        _savePositionImmediately();
      }
    });
  }

  void _startSleepTimerPolling() {
    _sleepTimerPollTimer?.cancel();
    _sleepTimerPollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final remaining = _playbackService.sleepTimerRemaining;
      state = state.copyWith(sleepTimerRemaining: remaining);
      if (remaining == null || remaining == Duration.zero) {
        _sleepTimerPollTimer?.cancel();
      }
    });
  }
}

final playerNotifierProvider = NotifierProvider<PlayerNotifier, PlayerState>(
  PlayerNotifier.new,
);
