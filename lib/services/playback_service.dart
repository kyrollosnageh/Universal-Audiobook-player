import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../data/models/book.dart';
import '../data/models/unified_chapter.dart';
import '../data/server_providers/server_provider.dart';

/// Audio engine wrapper around just_audio + audio_session.
///
/// Provides:
/// - Play / Pause / Stop
/// - Skip forward/back (configurable)
/// - Playback speed 0.5x - 3.0x with pitch correction
/// - Chapter navigation (next/previous)
/// - Sleep timer (duration or end-of-chapter)
/// - Gapless track transitions for MP3-per-chapter
/// - Position tracking via stream
/// - Error recovery with exponential backoff
class PlaybackService {
  PlaybackService();

  AudioPlayer? _player;
  AudioSession? _session;

  Book? _currentBook;
  List<UnifiedChapter> _chapters = [];
  UnifiedChapter? _currentChapter;
  ServerProvider? _provider;

  Timer? _sleepTimer;
  Duration? _sleepTimerDuration;
  bool _sleepAtEndOfChapter = false;
  DateTime? _sleepTimerStarted;

  // Retry state
  int _retryCount = 0;
  Timer? _retryTimer;

  // ── Streams ─────────────────────────────────────────────────────

  /// Position stream — emits current playback position.
  Stream<Duration> get positionStream =>
      _player?.positionStream ?? const Stream.empty();

  /// Buffered position stream.
  Stream<Duration> get bufferedPositionStream =>
      _player?.bufferedPositionStream ?? const Stream.empty();

  /// Duration stream — emits total duration when known.
  Stream<Duration?> get durationStream =>
      _player?.durationStream ?? const Stream.empty();

  /// Player state stream (playing, paused, etc.).
  Stream<PlayerState> get playerStateStream =>
      _player?.playerStateStream ?? const Stream.empty();

  /// Processing state stream (idle, loading, buffering, ready, completed).
  Stream<ProcessingState> get processingStateStream =>
      _player?.processingStateStream ?? const Stream.empty();

  /// Current position (synchronous).
  Duration get position => _player?.position ?? Duration.zero;

  /// Current duration (synchronous).
  Duration? get duration => _player?.duration;

  /// Whether currently playing.
  bool get isPlaying => _player?.playing ?? false;

  /// Current playback speed.
  double get speed => _player?.speed ?? 1.0;

  /// Current chapter.
  UnifiedChapter? get currentChapter => _currentChapter;

  /// All chapters.
  List<UnifiedChapter> get chapters => _chapters;

  /// Current book.
  Book? get currentBook => _currentBook;

  // ── Initialization ────────────────────────────────────────────

