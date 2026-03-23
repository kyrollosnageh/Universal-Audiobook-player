import 'dart:async';

import 'package:flutter/foundation.dart';

/// Crash reporting wrapper with PII stripping.
///
/// Never includes: server URLs, usernames, book titles, file paths.
/// Includes: audio format, OS version, device model, storage available,
///           playback state, streaming vs offline, chapter service path.
class CrashReportingService {
  CrashReportingService();

  bool _initialized = false;

  /// Initialize crash reporting (Firebase Crashlytics in production).
  Future<void> initialize() async {
    _initialized = true;

    // In production, this would be:
    // await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);

    // Set up Flutter error handling
    FlutterError.onError = (details) {
      _recordFlutterError(details);
    };
  }

  /// Record a non-fatal error with context.
  void recordError(
    Object error,
    StackTrace? stackTrace, {
    String? context,
    Map<String, String>? metadata,
  }) {
    if (!_initialized) return;

    final safeMetadata = _stripPii(metadata ?? {});
    if (context != null) {
      safeMetadata['context'] = context;
    }

    if (kDebugMode) {
      // In debug mode, just print
      debugPrint('CrashReport: $error');
      debugPrint('Context: $context');
      debugPrint('Metadata: $safeMetadata');
    }

    // In production:
    // FirebaseCrashlytics.instance.recordError(error, stackTrace,
    //   reason: context, information: safeMetadata.entries.map(
    //     (e) => '${e.key}: ${e.value}').toList());
  }

  /// Set custom keys for crash context.
  void setPlaybackContext({
    required String audioFormat,
    required bool isStreaming,
    required String chapterFormat,
  }) {
    if (!_initialized) return;

    // FirebaseCrashlytics.instance.setCustomKey('audio_format', audioFormat);
    // FirebaseCrashlytics.instance.setCustomKey('is_streaming', isStreaming);
    // FirebaseCrashlytics.instance.setCustomKey('chapter_format', chapterFormat);
  }

  void setDeviceContext({
    required int storageAvailableMb,
    required String osVersion,
  }) {
    if (!_initialized) return;

    // FirebaseCrashlytics.instance.setCustomKey('storage_mb', storageAvailableMb);
    // FirebaseCrashlytics.instance.setCustomKey('os_version', osVersion);
  }

  void _recordFlutterError(FlutterErrorDetails details) {
    if (kDebugMode) {
      FlutterError.dumpErrorToConsole(details);
      return;
    }

    // FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  }

  /// Strip PII from metadata before sending to crash reporting.
  Map<String, String> _stripPii(Map<String, String> metadata) {
    const piiKeys = {
      'server_url',
      'serverUrl',
      'username',
      'password',
      'token',
      'book_title',
      'bookTitle',
      'title',
      'file_path',
      'filePath',
      'cover_url',
      'coverUrl',
      'chapter_name',
      'chapterName',
      'author',
      'narrator',
    };

    return Map.fromEntries(
      metadata.entries.where((e) => !piiKeys.contains(e.key)),
    );
  }
}
