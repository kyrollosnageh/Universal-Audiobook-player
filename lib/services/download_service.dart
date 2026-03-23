import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../core/constants.dart';
import '../core/errors.dart';
import '../data/database/app_database.dart';
import '../data/database/daos/book_dao.dart';
import '../data/models/book.dart';
import '../data/models/unified_chapter.dart';
import '../data/server_providers/server_provider.dart';

/// Manages offline downloads with queue, resume, and storage management.
///
/// Features:
/// - Download individual books or series
/// - Queue with max 2 concurrent downloads
/// - Resume via Range headers if interrupted
/// - Storage cap enforcement
/// - Smart prefetch: buffer next 2-3 chapters on WiFi
/// - Progress tracking per-book and total
class DownloadService {
  DownloadService({
    required AppDatabase database,
    Dio? dio,
  })  : _bookDao = database.bookDao,
        _dio = dio ?? Dio();

  final BookDao _bookDao;
  final Dio _dio;

  final Map<String, _DownloadTask> _activeTasks = {};
  final List<_QueuedDownload> _queue = [];
  int _maxStorageBytes = 0; // 0 = unlimited
  int _totalStorageUsed = 0;
  StreamSubscription? _connectivitySub;

  /// Stream of download progress updates.
  final _progressController =
      StreamController<DownloadProgress>.broadcast();
  Stream<DownloadProgress> get progressStream => _progressController.stream;

  /// Current active downloads.
  Map<String, double> get activeDownloads =>
      _activeTasks.map((k, v) => MapEntry(k, v.progress));

  /// Total storage used by downloads (bytes).
  int get totalStorageUsed => _totalStorageUsed;

  // ── Configuration ─────────────────────────────────────────────

  /// Set maximum storage allowed for downloads.
  void setStorageCap(int bytes) {
    _maxStorageBytes = bytes;
  }

  // ── Download Book ─────────────────────────────────────────────

  /// Download all audio files for a book.
  Future<void> downloadBook({
    required Book book,
    required List<UnifiedChapter> chapters,
    required ServerProvider provider,
  }) async {
    // Check storage
    if (_maxStorageBytes > 0 && _totalStorageUsed >= _maxStorageBytes) {
      throw StorageLimitException(_maxStorageBytes, _totalStorageUsed);
    }

    // Get unique track item IDs (dedup for single-file books)
    final trackIds = <String>{};
    for (final ch in chapters) {
      trackIds.add(ch.trackItemId);
    }

    for (final trackId in trackIds) {
      _enqueue(_QueuedDownload(
        bookId: book.id,
        trackId: trackId,
        url: provider.getStreamUrl(trackId),
        title: book.title,
        serverId: provider.serverUrl,
      ));
    }

    _processQueue();
  }

  /// Cancel a download.
  void cancelDownload(String bookId) {
    // Cancel active task
    final task = _activeTasks.remove(bookId);
    task?.cancelToken.cancel();

    // Remove from queue
    _queue.removeWhere((q) => q.bookId == bookId);

    _progressController.add(DownloadProgress(
      bookId: bookId,
      status: DownloadStatus.cancelled,
    ));
  }

  /// Delete downloaded files for a book.
  Future<void> deleteDownload(String bookId) async {
    cancelDownload(bookId);

    final dir = await _getDownloadDir();
    final bookDir = Directory('${dir.path}/$bookId');
    if (await bookDir.exists()) {
      final size = await _directorySize(bookDir);
      await bookDir.delete(recursive: true);
      _totalStorageUsed -= size;
    }
  }

  /// Check if a book is downloaded.
  Future<bool> isDownloaded(String bookId) async {
    final dir = await _getDownloadDir();
    final bookDir = Directory('${dir.path}/$bookId');
    return bookDir.existsSync();
  }

  /// Get the local file path for a downloaded track.
  Future<String?> getLocalPath(String bookId, String trackId) async {
    final dir = await _getDownloadDir();
    final file = File('${dir.path}/$bookId/$trackId');
    if (await file.exists()) return file.path;
    return null;
  }

  // ── Smart Prefetch ────────────────────────────────────────────

  /// Prefetch the next few chapters ahead on WiFi.
  Future<void> prefetchAhead({
    required String bookId,
    required List<UnifiedChapter> chapters,
    required int currentIndex,
    required ServerProvider provider,
  }) async {
    // Only prefetch on WiFi
    final connectivity = await Connectivity().checkConnectivity();
    if (!connectivity.contains(ConnectivityResult.wifi)) return;

    final endIndex = (currentIndex + AppConstants.prefetchChaptersAhead)
        .clamp(0, chapters.length);

    for (var i = currentIndex + 1; i < endIndex; i++) {
      final ch = chapters[i];
      if (!ch.isSeparateTrack) continue; // Only for MP3-per-chapter

      final localPath = await getLocalPath(bookId, ch.trackItemId);
      if (localPath != null) continue; // Already downloaded

      _enqueue(_QueuedDownload(
        bookId: bookId,
        trackId: ch.trackItemId,
        url: provider.getStreamUrl(ch.trackItemId),
        title: ch.title,
        serverId: provider.serverUrl,
        isPrefetch: true,
      ));
    }

    _processQueue();
  }

  // ── Queue Management ──────────────────────────────────────────

