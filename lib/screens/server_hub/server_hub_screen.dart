import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/database/app_database.dart';
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

class _ServerHubScreenState extends ConsumerState<ServerHubScreen> {
  final Map<String, bool> _onlineStatus = {};

  @override
  void initState() {
    super.initState();
    _checkServerStatus();
  }

  Future<void> _checkServerStatus() async {
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
          loading: () => const Center(child: CircularProgressIndicator()),
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
          Text('Your Servers', style: theme.textTheme.headlineLarge),
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

          const SizedBox(height: 80), // FAB clearance
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.dns_outlined,
              size: 80,
              color: LibrettoTheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text('No servers yet', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Add your first server to get started',
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
          ],
        ),
      ),
    );
  }
}
