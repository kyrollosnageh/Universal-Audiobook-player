import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Download state — full implementation in Phase 4.
class DownloadState {
  const DownloadState({
    this.activeDownloads = const {},
    this.totalStorageUsed = 0,
  });

  final Map<String, double> activeDownloads; // bookId -> progress (0-1)
  final int totalStorageUsed; // bytes
}

final downloadProvider = StateProvider<DownloadState>((ref) {
  return const DownloadState();
});
