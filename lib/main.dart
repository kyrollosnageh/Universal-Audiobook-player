import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/server_providers/emby_provider.dart';
import 'services/crash_reporting_service.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize crash reporting (PII-stripped)
      final crashReporting = CrashReportingService();
      await crashReporting.initialize();
      await EmbyProvider.initDeviceId();

      runApp(const ProviderScope(child: LibrettoApp()));
    },
    (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Uncaught error: $error');
        debugPrint('Stack trace: $stackTrace');
      }
    },
  );
}
