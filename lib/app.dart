import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/theme.dart';
import 'screens/server_hub/server_hub_screen.dart';
import 'screens/welcome/welcome_screen.dart';
import 'screens/library_home/library_home_screen.dart';
import 'screens/book_detail/book_detail_screen.dart';
import 'screens/player/player_screen.dart';
import 'screens/series/series_view_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'state/auth_provider.dart';
import 'widgets/add_server_sheet.dart';

/// Key for tracking whether onboarding has been completed.
const _onboardingCompleteKey = 'onboarding_complete';

/// Root application widget with routing and theme.
class LibrettoApp extends ConsumerStatefulWidget {
  const LibrettoApp({super.key});

  @override
  ConsumerState<LibrettoApp> createState() => _LibrettoAppState();
}

class _LibrettoAppState extends ConsumerState<LibrettoApp> {
  bool? _onboardingComplete;
  int? _serverCount;

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool(_onboardingCompleteKey) ?? false;

    // Check how many servers exist
    final servers = await ref.read(savedServersProvider.future);

    if (mounted) {
      setState(() {
        _onboardingComplete = onboarded;
        _serverCount = servers.length;
      });
    }

    // Auto-restore session if exactly one server
    if (servers.length == 1) {
      await ref.read(authNotifierProvider.notifier).restoreSession();
    }
  }

  String _initialLocation(AuthState authState) {
    // Still loading initial state
    if (_onboardingComplete == null) return '/hub';

    // First launch — show welcome
    if (_onboardingComplete == false) return '/welcome';

    // Authenticated with auto-restored session — go to library
    if (authState.isAuthenticated) return '/library';

    // Has servers — show hub
    return '/hub';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    final router = GoRouter(
      initialLocation: _initialLocation(authState),
      routes: [
        GoRoute(
          path: '/welcome',
          builder: (context, state) => WelcomeScreen(
            onGetStarted: () async {
              final result = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const AddServerSheet(),
              );

              if (result == true) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_onboardingCompleteKey, true);
                if (context.mounted) context.go('/library');
              }
            },
          ),
        ),
        GoRoute(
          path: '/hub',
          builder: (context, state) => const ServerHubScreen(),
        ),
        GoRoute(
          path: '/library',
          builder: (context, state) => const LibraryHomeScreen(),
        ),
        GoRoute(
          path: '/book/:bookId',
          builder: (context, state) =>
              BookDetailScreen(bookId: state.pathParameters['bookId']!),
        ),
        GoRoute(
          path: '/player',
          builder: (context, state) => const PlayerScreen(),
        ),
        GoRoute(
          path: '/series/:seriesId',
          builder: (context, state) => SeriesViewScreen(
            seriesId: state.pathParameters['seriesId']!,
            seriesName: state.uri.queryParameters['name'],
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
      redirect: (context, state) {
        final isAuth = authState.isAuthenticated;
        final location = state.matchedLocation;

        // Allow welcome, hub, and settings without auth
        if (location == '/welcome' ||
            location == '/hub' ||
            location == '/settings')
          return null;

        // Require auth for everything else
        if (!isAuth) return '/hub';

        return null;
      },
    );

    return MaterialApp.router(
      title: 'Libretto',
      debugShowCheckedModeBanner: false,
      theme: LibrettoTheme.darkTheme(),
      routerConfig: router,
    );
  }
}
