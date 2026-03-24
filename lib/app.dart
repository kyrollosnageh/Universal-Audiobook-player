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
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = _createRouter();
    _loadInitialState();
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final onboarded = prefs.getBool(_onboardingCompleteKey) ?? false;

    // Check how many servers exist
    final servers = await ref.read(savedServersProvider.future);

    if (mounted) {
      setState(() {
        _onboardingComplete = onboarded;
      });

      // Navigate based on initial state
      if (!onboarded) {
        _router.go('/welcome');
      } else if (servers.length == 1) {
        // Auto-restore session if exactly one server
        await ref.read(authNotifierProvider.notifier).restoreSession();
        final authState = ref.read(authNotifierProvider);
        if (authState.isAuthenticated) {
          _router.go('/library');
        }
      }
    }
  }

  GoRouter _createRouter() {
    return GoRouter(
      initialLocation: '/hub',
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
                if (context.mounted) _router.go('/library');
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
        final authState = ref.read(authNotifierProvider);
        final isAuth = authState.isAuthenticated;
        final location = state.matchedLocation;

        // Allow welcome, hub, and settings without auth
        if (location == '/welcome' ||
            location == '/hub' ||
            location == '/settings') {
          return null;
        }

        // Require auth for everything else
        if (!isAuth) return '/hub';

        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch auth state to trigger redirect evaluation on login/logout
    ref.listen(authNotifierProvider, (previous, next) {
      if (next.isAuthenticated && !(previous?.isAuthenticated ?? false)) {
        // Just logged in — navigate to library
        _router.go('/library');
      } else if (!next.isAuthenticated &&
          (previous?.isAuthenticated ?? false)) {
        // Just logged out — navigate to hub
        _router.go('/hub');
      }
    });

    return MaterialApp.router(
      title: 'Libretto',
      debugShowCheckedModeBanner: false,
      theme: LibrettoTheme.darkTheme(),
      routerConfig: _router,
    );
  }
}
