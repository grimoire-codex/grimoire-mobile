import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth.dart';
import '../core/models.dart';
import '../features/characters/characters_screen.dart';
import '../features/characters/sheet_screen.dart';
import '../features/downloads/downloads_screen.dart';
import '../features/library/book_screen.dart';
import '../features/library/library_screen.dart';
import '../features/library/system_screen.dart';
import '../features/login/login_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/search/search_screen.dart';
import '../features/settings/settings_screen.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects on sign-in/out without rebuilding the router.
  final signedIn = ValueNotifier(ref.read(authProvider) != null);
  ref.listen(authProvider, (_, session) => signedIn.value = session != null);
  ref.onDispose(signedIn.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/library',
    refreshListenable: signedIn,
    redirect: (context, state) {
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn.value) return atLogin ? null : '/login';
      if (atLogin) return '/library';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _Shell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => const LibraryScreen(),
                routes: [
                  GoRoute(
                    path: 'system/:id',
                    builder: (context, state) => SystemScreen(
                      systemId: state.pathParameters['id']!,
                      preview: state.extra is GameSystem ? state.extra! as GameSystem : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/search', builder: (context, state) => const SearchScreen())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/characters', builder: (context, state) => const CharactersScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/downloads', builder: (context, state) => const DownloadsScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/book/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => BookScreen(
          bookId: state.pathParameters['id']!,
          preview: state.extra is Book ? state.extra! as Book : null,
        ),
      ),
      GoRoute(
        path: '/character/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => SheetScreen(
          characterId: state.pathParameters['id']!,
          preview: state.extra is Character ? state.extra! as Character : null,
        ),
      ),
      GoRoute(
        path: '/read/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => ReaderScreen(
          bookId: state.pathParameters['id']!,
          initialPage: int.tryParse(state.uri.queryParameters['page'] ?? ''),
        ),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class _Shell extends StatelessWidget {
  const _Shell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Library',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
          NavigationDestination(
            icon: Icon(Icons.badge_outlined),
            selectedIcon: Icon(Icons.badge),
            label: 'Characters',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_for_offline_outlined),
            selectedIcon: Icon(Icons.download_for_offline),
            label: 'Downloads',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
