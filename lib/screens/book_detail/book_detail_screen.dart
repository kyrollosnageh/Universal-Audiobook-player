import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/models/book.dart';
import '../../data/models/unified_chapter.dart';
import '../../services/chapter_service.dart';
import '../../state/auth_provider.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/chapter_list.dart';
import 'package:go_router/go_router.dart';

/// Chapter service provider.
final chapterServiceProvider = Provider<ChapterService>((ref) {
  final db = ref.watch(databaseProvider);
  return ChapterService(database: db);
});

/// Book detail provider — fetches on demand.
final bookDetailProvider = FutureProvider.family<BookDetail?, String>((
  ref,
  bookId,
) async {
  final provider = ref.watch(activeServerProvider);
  if (provider == null) return null;
  return provider.getBookDetail(bookId);
});

/// Chapters provider — fetches on demand.
final chaptersProvider = FutureProvider.family<List<UnifiedChapter>, String>((
  ref,
  bookId,
) async {
  final provider = ref.watch(activeServerProvider);
  if (provider == null) return [];
  final chapterService = ref.watch(chapterServiceProvider);
  return chapterService.getChapters(provider, bookId);
});

/// Book detail screen.
///
/// Shows cover art, metadata, chapter list, play/download buttons.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});

  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(bookDetailProvider(bookId));
    final chaptersAsync = ref.watch(chaptersProvider(bookId));
    final theme = Theme.of(context);

    return Scaffold(
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              const Text('Failed to load book details'),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  '$err',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(bookDetailProvider(bookId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Book not found'));
          }

          final book = detail.book;

          final layout = ResponsiveLayout.of(context);

          if (layout.isTablet) {
            return _buildTabletLayout(
              context,
              ref,
              theme,
              book,
              detail,
              chaptersAsync,
            );
          }

          return CustomScrollView(
            slivers: [
              // Collapsing app bar with cover art
              SliverAppBar(
                expandedHeight: 320,
                pinned: true,
                actions: [
                  // Favorite button
                  IconButton(
                    onPressed: () {
                      final provider = ref.read(activeServerProvider);
                      if (provider == null) return;
                      ref
                          .read(libraryNotifierProvider.notifier)
                          .toggleFavorite(book);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            book.isFavorite
                                ? 'Removed from favorites'
                                : 'Added to favorites',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(
                      book.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: book.isFavorite ? LibrettoTheme.secondary : null,
                    ),
                    tooltip: book.isFavorite
                        ? 'Remove from favorites'
                        : 'Add to favorites',
                  ),
                  // Overflow menu
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      final provider = ref.read(activeServerProvider);
                      if (provider == null) return;
                      if (value == 'finished') {
                        ref
                            .read(libraryNotifierProvider.notifier)
                            .toggleFinished(book);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              book.isFinished
                                  ? 'Marked as unfinished'
                                  : 'Marked as finished',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'finished',
                        child: Row(
                          children: [
                            Icon(
                              book.isFinished
                                  ? Icons.check_circle
                                  : Icons.check_circle_outline,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              book.isFinished
                                  ? 'Mark as unfinished'
                                  : 'Mark as finished',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          LibrettoTheme.primary.withValues(alpha: 0.3),
                          LibrettoTheme.background,
                        ],
                      ),
                    ),
                    child: SafeArea(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: Semantics(
                            label:
                                'Cover art for ${book.title} by ${book.author}',
                            child: BookCover(
                              imageUrl: book.coverUrl,
                              width: 200,
                              height: 200,
                              borderRadius: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Book metadata
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        book.title,
                        style: theme.textTheme.headlineMedium,
                        semanticsLabel: book.title,
                      ),
                      const SizedBox(height: 8),

                      // Author
                      if (book.author != null) ...[
                        Text(
                          'by ${book.author}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: LibrettoTheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],

                      // Narrator
                      if (book.narrator != null)
                        Text(
                          'Narrated by ${book.narrator}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: LibrettoTheme.onSurfaceVariant,
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Duration + progress
                      Row(
                        children: [
                          if (book.duration != null) ...[
                            const Icon(
                              Icons.schedule,
                              size: 16,
                              color: LibrettoTheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              book.duration!.toHumanReadable(),
                              style: theme.textTheme.bodySmall,
                            ),
                            const SizedBox(width: 16),
                          ],
                          if (book.progress != null && book.progress! > 0) ...[
                            const Icon(
                              Icons.play_circle_outline,
                              size: 16,
                              color: LibrettoTheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${(book.progress! * 100).toInt()}% complete',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ],
                      ),

                      // Progress bar
                      if (book.progress != null && book.progress! > 0) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(
                          value: book.progress!,
                          minHeight: 4,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],

                      // Finished badge
                      if (book.isFinished) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle,
                                size: 14,
                                color: Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Finished',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.green,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Series info
                      if (book.seriesName != null) ...[
                        Semantics(
                          label:
                              'Part of series: ${book.seriesName}'
                              '${book.seriesIndex != null ? ', book ${book.seriesIndex}' : ''}',
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: LibrettoTheme.cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.library_books, size: 16),
                                const SizedBox(width: 8),
                                Text(
                                  '${book.seriesName}'
                                  '${book.seriesIndex != null ? ' #${book.seriesIndex!.toInt()}' : ''}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Action buttons
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 140),
                            child: Semantics(
                              label: book.isFinished
                                  ? 'Listen again to ${book.title}'
                                  : book.progress != null && book.progress! > 0
                                  ? 'Resume ${book.title}'
                                  : 'Play ${book.title}',
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  final chapters = chaptersAsync.value ?? [];
                                  final provider = ref.read(
                                    activeServerProvider,
                                  );
                                  if (provider == null) return;

                                  final notifier = ref.read(
                                    playerNotifierProvider.notifier,
                                  );
                                  await notifier.playBook(
                                    book: book,
                                    chapters: chapters,
                                    provider: provider,
                                  );

                                  if (context.mounted) {
                                    unawaited(context.push('/player'));
                                  }
                                },
                                icon: Icon(
                                  book.isFinished
                                      ? Icons.replay
                                      : Icons.play_arrow,
                                ),
                                label: Text(
                                  book.isFinished
                                      ? 'Listen Again'
                                      : book.progress != null &&
                                            book.progress! > 0
                                      ? 'Resume'
                                      : 'Play',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // Description
                      if (detail.description != null) ...[
                        const SizedBox(height: 24),
                        Text('About', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          detail.description!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],

                      // Genres
                      if (detail.genres.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: detail.genres.map((genre) {
                            return Chip(
                              label: Text(genre),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 24),
                      Text('Chapters', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // Chapter list
              chaptersAsync.when(
                loading: () => const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
                error: (_, _) => const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Failed to load chapters'),
                  ),
                ),
                data: (chapters) => SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    return ChapterListTile(
                      chapter: chapters[index],
                      index: index,
                      isCurrentChapter: false,
                      onTap: null,
                    );
                  }, childCount: chapters.length),
                ),
              ),

              // Bottom padding
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabletLayout(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Book book,
    BookDetail detail,
    AsyncValue<List<UnifiedChapter>> chaptersAsync,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: cover art pinned
        SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 48),
                Semantics(
                  label: 'Cover art for ${book.title} by ${book.author}',
                  child: BookCover(
                    imageUrl: book.coverUrl,
                    width: 250,
                    height: 250,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(height: 24),
                // Play button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final chapters = chaptersAsync.value ?? [];
                      final provider = ref.read(activeServerProvider);
                      if (provider == null) return;
                      final notifier = ref.read(
                        playerNotifierProvider.notifier,
                      );
                      await notifier.playBook(
                        book: book,
                        chapters: chapters,
                        provider: provider,
                      );
                      if (context.mounted) {
                        unawaited(context.push('/player'));
                      }
                    },
                    icon: Icon(
                      book.isFinished ? Icons.replay : Icons.play_arrow,
                    ),
                    label: Text(
                      book.isFinished
                          ? 'Listen Again'
                          : book.progress != null && book.progress! > 0
                          ? 'Resume'
                          : 'Play',
                    ),
                  ),
                ),
                if (book.progress != null && book.progress! > 0) ...[
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: book.progress!,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(book.progress! * 100).toInt()}% complete',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        // Right: metadata + chapters
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(book.title, style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              if (book.author != null)
                Text(
                  'by ${book.author}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: LibrettoTheme.onSurfaceVariant,
                  ),
                ),
              if (book.narrator != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Narrated by ${book.narrator}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: LibrettoTheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (book.duration != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.schedule,
                      size: 16,
                      color: LibrettoTheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      book.duration!.toHumanReadable(),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
              if (book.seriesName != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: LibrettoTheme.cardColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.library_books, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${book.seriesName}'
                        '${book.seriesIndex != null ? ' #${book.seriesIndex!.toInt()}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (detail.description != null) ...[
                const SizedBox(height: 24),
                Text('About', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(detail.description!, style: theme.textTheme.bodyMedium),
              ],
              if (detail.genres.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: detail.genres
                      .map(
                        (genre) => Chip(
                          label: Text(genre),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                      .toList(),
                ),
              ],
              const SizedBox(height: 24),
              Text('Chapters', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              chaptersAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (_, _) => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Failed to load chapters'),
                ),
                data: (chapters) => Column(
                  children: [
                    for (var i = 0; i < chapters.length; i++)
                      ChapterListTile(
                        chapter: chapters[i],
                        index: i,
                        isCurrentChapter: false,
                        onTap: null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ],
    );
  }
}
