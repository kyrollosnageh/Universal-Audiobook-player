import 'package:flutter/services.dart';

import '../data/models/book.dart';
import '../data/models/unified_chapter.dart';

/// CarPlay UI templates via Flutter method channels.
///
/// Implements CPTemplate-based UI for Apple CarPlay:
/// - CPTabBarTemplate: root navigation with tabs
/// - CPListTemplate: library browsing lists
/// - CPNowPlayingTemplate: active playback display
///
/// The native Swift/Objective-C CarPlay scene delegate
/// communicates with Flutter via method channels.
class CarUiTemplates {
  CarUiTemplates() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const _channel = MethodChannel('com.libretto/carplay');

  /// Callbacks for CarPlay events.
  void Function(String bookId)? onBookSelected;
  void Function()? onPlayPause;
  void Function()? onNextChapter;
  void Function()? onPreviousChapter;

  // ── Push Templates ────────────────────────────────────────────

  /// Update the CarPlay "Now Playing" display.
  Future<void> updateNowPlaying({
    required Book book,
    UnifiedChapter? chapter,
    Duration position = Duration.zero,
    Duration duration = Duration.zero,
    bool isPlaying = false,
    double speed = 1.0,
  }) async {
    try {
      await _channel.invokeMethod('updateNowPlaying', {
        'title': book.title,
        'artist': book.author ?? '',
        'album': book.seriesName ?? '',
        'chapter': chapter?.title ?? '',
        'position': position.inMilliseconds,
        'duration': duration.inMilliseconds,
        'isPlaying': isPlaying,
        'speed': speed,
        'coverUrl': book.coverUrl ?? '',
      });
    } on PlatformException {
      // CarPlay not available
    }
  }

  /// Update the library list on CarPlay.
  Future<void> updateLibraryList(List<Map<String, dynamic>> items) async {
    try {
      await _channel.invokeMethod('updateLibraryList', {
        'items': items,
      });
    } on PlatformException {
      // CarPlay not available
    }
  }

  /// Show an alert on CarPlay.
  Future<void> showAlert(String title, String message) async {
    try {
      await _channel.invokeMethod('showAlert', {
        'title': title,
        'message': message,
      });
    } on PlatformException {
      // CarPlay not available
    }
  }

  // ── Handle CarPlay Events ─────────────────────────────────────

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onBookSelected':
        final bookId = call.arguments as String;
        onBookSelected?.call(bookId);
        break;
      case 'onPlayPause':
        onPlayPause?.call();
        break;
      case 'onNextChapter':
        onNextChapter?.call();
        break;
      case 'onPreviousChapter':
        onPreviousChapter?.call();
        break;
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}
