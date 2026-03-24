/// Application-wide constants for Libretto.
class AppConstants {
  AppConstants._();

  // App info
  static const String appName = 'Libretto';
  static const String appVersion = '1.0.43';

  /// App Store URL — update this once the app is published.
  static const String appStoreUrl =
      'https://apps.apple.com/app/libretto-audiobook-player/idXXXXXXXXXX';

  // Pagination
  static const int defaultPageSize = 100;
  static const int prefetchThreshold = 10;
  static const int backgroundPrefetchBatchSize = 200;

  // Search
  static const Duration searchDebounce = Duration(milliseconds: 300);
  static const int searchResultLimit = 50;
  static const int searchCoverMaxWidth = 150;

  // Cover art sizes
  static const int coverListWidth = 150;
  static const int coverGridWidth = 300;
  static const int coverDetailWidth = 600;

  // Playback
  static const Duration skipForwardDuration = Duration(seconds: 30);
  static const Duration skipBackwardDuration = Duration(seconds: 15);
  static const Duration positionSaveInterval = Duration(seconds: 10);
  static const Duration positionSyncInterval = Duration(seconds: 30);
  static const double minPlaybackSpeed = 0.5;
  static const double maxPlaybackSpeed = 3.0;
  static const double defaultPlaybackSpeed = 1.0;

  // Downloads
  static const int maxConcurrentDownloads = 2;
  static const int prefetchChaptersAhead = 3;

  // Retry / backoff
  static const int maxRetryAttempts = 4;
  static const Duration initialRetryDelay = Duration(seconds: 2);
  static const Duration maxRetryDelay = Duration(seconds: 60);

  // Sleep timer presets (minutes)
  static const List<int> sleepTimerPresets = [15, 30, 45, 60];

  // Auto-advance countdown
  static const Duration autoAdvanceCountdown = Duration(seconds: 15);

  // Accessibility
  static const double minTouchTarget = 48.0;
  static const double highTextScaleThreshold = 1.5;
}

/// Emby/Jellyfin API paths.
class EmbyApiPaths {
  EmbyApiPaths._();

  static const String systemInfo = '/System/Info';
  static const String systemInfoPublic = '/System/Info/Public';
  static const String authenticateByName = '/Users/AuthenticateByName';
  static String userItems(String userId) => '/Users/$userId/Items';
  static String userItemDetail(String userId, String itemId) =>
      '/Users/$userId/Items/$itemId';
  static String itemDetail(String itemId) => '/Items/$itemId';
  static String audioStream(String itemId) => '/Audio/$itemId/stream';
  static String itemImage(String itemId) => '/Items/$itemId/Images/Primary';
  static const String sessionsLogout = '/Sessions/Logout';
}

/// Audiobookshelf API paths.
class AbsApiPaths {
  AbsApiPaths._();

  static const String status = '/api/status';
  static const String login = '/login';
  static String libraryItems(String libraryId) =>
      '/api/libraries/$libraryId/items';
  static String itemDetail(String itemId) => '/api/items/$itemId';
  static String itemChapters(String itemId) => '/api/items/$itemId/chapters';
  static String itemPlay(String itemId) => '/api/items/$itemId/play';
  static const String libraries = '/api/libraries';
  static const String series = '/api/series';
}

/// Plex API paths.
class PlexApiPaths {
  PlexApiPaths._();

  static const String identity = '/identity';
  static const String plexTvPins = 'https://plex.tv/api/v2/pins';
  static const String plexTvAuth = 'https://app.plex.tv/auth';
  static const String plexTvResources = 'https://plex.tv/api/v2/resources';
  static String librarySections(String sectionId) =>
      '/library/sections/$sectionId/all';
  static String metadata(String ratingKey) => '/library/metadata/$ratingKey';
  static String children(String ratingKey) =>
      '/library/metadata/$ratingKey/children';
}

/// Secure storage key patterns.
class StorageKeys {
  StorageKeys._();

  static String serverToken(String serverUrl) => 'server:$serverUrl:token';
  static String serverUserId(String serverUrl) => 'server:$serverUrl:userId';
  static String serverType(String serverUrl) => 'server:$serverUrl:type';
  static String certFingerprint(String serverUrl) =>
      'server:$serverUrl:certFingerprint';

  static const String activeServerId = 'activeServerId';
  static const String biometricEnabled = 'biometricEnabled';
  static const String analyticsOptIn = 'analyticsOptIn';
}
