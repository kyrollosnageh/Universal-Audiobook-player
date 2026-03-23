import 'package:equatable/equatable.dart';
import 'book.dart';

/// A series of audiobooks.
class Series extends Equatable {
  const Series({
    required this.id,
    required this.serverId,
    required this.name,
    this.coverUrl,
    this.totalBooks = 0,
    this.completedBooks = 0,
    this.totalDuration,
    this.remainingDuration,
  });

  final String id;
  final String serverId;
  final String name;
  final String? coverUrl;
  final int totalBooks;
  final int completedBooks;
  final Duration? totalDuration;
  final Duration? remainingDuration;

  double get completionFraction =>
      totalBooks > 0 ? completedBooks / totalBooks : 0.0;

  @override
  List<Object?> get props => [id, serverId];
}

/// A book within a series, with its position/order.
class SeriesBook extends Equatable {
  const SeriesBook({
    required this.book,
    required this.index,
    this.status = BookStatus.notStarted,
  });

  final Book book;
  final double index;
  final BookStatus status;

  @override
  List<Object?> get props => [book.id, index];
}

enum BookStatus { notStarted, inProgress, completed }
