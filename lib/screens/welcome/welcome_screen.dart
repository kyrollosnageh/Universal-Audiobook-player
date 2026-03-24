import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// First-launch welcome screen with branding and "Get Started" CTA.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );

    // Pulse animation for the splash logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // After 2 seconds, transition from splash to content
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showSplash = false);
        _pulseController.stop();
        _fadeController.forward();
      }
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Widget _buildSplash(ThemeData theme) {
    return Center(
      key: const ValueKey('splash'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pulsing logo
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 140,
              height: 140,
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
                size: 64,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Libretto',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 36,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return FadeTransition(
      key: const ValueKey('content'),
      opacity: _fadeAnimation,
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
                onPressed: widget.onGetStarted,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 600),
          child: _showSplash ? _buildSplash(theme) : _buildContent(theme),
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
        ExcludeSemantics(
          child: Icon(icon, color: LibrettoTheme.primary, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      ],
    );
  }
}
