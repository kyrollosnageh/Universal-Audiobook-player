import 'dart:async';
import 'dart:ui';

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
import 'package:go_router/go_router.dart';

/// Chapter service provider.
final chapterServiceProvider = Provider<ChapterService>((ref) {
  final db = ref.watch(databaseProvider);
  return ChapterService(database: db);
});

/// Book detail provider — fetches on demand.
/// Uses keepAlive to cache results for the session.
final bookDetailProvider = FutureProvider.family<BookDetail?, String>((
  ref,
  bookId,
) async {
  ref.keepAlive();
  final provider = ref.watch(activeServerProvider);
  if (provider == null) return null;
  return provider.getBookDetail(bookId);
});

/// Chapters provider — fetches on demand.
/// Uses keepAlive to cache results for the session.
final chaptersProvider = FutureProvider.family<List<UnifiedChapter>, String>((
  ref,
  bookId,
) async {
  ref.keepAlive();
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

    // Find the book in the already-loaded library for instant display
    final libraryState = ref.watch(libraryNotifierProvider);
    final cachedBook = libraryState.books.cast<Book?>().firstWhere(
      (b) => b?.id == bookId,
      orElse: () => null,
    );

    return Scaffold(
      body: detailAsync.when(
        loading: () {
          if (cachedBook != null) {
            // Show instantly with data we already have
            return _buildBody(
              context,
              ref,
              theme,
              cachedBook,
              BookDetail(book: cachedBook),
              chaptersAsync,
              isLoading: true,
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
        error: (err, _) {
          // Even on error, show cached book if available
          if (cachedBook != null) {
            return _buildBody(
              context,
              ref,
              theme,
              cachedBook,
              BookDetail(book: cachedBook),
              chaptersAsync,
              isLoading: false,
            );
          }
          return Center(
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
          );
        },
        data: (detail) {
          if (detail == null) {
            return const Center(child: Text('Book not found'));
          }

          final book = detail.book;
          return _buildBody(context, ref, theme, book, detail, chaptersAsync);
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    Book book,
    BookDetail detail,
    AsyncValue<List<UnifiedChapter>> chaptersAsync, {
    bool isLoading = false,
  }) {
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
        // Collapsing app bar with blurred cover backdrop
        SliverAppBar(
          expandedHeight: 340,
          pinned: true,
          actions: [
            // Favorite button
            IconButton(
              onPressed: () {
                final provider = ref.read(activeServerProvider);
                if (provider == null) return;
                ref.read(libraryNotifierProvider.notifier).toggleFavorite(book);
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
            background: _HeroBackdrop(
              coverUrl: book.coverUrl,
              title: book.title,
              author: book.author,
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
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  semanticsLabel: book.title,
                ),
                const SizedBox(height: 12),

                // Metadata chips: author / narrator / duration
                _MetadataChips(book: book),

                // Progress bar
                if (book.progress != null && book.progress! > 0) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(
                        Icons.play_circle_outline,
                        size: 14,
                        color: LibrettoTheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${(book.progress! * 100).toInt()}% complete',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: book.progress!,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ],

                // Finished badge
                if (book.isFinished) ...[
                  const SizedBox(height: 10),
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

                // Full-width play button — pill shape with berry gradient
                _PlayButton(
                  book: book,
                  chaptersAsync: chaptersAsync,
                  bookId: bookId,
                  ref: ref,
                  context: context,
                ),

                // Description with Read more / Read less
                if (detail.description != null) ...[
                  const SizedBox(height: 24),
                  Text('About', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _ExpandableDescription(description: detail.description!),
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              return _BerryChapterTile(
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
                    borderRadius: LibrettoTheme.heroCardRadius,
                  ),
                ),
                const SizedBox(height: 24),
                // Full-width play button with berry gradient
                _PlayButton(
                  book: book,
                  chaptersAsync: chaptersAsync,
                  bookId: bookId,
                  ref: ref,
                  context: context,
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
              Text(
                book.title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _MetadataChips(book: book),
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
                _ExpandableDescription(description: detail.description!),
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
                      _BerryChapterTile(
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

// ---------------------------------------------------------------------------
// Hero backdrop — blurred cover art behind the main cover
// ---------------------------------------------------------------------------

class _HeroBackdrop extends StatelessWidget {
  const _HeroBackdrop({
    required this.coverUrl,
    required this.title,
    this.author,
  });

  final String? coverUrl;
  final String title;
  final String? author;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Blurred backdrop image
        if (coverUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Image.network(
              coverUrl!,
              fit: BoxFit.cover,
              // Suppress errors — dark overlay hides any broken state
              errorBuilder: (context, error, stackTrace) =>
                  const SizedBox.shrink(),
            ),
          ),
        // Dark overlay
        Container(color: LibrettoTheme.background.withValues(alpha: 0.6)),
        // Foreground: centred cover art
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 48),
              child: Semantics(
                label:
                    'Cover art for $title${author != null ? ' by $author' : ''}',
                child: BookCover(
                  imageUrl: coverUrl,
                  width: 200,
                  height: 200,
                  borderRadius: LibrettoTheme.heroCardRadius,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Metadata chips row — author / narrator / duration
// ---------------------------------------------------------------------------

class _MetadataChips extends StatelessWidget {
  const _MetadataChips({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    if (book.author != null) {
      chips.add(_PillChip(icon: Icons.person_outline, label: book.author!));
    }

    if (book.narrator != null) {
      chips.add(_PillChip(icon: Icons.mic_none, label: book.narrator!));
    }

    if (book.duration != null) {
      chips.add(
        _PillChip(
          icon: Icons.schedule,
          label: book.duration!.toHumanReadable(),
        ),
      );
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }
}

class _PillChip extends StatelessWidget {
  const _PillChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: LibrettoTheme.cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: LibrettoTheme.secondary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: LibrettoTheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Full-width pill play button with berry gradient
// ---------------------------------------------------------------------------

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.book,
    required this.chaptersAsync,
    required this.bookId,
    required this.ref,
    required this.context,
  });

  final Book book;
  final AsyncValue<List<UnifiedChapter>> chaptersAsync;
  final String bookId;
  final WidgetRef ref;
  final BuildContext context;

  @override
  Widget build(BuildContext _) {
    final label = book.isFinished
        ? 'Listen Again'
        : (book.progress != null && book.progress! > 0 ? 'Resume' : 'Play');
    final icon = book.isFinished ? Icons.replay : Icons.play_arrow;
    final semanticsLabel = book.isFinished
        ? 'Listen again to ${book.title}'
        : book.progress != null && book.progress! > 0
        ? 'Resume ${book.title}'
        : 'Play ${book.title}';

    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [LibrettoTheme.primary, LibrettoTheme.primaryVariant],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: LibrettoTheme.onPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            onPressed: () async {
              final provider = ref.read(activeServerProvider);
              if (provider == null) return;

              // Ensure chapters are loaded before playing
              var chapters = chaptersAsync.value;
              if (chapters == null || chapters.isEmpty) {
                final chapterService = ref.read(chapterServiceProvider);
                chapters = await chapterService.getChapters(provider, bookId);
              }

              final notifier = ref.read(playerNotifierProvider.notifier);
              await notifier.playBook(
                book: book,
                chapters: chapters,
                provider: provider,
              );

              if (context.mounted) {
                unawaited(context.push('/player'));
              }
            },
            icon: Icon(icon),
            label: Text(label),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expandable description (max 4 lines + Read more / Read less)
// ---------------------------------------------------------------------------

class _ExpandableDescription extends StatefulWidget {
  const _ExpandableDescription({required this.description});

  final String description;

  @override
  State<_ExpandableDescription> createState() => _ExpandableDescriptionState();
}

class _ExpandableDescriptionState extends State<_ExpandableDescription> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.description,
          style: theme.textTheme.bodyMedium,
          maxLines: _expanded ? null : 4,
          overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Text(
            _expanded ? 'Read less' : 'Read more',
            style: theme.textTheme.bodySmall?.copyWith(
              color: LibrettoTheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Berry-styled chapter tile (inline, only used in this screen)
// ---------------------------------------------------------------------------

class _BerryChapterTile extends StatelessWidget {
  const _BerryChapterTile({
    required this.chapter,
    required this.index,
    required this.isCurrentChapter,
    this.onTap,
  });

  final UnifiedChapter chapter;
  final int index;
  final bool isCurrentChapter;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label:
          'Chapter ${index + 1}: ${chapter.title}, '
          'duration ${chapter.duration.toHms()}'
          '${isCurrentChapter ? ', currently playing' : ''}',
      child: InkWell(
        onTap: onTap,
        child: Container(
          color: isCurrentChapter
              ? LibrettoTheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Berry number circle / equalizer icon
              SizedBox(
                width: 32,
                height: 32,
                child: isCurrentChapter
                    ? const DecoratedBox(
                        decoration: BoxDecoration(
                          color: LibrettoTheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            Icons.equalizer,
                            color: LibrettoTheme.onPrimary,
                            size: 16,
                          ),
                        ),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: LibrettoTheme.primary.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: LibrettoTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              // Chapter title
              Expanded(
                child: Text(
                  chapter.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isCurrentChapter ? LibrettoTheme.primary : null,
                    fontWeight: isCurrentChapter ? FontWeight.w600 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Duration in lavender
              Text(
                chapter.duration.toHms(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: LibrettoTheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
