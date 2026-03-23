import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Series view screen — full implementation in Phase 5.
///
/// Will show: series cover, progress bar, book list with status,
/// estimated time to complete, and auto-advance settings.
class SeriesViewScreen extends ConsumerWidget {
  const SeriesViewScreen({
    super.key,
    required this.seriesId,
  });

  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Series')),
      body: const Center(
        child: Text('Series view — coming in Phase 5'),
      ),
    );
  }
}
