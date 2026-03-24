import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../state/auth_provider.dart';
import '../state/library_provider.dart';

/// Navigation drawer for the library home screen.
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);
    final libraryState = ref.watch(libraryNotifierProvider);
    final activeFilter = libraryState.activeFilter;
    final theme = Theme.of(context);

    return Drawer(
      backgroundColor: LibrettoTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Libretto',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: LibrettoTheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (authState.activeServer != null)
                    Text(
                      authState.activeServer!.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: LibrettoTheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: LibrettoTheme.divider),

            // Navigation items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerItem(
                    icon: Icons.library_books,
                    label: 'All Books',
                    isActive: activeFilter == LibraryFilter.all,
                    onTap: () => _selectFilter(context, ref, LibraryFilter.all),
                  ),
                  _DrawerItem(
                    icon: Icons.new_releases,
                    label: 'Recently Added',
                    isActive: activeFilter == LibraryFilter.recentlyAdded,
                    onTap: () => _selectFilter(
                      context, ref, LibraryFilter.recentlyAdded,
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.auto_stories,
                    label: 'Currently Reading',
                    isActive: activeFilter == LibraryFilter.currentlyReading,
                    count: libraryState.continueListening.length,
                    onTap: () => _selectFilter(
                      context, ref, LibraryFilter.currentlyReading,
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.favorite,
                    label: 'Favorites',
                    isActive: activeFilter == LibraryFilter.favorites,
                    count: libraryState.favoriteBooks.length,
                    onTap: () => _selectFilter(
                      context, ref, LibraryFilter.favorites,
                    ),
                  ),
                  _DrawerItem(
                    icon: Icons.check_circle,
                    label: 'Finished',
                    isActive: activeFilter == LibraryFilter.finished,
                    count: libraryState.finishedBooks.length,
                    onTap: () => _selectFilter(
                      context, ref, LibraryFilter.finished,
                    ),
                  ),
                  const Divider(
                    height: 24,
                    indent: 16,
                    endIndent: 16,
                    color: LibrettoTheme.divider,
                  ),
                  _DrawerItem(
                    icon: Icons.settings,
                    label: 'Settings',
                    isActive: false,
                    onTap: () {
                      Navigator.pop(context);
                      context.push('/settings');
                    },
                  ),
                ],
              ),
            ),

            // Footer
            const Divider(height: 1, color: LibrettoTheme.divider),
            _DrawerItem(
              icon: Icons.swap_horiz,
              label: 'Switch Server',
              isActive: false,
              onTap: () {
                Navigator.pop(context);
                context.go('/hub');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _selectFilter(
    BuildContext context,
    WidgetRef ref,
    LibraryFilter filter,
  ) {
    ref.read(libraryNotifierProvider.notifier).setFilter(filter);
    Navigator.pop(context);
  }
}

class _DrawerItem extends StatelessWidget {
  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
    this.count,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive
              ? LibrettoTheme.primary
              : LibrettoTheme.onSurfaceVariant,
          size: 22,
        ),
        title: Text(
          label,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isActive ? LibrettoTheme.primary : LibrettoTheme.onSurface,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: count != null && count! > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? LibrettoTheme.primary.withValues(alpha: 0.15)
                      : LibrettoTheme.cardColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isActive
                        ? LibrettoTheme.primary
                        : LibrettoTheme.onSurfaceVariant,
                  ),
                ),
              )
            : null,
        selected: isActive,
        selectedTileColor: LibrettoTheme.primary.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        onTap: onTap,
      ),
    );
  }
}
