import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/database/app_database.dart';
import '../../widgets/cloud_login_sheet.dart';
import '../../data/models/server_config.dart';
import '../../data/server_providers/server_detector.dart';
import '../../state/auth_provider.dart';
import '../../widgets/add_server_sheet.dart';
import '../../widgets/server_card.dart';

/// Server hub screen — shows saved servers with a hero card for the last-used server.
class ServerHubScreen extends ConsumerStatefulWidget {
  const ServerHubScreen({super.key});

  @override
  ConsumerState<ServerHubScreen> createState() => _ServerHubScreenState();
}

class _ServerHubScreenState extends ConsumerState<ServerHubScreen>
    with SingleTickerProviderStateMixin {
  final Map<String, bool> _onlineStatus = {};
  bool _isCheckingStatus = true;
  late final AnimationController _shimmerController;
  late final Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _shimmerAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.easeInOut),
    );
    _shimmerController.repeat(reverse: true);
    _checkServerStatus();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Future<void> _checkServerStatus() async {
    setState(() => _isCheckingStatus = true);
    final servers = await ref.read(savedServersProvider.future);
    final detector = ServerDetector();

    for (final server in servers) {
      if (!mounted) break;
      try {
        await detector.detect(server.url);
        if (mounted) setState(() => _onlineStatus[server.id] = true);
      } catch (_) {
        if (mounted) setState(() => _onlineStatus[server.id] = false);
      }
    }

    detector.dispose();

    if (mounted) {
      setState(() => _isCheckingStatus = false);
      _shimmerController.stop();
      final offlineCount = _onlineStatus.values
          .where((online) => !online)
          .length;
      final message = offlineCount > 0
          ? '$offlineCount server${offlineCount > 1 ? 's' : ''} offline'
          : 'All servers checked';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
    }
  }

  Future<void> _connectToServer(ServerEntry server) async {
    final config = ServerConfig(
      id: server.id,
      name: server.name,
      url: server.url,
      type: ServerType.values.byName(server.type),
      userId: server.userId,
      isActive: true,
    );

    try {
      await ref.read(authServiceProvider).switchServer(config);
      ref
          .read(authNotifierProvider.notifier)
          .login(
            url: server.url,
            username: '', // Will use stored credentials
            password: '',
            serverType: config.type,
            serverName: server.name,
          );

      // Try restoring session first (faster — no re-auth)
      final provider = await ref
          .read(authServiceProvider)
          .restoreSession(config);
      if (provider != null && mounted) {
        ref.read(authNotifierProvider.notifier).state = AuthState(
          isAuthenticated: true,
          activeServer: config,
        );
        context.go('/library');
      }
    } catch (_) {
      // Session restore failed — open add server sheet to re-authenticate
      if (mounted) _showAddServerSheet();
    }
  }

  Future<void> _showAddServerSheet() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddServerSheet(),
    );

    if (result == true && mounted) {
      // Server was added and authenticated
      ref.invalidate(savedServersProvider);
      final authState = ref.read(authNotifierProvider);
      if (authState.isAuthenticated) {
        context.go('/library');
      }
    }
  }

  void _removeServer(ServerEntry server) {
    ref.read(authServiceProvider).removeServer(server.id, server.url);
    ref.invalidate(savedServersProvider);
    setState(() => _onlineStatus.remove(server.id));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final serversAsync = ref.watch(savedServersProvider);

    return Scaffold(
      body: SafeArea(
        child: serversAsync.when(
          data: (servers) => _buildContent(context, theme, servers),
          loading: () => _buildLoadingSkeleton(),
          error: (_, __) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Error loading servers'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(savedServersProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddServerSheet,
        backgroundColor: LibrettoTheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    List<ServerEntry> servers,
  ) {
    if (servers.isEmpty) {
      return _buildEmptyState(theme);
    }

    // Find the active (hero) server — most recently used
    final activeServer = servers.firstWhere(
      (s) => s.isActive,
      orElse: () => servers.first,
    );
    final otherServers = servers.where((s) => s.id != activeServer.id).toList();

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(savedServersProvider);
        _onlineStatus.clear();
        await _checkServerStatus();
      },
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your Servers', style: theme.textTheme.headlineLarge),
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: 'Settings',
                onPressed: () => context.push('/settings'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Hero card
          ServerCard(
            server: activeServer,
            isHero: true,
            isOnline: _onlineStatus[activeServer.id],
            onTap: () => _connectToServer(activeServer),
            onDelete: otherServers.isNotEmpty
                ? () => _removeServer(activeServer)
                : null,
          ),

          // Other servers
          if (otherServers.isNotEmpty) ...[
            const SizedBox(height: 32),
            Text('Other Servers', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final server in otherServers) ...[
              ServerCard(
                server: server,
                isOnline: _onlineStatus[server.id],
                onTap: () => _connectToServer(server),
                onDelete: () => _removeServer(server),
              ),
              const SizedBox(height: 8),
            ],
          ],

          SizedBox(
            height: MediaQuery.of(context).padding.bottom + 80,
          ), // FAB clearance + safe area
        ],
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fake header
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) => Container(
              width: 180,
              height: 28,
              decoration: BoxDecoration(
                color: LibrettoTheme.cardColor.withValues(
                  alpha: _shimmerAnimation.value,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Fake hero card
          AnimatedBuilder(
            animation: _shimmerController,
            builder: (context, child) => Container(
              width: double.infinity,
              height: 120,
              decoration: BoxDecoration(
                color: LibrettoTheme.cardColor.withValues(
                  alpha: _shimmerAnimation.value,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const SizedBox(height: 32),
          // Fake secondary cards
          for (int i = 0; i < 2; i++) ...[
            AnimatedBuilder(
              animation: _shimmerController,
              builder: (context, child) => Container(
                width: double.infinity,
                height: 72,
                decoration: BoxDecoration(
                  color: LibrettoTheme.cardColor.withValues(
                    alpha: _shimmerAnimation.value,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  void _showCloudLoginSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const CloudLoginSheet(),
    ).then((_) {
      // Refresh server list after cloud login sheet closes
      ref.invalidate(savedServersProvider);
    });
  }

  Widget _buildEmptyState(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(savedServersProvider);
        _onlineStatus.clear();
        await _checkServerStatus();
      },
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Stack(
              children: [
                // Settings icon in the top-right corner
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: 'Settings',
                    onPressed: () => context.push('/settings'),
                  ),
                ),
                // Centered content
                SizedBox(
                  width: double.infinity,
                  height: constraints.maxHeight,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.dns_outlined,
                          size: 80,
                          color: LibrettoTheme.onSurfaceVariant
                              .withValues(alpha: 0.5),
                          semanticLabel: 'No servers configured',
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'No servers added',
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Please add a server to load your audiobooks',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: LibrettoTheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: _showAddServerSheet,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Server'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _showCloudLoginSheet,
                          icon: const Icon(Icons.cloud),
                          label: const Text('Sign in to Plex or Emby'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
