import 'server_config.dart';

/// Result of a successful authentication attempt.
class AuthResult {
  const AuthResult({
    required this.token,
    required this.userId,
    required this.serverName,
    required this.serverType,
    this.serverId,
    this.username,
  });

  /// The access token to use for subsequent requests.
  final String token;

  /// The user's ID on this server.
  final String userId;

  /// The server's display name.
  final String serverName;

  /// The detected server type.
  final ServerType serverType;

  /// Server-assigned ID (if available).
  final String? serverId;

  /// The username (for display only — never stored).
  final String? username;
}

/// Paginated result from a library fetch.
class PaginatedResult<T> {
  const PaginatedResult({
    required this.items,
    required this.totalCount,
    required this.offset,
    required this.limit,
  });

  final List<T> items;
  final int totalCount;
  final int offset;
  final int limit;

  bool get hasMore => offset + items.length < totalCount;
  int get nextOffset => offset + items.length;
}

/// Supported sort orders for library browsing.
enum SortOrder {
  titleAsc,
  titleDesc,
  authorAsc,
  authorDesc,
  dateAddedDesc,
  dateAddedAsc,
  datePlayedDesc,
  communityRatingDesc,
}

/// Audio format for transcode requests.
enum AudioFormat { aac, mp3, opus, flac, original }
