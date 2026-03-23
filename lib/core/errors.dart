/// Base exception for all Libretto errors.
abstract class LibrettoException implements Exception {
  const LibrettoException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Server authentication failed or token expired.
class AuthenticationException extends LibrettoException {
  const AuthenticationException([String message = 'Authentication failed'])
    : super(message);
}

/// Token has expired or been revoked (HTTP 401).
class TokenExpiredException extends AuthenticationException {
  const TokenExpiredException()
    : super('Token expired or revoked. Please log in again.');
}

/// Server is unreachable.
class ServerUnreachableException extends LibrettoException {
  const ServerUnreachableException(String serverUrl)
    : super('Cannot reach server: $serverUrl');
}

/// Server type could not be detected from the URL.
class ServerDetectionException extends LibrettoException {
  const ServerDetectionException(String url)
    : super('Could not detect server type at: $url');
}

/// HTTPS is required but HTTP was provided without explicit acknowledgment.
class InsecureConnectionException extends LibrettoException {
  const InsecureConnectionException()
    : super('HTTPS is required. HTTP is only allowed for localhost/LAN.');
}

/// Certificate validation failed (self-signed cert not yet trusted).
class CertificateException extends LibrettoException {
  const CertificateException(String fingerprint)
    : super('Untrusted certificate with fingerprint: $fingerprint');
}

/// An audio playback error.
class PlaybackException extends LibrettoException {
  const PlaybackException(super.message, [super.cause]);
}

/// Unsupported audio format.
class UnsupportedFormatException extends PlaybackException {
  const UnsupportedFormatException(String format)
    : super('Unsupported audio format: $format');
}

/// Chapter data is malformed or invalid.
class ChapterParsingException extends LibrettoException {
  const ChapterParsingException(super.message, [super.cause]);
}

/// Download failed or was interrupted.
class DownloadException extends LibrettoException {
  const DownloadException(super.message, [super.cause]);
}

/// Position sync conflict between local and server.
class SyncConflictException extends LibrettoException {
  const SyncConflictException({
    required this.localPosition,
    required this.serverPosition,
  }) : super('Position sync conflict');

  final Duration localPosition;
  final Duration serverPosition;
}

/// Storage limit exceeded for downloads.
class StorageLimitException extends LibrettoException {
  const StorageLimitException(int bytesNeeded, int bytesAvailable)
    : super(
        'Insufficient storage: need $bytesNeeded bytes, '
        'have $bytesAvailable bytes',
      );
}
