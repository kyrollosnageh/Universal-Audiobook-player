import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'screens/server_connect/server_connect_screen.dart';
import 'screens/library_home/library_home_screen.dart';
import 'screens/book_detail/book_detail_screen.dart';
import 'screens/player/player_screen.dart';
import 'screens/series/series_view_screen.dart';
import 'state/auth_provider.dart';

/// Root application widget with routing and theme.
class LibrettoApp extends ConsumerWidget {
  const LibrettoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    final router = GoRouter(
      initialLocation: authState.isAuthenticated ? '/library' : '/connect',
      routes: [
        GoRoute(
          path: '/connect',
          builder: (context, state) => const ServerConnectScreen(),
        ),
        GoRoute(
          path: '/library',
          builder: (context, state) => const LibraryHomeScreen(),
        ),
        GoRoute(
          path: '/book/:bookId',
          builder: (context, state) => BookDetailScreen(
            bookId: state.pathParameters['bookId']!,
          ),
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
      ],
      redirect: (context, state) {
        final isAuth = authState.isAuthenticated;
        final isConnectPage = state.matchedLocation == '/connect';

        if (!isAuth && !isConnectPage) return '/connect';
        if (isAuth && isConnectPage) return '/library';
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
