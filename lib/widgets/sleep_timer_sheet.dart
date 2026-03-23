import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// Bottom sheet for selecting a sleep timer duration.
class SleepTimerSheet extends StatelessWidget {
  const SleepTimerSheet({
    super.key,
    required this.onSelect,
    this.currentTimer,
  });

  final ValueChanged<Duration?> onSelect;
  final Duration? currentTimer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Sleep Timer',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),

            // Preset durations
            ...AppConstants.sleepTimerPresets.map((minutes) {
              final duration = Duration(minutes: minutes);
              return Semantics(
                label: '$minutes minute sleep timer',
                child: ListTile(
                  title: Text('$minutes minutes'),
                  trailing: currentTimer == duration
                      ? const Icon(Icons.check, color: LibrettoTheme.primary)
                      : null,
                  onTap: () {
                    onSelect(duration);
                    Navigator.pop(context);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              );
            }),

            // End of chapter
            Semantics(
              label: 'Sleep at end of current chapter',
              child: ListTile(
                title: const Text('End of chapter'),
                leading: const Icon(Icons.bookmark_outline),
                onTap: () {
                  // Special sentinel value — handled by PlaybackService
                  onSelect(const Duration(milliseconds: -1));
                  Navigator.pop(context);
                },
                contentPadding: EdgeInsets.zero,
              ),
            ),

            // Cancel timer
            if (currentTimer != null) ...[
              const Divider(),
              Semantics(
                label: 'Cancel sleep timer',
                child: ListTile(
                  title: const Text('Cancel Timer'),
                  leading: const Icon(Icons.timer_off),
                  onTap: () {
                    onSelect(null);
                    Navigator.pop(context);
                  },
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
