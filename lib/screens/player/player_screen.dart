import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/responsive.dart';

// ignore: unused_import
import '../../core/extensions.dart';
import '../../widgets/a11y/semantic_player.dart';
import '../../core/theme.dart';
import '../../data/models/unified_chapter.dart';
import '../../state/player_provider.dart';
import '../../widgets/book_cover.dart';
import '../../widgets/chapter_list.dart';
import '../../widgets/scrubber.dart';
import '../../widgets/sleep_timer_sheet.dart';

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
      // Transparent so the blurred background shows through the entire screen
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Minimize player',
        ),
        title: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Blurred cover art background ──────────────────────────────────
          _BlurredBackground(coverUrl: book.coverUrl),

          // ── Dark overlay ─────────────────────────────────────────────────
          Container(color: Colors.black.withValues(alpha: 0.7)),

          // ── Player content ────────────────────────────────────────────────
          SafeArea(
            child: _buildPlayerBody(context, ref, theme, state, notifier),
          ),
        ],
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
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              offset: Offset(0, 8),
              blurRadius: 24,
              color: Colors.black45,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BookCover(
            imageUrl: book.coverUrl,
            width: coverSize,
            height: coverSize,
            borderRadius: 0, // Clipping is handled by parent ClipRRect
          ),
        ),
      ),
    );

    final titleSection = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          book.title,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        if (state.currentChapter != null)
          Text(
            state.currentChapter!.title,
            style: theme.textTheme.bodyLarge?.copyWith(
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

    final scrubber = _BerryGardenScrubber(
      position: state.position,
      duration: state.duration,
      chapters: state.chapters,
      bufferedPosition: state.bufferedPosition,
      onSeek: (position) => notifier.seek(position),
    );

    final controls = _BerryGardenControls(
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
        // Speed chip — pill-shaped, lime text on cardColor
        _BerrySpeedChip(
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
                  : LibrettoTheme.onSurfaceVariant,
            ),
            onPressed: () => _showSleepTimer(context, notifier, state),
            tooltip: 'Sleep timer',
          ),
        ),
        Semantics(
          label: 'Chapter list',
          child: IconButton(
            icon: const Icon(Icons.list, color: LibrettoTheme.onSurfaceVariant),
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
            Expanded(flex: 4, child: Center(child: coverArt)),
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

// ─────────────────────────────────────────────────────────────────────────────
// Berry Garden sub-widgets (player-screen-local styling, no logic changes)
// ─────────────────────────────────────────────────────────────────────────────

/// Blurred cover art that fills the screen background.
class _BlurredBackground extends StatelessWidget {
  const _BlurredBackground({required this.coverUrl});

  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    if (coverUrl == null) {
      return Container(color: LibrettoTheme.background);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Solid fallback colour shown while image loads / on error
        Container(color: LibrettoTheme.background),
        CachedNetworkImage(
          imageUrl: coverUrl!,
          fit: BoxFit.cover,
          // Intentionally low-res for the blur — saves memory
          memCacheWidth: 200,
          errorWidget: (_, url, err) =>
              Container(color: LibrettoTheme.background),
        ),
        // Gaussian blur
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: const SizedBox.expand(),
        ),
      ],
    );
  }
}

/// Berry Garden play/pause + skip controls.
class _BerryGardenControls extends StatelessWidget {
  const _BerryGardenControls({
    required this.isPlaying,
    required this.onPlayPause,
    this.onSkipForward,
    this.onSkipBackward,
    this.onNextChapter,
    this.onPreviousChapter,
  });

  final bool isPlaying;
  final VoidCallback onPlayPause;
  final VoidCallback? onSkipForward;
  final VoidCallback? onSkipBackward;
  final VoidCallback? onNextChapter;
  final VoidCallback? onPreviousChapter;

  @override
  Widget build(BuildContext context) {
    const lavender = LibrettoTheme.onSurfaceVariant;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rewind (skip back)
        Semantics(
          label: 'Skip back 15 seconds',
          child: IconButton(
            icon: const Icon(Icons.replay_10, color: lavender),
            iconSize: 32,
            onPressed: onSkipBackward,
            tooltip: 'Skip back',
          ),
        ),

        // Previous chapter
        Semantics(
          label: 'Previous chapter',
          child: IconButton(
            icon: const Icon(Icons.skip_previous, color: lavender),
            iconSize: 36,
            onPressed: onPreviousChapter,
            tooltip: 'Previous chapter',
          ),
        ),

        // Play / Pause — 64px berry gradient circle
        const SizedBox(width: 8),
        Semantics(
          label: isPlaying ? 'Pause' : 'Play',
          child: GestureDetector(
            onTap: onPlayPause,
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    LibrettoTheme.primary,
                    LibrettoTheme.primaryVariant,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: LibrettoTheme.primary,
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 36,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Next chapter
        Semantics(
          label: 'Next chapter',
          child: IconButton(
            icon: const Icon(Icons.skip_next, color: lavender),
            iconSize: 36,
            onPressed: onNextChapter,
            tooltip: 'Next chapter',
          ),
        ),

        // Skip forward
        Semantics(
          label: 'Skip forward 30 seconds',
          child: IconButton(
            icon: const Icon(Icons.forward_30, color: lavender),
            iconSize: 32,
            onPressed: onSkipForward,
            tooltip: 'Skip forward',
          ),
        ),
      ],
    );
  }
}

/// Berry Garden scrubber: thick lime active track, berry inactive, lavender labels.
class _BerryGardenScrubber extends StatelessWidget {
  const _BerryGardenScrubber({
    required this.position,
    required this.duration,
    required this.onSeek,
    this.chapters = const [],
    this.bufferedPosition = Duration.zero,
  });

  final Duration position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;
  final List<UnifiedChapter> chapters;
  final Duration bufferedPosition;

  @override
  Widget build(BuildContext context) {
    // Delegate all logic to the existing Scrubber widget, but wrap it in a
    // SliderTheme that applies the Berry Garden palette.
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 6,
        activeTrackColor: LibrettoTheme.secondary, // lime
        inactiveTrackColor: LibrettoTheme.primary.withValues(
          alpha: 0.3,
        ), // berry 30%
        thumbColor: LibrettoTheme.secondary, // lime
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
        overlayColor: LibrettoTheme.secondary.withValues(alpha: 0.2),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Scrubber(
        position: position,
        duration: duration,
        chapters: chapters,
        bufferedPosition: bufferedPosition,
        onSeek: onSeek,
      ),
    );
  }
}

/// Pill-shaped speed chip: lime text on cardColor background.
class _BerrySpeedChip extends StatelessWidget {
  const _BerrySpeedChip({
    required this.currentSpeed,
    required this.onChanged,
  });

  final double currentSpeed;
  final ValueChanged<double> onChanged;

  static const List<double> _presets = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    2.5,
    3.0,
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Playback speed: ${currentSpeed}x. Tap to change.',
      child: PopupMenuButton<double>(
        initialValue: currentSpeed,
        onSelected: onChanged,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: LibrettoTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${currentSpeed}x',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: LibrettoTheme.secondary, // lime
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        itemBuilder: (context) => _presets.map((speed) {
          final isSelected = speed == currentSpeed;
          return PopupMenuItem<double>(
            value: speed,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: isSelected
                      ? const Icon(
                          Icons.check,
                          size: 18,
                          color: LibrettoTheme.secondary,
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  '${speed}x',
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : null,
                    color: isSelected ? LibrettoTheme.secondary : null,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
