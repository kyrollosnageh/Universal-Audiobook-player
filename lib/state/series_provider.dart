import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/series.dart';

/// Series state — full implementation in Phase 5.
class SeriesState {
  const SeriesState({
    this.seriesList = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Series> seriesList;
  final bool isLoading;
  final String? error;
}

final seriesProvider = StateProvider<SeriesState>((ref) {
  return const SeriesState();
});
