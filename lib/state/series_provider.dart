import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/series.dart';
import '../services/series_service.dart';
import 'auth_provider.dart';

/// Series service provider.
final seriesServiceProvider = Provider<SeriesService>((ref) {
  final service = SeriesService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Series list state.
class SeriesState {
  const SeriesState({
    this.seriesList = const [],
    this.isLoading = false,
    this.error,
  });

  final List<Series> seriesList;
  final bool isLoading;
  final String? error;

  SeriesState copyWith({
    List<Series>? seriesList,
    bool? isLoading,
    String? error,
  }) {
    return SeriesState(
      seriesList: seriesList ?? this.seriesList,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SeriesNotifier extends StateNotifier<SeriesState> {
  SeriesNotifier(this._seriesService, this._ref) : super(const SeriesState());

  final SeriesService _seriesService;
  final Ref _ref;

  Future<void> loadSeries() async {
    final provider = _ref.read(activeServerProvider);
    if (provider == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final series = await _seriesService.fetchSeries(provider);
      state = SeriesState(seriesList: series);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

final seriesNotifierProvider =
    StateNotifierProvider<SeriesNotifier, SeriesState>((ref) {
      final service = ref.watch(seriesServiceProvider);
      return SeriesNotifier(service, ref);
    });

/// Series detail: books within a series.
final seriesBooksProvider = FutureProvider.family<List<SeriesBook>, String>((
  ref,
  seriesId,
) async {
  final provider = ref.watch(activeServerProvider);
  if (provider == null) return [];
  final service = ref.watch(seriesServiceProvider);
  return service.fetchSeriesBooks(provider, seriesId);
});
