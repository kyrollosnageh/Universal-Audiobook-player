import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/server_config.dart';
import '../../data/server_providers/server_detector.dart';
import '../../state/auth_provider.dart';

/// Server connection screen.
///
/// Features:
/// - URL input with auto-detect
/// - Server type logo display
/// - Username/password fields
/// - HTTPS enforcement with HTTP warning
/// - Saved servers list with swipe-to-delete
class ServerConnectScreen extends ConsumerStatefulWidget {
  const ServerConnectScreen({super.key});

  @override
  ConsumerState<ServerConnectScreen> createState() =>
      _ServerConnectScreenState();
}

class _ServerConnectScreenState extends ConsumerState<ServerConnectScreen> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final _formKey = GlobalKey<FormState>();

  ServerDetectionResult? _detectedServer;
  bool _isDetecting = false;
  bool _httpAcknowledged = false;
  String? _urlWarning;
  String? _detectError;

  @override
  void dispose() {
    _urlController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  Future<void> _detectServer() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    // Validate HTTPS
    final authService = ref.read(authServiceProvider);
    try {
      _urlWarning = authService.validateUrl(
        url,
        httpAcknowledged: _httpAcknowledged,
      );
    } on InsecureConnectionException {
      _showHttpWarningDialog(url);
      return;
    }

    setState(() {
      _isDetecting = true;
      _detectError = null;
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
        _detectError = 'Could not detect server type. Check the URL.';
        _isDetecting = false;
      });
    }
  }

  Future<void> _showHttpWarningDialog(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Insecure Connection'),
        content: Text(
          url.isLocalNetwork
              ? 'You are connecting via HTTP. Your credentials will be sent '
                    'unencrypted. This is acceptable for local network connections '
                    'but not recommended.'
              : 'WARNING: You are connecting to a public server via HTTP. '
                    'Your username and password will be sent in plain text and '
                    'can be intercepted. Use HTTPS instead if possible.',
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

    if (confirmed == true) {
      setState(() => _httpAcknowledged = true);
      _detectServer();
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    if (_detectedServer == null) return;

    await ref
        .read(authNotifierProvider.notifier)
        .login(
          url: _urlController.text.trim(),
          username: _usernameController.text.trim(),
          password: _passwordController.text,
          serverType: _detectedServer!.type,
          serverName: _detectedServer!.serverName,
        );

    final authState = ref.read(authNotifierProvider);
    if (authState.isAuthenticated && mounted) {
      context.go('/library');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final savedServers = ref.watch(savedServersProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 48),
                // App logo/title
                Text(
                  'Libretto',
                  style: theme.textTheme.headlineLarge,
                  textAlign: TextAlign.center,
                  semanticsLabel: 'Libretto, Universal Audiobook Player',
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect to your audiobook server',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 48),

                // Server URL
                Semantics(
                  label: 'Server URL input',
                  child: TextFormField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
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
                              tooltip: 'Detect server type',
                            ),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    onFieldSubmitted: (_) => _detectServer(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a server URL';
                      }
                      final uri = Uri.tryParse(value.trim());
                      if (uri == null || !uri.hasScheme) {
                        return 'Please enter a valid URL (e.g., https://server:8096)';
                      }
                      return null;
                    },
                  ),
                ),

                // URL warning
                if (_urlWarning != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _urlWarning!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: LibrettoTheme.secondary,
                    ),
                  ),
                ],

                // Detection result
                if (_detectedServer != null) ...[
                  const SizedBox(height: 16),
                  _ServerTypeBadge(result: _detectedServer!),
                ],
                if (_detectError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _detectError!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Username
                Semantics(
                  label: 'Username input',
                  child: TextFormField(
                    controller: _usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your username';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                Semantics(
                  label: 'Password input',
                  child: TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(height: 8),

                // Error message
                if (authState.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      authState.error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),

                const SizedBox(height: 24),

                // Login button
                Semantics(
                  label: 'Connect to server',
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: authState.isLoading || _detectedServer == null
                          ? null
                          : _login,
                      child: authState.isLoading
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onPrimary,
                              ),
                            )
                          : const Text('Connect'),
                    ),
                  ),
                ),

                // Saved servers
                const SizedBox(height: 48),
                savedServers.when(
                  data: (servers) {
                    if (servers.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saved Servers',
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        ...servers.map(
                          (server) => Dismissible(
                            key: ValueKey(server.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 16),
                              color: theme.colorScheme.error,
                              child: const Icon(
                                Icons.delete,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                            onDismissed: (_) {
                              ref
                                  .read(authServiceProvider)
                                  .removeServer(server.id, server.url);
                              ref.invalidate(savedServersProvider);
                            },
                            child: Semantics(
                              label:
                                  '${server.name}, ${server.type} server. '
                                  'Swipe to delete.',
                              child: ListTile(
                                leading: Icon(
                                  _serverTypeIcon(server.type),
                                  color: LibrettoTheme.primary,
                                ),
                                title: Text(server.name),
                                subtitle: Text(server.url),
                                trailing: server.isActive
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: LibrettoTheme.primary,
                                      )
                                    : null,
                                onTap: () {
                                  _urlController.text = server.url;
                                  _detectServer();
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _serverTypeIcon(String type) {
    switch (type) {
      case 'emby':
        return Icons.play_circle_outline;
      case 'jellyfin':
        return Icons.play_circle_filled;
      case 'audiobookshelf':
        return Icons.headphones;
      case 'plex':
        return Icons.tv;
      default:
        return Icons.dns;
    }
  }
}

class _ServerTypeBadge extends StatelessWidget {
  const _ServerTypeBadge({required this.result});

  final ServerDetectionResult result;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Detected ${result.type.name} server: ${result.serverName}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: LibrettoTheme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: LibrettoTheme.primary.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: LibrettoTheme.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.serverName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${result.type.name.toUpperCase()}'
                    '${result.version != null ? ' v${result.version}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
