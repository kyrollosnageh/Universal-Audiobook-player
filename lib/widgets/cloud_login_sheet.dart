import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../data/models/server_config.dart';
import '../services/cloud_login_service.dart';
import '../state/auth_provider.dart';

/// The current step in the cloud login flow.
enum _CloudLoginStep {
  providerSelection,
  plexAuth,
  embyCredentials,
  serverList,
}

/// Bottom sheet that lets users sign in to Plex.tv or Emby Connect
/// to discover and add their servers.
class CloudLoginSheet extends ConsumerStatefulWidget {
  const CloudLoginSheet({super.key});

  @override
  ConsumerState<CloudLoginSheet> createState() => _CloudLoginSheetState();
}

class _CloudLoginSheetState extends ConsumerState<CloudLoginSheet> {
  final _cloudLoginService = CloudLoginService();

  // Navigation
  _CloudLoginStep _step = _CloudLoginStep.providerSelection;

  // Plex flow state
  int? _plexPinId;
  String? _plexCode;
  String? _plexAuthToken;
  Timer? _plexPollTimer;
  bool _plexAuthInProgress = false;

  // Emby flow state
  final _embyUsernameController = TextEditingController();
  final _embyPasswordController = TextEditingController();
  final _embyFormKey = GlobalKey<FormState>();
  bool _embyLoginInProgress = false;
  bool _obscurePassword = true;

  // Server list state
  List<CloudServer> _servers = [];
  bool _isFetchingServers = false;
  final Set<String> _addingServers = {};
  final Set<String> _addedServers = {};

  // Shared
  String? _error;
  ServerType? _selectedProviderType;

  @override
  void dispose() {
    _plexPollTimer?.cancel();
    _embyUsernameController.dispose();
    _embyPasswordController.dispose();
    _cloudLoginService.dispose();
    super.dispose();
  }

  // ── Plex Flow ────────────────────────────────────────────────

  Future<void> _startPlexAuth() async {
    setState(() {
      _step = _CloudLoginStep.plexAuth;
      _plexAuthInProgress = true;
      _selectedProviderType = ServerType.plex;
      _error = null;
    });

    try {
      final pin = await _cloudLoginService.requestPlexPin();
      _plexPinId = pin['id'] as int;
      _plexCode = pin['code'] as String;

      final authUrl = _cloudLoginService.getPlexAuthUrl(_plexCode!);
      final uri = Uri.parse(authUrl);

      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          setState(() {
            _error = 'Could not open browser. Please try again.';
            _plexAuthInProgress = false;
          });
        }
        return;
      }

