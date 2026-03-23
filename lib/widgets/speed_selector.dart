import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../core/theme.dart';

/// Playback speed selector widget.
class SpeedSelector extends StatelessWidget {
  const SpeedSelector({
    super.key,
    required this.currentSpeed,
    required this.onChanged,
  });

  final double currentSpeed;
  final ValueChanged<double> onChanged;

  static const List<double> _presets = [
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    2.5,
    3.0,
  ];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Playback speed: ${currentSpeed}x. Tap to change.',
      child: PopupMenuButton<double>(
        initialValue: currentSpeed,
        onSelected: onChanged,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: LibrettoTheme.cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            '${currentSpeed}x',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: currentSpeed != 1.0 ? LibrettoTheme.primary : null,
            ),
          ),
        ),
        itemBuilder: (context) => _presets.map((speed) {
          return PopupMenuItem<double>(
            value: speed,
            child: Text(
              '${speed}x',
              style: TextStyle(
                fontWeight: speed == currentSpeed ? FontWeight.bold : null,
                color: speed == currentSpeed ? LibrettoTheme.primary : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
