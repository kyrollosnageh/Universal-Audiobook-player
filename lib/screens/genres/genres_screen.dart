import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../state/library_provider.dart';

/// Screen showing all available genres as a grid of cards.
class GenresScreen extends ConsumerWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final libraryState = ref.watch(libraryNotifierProvider);
    final theme = Theme.of(context);

    // Extract unique genres from all loaded books
    final genres =
        libraryState.books
            .where((b) => b.genre != null && b.genre!.isNotEmpty)
            .map((b) => b.genre!)
            .toSet()
            .toList()
          ..sort();

    // Currently active genre filter (if any)
    final activeGenre = libraryState.filterGenre;

    return Scaffold(
      appBar: AppBar(title: const Text('Genres')),
      body: genres.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.category_outlined,
                    size: 64,
                    color: LibrettoTheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No genres found',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: LibrettoTheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Genres will appear once your library is loaded',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: LibrettoTheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 2.2,
              ),
              itemCount: genres.length,
              itemBuilder: (context, index) {
                final genre = genres[index];
                final bookCount = libraryState.books
                    .where((b) => b.genre == genre)
                    .length;
                final isSelected = genre == activeGenre;

                return _GenreCard(
                  genre: genre,
                  bookCount: bookCount,
                  isSelected: isSelected,
                  onTap: () {
                    ref
                        .read(libraryNotifierProvider.notifier)
                        .setGenreFilter(genre);
                    context.go('/library');
                  },
                );
              },
            ),
    );
  }
}

class _GenreCard extends StatelessWidget {
  const _GenreCard({
    required this.genre,
    required this.bookCount,
    required this.onTap,
    this.isSelected = false,
  });

  final String genre;
  final int bookCount;
  final VoidCallback onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: isSelected
          ? LibrettoTheme.primary.withValues(alpha: 0.15)
          : LibrettoTheme.cardColor,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? LibrettoTheme.primary : LibrettoTheme.divider,
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                genre,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isSelected
                      ? LibrettoTheme.primary
                      : LibrettoTheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                '$bookCount ${bookCount == 1 ? 'book' : 'books'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: LibrettoTheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