  /// Initialize the audio engine and configure the audio session.
  Future<void> initialize() async {
    _player = AudioPlayer();

    // Configure audio session for audiobook playback
    _session = await AudioSession.instance;
    await _session!.configure(const AudioSessionConfiguration.speech());

    // Handle audio interruptions (phone calls, etc.)
    _session!.interruptionEventStream.listen((event) {
      if (event.begin) {
        // Interrupted — pause
        if (isPlaying) {
          pause();
        }
      } else {
        // Interruption ended — optionally resume
        if (event.type == AudioInterruptionType.pause) {
          // Only auto-resume for transient interruptions
          play();
        }
      }
    });

    // Handle becoming noisy (headphones unplugged)
    _session!.becomingNoisyEventStream.listen((_) {
      pause();
    });

    // Listen for playback completion
    _player!.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _onTrackCompleted();
      }
    });
  }

  // ── Loading ───────────────────────────────────────────────────

  /// Load a book for playback.
  ///
  /// Sets up the audio source based on chapter format:
  /// - Single file (M4B): loads the file, seeks to resume position
  /// - MP3-per-chapter: builds a ConcatenatingAudioSource playlist
  Future<void> loadBook({
    required Book book,
    required List<UnifiedChapter> chapters,
    required ServerProvider provider,
    Duration startPosition = Duration.zero,
  }) async {
    _ensureInitialized();
    _currentBook = book;
    _chapters = chapters;
    _provider = provider;
    _retryCount = 0;

    if (chapters.isEmpty) {
      throw const PlaybackException('No chapters available for this book');
    }

    try {
      if (_hasSeparateTracks(chapters)) {
        // MP3-per-chapter: build a playlist
        await _loadPlaylist(chapters, provider, startPosition);
      } else {
        // Single file: load directly
        await _loadSingleFile(chapters.first, provider, startPosition);
      }

      // Find which chapter corresponds to startPosition
      _currentChapter = _chapterAtPosition(startPosition);
    } on PlayerException catch (e) {
      throw PlaybackException('Failed to load audio: ${e.message}', e);
    }
  }

  Future<void> _loadSingleFile(
    UnifiedChapter chapter,
    ServerProvider provider,
    Duration startPosition,
  ) async {
    final url = provider.getStreamUrl(chapter.trackItemId);
    await _player!.setUrl(url.toString());
    if (startPosition > Duration.zero) {
      await _player!.seek(startPosition);
    }
  }

  Future<void> _loadPlaylist(
    List<UnifiedChapter> chapters,
    ServerProvider provider,
    Duration startPosition,
  ) async {
    final sources = chapters.map((ch) {
      final url = provider.getStreamUrl(ch.trackItemId);
      return AudioSource.uri(
        Uri.parse(url.toString()),
        tag: ch.id,
      );
    }).toList();

    final playlist = ConcatenatingAudioSource(
      useLazyPreparation: true,
      children: sources,
    );

    await _player!.setAudioSource(playlist);

    // Seek to the correct track and position
    if (startPosition > Duration.zero) {
      final (trackIndex, trackPosition) =
          _resolvePlaylistPosition(chapters, startPosition);
      await _player!.seek(trackPosition, index: trackIndex);
    }
  }

  // ── Playback Controls ─────────────────────────────────────────

  /// Start or resume playback.
  Future<void> play() async {
    _ensureInitialized();
    await _player!.play();
  }

  /// Pause playback.
  Future<void> pause() async {
    _ensureInitialized();
    await _player!.pause();
  }

  /// Stop playback completely.
  Future<void> stop() async {
    _ensureInitialized();
    await _player!.stop();
    cancelSleepTimer();
  }

  /// Toggle play/pause.
  Future<void> togglePlayPause() async {
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  /// Seek to an absolute position.
  Future<void> seek(Duration position) async {
    _ensureInitialized();

    if (_hasSeparateTracks(_chapters)) {
      final (trackIndex, trackPosition) =
          _resolvePlaylistPosition(_chapters, position);
      await _player!.seek(trackPosition, index: trackIndex);
    } else {
      await _player!.seek(position);
    }

    _currentChapter = _chapterAtPosition(position);
  }

  /// Skip forward by the configured duration (default 30s).
  Future<void> skipForward([Duration? duration]) async {
    final skip = duration ?? AppConstants.skipForwardDuration;
    final newPos = position + skip;
    final maxPos = this.duration ?? Duration.zero;

    if (newPos < maxPos) {
      await seek(newPos);
    } else {
      await seek(maxPos);
    }
  }

  /// Skip backward by the configured duration (default 15s).
  Future<void> skipBackward([Duration? duration]) async {
    final skip = duration ?? AppConstants.skipBackwardDuration;
    final newPos = position - skip;

    if (newPos > Duration.zero) {
      await seek(newPos);
    } else {
      await seek(Duration.zero);
    }
  }

  // ── Chapter Navigation ────────────────────────────────────────

  /// Skip to the next chapter.
  Future<void> nextChapter() async {
    if (_currentChapter == null || _chapters.isEmpty) return;

    final idx = _chapters.indexOf(_currentChapter!);
    if (idx < 0 || idx >= _chapters.length - 1) return;

    final next = _chapters[idx + 1];
    _currentChapter = next;
    await seek(next.startOffset);
  }

  /// Skip to the previous chapter.
  /// If more than 3 seconds into current chapter, restarts it instead.
  Future<void> previousChapter() async {
    if (_currentChapter == null || _chapters.isEmpty) return;

    final idx = _chapters.indexOf(_currentChapter!);
    if (idx < 0) return;

    // If more than 3s into chapter, restart it
    final chapterElapsed = position - _currentChapter!.startOffset;
    if (chapterElapsed > const Duration(seconds: 3) || idx == 0) {
      await seek(_currentChapter!.startOffset);
      return;
    }

    // Go to previous chapter
    final prev = _chapters[idx - 1];
    _currentChapter = prev;
    await seek(prev.startOffset);
  }

  /// Seek to a specific chapter by index.
  Future<void> seekToChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    _currentChapter = _chapters[index];
    await seek(_currentChapter!.startOffset);
  }

  // ── Playback Speed ────────────────────────────────────────────

  /// Set playback speed (0.5x - 3.0x) with pitch correction.
  Future<void> setSpeed(double speed) async {
    _ensureInitialized();
    final clamped = speed.clamp(
      AppConstants.minPlaybackSpeed,
      AppConstants.maxPlaybackSpeed,
    );
    await _player!.setSpeed(clamped);
  }

  // ── Sleep Timer ───────────────────────────────────────────────

  /// Set a sleep timer.
  ///
  /// [duration] of -1ms means "end of current chapter".
  void setSleepTimer(Duration duration) {
    cancelSleepTimer();

    if (duration.isNegative) {
      // Sleep at end of chapter
      _sleepAtEndOfChapter = true;
      return;
    }

    _sleepTimerDuration = duration;
    _sleepTimerStarted = DateTime.now();
    _sleepTimer = Timer(duration, () {
      pause();
      _sleepTimerDuration = null;
      _sleepTimerStarted = null;
    });
  }

  /// Cancel the active sleep timer.
  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerDuration = null;
    _sleepTimerStarted = null;
    _sleepAtEndOfChapter = false;
  }

  /// Get remaining sleep timer duration.
  Duration? get sleepTimerRemaining {
    if (_sleepAtEndOfChapter) {
      if (_currentChapter == null) return null;
      final chapterEnd = _currentChapter!.endOffset;
      final remaining = chapterEnd - position;
      return remaining.isNegative ? Duration.zero : remaining;
    }

    if (_sleepTimerDuration == null || _sleepTimerStarted == null) {
      return null;
    }

    final elapsed = DateTime.now().difference(_sleepTimerStarted!);
    final remaining = _sleepTimerDuration! - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  // ── Volume ────────────────────────────────────────────────────

  /// Set volume (0.0 - 1.0).
  Future<void> setVolume(double volume) async {
    _ensureInitialized();
    await _player!.setVolume(volume.clamp(0.0, 1.0));
  }

  // ── Error Recovery ────────────────────────────────────────────

  /// Retry loading after an error with exponential backoff.
  Future<void> retryAfterError() async {
    if (_currentBook == null || _provider == null) return;
    if (_retryCount >= AppConstants.maxRetryAttempts) return;

    _retryCount++;
    final delay = AppConstants.initialRetryDelay * (1 << (_retryCount - 1));
    final clampedDelay = delay > AppConstants.maxRetryDelay
        ? AppConstants.maxRetryDelay
        : delay;

    _retryTimer = Timer(clampedDelay, () async {
      try {
        await loadBook(
          book: _currentBook!,
          chapters: _chapters,
          provider: _provider!,
          startPosition: position,
        );
        await play();
        _retryCount = 0;
      } catch (_) {
        retryAfterError(); // Try again with longer delay
      }
    });
  }

  // ── Lifecycle ─────────────────────────────────────────────────

  /// Dispose of all resources.
  Future<void> dispose() async {
    cancelSleepTimer();
    _retryTimer?.cancel();
    await _player?.dispose();
    _player = null;
  }

  // ── Private Helpers ───────────────────────────────────────────

  void _ensureInitialized() {
    if (_player == null) {
      throw const PlaybackException('PlaybackService not initialized');
    }
  }

  bool _hasSeparateTracks(List<UnifiedChapter> chapters) {
    return chapters.any((ch) => ch.isSeparateTrack);
  }

  UnifiedChapter? _chapterAtPosition(Duration position) {
    for (final ch in _chapters.reversed) {
      if (position >= ch.startOffset) return ch;
    }
    return _chapters.isNotEmpty ? _chapters.first : null;
  }

  /// Resolve an absolute position to a playlist track index + offset.
  (int, Duration) _resolvePlaylistPosition(
    List<UnifiedChapter> chapters,
    Duration absolutePosition,
  ) {
    var accumulated = Duration.zero;

    for (var i = 0; i < chapters.length; i++) {
      final chEnd = accumulated + chapters[i].duration;
      if (absolutePosition < chEnd) {
        return (i, absolutePosition - accumulated);
      }
      accumulated = chEnd;
    }

    // Past the end — return last track
    if (chapters.isNotEmpty) {
      return (chapters.length - 1, Duration.zero);
    }
    return (0, Duration.zero);
  }

  /// Called when the current track finishes.
  void _onTrackCompleted() {
    // Sleep at end of chapter
    if (_sleepAtEndOfChapter) {
      pause();
      _sleepAtEndOfChapter = false;
      return;
    }

    // For single-file books, check if there's a next chapter
    // (handled by just_audio's playlist for MP3-per-chapter)
    if (!_hasSeparateTracks(_chapters) && _currentChapter != null) {
      final idx = _chapters.indexOf(_currentChapter!);
      if (idx >= 0 && idx < _chapters.length - 1) {
        _currentChapter = _chapters[idx + 1];
      }
    }
  }
}
