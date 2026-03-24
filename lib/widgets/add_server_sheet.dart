import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/extensions.dart';
import '../core/theme.dart';
import '../data/models/server_config.dart';
import '../data/server_providers/server_detector.dart';
import '../services/discovery_service.dart';
import '../state/auth_provider.dart';
import 'cloud_login_sheet.dart';

/// Bottom sheet for adding a new server via auto-discovery or manual URL.
class AddServerSheet extends ConsumerStatefulWidget {
  const AddServerSheet({super.key});

  @override
  ConsumerState<AddServerSheet> createState() => _AddServerSheetState();
}

class _AddServerSheetState extends ConsumerState<AddServerSheet> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _discoveryService = DiscoveryService();
  final _discoveredServers = <DiscoveredServer>[];
  StreamSubscription<DiscoveredServer>? _discoverySub;

  ServerType? _filterType;
  bool _isScanning = false;
  bool _showManualEntry = false;
  bool _passiveScanDone = false;

  // Connection state
  ServerDetectionResult? _detectedServer;
  bool _isDetecting = false;
  bool _isConnecting = false;
  bool _httpAcknowledged = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startPassiveScan();
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _discoveryService.dispose();
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startPassiveScan() {
    setState(() => _isScanning = true);

    _discoverySub = _discoveryService
        .discover(filterType: _filterType)
        .listen(
          (server) {
            if (mounted) {
              setState(() {
                // Deduplicate by URL
                if (!_discoveredServers.any((s) => s.url == server.url)) {
                  _discoveredServers.add(server);
                }
              });
            }
          },
          onDone: () {
            if (mounted) {
              setState(() {
                _isScanning = false;
                _passiveScanDone = true;
              });
            }
          },
          onError: (_) {
            if (mounted) setState(() => _isScanning = false);
          },
        );
  }

  void _startActiveScan() {
    _discoverySub?.cancel();
    setState(() {
      _discoveredServers.clear();
      _passiveScanDone = false;
    });
    _startPassiveScan();
  }

  void _onFilterChanged(ServerType? type) {
    _discoverySub?.cancel();
    setState(() {
      _filterType = type;
      _discoveredServers.clear();
      _passiveScanDone = false;
    });
    _startPassiveScan();
  }

  void _selectDiscoveredServer(DiscoveredServer server) {
    _urlController.text = server.url;
    setState(() {
      _detectedServer = ServerDetectionResult(
        type: server.type,
        serverName: server.name,
        version: server.version,
      );
      _showManualEntry = true;
    });
  }

  Future<void> _detectServer() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    final authService = ref.read(authServiceProvider);
    try {
      authService.validateUrl(url, httpAcknowledged: _httpAcknowledged);
    } on InsecureConnectionException {
      final confirmed = await _showHttpWarning(url);
      if (confirmed != true) return;
      _httpAcknowledged = true;
    }

    setState(() {
      _isDetecting = true;
      _error = null;
      _detectedServer = null;
    });

    try {
      final result = await authService.detectServer(url);
      setState(() {
        _detectedServer = result;
        _isDetecting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not detect server. Check the URL.';
        _isDetecting = false;
      });
    }
  }

  Future<bool?> _showHttpWarning(String url) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insecure Connection'),
        content: Text(
          url.isLocalNetwork
              ? 'Connecting via HTTP on a local network. Credentials will be '
                    'sent unencrypted.'
              : 'WARNING: Connecting to a public server via HTTP. Your '
                    'credentials can be intercepted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Connect Anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _connect() async {
    if (!_formKey.currentState!.validate()) return;
    if (_detectedServer == null) return;

    setState(() {
      _isConnecting = true;
      _error = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .login(
            url: _urlController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
            serverType: _detectedServer!.type,
            serverName: _detectedServer!.serverName,
          );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isConnecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: LibrettoTheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: LibrettoTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Title
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Text('Add Server', style: theme.textTheme.headlineMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Filter chips
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: _filterType == null,
                    onTap: () => _onFilterChanged(null),
                  ),
                  for (final type in ServerType.values)
                    _FilterChip(
                      label:
                          type.name[0].toUpperCase() + type.name.substring(1),
                      selected: _filterType == type,
                      onTap: () => _onFilterChanged(type),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Content
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  // Scanning indicator
                  if (_isScanning)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Scanning your network...',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),

                  // Discovered servers
                  if (_discoveredServers.isNotEmpty) ...[
                    Text(
                      'Found on your network',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    for (final server in _discoveredServers)
                      _DiscoveredServerTile(
                        server: server,
                        onTap: () => _selectDiscoveredServer(server),
                      ),
                    const SizedBox(height: 16),
                  ],

                  // Scan button (appears after passive scan with no results)
                  if (_passiveScanDone &&
                      _discoveredServers.isEmpty &&
                      !_isScanning)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: OutlinedButton.icon(
                        onPressed: _startActiveScan,
                        icon: const Icon(Icons.wifi_find),
                        label: const Text('Scan Network'),
                      ),
                    ),

                  // Action buttons
                  if (!_showManualEntry)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _showManualEntry = true),
                          icon: const Icon(Icons.edit),
                          label: const Text('Enter URL'),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            showModalBottomSheet<void>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const CloudLoginSheet(),
                            );
                          },
                          icon: const Icon(Icons.cloud),
                          label: const Text('Cloud login'),
                        ),
                      ],
                    )
                  else ...[
                    const Divider(),
                    const SizedBox(height: 16),
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // URL field
                          TextFormField(
                            controller: _urlController,
                            decoration: InputDecoration(
                              labelText: 'Server URL',
                              hintText: 'https://your-server.com:8096',
                              suffixIcon: _isDetecting
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.search),
                                      onPressed: _detectServer,
                                      tooltip: 'Detect server',
                                    ),
                            ),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                            onFieldSubmitted: (_) => _detectServer(),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter a server URL';
                              }
                              final uri = Uri.tryParse(value.trim());
                              if (uri == null || !uri.hasScheme) {
                                return 'Enter a valid URL';
                              }
                              return null;
                            },
                          ),

                          // Detection result
                          if (_detectedServer != null) ...[
                            const SizedBox(height: 12),
                            _DetectedBadge(result: _detectedServer!),
                          ],

                          const SizedBox(height: 16),

                          // Username
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Username',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            autocorrect: false,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter your username';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),

                          // Password
                          TextFormField(
                            controller: _passwordController,
                            decoration: const InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                            onFieldSubmitted: (_) => _connect(),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Enter your password';
                              }
                              return null;
                            },
                          ),

                          // Error
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],

                          const SizedBox(height: 24),

                          // Connect button
                          SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed:
                                  _isConnecting || _detectedServer == null
                                  ? null
                                  : _connect,
                              child: _isConnecting
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Connect'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: LibrettoTheme.primary.withValues(alpha: 0.2),
        checkmarkColor: LibrettoTheme.primary,
      ),
    );
  }
}

class _DiscoveredServerTile extends StatelessWidget {
  const _DiscoveredServerTile({required this.server, required this.onTap});

  final DiscoveredServer server;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: LibrettoTheme.cardColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(_iconForType(server.type), color: LibrettoTheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(server.name, style: theme.textTheme.titleMedium),
                    Text(
                      '${server.type.name.toUpperCase()}'
                      '${server.version != null ? ' v${server.version}' : ''}'
                      ' — ${server.url}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: LibrettoTheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(ServerType type) {
    return switch (type) {
      ServerType.jellyfin => Icons.play_circle_filled,
      ServerType.emby => Icons.play_circle_outline,
      ServerType.audiobookshelf => Icons.headphones,
      ServerType.plex => Icons.tv,
    };
  }
}

class _DetectedBadge extends StatelessWidget {
  const _DetectedBadge({required this.result});

  final ServerDetectionResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: LibrettoTheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: LibrettoTheme.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: LibrettoTheme.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            '${result.serverName} — ${result.type.name.toUpperCase()}'
            '${result.version != null ? ' v${result.version}' : ''}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
