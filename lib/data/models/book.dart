import 'package:equatable/equatable.dart';

/// A book in the library — lightweight model for list/grid display.
class Book extends Equatable {
  const Book({
    required this.id,
    required this.serverId,
    required this.title,
    this.author,
    this.narrator,
    this.coverUrl,
    this.duration,
    this.progress,
    this.seriesName,
    this.seriesIndex,
    this.genre,
    this.year,
    this.dateAdded,
    this.lastPlayedAt,
    this.isDownloaded = false,
    this.isFinished = false,
    this.isFavorite = false,
    this.userRating,
  });

  final String id;
  final String serverId;
  final String title;
  final String? author;
  final String? narrator;
  final String? coverUrl;
  final Duration? duration;
  final double? progress; // 0.0 to 1.0
  final String? seriesName;
  final double? seriesIndex;
  final String? genre;
  final int? year;
  final DateTime? dateAdded;
  final DateTime? lastPlayedAt;
  final bool isDownloaded;
  final bool isFinished;
  final bool isFavorite;
  final double? userRating; // 0.0 to 1.0 normalized

  Book copyWith({
    String? id,
    String? serverId,
    String? title,
    String? author,
    String? narrator,
    String? coverUrl,
    Duration? duration,
    double? progress,
    String? seriesName,
    double? seriesIndex,
    String? genre,
    int? year,
    DateTime? dateAdded,
    DateTime? lastPlayedAt,
    bool? isDownloaded,
    bool? isFinished,
    bool? isFavorite,
    double? userRating,
  }) {
    return Book(
      id: id ?? this.id,
      serverId: serverId ?? this.serverId,
      title: title ?? this.title,
      author: author ?? this.author,
      narrator: narrator ?? this.narrator,
      coverUrl: coverUrl ?? this.coverUrl,
      duration: duration ?? this.duration,
      progress: progress ?? this.progress,
      seriesName: seriesName ?? this.seriesName,
      seriesIndex: seriesIndex ?? this.seriesIndex,
      genre: genre ?? this.genre,
      year: year ?? this.year,
      dateAdded: dateAdded ?? this.dateAdded,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      isFinished: isFinished ?? this.isFinished,
      isFavorite: isFavorite ?? this.isFavorite,
      userRating: userRating ?? this.userRating,
    );
  }

  @override
  List<Object?> get props => [id, serverId];
}

/// Extended book details fetched on-demand when user opens a book.
class BookDetail extends Equatable {
  const BookDetail({
    required this.book,
    this.description,
    this.publisher,
    this.isbn,
    this.asin,
    this.language,
    this.fileSize,
    this.audioFormat,
    this.bitrate,
    this.sampleRate,
    this.channels,
    this.communityRating,
    this.parentId,
    this.genres = const [],
    this.tags = const [],
  });

  final Book book;
  final String? description;
  final String? publisher;
  final String? isbn;
  final String? asin;
  final String? language;
  final int? fileSize;
  final String? audioFormat;
  final int? bitrate;
  final int? sampleRate;
  final int? channels;
  final double? communityRating;
  final String? parentId;
  final List<String> genres;
  final List<String> tags;

  @override
  List<Object?> get props => [book.id, book.serverId];
}
