import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import '../core/constants.dart';

/// AudioHandler for background playback, lock screen controls,
/// notification controls, and CarPlay/Android Auto integration.
///
/// Bridges just_audio's AudioPlayer with audio_service's MediaSession.
class LibrettoAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  LibrettoAudioHandler(this._player) {
    _init();
  }

  final AudioPlayer _player;

  void _init() {
    // Broadcast player state changes to the system
    _player.playbackEventStream.map(_transformEvent).pipe(playbackState);

    // Update the current media item when duration changes
    _player.durationStream.listen((duration) {
      final item = mediaItem.value;
      if (item != null && duration != null) {
        mediaItem.add(item.copyWith(duration: duration));
      }
    });

    // Handle sequence state changes (for playlists)
    _player.currentIndexStream.listen((index) {
      if (index != null && queue.value.isNotEmpty) {
        if (index < queue.value.length) {
          mediaItem.add(queue.value[index]);
        }
      }
    });
  }

  /// Set the current media item metadata for lock screen / notification.
  void setMediaItemInfo({
    required String title,
    String? artist,
    String? album,
    Duration? duration,
    Uri? artUri,
  }) {
    mediaItem.add(
      MediaItem(
        id: 'current',
        title: title,
        artist: artist,
        album: album,
        duration: duration,
        artUri: artUri,
      ),
    );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    return super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Chapter skip forward — handled by PlayerNotifier
  }

  @override
  Future<void> skipToPrevious() async {
    // Chapter skip backward — handled by PlayerNotifier
  }

  @override
  Future<void> fastForward() async {
    final newPos = _player.position + AppConstants.skipForwardDuration;
    final maxPos = _player.duration ?? Duration.zero;
    await _player.seek(newPos < maxPos ? newPos : maxPos);
  }

  @override
  Future<void> rewind() async {
    final newPos = _player.position - AppConstants.skipBackwardDuration;
    await _player.seek(newPos > Duration.zero ? newPos : Duration.zero);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  PlaybackState _transformEvent(PlaybackEvent event) {
    return PlaybackState(
      controls: [
        MediaControl.rewind,
        MediaControl.skipToPrevious,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 2, 4],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    );
  }
}

/// Initialize audio_service with our handler.
Future<LibrettoAudioHandler> initAudioHandler(AudioPlayer player) async {
  return await AudioService.init(
    builder: () => LibrettoAudioHandler(player),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.libretto.audio',
      androidNotificationChannelName: 'Libretto Playback',
      androidStopForegroundOnPause: false,
      artDownscaleWidth: 300,
      artDownscaleHeight: 300,
      fastForwardInterval: AppConstants.skipForwardDuration,
      rewindInterval: AppConstants.skipBackwardDuration,
    ),
  );
}
