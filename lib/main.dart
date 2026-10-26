import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/router.dart';
import 'app/theme.dart';
import 'core/auth.dart';
import 'core/disk_cache.dart';
import 'core/session.dart';
import 'core/settings.dart';
import 'core/storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final (prefs, session, data, cache) = await (
    SharedPreferences.getInstance(),
    SessionStore().load(),
    getApplicationSupportDirectory(),
    getApplicationCacheDirectory(),
  ).wait;
  final dirs = StorageDirs(data: data, cache: cache);

  // A decoded phone-width page is roughly 8-15 MB of pixels; this keeps the
  // pages either side of the current one plus covers in memory.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 256 << 20;

  unawaited(DiskCache(dirs.pages).prune(pageCacheLimitBytes));

  runApp(
    ProviderScope(
      // Failures here are mostly "offline"; screens offer their own retry
      // instead of Riverpod retrying in the background.
      retry: (retryCount, error) => null,
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        initialSessionProvider.overrideWithValue(session),
        storageDirsProvider.overrideWithValue(dirs),
      ],
      child: const GrimoireApp(),
    ),
  );
}

class GrimoireApp extends ConsumerWidget {
  const GrimoireApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Grimoire',
      debugShowCheckedModeBanner: false,
      theme: grimoireTheme(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
