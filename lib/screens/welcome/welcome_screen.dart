import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// First-launch welcome screen with branding and "Get Started" CTA.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      LibrettoTheme.primary,
                      LibrettoTheme.primary.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.headphones_rounded,
                  size: 56,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 32),

              // Title
              Text(
                'Libretto',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 36,
                ),
              ),

              const SizedBox(height: 12),

              // Subtitle
              Text(
                'Your universal audiobook player.\nConnect to Jellyfin, Emby, Plex,\nor Audiobookshelf.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: LibrettoTheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),

              const Spacer(flex: 2),

              // Feature highlights
              _FeatureRow(
                icon: Icons.devices_rounded,
                text: 'One app for all your servers',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                icon: Icons.wifi_find_rounded,
                text: 'Auto-discover servers on your network',
              ),
              const SizedBox(height: 16),
              _FeatureRow(
                icon: Icons.sync_rounded,
                text: 'Sync progress across devices',
              ),

              const Spacer(),

              // Get Started button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: onGetStarted,
                  style: ElevatedButton.styleFrom(
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Get Started'),
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: LibrettoTheme.primary, size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}
