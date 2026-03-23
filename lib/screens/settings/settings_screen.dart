import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../services/update_service.dart';

/// App settings screen with check-for-update functionality.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _updateService = UpdateService();
  bool _checking = false;
  bool _downloading = false;
  double _downloadProgress = 0;
  String? _error;

  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final result = await _updateService.checkForUpdate();

      if (!mounted) return;

      if (result.hasUpdate && result.latestRelease != null) {
        _showUpdateDialog(result);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You\'re on the latest version (${AppConstants.appVersion})',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Failed to check for updates. Try again later.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showUpdateDialog(UpdateCheckResult result) {
    final release = result.latestRelease!;
    final hasApk = release.apkDownloadUrl != null && Platform.isAndroid;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update Available — v${release.version}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Current: v${result.currentVersion}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: LibrettoTheme.spacingLg),
              Text(
                'What\'s new:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: LibrettoTheme.spacingSm),
              Text(
                release.changelog,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          if (hasApk)
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _downloadAndInstall(release.apkDownloadUrl!);
              },
              icon: const Icon(Icons.download),
              label: const Text('Update'),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                // Copy release URL to clipboard for iOS/desktop users
                Clipboard.setData(
                  ClipboardData(
                    text:
                        'https://github.com/kyrollosnageh/Universal-Audiobook-player/releases/tag/${release.tagName}',
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Release link copied to clipboard'),
                  ),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy Link'),
            ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall(String url) async {
    setState(() {
      _downloading = true;
      _downloadProgress = 0;
    });

    try {
      final filePath = await _updateService.downloadApk(
        url,
        onProgress: (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );

      if (!mounted) return;

      // Launch Android install intent via platform channel
      await _installApk(filePath);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Download failed')));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _installApk(String filePath) async {
    try {
      // Use platform channel to trigger APK install on Android
      const channel = MethodChannel('com.libretto/updates');
      await channel.invokeMethod('installApk', {'path': filePath});
    } on MissingPluginException {
      // Platform channel not implemented yet — open file directly
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('APK downloaded to: $filePath')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(LibrettoTheme.spacingLg),
        children: [
          // ── App Info ──
          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppConstants.appName),
            subtitle: Text('Version ${AppConstants.appVersion}'),
          ),

          const SizedBox(height: LibrettoTheme.spacingLg),

          // ── Check for Update ──
          _SectionHeader(title: 'Updates'),
          if (_downloading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LibrettoTheme.spacingLg,
                vertical: LibrettoTheme.spacingMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Downloading update... ${(_downloadProgress * 100).toInt()}%',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: LibrettoTheme.spacingSm),
                  LinearProgressIndicator(value: _downloadProgress),
                ],
              ),
            ),
          ] else
            ListTile(
              leading: _checking
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.system_update),
              title: const Text('Check for updates'),
              subtitle: _error != null
                  ? Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    )
                  : const Text('Download the latest version from GitHub'),
              enabled: !_checking,
              onTap: _checkForUpdate,
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        left: LibrettoTheme.spacingLg,
        bottom: LibrettoTheme.spacingSm,
      ),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(color: LibrettoTheme.primary),
      ),
    );
  }
}
