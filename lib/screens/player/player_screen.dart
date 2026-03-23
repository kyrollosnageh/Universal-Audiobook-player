import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../state/player_provider.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/playback_controls.dart';
import '../../widgets/scrubber.dart';
import '../../widgets/speed_selector.dart';

/// Full-screen player screen — playback integration in Phase 2.
class PlayerScreen extends ConsumerWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(playerNotifierProvider);
    final theme = Theme.of(context);

    if (!state.hasBook) {
      return const Scaffold(
        body: Center(child: Text('No book loaded')),
      );
    }

    final book = state.book!;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Minimize player',
        ),
        title: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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

              // Scrubber
              Scrubber(
                position: state.position,
                duration: state.duration,
                chapters: state.chapters,
                onSeek: (position) {
                  // Phase 2: seek to position
                },
              ),

              const SizedBox(height: 16),

              // Controls
              PlaybackControls(
                isPlaying: state.isPlaying,
                onPlayPause: () {
                  // Phase 2: toggle playback
                },
                onSkipForward: () {},
                onSkipBackward: () {},
                onNextChapter: () {},
                onPreviousChapter: () {},
              ),

              const SizedBox(height: 24),

              // Bottom row: speed, sleep timer, bookmarks, chapter list
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  SpeedSelector(
                    currentSpeed: state.speed,
                    onChanged: (speed) {
                      // Phase 2: set speed
                    },
                  ),
                  Semantics(
                    label: 'Sleep timer',
                    child: IconButton(
                      icon: const Icon(Icons.bedtime_outlined),
                      onPressed: () {
                        // Show sleep timer sheet
                      },
                      tooltip: 'Sleep timer',
                    ),
                  ),
                  Semantics(
                    label: 'Bookmarks',
                    child: IconButton(
                      icon: const Icon(Icons.bookmark_outline),
                      onPressed: () {
                        // Phase 2: bookmarks
                      },
                      tooltip: 'Bookmarks',
                    ),
                  ),
                  Semantics(
                    label: 'Chapter list',
                    child: IconButton(
                      icon: const Icon(Icons.list),
                      onPressed: () {
                        // Show chapter list overlay
                      },
                      tooltip: 'Chapters',
                    ),
                  ),
                ],
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
