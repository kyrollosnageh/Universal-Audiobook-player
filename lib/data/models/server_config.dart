import 'package:equatable/equatable.dart';

/// Supported server types.
enum ServerType { emby, jellyfin, audiobookshelf, plex }

/// Configuration for a connected media server.
class ServerConfig extends Equatable {
  const ServerConfig({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
    this.userId,
    this.isActive = false,
    this.trustedCertFingerprint,
    this.addedAt,
  });

  final String id;
  final String name;
  final String url;
  final ServerType type;
  final String? userId;
  final bool isActive;
  final String? trustedCertFingerprint;
  final DateTime? addedAt;

  ServerConfig copyWith({
    String? id,
    String? name,
    String? url,
    ServerType? type,
    String? userId,
    bool? isActive,
    String? trustedCertFingerprint,
    DateTime? addedAt,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      userId: userId ?? this.userId,
      isActive: isActive ?? this.isActive,
      trustedCertFingerprint:
          trustedCertFingerprint ?? this.trustedCertFingerprint,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  @override
  List<Object?> get props => [id, name, url, type, userId, isActive];
}
