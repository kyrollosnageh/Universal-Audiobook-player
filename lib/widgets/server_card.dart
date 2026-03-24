import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../data/database/app_database.dart';

/// Reusable server card widget for the server hub.
class ServerCard extends StatelessWidget {
  const ServerCard({
    super.key,
    required this.server,
    required this.onTap,
    this.onDelete,
    this.isOnline,
    this.bookCount,
    this.isHero = false,
  });

  final ServerEntry server;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final bool? isOnline;
  final int? bookCount;
  final bool isHero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isHero) return _buildHeroCard(context, theme);
    return _buildCompactCard(context, theme);
  }

  void _showDeleteMenu(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: LibrettoTheme.surface,
        title: Text('Remove ${server.name}?'),
        content: const Text(
          'This will remove the server from your saved list. '
          'You can add it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, true);
              onDelete?.call();
            },
            style: TextButton.styleFrom(
              foregroundColor: LibrettoTheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, ThemeData theme) {
    return Semantics(
      label:
          '${server.name}, ${server.type} server. '
          '${isOnline == true
              ? 'Online'
              : isOnline == false
              ? 'Offline'
              : 'Checking'}. '
          '${bookCount != null ? '$bookCount books. ' : ''}'
          'Tap to continue.',
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onLongPress: onDelete != null
              ? () => _showDeleteMenu(context)
              : null,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  LibrettoTheme.primary.withValues(alpha: 0.3),
                  LibrettoTheme.cardColor,
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: LibrettoTheme.primary.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ServerTypeIcon(type: server.type, size: 40),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            server.name,
                            style: theme.textTheme.headlineMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            server.type.toUpperCase(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: LibrettoTheme.primary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusDot(isOnline: isOnline),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    if (bookCount != null) ...[
                      Icon(
                        Icons.library_books_outlined,
                        size: 16,
                        color: LibrettoTheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '$bookCount books',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 16),
                    ],
                    Text(
                      server.url,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: LibrettoTheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Continue',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactCard(BuildContext context, ThemeData theme) {
    return Semantics(
      label:
          '${server.name}, ${server.type} server. '
          '${isOnline == true
              ? 'Online'
              : isOnline == false
              ? 'Offline'
              : 'Checking'}. '
          'Tap to connect.',
      button: true,
      child: Dismissible(
        key: ValueKey(server.id),
        direction: onDelete != null
            ? DismissDirection.endToStart
            : DismissDirection.none,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: theme.colorScheme.error,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (_) => onDelete?.call(),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onDelete != null
                ? () => _showDeleteMenu(context)
                : null,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LibrettoTheme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LibrettoTheme.divider),
              ),
              child: Row(
                children: [
                  _ServerTypeIcon(type: server.type, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (bookCount != null) ...[
                              Icon(
                                Icons.library_books_outlined,
                                size: 12,
                                color: LibrettoTheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$bookCount books',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: LibrettoTheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '·',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: LibrettoTheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Text(
                                server.url,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: LibrettoTheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  _StatusDot(isOnline: isOnline),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServerTypeIcon extends StatelessWidget {
  const _ServerTypeIcon({required this.type, this.size = 32});

  final String type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color) = switch (type) {
      'jellyfin' => (Icons.play_circle_filled, LibrettoTheme.jellyfinColor),
      'emby' => (Icons.play_circle_outline, LibrettoTheme.embyColor),
      'audiobookshelf' => (Icons.headphones, LibrettoTheme.audiobookshelfColor),
      'plex' => (Icons.tv, LibrettoTheme.plexColor),
      _ => (Icons.dns, LibrettoTheme.primary),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: color, size: size * 0.55),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({this.isOnline});

  final bool? isOnline;

  @override
  Widget build(BuildContext context) {
    final color = switch (isOnline) {
      true => LibrettoTheme.secondary,
      false => LibrettoTheme.error,
      null => LibrettoTheme.onSurfaceVariant,
    };

    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
