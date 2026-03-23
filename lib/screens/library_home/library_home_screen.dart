import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/auth_result.dart';
import '../../data/models/book.dart';
import '../../state/auth_provider.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/book_cover.dart';

/// Library home screen with Continue Listening, search, filters, and grid.
class LibraryHomeScreen extends ConsumerStatefulWidget {
  const LibraryHomeScreen({super.key});

  @override
  ConsumerState<LibraryHomeScreen> createState() => _LibraryHomeScreenState();
}

class _LibraryHomeScreenState extends ConsumerState<LibraryHomeScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Load library on first build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(libraryNotifierProvider.notifier).loadLibrary();
    });

    // Prefetch next page when near the end
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 500) {
      ref.read(libraryNotifierProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryNotifierProvider);
    final playerState = ref.watch(playerNotifierProvider);
    final authState = ref.watch(authNotifierProvider);
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    final useListLayout = textScale > AppConstants.highTextScaleThreshold;

    return Scaffold(
      appBar: AppBar(
        title: Text(authState.activeServer?.name ?? 'Library'),
        actions: [
          // Sort menu
          PopupMenuButton<SortOrder>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort library',
            onSelected: (sort) {
              ref.read(libraryNotifierProvider.notifier).setSort(sort);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: SortOrder.titleAsc,
                child: Text('Title A-Z'),
              ),
              const PopupMenuItem(
                value: SortOrder.titleDesc,
                child: Text('Title Z-A'),
              ),
              const PopupMenuItem(
                value: SortOrder.authorAsc,
                child: Text('Author A-Z'),
              ),
              const PopupMenuItem(
                value: SortOrder.dateAddedDesc,
                child: Text('Recently Added'),
              ),
              const PopupMenuItem(
                value: SortOrder.datePlayedDesc,
                child: Text('Recently Played'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(libraryNotifierProvider.notifier).loadLibrary();
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Semantics(
                  label: 'Search audiobooks',
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search books, authors, narrators...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(libraryNotifierProvider.notifier)
                                    .search('');
                              },
                            )
                          : null,
                    ),
                    onChanged: (query) {
                      ref.read(libraryNotifierProvider.notifier).search(query);
                      // Trigger rebuild for clear button visibility
                      setState(() {});
                    },
                  ),
                ),
              ),
            ),

            // Continue Listening
            if (libraryState.continueListening.isNotEmpty &&
                libraryState.searchQuery == null) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Continue Listening',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: libraryState.continueListening.length,
                    itemBuilder: (context, index) {
                      final book = libraryState.continueListening[index];
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: _ContinueListeningCard(
                          book: book,
                          onTap: () => context.push('/book/${book.id}'),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: Divider(indent: 16, endIndent: 16),
              ),
            ],

            // Library header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Text(
                      libraryState.searchQuery != null ? 'Results' : 'Library',
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    if (libraryState.totalCount > 0)
                      Text(
                        '${libraryState.totalCount} books',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            ),

            // Loading state
            if (libraryState.isLoading && libraryState.books.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            // Error state
            else if (libraryState.error != null && libraryState.books.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(libraryState.error!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          ref
                              .read(libraryNotifierProvider.notifier)
                              .loadLibrary();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              )
            // Empty state — search vs general
            else if (libraryState.books.isEmpty &&
                libraryState.searchQuery != null &&
                libraryState.searchQuery!.isNotEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 48,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "No books matching '${libraryState.searchQuery}'",
                        style: theme.textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(libraryNotifierProvider.notifier)
                              .search('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear search'),
                      ),
                    ],
                  ),
                ),
              )
            else if (libraryState.books.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No audiobooks found')),
              )
            // Book grid/list
            else if (useListLayout)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= libraryState.books.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final book = libraryState.books[index];
                    return _BookListTile(
                      book: book,
                      onTap: () => context.push('/book/${book.id}'),
                    );
                  },
                  childCount:
                      libraryState.books.length +
                      (libraryState.isLoadingMore ? 1 : 0),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.6,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= libraryState.books.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final book = libraryState.books[index];
                      return _BookGridCard(
                        book: book,
                        onTap: () => context.push('/book/${book.id}'),
                      );
                    },
                    childCount:
                        libraryState.books.length +
                        (libraryState.isLoadingMore ? 1 : 0),
                  ),
                ),
              ),

            // Pagination loading indicator
            if (libraryState.isLoadingMore && libraryState.books.isNotEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
              ),

            // Bottom padding for mini-player
            if (playerState.hasBook)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: (72 * textScale).clamp(72, 96).toDouble(),
                ),
              ),
          ],
        ),
      ),

      // Mini-player at bottom
      bottomNavigationBar: playerState.hasBook
          ? _MiniPlayer(playerState: playerState)
          : null,
    );
  }
}

class _ContinueListeningCard extends StatelessWidget {
  const _ContinueListeningCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${book.title} by ${book.author ?? "Unknown Author"}, '
          '${((book.progress ?? 0) * 100).toInt()}% complete. '
          'Tap to continue listening.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    BookCover(imageUrl: book.coverUrl, width: 130, height: 130),
                    if (book.progress != null)
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(
                          value: book.progress!,
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookGridCard extends StatelessWidget {
  const _BookGridCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${book.title} by ${book.author ?? "Unknown Author"}. '
          '${book.duration?.toHumanReadable() ?? "unknown duration"}. '
          'Tap for details.',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: BookCover(imageUrl: book.coverUrl, borderRadius: 8),
            ),
            const SizedBox(height: 6),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (book.author != null)
              Text(
                book.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _BookListTile extends StatelessWidget {
  const _BookListTile({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          '${book.title} by ${book.author ?? "Unknown Author"}. '
          '${book.duration?.toHumanReadable() ?? "unknown duration"}.',
      child: ListTile(
        leading: SizedBox(
          width: 48,
          height: 48,
          child: BookCover(imageUrl: book.coverUrl),
        ),
        title: Text(book.title),
        subtitle: Text(book.author ?? 'Unknown Author'),
        trailing: book.duration != null
            ? Text(
                book.duration!.toHumanReadable(),
                style: Theme.of(context).textTheme.bodySmall,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _MiniPlayer extends ConsumerWidget {
  const _MiniPlayer({required this.playerState});

  final PlayerState playerState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final book = playerState.book!;
    return Semantics(
      label:
          'Now playing: ${book.title}. '
          '${playerState.isPlaying ? "Playing" : "Paused"}. '
          'Tap for full player.',
      child: Container(
        height: (72 * MediaQuery.textScalerOf(context).scale(1)).clamp(72, 96),
        decoration: const BoxDecoration(
          color: LibrettoTheme.cardColor,
          border: Border(top: BorderSide(color: LibrettoTheme.divider)),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            SizedBox(
              width: 48,
              height: 48,
              child: BookCover(imageUrl: book.coverUrl),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (playerState.currentChapter != null)
                    Text(
                      playerState.currentChapter!.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                playerState.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
              iconSize: 32,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () {
                ref.read(playerNotifierProvider.notifier).togglePlayPause();
              },
              tooltip: playerState.isPlaying ? 'Pause' : 'Play',
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
