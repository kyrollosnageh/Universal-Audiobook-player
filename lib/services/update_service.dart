import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/constants.dart';

/// GitHub release info.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.tagName,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.publishedAt,
  });

  final String version;
  final String tagName;
  final String changelog;
  final String? apkDownloadUrl;
  final DateTime publishedAt;
}

/// Result of an update check.
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.hasUpdate,
    this.currentVersion,
    this.latestRelease,
  });

  final bool hasUpdate;
  final String? currentVersion;
  final AppRelease? latestRelease;
}

/// Checks GitHub Releases for app updates and downloads APKs.
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _owner = 'kyrollosnageh';
  static const String _repo = 'Universal-Audiobook-player';

  /// Check if a newer version is available on GitHub Releases.
  Future<UpdateCheckResult> checkForUpdate() async {
    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$_owner/$_repo/releases/latest',
        options: Options(
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Accept': 'application/vnd.github.v3+json'},
        ),
      );

      if (response.statusCode != 200 || response.data is! Map) {
        return const UpdateCheckResult(hasUpdate: false);
      }

      final data = response.data as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final latestVersion = tagName.replaceFirst('v', '');
      final currentVersion = AppConstants.appVersion;

      // Find APK asset
      String? apkUrl;
      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final asset in assets) {
        if (asset is Map<String, dynamic>) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            apkUrl = asset['browser_download_url'] as String?;
            break;
          }
        }
      }

      final release = AppRelease(
        version: latestVersion,
        tagName: tagName,
        changelog: data['body'] as String? ?? 'No changelog available.',
        apkDownloadUrl: apkUrl,
        publishedAt: DateTime.tryParse(
              data['published_at'] as String? ?? '',
            ) ??
            DateTime.now(),
      );

      final hasUpdate = _isNewer(latestVersion, currentVersion);

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        currentVersion: currentVersion,
        latestRelease: release,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Update check failed: $e');
      rethrow;
    }
  }

  /// Download the APK to a temporary directory.
  /// Returns the file path of the downloaded APK.
  /// [onProgress] reports download progress as 0.0 to 1.0.
  Future<String> downloadApk(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/libretto-update.apk';

    await _dio.download(
      url,
      filePath,
      onReceiveProgress: (received, total) {
        if (total > 0) {
          onProgress?.call(received / total);
        }
      },
    );

    return filePath;
  }

  /// Compare semantic versions. Returns true if [latest] is newer than [current].
  bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();

    for (var i = 0; i < 3; i++) {
      final l = (i < latestParts.length ? latestParts[i] : 0) ?? 0;
      final c = (i < currentParts.length ? currentParts[i] : 0) ?? 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  void dispose() {
    _dio.close();
  }
}
