import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/series.dart';
import '../../services/series_service.dart';
import '../../state/series_provider.dart';
import '../../widgets/book_cover.dart';

/// Series progress view.
///
/// Shows: series cover art, progress bar ("7 of 15 completed"),
/// book list with individual status, "Up Next" highlight,
/// and estimated time to complete.
class SeriesViewScreen extends ConsumerWidget {
  const SeriesViewScreen({super.key, required this.seriesId, this.seriesName});

  final String seriesId;
  final String? seriesName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booksAsync = ref.watch(seriesBooksProvider(seriesId));
    final seriesService = ref.watch(seriesServiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(seriesName ?? 'Series')),
      body: booksAsync.when(
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
              const Text('Failed to load series'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(seriesBooksProvider(seriesId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (books) {
          if (books.isEmpty) {
            return const Center(child: Text('No books in this series'));
          }

          final stats = seriesService.calculateStats(books);
          final upNext = seriesService.getUpNext(books);

          return CustomScrollView(
            slivers: [
              // Series header with stats
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Progress bar
                      Semantics(
                        label:
                            '${stats.completedBooks} of ${stats.totalBooks} '
                            'books completed',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: LinearProgressIndicator(
                                    value: stats.completionFraction,
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${stats.completedBooks} of ${stats.totalBooks}',
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Stats row
                      Wrap(
                        spacing: 16,
                        children: [
                          if (stats.totalDuration > Duration.zero)
                            _StatChip(
                              icon: Icons.schedule,
                              label:
                                  'Total: ${stats.totalDuration.toHumanReadable()}',
                            ),
                          if (stats.remainingDuration > Duration.zero)
                            _StatChip(
                              icon: Icons.timelapse,
                              label:
                                  'Remaining: ${stats.remainingDuration.toHumanReadable()}',
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Up Next highlight
              if (upNext != null) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Up Next', style: theme.textTheme.titleMedium),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Semantics(
                      label:
                          'Up next: ${upNext.book.title}. '
                          'Tap to start.',
                      child: Card(
                        child: ListTile(
                          leading: SizedBox(
                            width: 48,
                            height: 48,
                            child: BookCover(imageUrl: upNext.book.coverUrl),
                          ),
                          title: Text(upNext.book.title),
                          subtitle: Text(
                            upNext.book.duration?.toHumanReadable() ?? '',
                          ),
                          trailing: const Icon(
                            Icons.play_circle_fill,
                            color: LibrettoTheme.primary,
                            size: 36,
                          ),
                          onTap: () => context.push('/book/${upNext.book.id}'),
                        ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Divider(indent: 16, endIndent: 16),
                ),
              ],

              // All books in series
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Text('All Books', style: theme.textTheme.titleMedium),
                ),
              ),

              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final sb = books[index];
                  return _SeriesBookTile(
                    seriesBook: sb,
                    index: index,
                    isUpNext: upNext != null && sb.book.id == upNext.book.id,
                    onTap: () => context.push('/book/${sb.book.id}'),
                  );
                }, childCount: books.length),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: LibrettoTheme.cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: LibrettoTheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SeriesBookTile extends StatelessWidget {
  const _SeriesBookTile({
    required this.seriesBook,
    required this.index,
    required this.isUpNext,
    required this.onTap,
  });

  final SeriesBook seriesBook;
  final int index;
  final bool isUpNext;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final book = seriesBook.book;
    final theme = Theme.of(context);

    IconData statusIcon;
    Color statusColor;
    switch (seriesBook.status) {
      case BookStatus.completed:
        statusIcon = Icons.check_circle;
        statusColor = const Color(0xFF4CAF50);
        break;
      case BookStatus.inProgress:
        statusIcon = Icons.play_circle;
        statusColor = LibrettoTheme.primary;
        break;
      case BookStatus.notStarted:
        statusIcon = Icons.circle_outlined;
        statusColor = LibrettoTheme.onSurfaceVariant;
        break;
    }

    return Semantics(
      label:
          '${book.title}, '
          '${seriesBook.status.name.replaceAll(RegExp(r'(?=[A-Z])'), ' ').trim()}. '
          '${book.duration?.toHumanReadable() ?? ""}',
      child: ListTile(
        leading: SizedBox(
          width: 48,
          height: 48,
          child: BookCover(imageUrl: book.coverUrl),
        ),
        title: Text(
          book.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: isUpNext ? FontWeight.w600 : null,
          ),
        ),
        subtitle: Row(
          children: [
            Icon(statusIcon, size: 14, color: statusColor),
            const SizedBox(width: 4),
            Text(
              _statusLabel(seriesBook.status),
              style: theme.textTheme.bodySmall,
            ),
            if (book.duration != null) ...[
              const Text(' · '),
              Text(
                book.duration!.toHumanReadable(),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
        trailing: isUpNext
            ? const Icon(Icons.arrow_forward_ios, size: 16)
            : null,
        onTap: onTap,
      ),
    );
  }

  String _statusLabel(BookStatus status) {
    switch (status) {
      case BookStatus.notStarted:
        return 'Not started';
      case BookStatus.inProgress:
        return 'In progress';
      case BookStatus.completed:
        return 'Completed';
    }
  }
}
