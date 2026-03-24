import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../data/server_providers/server_detector.dart';
import '../data/models/server_config.dart';

/// A server discovered on the local network.
class DiscoveredServer {
  const DiscoveredServer({
    required this.address,
    required this.port,
    required this.type,
    required this.name,
    this.version,
  });

  final String address;
  final int port;
  final ServerType type;
  final String name;
  final String? version;

  /// URL defaults to HTTP; callers should upgrade to HTTPS when possible.
  String get url {
    // Port 8920 is Emby HTTPS
    if (port == 8920) return 'https://$address:$port';
    return 'http://$address:$port';
  }
}

/// Discovers media servers on the local network via UDP broadcast and port scanning.
class DiscoveryService {
  DiscoveryService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  bool _cancelled = false;

  /// Scan for servers on the local network.
  /// Returns a stream of discovered servers as they're found.
  Stream<DiscoveredServer> discover({ServerType? filterType}) async* {
    _cancelled = false;

    // Run discovery protocols concurrently
    yield* _mergeStreams([
      _discoverJellyfinEmby(),
      _discoverPlex(),
      _scanCommonPorts(),
    ]).where((server) {
      if (_cancelled) return false;
      if (filterType != null) return server.type == filterType;
      return true;
    });
  }

  /// Cancel ongoing discovery.
  void cancel() {
    _cancelled = true;
  }

  /// Discover Jellyfin/Emby servers via UDP broadcast on port 7359.
  Stream<DiscoveredServer> _discoverJellyfinEmby() async* {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // Send discovery message
      final message = 'who is JellyfinServer?';
      socket.send(message.codeUnits, InternetAddress('255.255.255.255'), 7359);

      // Listen for responses with timeout
      await for (final event in socket.timeout(const Duration(seconds: 5))) {
        if (_cancelled) break;
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) continue;

          final response = String.fromCharCodes(datagram.data);
          final server = _parseJellyfinResponse(response, datagram.address);
          if (server != null) yield server;
        }
      }
    } on TimeoutException {
      // Expected — discovery period ended
    } catch (_) {
      // UDP not available on this platform
    } finally {
      socket?.close();
    }
  }

  DiscoveredServer? _parseJellyfinResponse(
    String response,
    InternetAddress address,
  ) {
    try {
      // Response format: JSON with Address, Id, Name fields
      if (!response.contains('{')) return null;

      final jsonStr = response.substring(response.indexOf('{'));
      // Simple JSON parse without importing dart:convert at top level
      final fields = <String, String>{};
      for (final match in RegExp(
        r'"(\w+)"\s*:\s*"([^"]*)"',
      ).allMatches(jsonStr)) {
        fields[match.group(1)!] = match.group(2)!;
      }

      final name = fields['Name'] ?? 'Media Server';
      final serverAddress = fields['Address'];

      if (serverAddress == null) return null;

      final uri = Uri.tryParse(serverAddress);
      final port = uri?.port ?? 8096;
      final isJellyfin =
          name.toLowerCase().contains('jellyfin') ||
          response.toLowerCase().contains('jellyfin');

      return DiscoveredServer(
        address: address.address,
        port: port,
        type: isJellyfin ? ServerType.jellyfin : ServerType.emby,
        name: name,
      );
    } catch (_) {
      return null;
    }
  }

  /// Discover Plex servers via GDM (G'Day Mate) protocol on port 32414.
  Stream<DiscoveredServer> _discoverPlex() async* {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      // GDM discovery message
      final message = 'M-SEARCH * HTTP/1.1\r\n\r\n';
      socket.send(message.codeUnits, InternetAddress('255.255.255.255'), 32414);

      await for (final event in socket.timeout(const Duration(seconds: 5))) {
        if (_cancelled) break;
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram == null) continue;

          final response = String.fromCharCodes(datagram.data);
          if (response.contains('Content-Type: plex/media-player') ||
              response.contains('Name:')) {
            final nameMatch = RegExp(r'Name:\s*(.+)').firstMatch(response);
            final portMatch = RegExp(r'Port:\s*(\d+)').firstMatch(response);

            yield DiscoveredServer(
              address: datagram.address.address,
              port: int.tryParse(portMatch?.group(1) ?? '') ?? 32400,
              type: ServerType.plex,
              name: nameMatch?.group(1)?.trim() ?? 'Plex Server',
            );
          }
        }
      }
    } on TimeoutException {
      // Expected
    } catch (_) {
      // UDP not available
    } finally {
      socket?.close();
    }
  }

  /// Fallback: scan common ports on the local subnet.
  Stream<DiscoveredServer> _scanCommonPorts() async* {
    final localIp = await _getLocalIp();
    if (localIp == null || _cancelled) return;

    final subnet = localIp.substring(0, localIp.lastIndexOf('.'));
    final detector = ServerDetector(dio: _dio);

    // Common server ports
    const ports = {
      8096: ServerType.emby, // Emby/Jellyfin
      8920: ServerType.emby, // Emby HTTPS
      32400: ServerType.plex, // Plex
      13378: ServerType.audiobookshelf, // Audiobookshelf
    };

    // Scan a limited range around common DHCP addresses
    for (var i = 1; i < 255 && !_cancelled; i++) {
      final host = '$subnet.$i';
      if (host == localIp) continue;

      for (final entry in ports.entries) {
        if (_cancelled) return;

        try {
          final scheme = entry.key == 8920 ? 'https' : 'http';
          final result = await detector.detect('$scheme://$host:${entry.key}');
          yield DiscoveredServer(
            address: host,
            port: entry.key,
            type: result.type,
            name: result.serverName,
            version: result.version,
          );
        } catch (_) {
          // Server not found at this address — expected
        }
      }
    }
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Merge multiple streams into one.
  Stream<T> _mergeStreams<T>(List<Stream<T>> streams) async* {
    final controller = StreamController<T>();
    final subs = <StreamSubscription<T>>[];
    var remaining = streams.length;

    for (final stream in streams) {
      subs.add(stream.listen(
        controller.add,
        onError: (_) {},
        onDone: () {
          remaining--;
          if (remaining == 0) controller.close();
        },
      ));
    }

    controller.onCancel = () {
      for (final sub in subs) {
        sub.cancel();
      }
    };

    yield* controller.stream;
  }

  void dispose() {
    cancel();
    _dio.close();
  }
}
