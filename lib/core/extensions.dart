/// Extension methods used throughout Libretto.
library;

/// Emby/Jellyfin use "ticks" (1 tick = 100 nanoseconds).
/// 10,000,000 ticks = 1 second.

extension DurationTickConversion on Duration {
  /// Convert a Dart [Duration] to Emby/Jellyfin ticks.
  int toTicks() => inMicroseconds * 10;
}

extension TicksToDuration on int {
  /// Convert Emby/Jellyfin ticks to a Dart [Duration].
  Duration ticksToDuration() => Duration(microseconds: this ~/ 10);
}

extension DurationFormatting on Duration {
  /// Format as "HH:MM:SS" or "MM:SS" if under an hour.
  String toHms() {
    final hours = inHours;
    final minutes = inMinutes.remainder(60);
    final seconds = inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  /// Human-readable: "2h 15m", "45m", "30s".
  String toHumanReadable() {
    if (inHours > 0) {
      final m = inMinutes.remainder(60);
      return m > 0 ? '${inHours}h ${m}m' : '${inHours}h';
    }
    if (inMinutes > 0) {
      return '${inMinutes}m';
    }
    return '${inSeconds}s';
  }
}

extension StringExtensions on String {
  /// Remove trailing occurrences of [char] from the string.
  String trimTrailing(String char) {
    var s = this;
    while (s.endsWith(char)) {
      s = s.substring(0, s.length - char.length);
    }
    return s;
  }

  /// Capitalize the first letter.
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Check if this URL points to a local network address.
  bool get isLocalNetwork {
    final uri = Uri.tryParse(this);
    if (uri == null) return false;
    final host = uri.host;
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.16.') ||
        host.startsWith('172.17.') ||
        host.startsWith('172.18.') ||
        host.startsWith('172.19.') ||
        host.startsWith('172.2') ||
        host.startsWith('172.3') ||
        host.endsWith('.local');
  }
}

extension UriExtensions on Uri {
  /// Append query parameters to an existing URI.
  Uri withQueryParams(Map<String, String> params) {
    final merged = Map<String, String>.from(queryParameters)..addAll(params);
    return replace(queryParameters: merged);
  }
}
