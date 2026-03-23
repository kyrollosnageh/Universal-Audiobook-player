import 'package:flutter/material.dart';

import '../core/extensions.dart';
import '../core/theme.dart';
import '../data/models/unified_chapter.dart';
import '../services/chapter_service.dart';

/// Audio scrubber/seek bar with chapter boundary tick marks and buffered indicator.
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
    final bufferedValue = durationMs > 0
        ? bufferedPosition.inMilliseconds.toDouble().clamp(0, durationMs) /
              durationMs
        : 0.0;

    // Calculate chapter boundary positions
    final chapterService = ChapterService._staticInstance;
    final boundaries = chapters.length > 1
        ? _getChapterBoundaries(chapters, duration)
        : <double>[];

    return Column(
      children: [
        // Scrubber with chapter ticks
        SizedBox(
          height: 40,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth - 40; // padding

              return Stack(
                alignment: Alignment.center,
                children: [
                  // Buffered position track
                  Positioned(
                    left: 20,
                    right: 20,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: bufferedValue,
                        backgroundColor: LibrettoTheme.divider,
                        valueColor: AlwaysStoppedAnimation(
                          LibrettoTheme.primary.withOpacity(0.3),
                        ),
                        minHeight: 4,
                      ),
                    ),
                  ),

                  // Chapter boundary tick marks
                  ...boundaries.map((fraction) {
                    return Positioned(
                      left: 20 + (fraction * width),
                      top: 8,
                      bottom: 8,
                      child: Container(
                        width: 2,
                        decoration: BoxDecoration(
                          color: LibrettoTheme.onSurfaceVariant.withOpacity(
                            0.5,
                          ),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    );
                  }),

                  // Main slider
                  Semantics(
                    label:
                        'Playback position. '
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
                        activeTrackColor: LibrettoTheme.primary,
                        inactiveTrackColor: Colors.transparent,
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
                ],
              );
            },
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
              // Chapter indicator
              if (chapters.length > 1)
                Text(
                  _currentChapterLabel(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: LibrettoTheme.onSurfaceVariant,
                  ),
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

  List<double> _getChapterBoundaries(
    List<UnifiedChapter> chapters,
    Duration totalDuration,
  ) {
    if (chapters.length <= 1 || totalDuration == Duration.zero) return [];

    final totalMs = totalDuration.inMilliseconds.toDouble();
    return chapters.skip(1).map((ch) {
      return (ch.startOffset.inMilliseconds / totalMs).clamp(0.0, 1.0);
    }).toList();
  }

  String _currentChapterLabel() {
    if (chapters.isEmpty) return '';

    for (var i = chapters.length - 1; i >= 0; i--) {
      if (position >= chapters[i].startOffset) {
        return '${i + 1} of ${chapters.length}';
      }
    }
    return '1 of ${chapters.length}';
  }
}

// Static instance helper for chapter calculations
extension on ChapterService {
  static final _staticInstance = _ChapterCalcHelper();
}

class _ChapterCalcHelper {
  List<double> getChapterBoundaries(
    List<UnifiedChapter> chapters,
    Duration totalDuration,
  ) {
    if (chapters.length <= 1 || totalDuration == Duration.zero) return [];
    final totalMs = totalDuration.inMilliseconds.toDouble();
    return chapters.skip(1).map((ch) {
      return ch.startOffset.inMilliseconds / totalMs;
    }).toList();
  }
}
