import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/auth_result.dart';
import '../../data/models/book.dart';
import '../../state/auth_provider.dart';
import '../../state/library_provider.dart';
import '../../state/player_provider.dart';
import '../../widgets/app_drawer.dart';
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
    final layout = ResponsiveLayout.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Open navigation menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text(
          libraryState.filterGenre ??
              _filterTitle(
                libraryState.activeFilter,
                authState.activeServer?.name,
              ),
        ),
        actions: [
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
        bottom: libraryState.isSyncing
            ? PreferredSize(
                preferredSize: const Size.fromHeight(32),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: libraryState.syncProgress,
                          backgroundColor: LibrettoTheme.primary.withValues(
                            alpha: 0.2,
                          ),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            LibrettoTheme.secondary,
                          ),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Syncing ${libraryState.syncedCount} / ${libraryState.totalCount} books...',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: LibrettoTheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
      drawer: const AppDrawer(),
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

            // Library header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  children: [
                    Text(
                      libraryState.searchQuery != null
                          ? 'Results'
                          : _filterTitle(libraryState.activeFilter, null),
                      style: theme.textTheme.titleLarge,
                    ),
                    const Spacer(),
                    Text(
                      '${libraryState.displayedBooks.length} books',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),

            // Loading state
            if (libraryState.isLoading && libraryState.displayedBooks.isEmpty)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            // Error state
            else if (libraryState.error != null &&
                libraryState.displayedBooks.isEmpty)
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
            else if (libraryState.displayedBooks.isEmpty &&
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
                          ref.read(libraryNotifierProvider.notifier).search('');
                          setState(() {});
                        },
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear search'),
                      ),
                    ],
                  ),
                ),
              )
            else if (libraryState.displayedBooks.isEmpty)
              const SliverFillRemaining(
                child: Center(child: Text('No audiobooks found')),
              )
            // Book grid/list
            else if (useListLayout)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= libraryState.displayedBooks.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    final book = libraryState.displayedBooks[index];
                    return _BookListTile(
                      book: book,
                      onTap: () => context.push('/book/${book.id}'),
                    );
                  },
                  childCount:
                      libraryState.displayedBooks.length +
                      (libraryState.isLoadingMore ? 1 : 0),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: layout.gridMaxExtent,
                    mainAxisSpacing: layout.isTablet ? 16 : 12,
                    crossAxisSpacing: layout.isTablet ? 16 : 12,
                    childAspectRatio: 0.6,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      if (index >= libraryState.displayedBooks.length) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final book = libraryState.displayedBooks[index];
                      return _BookGridCard(
                        book: book,
                        onTap: () => context.push('/book/${book.id}'),
                      );
                    },
                    childCount:
                        libraryState.displayedBooks.length +
                        (libraryState.isLoadingMore ? 1 : 0),
                  ),
                ),
              ),

            // Pagination loading indicator
            if (libraryState.isLoadingMore &&
                libraryState.displayedBooks.isNotEmpty)
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
    final hasProgress = (book.progress ?? 0) > 0;

    return Semantics(
      label:
          '${book.title} by ${book.author ?? "Unknown Author"}. '
          '${book.duration?.toHumanReadable() ?? "unknown duration"}. '
          'Tap for details.',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(LibrettoTheme.radiusSm),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(LibrettoTheme.radiusSm),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Cover art fills the entire card
                BookCover(
                  imageUrl: book.coverUrl,
                  borderRadius: 0,
                  fit: BoxFit.cover,
                ),

                // Gradient overlay at the bottom for title/author legibility
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xE6000000), // ~90% black at bottom
                          Colors.transparent,
                        ],
                        stops: [0.0, 1.0],
                      ),
                    ),
                    padding: EdgeInsets.fromLTRB(
                      8,
                      24,
                      8,
                      hasProgress ? 11 : 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                        if (book.author != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            book.author!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xCCFFFFFF), // 80% white
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Lime progress bar at the very bottom edge
                if (hasProgress)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SizedBox(
                      height: 3,
                      child: LinearProgressIndicator(
                        value: book.progress!,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          LibrettoTheme.secondary,
                        ),
                        minHeight: 3,
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

String _filterTitle(LibraryFilter filter, String? serverName) {
  return switch (filter) {
    LibraryFilter.all => serverName ?? 'Library',
    LibraryFilter.recentlyAdded => 'Recently Added',
    LibraryFilter.currentlyReading => 'Currently Reading',
    LibraryFilter.favorites => 'Favorites',
    LibraryFilter.finished => 'Finished',
  };
}
