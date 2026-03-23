/// Opt-in usage analytics with PII stripping.
///
/// NEVER tracks: server URLs, usernames, passwords, book titles,
/// library contents, listening history, file paths, cover art URLs,
/// chapter names.
///
/// Tracks: session duration, feature usage, playback speed distribution,
/// error rates by format, search-to-play conversion, offline vs streaming ratio.
class AnalyticsService {
  AnalyticsService();

  bool _optedIn = false;

  bool get isOptedIn => _optedIn;

  Future<void> initialize({required bool optIn}) async {
    _optedIn = optIn;
    if (!optIn) return;

    // PostHog/Aptabase initialization would go here
  }

  Future<void> setOptIn(bool optIn) async {
    _optedIn = optIn;
    if (!optIn) {
      // Disable and clear any pending events
    }
  }

  /// Track a generic event (PII-stripped).
  void trackEvent(String name, [Map<String, dynamic>? properties]) {
    if (!_optedIn) return;
    // Strip any PII fields before sending
    final safe = _stripPii(properties);
    // Send to analytics backend
  }

  void trackPlaybackStart({
    required String audioFormat,
    required bool isOffline,
  }) {
    trackEvent('playback_start', {
      'audio_format': audioFormat,
      'is_offline': isOffline,
    });
  }

  void trackPlaybackSpeed(double speed) {
    trackEvent('playback_speed', {'speed': speed});
  }

  void trackSearch({required bool hadResults}) {
    trackEvent('search', {'had_results': hadResults});
  }

  void trackError({required String type, required String context}) {
    trackEvent('error', {'error_type': type, 'context': context});
  }

  Map<String, dynamic>? _stripPii(Map<String, dynamic>? properties) {
    if (properties == null) return null;

    const piiKeys = {
      'server_url',
      'username',
      'password',
      'token',
      'book_title',
      'title',
      'file_path',
      'cover_url',
      'chapter_name',
    };

    return Map.fromEntries(
      properties.entries.where((e) => !piiKeys.contains(e.key)),
    );
  }

  void dispose() {}
}