      _startPlexPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to start Plex authentication. Please try again.';
          _plexAuthInProgress = false;
        });
      }
    }
  }

  void _startPlexPolling() {
    _plexPollTimer?.cancel();
    _plexPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkPlexPin(),
    );
  }

  Future<void> _checkPlexPin() async {
    if (_plexPinId == null || !mounted) return;

    try {
      final token = await _cloudLoginService.checkPlexPin(_plexPinId!);
      if (token != null && mounted) {
        _plexPollTimer?.cancel();
        _plexAuthToken = token;
        await _fetchServers();
      }
    } catch (_) {
      // Polling — silently retry on transient errors.
    }
  }

  void _cancelPlexAuth() {
    _plexPollTimer?.cancel();
    setState(() {
      _step = _CloudLoginStep.providerSelection;
      _plexAuthInProgress = false;
      _plexPinId = null;
      _plexCode = null;
      _error = null;
    });
  }

  // ── Emby Flow ────────────────────────────────────────────────

  Future<void> _startEmbyLogin() async {
    if (!_embyFormKey.currentState!.validate()) return;

    setState(() {
      _embyLoginInProgress = true;
      _error = null;
    });

    try {
      final result = await _cloudLoginService.loginEmbyConnect(
        username: _embyUsernameController.text.trim(),
        password: _embyPasswordController.text,
      );

      if (!mounted) return;

      _selectedProviderType = ServerType.emby;
      await _fetchEmbyServers(
        connectToken: result['accessToken']!,
        userId: result['userId']!,
      );
    } on DioException catch (e) {
      if (mounted) {
        final status = e.response?.statusCode;
        final message = status == 401
            ? 'Invalid username or password.'
            : status == 400
                ? 'Invalid request. Please check your email/username format.'
                : 'Could not reach Emby Connect. Check your internet connection.';
        setState(() {
          _error = message;
          _embyLoginInProgress = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().contains('Authentication failed')
              ? 'Invalid username or password. Please try again.'
              : 'Login failed. Please try again.';
          _embyLoginInProgress = false;
        });
      }
    }
  }

  Future<void> _fetchEmbyServers({
    required String connectToken,
    required String userId,
  }) async {
    setState(() => _isFetchingServers = true);

    try {
      final servers = await _cloudLoginService.fetchEmbyServers(
        connectToken: connectToken,
        userId: userId,
      );

      if (mounted) {
        setState(() {
          _servers = servers;
          _isFetchingServers = false;
          _embyLoginInProgress = false;
          _step = _CloudLoginStep.serverList;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch servers. Please try again.';
          _isFetchingServers = false;
          _embyLoginInProgress = false;
        });
      }
    }
  }

  // ── Server Fetching (Plex) ───────────────────────────────────

  Future<void> _fetchServers() async {
    if (_plexAuthToken == null) return;

    setState(() {
      _isFetchingServers = true;
      _error = null;
    });

    try {
      final servers = await _cloudLoginService.fetchPlexServers(
        _plexAuthToken!,
      );

      if (mounted) {
        setState(() {
          _servers = servers;
          _isFetchingServers = false;
          _plexAuthInProgress = false;
          _step = _CloudLoginStep.serverList;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to fetch servers. Please try again.';
          _isFetchingServers = false;
          _plexAuthInProgress = false;
        });
      }
    }
  }

  // ── Server Connection ────────────────────────────────────────

  Future<void> _addServer(CloudServer server) async {
    if (_addingServers.contains(server.url)) return;

    setState(() {
      _addingServers.add(server.url);
      _error = null;
    });

    try {
      await ref
          .read(authNotifierProvider.notifier)
          .login(
            url: server.url,
            username:
                '', // Cloud-authenticated — token is already set server-side.
            password: '',
            serverType: server.type,
            serverName: server.name,
          );

      if (mounted) {
        setState(() {
          _addingServers.remove(server.url);
          _addedServers.add(server.url);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _addingServers.remove(server.url);
          _error = 'Could not add ${server.name}. Please try again.';
        });
      }
    }
  }

  Future<void> _addAllServers() async {
    for (final server in _servers) {
      if (!_addedServers.contains(server.url)) {
        await _addServer(server);
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: LibrettoTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            _buildDragHandle(),
            _buildHeader(context),
            const Divider(height: 1, color: LibrettoTheme.divider),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(LibrettoTheme.spacingXl),
                children: [
                  if (_error != null) _buildErrorBanner(context),
                  ..._buildStepContent(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Semantics(
      label: 'Drag handle',
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: LibrettoTheme.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: LibrettoTheme.spacingXl,
        vertical: LibrettoTheme.spacingSm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Sign in to your account',
              style: theme.textTheme.headlineMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: LibrettoTheme.spacingLg),
      child: Container(
        padding: const EdgeInsets.all(LibrettoTheme.spacingMd),
        decoration: BoxDecoration(
          color: LibrettoTheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(LibrettoTheme.radiusSm),
          border: Border.all(color: LibrettoTheme.error.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: LibrettoTheme.error,
              size: 20,
            ),
            const SizedBox(width: LibrettoTheme.spacingSm),
            Expanded(
              child: Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: LibrettoTheme.error),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _error = null),
              tooltip: 'Dismiss error',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStepContent(BuildContext context) {
    return switch (_step) {
      _CloudLoginStep.providerSelection => _buildProviderSelection(context),
      _CloudLoginStep.plexAuth => _buildPlexAuth(context),
      _CloudLoginStep.embyCredentials => _buildEmbyCredentials(context),
      _CloudLoginStep.serverList => _buildServerList(context),
    };
  }

  // ── Provider Selection ───────────────────────────────────────

  List<Widget> _buildProviderSelection(BuildContext context) {
    final theme = Theme.of(context);

    return [
      Text(
        'Choose your media server provider to discover your servers automatically.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: LibrettoTheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: LibrettoTheme.spacingXl),
      Row(
        children: [
          Expanded(
            child: _ProviderCard(
              label: 'Plex',
              subtitle: 'Sign in via browser',
              color: LibrettoTheme.plexColor,
              icon: Icons.tv,
              onTap: _startPlexAuth,
            ),
          ),
          const SizedBox(width: LibrettoTheme.spacingLg),
          Expanded(
            child: _ProviderCard(
              label: 'Emby Connect',
              subtitle: 'Sign in with credentials',
              color: LibrettoTheme.embyColor,
              icon: Icons.play_circle_outline,
              onTap: () => setState(() {
                _step = _CloudLoginStep.embyCredentials;
                _selectedProviderType = ServerType.emby;
                _error = null;
              }),
            ),
          ),
        ],
      ),
    ];
  }

  // ── Plex Auth ────────────────────────────────────────────────

  List<Widget> _buildPlexAuth(BuildContext context) {
    final theme = Theme.of(context);

    return [
      const SizedBox(height: LibrettoTheme.spacingXl),
      Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: LibrettoTheme.plexColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.tv, color: LibrettoTheme.plexColor, size: 32),
        ),
      ),
      const SizedBox(height: LibrettoTheme.spacingXl),
      if (_plexAuthInProgress && !_isFetchingServers) ...[
        Center(
          child: Text(
            'Opening Plex.tv in your browser...',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingXl),
        const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingLg),
        Center(
          child: Text(
            'Waiting for authentication...',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: LibrettoTheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingMd),
        Center(
          child: Text(
            'Complete the sign-in in your browser, then return here.',
            style: theme.textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingXxl),
        Center(
          child: OutlinedButton(
            onPressed: _cancelPlexAuth,
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
            child: const Text('Cancel'),
          ),
        ),
      ],
      if (_isFetchingServers) ...[
        Center(
          child: Text(
            'Fetching your servers...',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingXl),
        const Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
      ],
    ];
  }

  // ── Emby Credentials ────────────────────────────────────────

  List<Widget> _buildEmbyCredentials(BuildContext context) {
    final theme = Theme.of(context);

    return [
      // Back button
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _embyLoginInProgress
              ? null
              : () => setState(() {
                  _step = _CloudLoginStep.providerSelection;
                  _error = null;
                }),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
      ),
      const SizedBox(height: LibrettoTheme.spacingSm),
      Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: LibrettoTheme.embyColor.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.play_circle_outline,
            color: LibrettoTheme.embyColor,
            size: 32,
          ),
        ),
      ),
      const SizedBox(height: LibrettoTheme.spacingLg),
      Center(
        child: Text(
          'Sign in to Emby Connect',
          style: theme.textTheme.titleMedium,
        ),
      ),
      const SizedBox(height: LibrettoTheme.spacingXl),
      Form(
        key: _embyFormKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _embyUsernameController,
                decoration: const InputDecoration(
                  labelText: 'Username or email',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.username],
                autocorrect: false,
                enabled: !_embyLoginInProgress,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Enter your username or email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: LibrettoTheme.spacingMd),
              TextFormField(
                controller: _embyPasswordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    tooltip: _obscurePassword
                        ? 'Show password'
                        : 'Hide password',
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                enabled: !_embyLoginInProgress,
                onFieldSubmitted: (_) => _startEmbyLogin(),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Enter your password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: LibrettoTheme.spacingXl),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _embyLoginInProgress ? null : _startEmbyLogin,
                  child: _embyLoginInProgress
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Sign In'),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── Server List ──────────────────────────────────────────────

  List<Widget> _buildServerList(BuildContext context) {
    final theme = Theme.of(context);
    final providerLabel = _selectedProviderType == ServerType.plex
        ? 'Plex'
        : 'Emby';

    if (_servers.isEmpty) {
      return [
        const SizedBox(height: LibrettoTheme.spacingXxl),
        Center(
          child: Icon(
            Icons.dns_outlined,
            size: 48,
            color: LibrettoTheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingLg),
        Center(
          child: Text('No servers found', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: LibrettoTheme.spacingSm),
        Center(
          child: Text(
            'No $providerLabel servers are linked to this account.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: LibrettoTheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: LibrettoTheme.spacingXl),
        Center(
          child: OutlinedButton(
            onPressed: () => setState(() {
              _step = _CloudLoginStep.providerSelection;
              _error = null;
            }),
            child: const Text('Go Back'),
          ),
        ),
      ];
    }

    final unadded = _servers.where((s) => !_addedServers.contains(s.url));

    return [
      // Back button
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() {
            _step = _CloudLoginStep.providerSelection;
            _servers = [];
            _addedServers.clear();
            _error = null;
          }),
          icon: const Icon(Icons.arrow_back, size: 18),
          label: const Text('Back'),
        ),
      ),
      const SizedBox(height: LibrettoTheme.spacingSm),
      Text('$providerLabel Servers', style: theme.textTheme.titleMedium),
      const SizedBox(height: LibrettoTheme.spacingXs),
      Text(
        '${_servers.length} server${_servers.length == 1 ? '' : 's'} found on your account.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: LibrettoTheme.spacingLg),
      for (final server in _servers)
        _CloudServerTile(
          server: server,
          isAdding: _addingServers.contains(server.url),
          isAdded: _addedServers.contains(server.url),
          onAdd: () => _addServer(server),
        ),
      if (unadded.length > 1) ...[
        const SizedBox(height: LibrettoTheme.spacingLg),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _addingServers.isNotEmpty
                ? null
                : () => _addAllServers(),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('Add All'),
          ),
        ),
      ],
    ];
  }
}

// ── Provider Card ──────────────────────────────────────────────

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: '$label. $subtitle',
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(LibrettoTheme.radiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: LibrettoTheme.spacingXl,
            horizontal: LibrettoTheme.spacingLg,
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(LibrettoTheme.radiusMd),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(height: LibrettoTheme.spacingMd),
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(color: color),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: LibrettoTheme.spacingXs),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Cloud Server Tile ──────────────────────────────────────────

class _CloudServerTile extends StatelessWidget {
  const _CloudServerTile({
    required this.server,
    required this.isAdding,
    required this.isAdded,
    required this.onAdd,
  });

  final CloudServer server;
  final bool isAdding;
  final bool isAdded;
  final VoidCallback onAdd;

  Color get _typeColor => switch (server.type) {
    ServerType.plex => LibrettoTheme.plexColor,
    ServerType.emby => LibrettoTheme.embyColor,
    ServerType.jellyfin => LibrettoTheme.jellyfinColor,
    ServerType.audiobookshelf => LibrettoTheme.audiobookshelfColor,
  };

  IconData get _typeIcon => switch (server.type) {
    ServerType.plex => Icons.tv,
    ServerType.emby => Icons.play_circle_outline,
    ServerType.jellyfin => Icons.play_circle_filled,
    ServerType.audiobookshelf => Icons.headphones,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: LibrettoTheme.spacingSm),
      child: Container(
        padding: const EdgeInsets.all(LibrettoTheme.spacingMd),
        decoration: BoxDecoration(
          color: LibrettoTheme.cardColor,
          borderRadius: BorderRadius.circular(LibrettoTheme.radiusMd),
        ),
        child: Row(
          children: [
            // Type icon
            Icon(_typeIcon, color: _typeColor, size: 28),
            const SizedBox(width: LibrettoTheme.spacingMd),

            // Server info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          server.name,
                          style: theme.textTheme.titleMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: LibrettoTheme.spacingSm),
                      // Online status dot
                      Semantics(
                        label: server.isOnline ? 'Online' : 'Offline',
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: server.isOnline
                                ? LibrettoTheme.successColor
                                : LibrettoTheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    server.url,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (server.version != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'v${server.version}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: LibrettoTheme.onSurfaceVariant.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: LibrettoTheme.spacingSm),

            // Add button
            if (isAdded)
              const Icon(
                Icons.check_circle,
                color: LibrettoTheme.successColor,
                size: 28,
                semanticLabel: 'Added',
              )
            else if (isAdding)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: onAdd,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(60, 36),
                  ),
                  child: const Text('Add'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
