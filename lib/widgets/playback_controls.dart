import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// Playback control buttons — full functionality in Phase 2.
///
/// Layout: skip back 15s, prev chapter, play/pause, next chapter, skip forward 30s
class PlaybackControls extends StatelessWidget {
  const PlaybackControls({
    super.key,
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Skip back 15s
        Semantics(
          label: 'Skip back ${AppConstants.skipBackwardDuration.inSeconds} seconds',
          child: IconButton(
            icon: const Icon(Icons.replay_10),
            iconSize: 32,
            onPressed: onSkipBackward,
            tooltip: 'Skip back',
          ),
        ),

        // Previous chapter
        Semantics(
          label: 'Previous chapter',
          child: IconButton(
            icon: const Icon(Icons.skip_previous),
            iconSize: 36,
            onPressed: onPreviousChapter,
            tooltip: 'Previous chapter',
          ),
        ),

        // Play/Pause
        const SizedBox(width: 8),
        Semantics(
          label: isPlaying ? 'Pause' : 'Play',
          child: Container(
            decoration: const BoxDecoration(
              color: LibrettoTheme.primary,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: LibrettoTheme.onPrimary,
              ),
              iconSize: 48,
              onPressed: onPlayPause,
              tooltip: isPlaying ? 'Pause' : 'Play',
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Next chapter
        Semantics(
          label: 'Next chapter',
          child: IconButton(
            icon: const Icon(Icons.skip_next),
            iconSize: 36,
            onPressed: onNextChapter,
            tooltip: 'Next chapter',
          ),
        ),

        // Skip forward 30s
        Semantics(
          label: 'Skip forward ${AppConstants.skipForwardDuration.inSeconds} seconds',
          child: IconButton(
            icon: const Icon(Icons.forward_30),
            iconSize: 32,
            onPressed: onSkipForward,
            tooltip: 'Skip forward',
          ),
        ),
      ],
    );
  }
}
