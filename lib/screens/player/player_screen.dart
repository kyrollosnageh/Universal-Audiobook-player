import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions.dart';
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),

              // Cover art
              Semantics(
                label: 'Cover art for ${book.title}',
                child: BookCover(
                  imageUrl: book.coverUrl,
                  width: 280,
                  height: 280,
                  borderRadius: 16,
                ),
              ),

              const SizedBox(height: 32),

              // Title + chapter
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

              const SizedBox(height: 24),

              // Buffering indicator
              if (state.isBuffering)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: LinearProgressIndicator(),
                ),

              // Scrubber
              Scrubber(
                position: state.position,
                duration: state.duration,
                chapters: state.chapters,
                bufferedPosition: state.bufferedPosition,
                onSeek: (position) => notifier.seek(position),
              ),

              const SizedBox(height: 16),

              // Controls
              PlaybackControls(
                isPlaying: state.isPlaying,
                onPlayPause: () => notifier.togglePlayPause(),
                onSkipForward: () => notifier.skipForward(),
                onSkipBackward: () => notifier.skipBackward(),
                onNextChapter: () => notifier.nextChapter(),
                onPreviousChapter: () => notifier.previousChapter(),
              ),

              const SizedBox(height: 24),

              // Error message
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Bottom row: speed, sleep timer, bookmarks, chapter list
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SpeedSelector(
                    currentSpeed: state.speed,
                    onChanged: (speed) => notifier.setSpeed(speed),
                  ),
                  // Sleep timer
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
                      onPressed: () =>
                          _showSleepTimer(context, notifier, state),
                      tooltip: 'Sleep timer',
                    ),
                  ),
                  // Bookmarks (coming soon)
                  Semantics(
                    label: 'Bookmarks. Coming soon.',
                    child: IconButton(
                      icon: const Icon(Icons.bookmark_outline),
                      onPressed: null,
                      tooltip: 'Bookmarks (coming soon)',
                    ),
                  ),
                  // Chapter list
                  Semantics(
                    label: 'Chapter list',
                    child: IconButton(
                      icon: const Icon(Icons.list),
                      onPressed: () =>
                          _showChapterList(context, ref, state, notifier),
                      tooltip: 'Chapters',
                    ),
                  ),
                ],
              ),

              // Sleep timer remaining display
              if (state.sleepTimerRemaining != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Sleep in ${state.sleepTimerRemaining!.toHms()}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: LibrettoTheme.primary,
                    ),
                  ),
                ),

              const Spacer(),
            ],
          ),
        ),
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
      builder: (context) => SleepTimerSheet(
        currentTimer: state.sleepTimerRemaining,
        onSelect: (duration) {
          if (duration == null) {
            notifier.cancelSleepTimer();
          } else {
            notifier.setSleepTimer(duration);
          }
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
                    SemanticsService.sendAnnouncement(
                      AnnounceSemanticsEvent(
                        'Now playing: ${state.chapters[index].title}',
                        TextDirection.ltr,
                      ),
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