  void _enqueue(_QueuedDownload download) {
    // Don't enqueue duplicates
    if (_queue.any((q) =>
        q.bookId == download.bookId && q.trackId == download.trackId)) {
      return;
    }
    if (_activeTasks.containsKey(
        '${download.bookId}/${download.trackId}')) {
      return;
    }
    _queue.add(download);
  }

  Future<void> _processQueue() async {
    while (_activeTasks.length < AppConstants.maxConcurrentDownloads &&
        _queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      await _startDownload(next);
    }
  }

  Future<void> _startDownload(_QueuedDownload queued) async {
    final taskKey = '${queued.bookId}/${queued.trackId}';
    final cancelToken = CancelToken();

    final dir = await _getDownloadDir();
    final bookDir = Directory('${dir.path}/${queued.bookId}');
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }

    final filePath = '${bookDir.path}/${queued.trackId}';
    final file = File(filePath);

    // Check for partial download (resume support)
    int downloadedBytes = 0;
    if (await file.exists()) {
      downloadedBytes = await file.length();
    }

    final task = _DownloadTask(
      bookId: queued.bookId,
      trackId: queued.trackId,
      cancelToken: cancelToken,
      filePath: filePath,
      downloadedBytes: downloadedBytes,
    );

    _activeTasks[taskKey] = task;

    _progressController.add(DownloadProgress(
      bookId: queued.bookId,
      trackId: queued.trackId,
      status: DownloadStatus.downloading,
      progress: 0,
    ));

    try {
      await _dio.download(
        queued.url.toString(),
        filePath,
        cancelToken: cancelToken,
        deleteOnError: false,
        options: Options(
          headers: downloadedBytes > 0
              ? {'Range': 'bytes=$downloadedBytes-'}
              : null,
        ),
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final totalWithExisting = total + downloadedBytes;
            final currentProgress =
                (received + downloadedBytes) / totalWithExisting;
            task.progress = currentProgress;
            task.totalBytes = totalWithExisting;

            _progressController.add(DownloadProgress(
              bookId: queued.bookId,
              trackId: queued.trackId,
              status: DownloadStatus.downloading,
              progress: currentProgress,
              downloadedBytes: received + downloadedBytes,
              totalBytes: totalWithExisting,
            ));
          }
        },
      );

      // Download complete
      _activeTasks.remove(taskKey);
      final fileSize = await File(filePath).length();
      _totalStorageUsed += fileSize;

      _progressController.add(DownloadProgress(
        bookId: queued.bookId,
        trackId: queued.trackId,
        status: DownloadStatus.complete,
        progress: 1.0,
        totalBytes: fileSize,
      ));

      // Process next in queue
      _processQueue();
    } on DioException catch (e) {
      _activeTasks.remove(taskKey);

      if (e.type == DioExceptionType.cancel) {
        return; // User cancelled
      }

      _progressController.add(DownloadProgress(
        bookId: queued.bookId,
        trackId: queued.trackId,
        status: DownloadStatus.error,
        error: e.message ?? 'Download failed',
      ));

      // Re-queue for retry if network error
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        _queue.add(queued); // Will retry when connection restored
      }
    }
  }

  // ── Connectivity Monitoring ───────────────────────────────────

  /// Start monitoring connectivity for download resume.
  void startConnectivityMonitoring() {
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        // Connection restored — process pending queue
        _processQueue();
      } else {
        // Connection lost — pause downloads gracefully
        for (final task in _activeTasks.values) {
          _progressController.add(DownloadProgress(
            bookId: task.bookId,
            trackId: task.trackId,
            status: DownloadStatus.paused,
            progress: task.progress,
          ));
        }
      }
    });
  }

  // ── Storage ───────────────────────────────────────────────────

  /// Calculate total storage used by all downloads.
  Future<int> calculateStorageUsed() async {
    final dir = await _getDownloadDir();
    if (!await dir.exists()) return 0;
    _totalStorageUsed = await _directorySize(dir);
    return _totalStorageUsed;
  }

  Future<Directory> _getDownloadDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory('${appDir.path}/downloads');
  }

  Future<int> _directorySize(Directory dir) async {
    int size = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        size += await entity.length();
      }
    }
    return size;
  }

  void dispose() {
    for (final task in _activeTasks.values) {
      task.cancelToken.cancel();
    }
    _activeTasks.clear();
    _queue.clear();
    _connectivitySub?.cancel();
    _progressController.close();
  }
}

class _QueuedDownload {
  _QueuedDownload({
    required this.bookId,
    required this.trackId,
    required this.url,
    required this.title,
    required this.serverId,
    this.isPrefetch = false,
  });

  final String bookId;
  final String trackId;
  final Uri url;
  final String title;
  final String serverId;
  final bool isPrefetch;
}

class _DownloadTask {
  _DownloadTask({
    required this.bookId,
    required this.trackId,
    required this.cancelToken,
    required this.filePath,
    this.downloadedBytes = 0,
  });

  final String bookId;
  final String trackId;
  final CancelToken cancelToken;
  final String filePath;
  int downloadedBytes;
  double progress = 0;
  int totalBytes = 0;
}

/// Download progress event.
class DownloadProgress {
  const DownloadProgress({
    required this.bookId,
    this.trackId,
    required this.status,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.error,
  });

  final String bookId;
  final String? trackId;
  final DownloadStatus status;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String? error;
}

enum DownloadStatus {
  queued,
  downloading,
  paused,
  complete,
  error,
  cancelled,
}
