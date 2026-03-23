import 'package:flutter/material.dart';

import '../core/extensions.dart';
import '../core/theme.dart';
import '../data/models/unified_chapter.dart';

/// Audio scrubber/seek bar with chapter boundary tick marks.
class Scrubber extends StatelessWidget {
  const Scrubber({
    super.key,
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
    final durationMs = duration.inMilliseconds.toDouble();
    final value = durationMs > 0
        ? position.inMilliseconds.toDouble().clamp(0, durationMs) / durationMs
        : 0.0;

    return Column(
      children: [
        // Scrubber
        Semantics(
          label: 'Playback position. '
              '${position.toHms()} of ${duration.toHms()}. '
              'Drag to seek.',
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 8,
              ),
              overlayShape: const RoundSliderOverlayShape(
                overlayRadius: 20,
              ),
            ),
            child: Slider(
              value: value,
              onChanged: (v) {
                final seekTo = Duration(
                  milliseconds: (v * durationMs).toInt(),
                );
                onSeek(seekTo);
              },
            ),
          ),
        ),

        // Time labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                position.toHms(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                '-${(duration - position).toHms()}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
