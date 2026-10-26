import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api.dart';
import 'reachability.dart';
import 'session.dart';

/// Overridden in `main()` with the session restored from secure storage.
final initialSessionProvider = Provider<Session?>((ref) => null);

final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());

/// The signed-in session, or null when signed out.
class AuthController extends Notifier<Session?> {
  @override
  Session? build() => ref.watch(initialSessionProvider);

  Future<void> signIn(Session session) async {
    await ref.read(sessionStoreProvider).save(session);
    state = session;
  }

  /// Token rotation: persist without rebuilding everything that watches the
  /// session (the API client already holds the new tokens).
  void tokensRotated(Session session) {
    unawaited(ref.read(sessionStoreProvider).save(session));
  }

  Future<void> signOut() async {
    // Parallel 401s each report an expired session; sign out once.
    if (state == null) return;
    final api = ref.read(apiProvider);
    try {
      await api?.logout();
    } catch (_) {
      // Offline or already revoked: signing out locally is what matters.
    }
    await ref.read(sessionStoreProvider).clear();
    state = null;
  }
}

final authProvider = NotifierProvider<AuthController, Session?>(AuthController.new);

/// The API client for the current session. Rebuilt only on sign-in/out, not
/// on token rotation.
final apiProvider = Provider<GrimoireApi?>((ref) {
  ref.watch(authProvider.select((s) => (s?.baseUrl, s?.apiKey, s?.user?.id)));
  final session = ref.read(authProvider);
  if (session == null) return null;
  return GrimoireApi(
    session,
    onSessionChanged: ref.read(authProvider.notifier).tokensRotated,
    onSessionExpired: () => unawaited(ref.read(authProvider.notifier).signOut()),
    onReachable: (ok) => ref.read(reachabilityProvider.notifier).report(ok),
  );
});
