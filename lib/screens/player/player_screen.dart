import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/responsive.dart';

// ignore: unused_import
import '../../core/extensions.dart';
import '../../widgets/a11y/semantic_player.dart';
import '../../core/theme.dart';
import '../../state/player_provider.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/chapter_list.dart';
import '../../widgets/playback_controls.dart';
import '../../widgets/scrubber.dart';
import '../../widgets/sleep_timer_sheet.dart';
import '../../widgets/speed_selector.dart';

/// Full-screen player screen with playback controls.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerNotifierProvider);
    final notifier = ref.read(playerNotifierProvider.notifier);
    final theme = Theme.of(context);

    if (!state.hasBook) {
      return const Scaffold(body: Center(child: Text('No book loaded')));
    }

    final book = state.book!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Minimize player',
        ),
        title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: _buildPlayerBody(context, ref, theme, state, notifier),
      ),
    );
  }

  Widget _buildPlayerBody(
    BuildContext context,
    WidgetRef ref,
    ThemeData theme,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    final layout = ResponsiveLayout.of(context);
    final useSideBySide = layout.isTablet || layout.isLandscape;
    final coverSize = layout.playerCoverSize;

    final book = state.book!;

    // Shared widgets
    final coverArt = Semantics(
      label: 'Cover art for ${book.title}',
      child: BookCover(
        imageUrl: book.coverUrl,
        width: coverSize,
        height: coverSize,
        borderRadius: 16,
      ),
    );

    final titleSection = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          book.title,
          style: theme.textTheme.headlineMedium,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        if (state.currentChapter != null)
          Text(
            state.currentChapter!.title,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: LibrettoTheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
      ],
    );

    final bufferingIndicator = state.isBuffering
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 4),
                Text(
                  'Buffering...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: LibrettoTheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final scrubber = Scrubber(
      position: state.position,
      duration: state.duration,
      chapters: state.chapters,
      bufferedPosition: state.bufferedPosition,
      onSeek: (position) => notifier.seek(position),
    );

    final controls = PlaybackControls(
      isPlaying: state.isPlaying,
      onPlayPause: () => notifier.togglePlayPause(),
      onSkipForward: () => notifier.skipForward(),
      onSkipBackward: () => notifier.skipBackward(),
      onNextChapter: () => notifier.nextChapter(),
      onPreviousChapter: () => notifier.previousChapter(),
    );

    final errorWidget = state.error != null
        ? Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  state.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () => notifier.togglePlayPause(),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final bottomRow = Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        SpeedSelector(
          currentSpeed: state.speed,
          onChanged: (speed) {
            notifier.setSpeed(speed);
            SemanticPlayer.announceSpeedChange(context, speed);
          },
        ),
        Semantics(
          label: state.sleepTimerRemaining != null
              ? 'Sleep timer: ${state.sleepTimerRemaining!.toHms()} remaining'
              : 'Sleep timer',
          child: IconButton(
            icon: Icon(
              state.sleepTimerRemaining != null
                  ? Icons.bedtime
                  : Icons.bedtime_outlined,
              color: state.sleepTimerRemaining != null
                  ? LibrettoTheme.primary
                  : null,
            ),
            onPressed: () => _showSleepTimer(context, notifier, state),
            tooltip: 'Sleep timer',
          ),
        ),
        Semantics(
          label: 'Chapter list',
          child: IconButton(
            icon: const Icon(Icons.list),
            onPressed: () => _showChapterList(context, ref, state, notifier),
            tooltip: 'Chapters',
          ),
        ),
      ],
    );

    final sleepTimerDisplay = state.sleepTimerRemaining != null
        ? Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sleep in ${state.sleepTimerRemaining!.toHms()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: LibrettoTheme.primary,
              ),
            ),
          )
        : const SizedBox.shrink();

    if (useSideBySide) {
      // Tablet / landscape: cover art on left, controls on right
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            // Left: cover art centered vertically
            Expanded(
              flex: 4,
              child: Center(child: coverArt),
            ),
            const SizedBox(width: 32),
            // Right: title, scrubber, controls
            Expanded(
              flex: 5,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  titleSection,
                  const SizedBox(height: 24),
                  bufferingIndicator,
                  scrubber,
                  const SizedBox(height: 16),
                  controls,
                  const SizedBox(height: 24),
                  errorWidget,
                  bottomRow,
                  sleepTimerDisplay,
                  const Spacer(),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Phone portrait: existing vertical layout
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          const Spacer(),
          coverArt,
          const SizedBox(height: 32),
          titleSection,
          const SizedBox(height: 24),
          bufferingIndicator,
          scrubber,
          const SizedBox(height: 16),
          controls,
          const SizedBox(height: 24),
          errorWidget,
          bottomRow,
          sleepTimerDisplay,
          const Spacer(),
        ],
      ),
    );
  }

  void _showSleepTimer(
    BuildContext context,
    PlayerNotifier notifier,
    PlayerState state,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SleepTimerSheet(
        currentTimer: state.sleepTimerRemaining,
        onSelect: (duration) {
          if (duration == null) {
            notifier.cancelSleepTimer();
          } else {
            notifier.setSleepTimer(duration);
          }
          SemanticPlayer.announceSleepTimer(context, duration);
        },
      ),
    );
  }

  void _showChapterList(
    BuildContext context,
    WidgetRef ref,
    PlayerState state,
    PlayerNotifier notifier,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Chapters',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: state.chapters.length,
                itemBuilder: (context, index) => ChapterListTile(
                  chapter: state.chapters[index],
                  index: index,
                  isCurrentChapter:
                      state.chapters[index] == state.currentChapter,
                  onTap: () {
                    notifier.seekToChapter(index);
                    Navigator.pop(context);
                    SemanticPlayer.announceChapterChange(
                      context,
                      state.chapters[index],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
