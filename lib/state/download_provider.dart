import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download_service.dart';
import 'auth_provider.dart';

/// Download service provider.
final downloadServiceProvider = Provider<DownloadService>((ref) {
  final db = ref.watch(databaseProvider);
  final service = DownloadService(database: db);
  service.startConnectivityMonitoring();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Download state.
class DownloadState {
  const DownloadState({
    this.activeDownloads = const {},
    this.completedDownloads = const {},
    this.errors = const {},
    this.totalStorageUsed = 0,
    this.storageCap = 0,
  });

  /// Active downloads: bookId -> progress (0-1).
  final Map<String, double> activeDownloads;

  /// Completed downloads: bookId -> total bytes.
  final Map<String, int> completedDownloads;

  /// Download errors: bookId -> error message.
  final Map<String, String> errors;

  /// Total storage used in bytes.
  final int totalStorageUsed;

  /// Storage cap in bytes (0 = unlimited).
  final int storageCap;

  DownloadState copyWith({
    Map<String, double>? activeDownloads,
    Map<String, int>? completedDownloads,
    Map<String, String>? errors,
    int? totalStorageUsed,
    int? storageCap,
  }) {
    return DownloadState(
      activeDownloads: activeDownloads ?? this.activeDownloads,
      completedDownloads: completedDownloads ?? this.completedDownloads,
      errors: errors ?? this.errors,
      totalStorageUsed: totalStorageUsed ?? this.totalStorageUsed,
      storageCap: storageCap ?? this.storageCap,
    );
  }
}

class DownloadNotifier extends Notifier<DownloadState> {
  late DownloadService _downloadService;
  StreamSubscription? _subscription;

  @override
  DownloadState build() {
    _downloadService = ref.read(downloadServiceProvider);
    _subscription = _downloadService.progressStream.listen(_onProgress);
    return const DownloadState();
  }

  void _onProgress(DownloadProgress progress) {
    switch (progress.status) {
      case DownloadStatus.downloading:
        final active = Map<String, double>.from(state.activeDownloads);
        active[progress.bookId] = progress.progress;
        state = state.copyWith(activeDownloads: active);
        break;

      case DownloadStatus.complete:
        final active = Map<String, double>.from(state.activeDownloads);
        active.remove(progress.bookId);
        final completed = Map<String, int>.from(state.completedDownloads);
        completed[progress.bookId] = progress.totalBytes;
        state = state.copyWith(
          activeDownloads: active,
          completedDownloads: completed,
          totalStorageUsed: _downloadService.totalStorageUsed,
        );
        break;

      case DownloadStatus.error:
        final active = Map<String, double>.from(state.activeDownloads);
        active.remove(progress.bookId);
        final errors = Map<String, String>.from(state.errors);
        errors[progress.bookId] = progress.error ?? 'Unknown error';
        state = state.copyWith(activeDownloads: active, errors: errors);
        break;

      case DownloadStatus.cancelled:
        final active = Map<String, double>.from(state.activeDownloads);
        active.remove(progress.bookId);
        state = state.copyWith(activeDownloads: active);
        break;

      case DownloadStatus.paused:
      case DownloadStatus.queued:
        break;
    }
  }

  void setStorageCap(int bytes) {
    _downloadService.setStorageCap(bytes);
    state = state.copyWith(storageCap: bytes);
  }

  Future<void> deleteDownload(String bookId) async {
    await _downloadService.deleteDownload(bookId);
    final completed = Map<String, int>.from(state.completedDownloads);
    completed.remove(bookId);
    state = state.copyWith(
      completedDownloads: completed,
      totalStorageUsed: _downloadService.totalStorageUsed,
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}

final downloadNotifierProvider =
    NotifierProvider<DownloadNotifier, DownloadState>(DownloadNotifier.new);
