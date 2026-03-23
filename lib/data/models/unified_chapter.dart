import 'package:equatable/equatable.dart';

/// Format-agnostic chapter model.
///
/// Handles all audiobook structures transparently:
/// - Single M4B/M4A with embedded chapters (isSeparateTrack = false)
/// - Multiple MP3s, one per chapter (isSeparateTrack = true)
/// - Single file with no chapters (time-based navigation)
/// - Mixed formats (playlist with sub-chapters)
class UnifiedChapter extends Equatable {
  const UnifiedChapter({
    required this.id,
    required this.title,
    required this.startOffset,
    required this.duration,
    required this.trackItemId,
    this.imageUrl,
    this.isSeparateTrack = false,
    this.trackIndex = 0,
  });

  /// Unique identifier for this chapter.
  final String id;

  /// Display title (e.g., "Chapter 1: The Beginning").
  final String title;

  /// Start offset within the audio file/track.
  final Duration startOffset;

  /// Duration of this chapter.
  final Duration duration;

  /// The server item ID to stream for this chapter.
  /// For M4B: the single file's item ID.
  /// For MP3-per-chapter: the individual track's item ID.
  final String trackItemId;

  /// Optional chapter-specific artwork.
  final String? imageUrl;

  /// Whether this chapter is a separate track/file (MP3-per-chapter)
  /// vs. embedded in a single file (M4B).
  final bool isSeparateTrack;

  /// Index in the playlist (for multi-track books).
  final int trackIndex;

  /// End offset (start + duration).
  Duration get endOffset => startOffset + duration;

  @override
  List<Object?> get props => [id, trackItemId, startOffset];
}
