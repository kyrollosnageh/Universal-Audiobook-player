import 'dart:async';

import '../core/constants.dart';
import '../data/models/book.dart';
import '../data/models/series.dart';
import '../data/server_providers/server_provider.dart';

/// Series tracking, auto-advance, and reading order management.
///
/// Features:
/// - Detect series from server metadata
/// - Track series completion progress
/// - Auto-advance to next book with 15-second countdown
/// - Custom reading order via drag-to-reorder (stored in Drift)
/// - Series stats: total time, remaining, estimated completion
class SeriesService {
  SeriesService();

  // Custom reading orders per series
  final Map<String, List<String>> _customOrder = {};

  // Auto-advance settings
  bool autoAdvanceEnabled = true;
  Duration autoAdvanceDelay = AppConstants.autoAdvanceCountdown;

  Timer? _autoAdvanceTimer;
  void Function(Book nextBook)? _onAutoAdvance;

  // ── Series Detection ──────────────────────────────────────────

  /// Fetch all series from the server.
  Future<List<Series>> fetchSeries(ServerProvider provider) async {
    return provider.getSeries();
  }

  /// Fetch books in a series, in order.
  Future<List<SeriesBook>> fetchSeriesBooks(
    ServerProvider provider,
    String seriesId,
  ) async {
    final books = await provider.getSeriesBooks(seriesId);

    return books.asMap().entries.map((entry) {
      final book = entry.value;
      final status = _determineBookStatus(book);

      return SeriesBook(
        book: book,
        index: book.seriesIndex ?? entry.key.toDouble(),
        status: status,
      );
    }).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
  }

  /// Group books by series name from library data.
  Map<String, List<Book>> groupBySeries(List<Book> books) {
    final groups = <String, List<Book>>{};

    for (final book in books) {
      if (book.seriesName != null && book.seriesName!.isNotEmpty) {
        groups.putIfAbsent(book.seriesName!, () => []);
        groups[book.seriesName!]!.add(book);
      }
    }

    // Sort books within each series by index
    for (final entry in groups.entries) {
      entry.value.sort((a, b) {
        final aIdx = a.seriesIndex ?? double.maxFinite;
        final bIdx = b.seriesIndex ?? double.maxFinite;
        return aIdx.compareTo(bIdx);
      });
    }

    return groups;
  }

  // ── Series Progress ───────────────────────────────────────────

  /// Calculate series progress stats.
  SeriesStats calculateStats(List<SeriesBook> books) {
    int completed = 0;
    var totalDuration = Duration.zero;
    var remainingDuration = Duration.zero;

    for (final sb in books) {
      if (sb.status == BookStatus.completed) {
        completed++;
      }
      if (sb.book.duration != null) {
        totalDuration += sb.book.duration!;
        if (sb.status != BookStatus.completed) {
          final progress = sb.book.progress ?? 0.0;
          final bookRemaining =
              sb.book.duration! * (1.0 - progress);
          remainingDuration += bookRemaining;
        }
      }
    }

    return SeriesStats(
      totalBooks: books.length,
      completedBooks: completed,
      totalDuration: totalDuration,
      remainingDuration: remainingDuration,
    );
  }

  /// Find the "Up Next" book in the series.
  SeriesBook? getUpNext(List<SeriesBook> books) {
    // First: find any in-progress book
    for (final sb in books) {
      if (sb.status == BookStatus.inProgress) return sb;
    }

    // Then: find the first not-started book after the last completed
    int lastCompletedIndex = -1;
    for (var i = 0; i < books.length; i++) {
      if (books[i].status == BookStatus.completed) {
        lastCompletedIndex = i;
      }
    }

    for (var i = lastCompletedIndex + 1; i < books.length; i++) {
      if (books[i].status == BookStatus.notStarted) {
        return books[i];
      }
    }

    return null;
  }

  // ── Auto-Advance ──────────────────────────────────────────────

  /// Start auto-advance countdown to the next book.
  ///
  /// Shows a 15-second countdown. [onAdvance] called when timer expires.
  /// Returns a stream of remaining seconds for UI countdown display.
  Stream<int> startAutoAdvance(
    Book nextBook,
    void Function(Book) onAdvance,
  ) {
    if (!autoAdvanceEnabled) return const Stream.empty();

    _onAutoAdvance = onAdvance;
    final controller = StreamController<int>.broadcast();

    var remaining = autoAdvanceDelay.inSeconds;
    controller.add(remaining);

    _autoAdvanceTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        remaining--;
        controller.add(remaining);

        if (remaining <= 0) {
          timer.cancel();
          onAdvance(nextBook);
          controller.close();
        }
      },
    );

    return controller.stream;
  }

  /// Cancel auto-advance countdown.
  void cancelAutoAdvance() {
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    _onAutoAdvance = null;
  }

  // ── Custom Reading Order ──────────────────────────────────────

  /// Set a custom reading order for a series (via drag-to-reorder).
  void setCustomOrder(String seriesId, List<String> bookIds) {
    _customOrder[seriesId] = bookIds;
  }

  /// Get the custom reading order, or null if using default.
  List<String>? getCustomOrder(String seriesId) {
    return _customOrder[seriesId];
  }

  /// Apply custom order to a list of series books.
  List<SeriesBook> applyCustomOrder(
    String seriesId,
    List<SeriesBook> books,
  ) {
    final order = _customOrder[seriesId];
    if (order == null) return books;

    final byId = {for (final sb in books) sb.book.id: sb};
    final ordered = <SeriesBook>[];

    for (final id in order) {
      final sb = byId.remove(id);
      if (sb != null) ordered.add(sb);
    }
    // Add any books not in the custom order at the end
    ordered.addAll(byId.values);

    return ordered;
  }

  // ── Helpers ───────────────────────────────────────────────────

  BookStatus _determineBookStatus(Book book) {
    if (book.progress == null || book.progress == 0.0) {
      return BookStatus.notStarted;
    }
    if (book.progress! >= 0.95) {
      return BookStatus.completed;
    }
    return BookStatus.inProgress;
  }

  void dispose() {
    cancelAutoAdvance();
  }
}

/// Computed series statistics.
class SeriesStats {
  const SeriesStats({
    required this.totalBooks,
    required this.completedBooks,
    required this.totalDuration,
    required this.remainingDuration,
  });

  final int totalBooks;
  final int completedBooks;
  final Duration totalDuration;
  final Duration remainingDuration;

  double get completionFraction =>
      totalBooks > 0 ? completedBooks / totalBooks : 0.0;

  /// Estimate completion time at current pace.
  /// [dailyListeningHours] = average hours per day.
  Duration estimatedTimeToComplete({double dailyListeningHours = 1.0}) {
    if (dailyListeningHours <= 0) return Duration.zero;
    final remainingHours = remainingDuration.inMinutes / 60.0;
    final days = remainingHours / dailyListeningHours;
    return Duration(hours: (days * 24).ceil());
  }
}
