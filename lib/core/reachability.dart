import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';

/// Whether the Grimoire server can be reached right now.
///
/// Starts optimistic, then follows every API response (via [report]) and
/// re-probes `/api/health` when the network changes, when the app returns to
/// the foreground, and every [_retryEvery] while unreachable.
class ReachabilityController extends Notifier<bool> {
  static const _retryEvery = Duration(seconds: 20);

  Timer? _retry;
  bool _checking = false;

  @override
  bool build() {
    final api = ref.watch(apiProvider);
    if (api == null) return true;

    final connectivity = Connectivity().onConnectivityChanged.listen((results) {
      if (results.every((r) => r == ConnectivityResult.none)) {
        report(false);
      } else {
        unawaited(check());
      }
    });
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(check()));
    ref.onDispose(() {
      connectivity.cancel();
      lifecycle.dispose();
      _retry?.cancel();
    });
    Future.microtask(check);
    return true;
  }

  void report(bool reachable) {
    if (!ref.mounted) return;
    if (reachable) {
      _retry?.cancel();
      _retry = null;
    } else {
      _retry ??= Timer.periodic(_retryEvery, (_) => unawaited(check()));
    }
    if (state != reachable) state = reachable;
  }

  Future<void> check() async {
    final api = ref.read(apiProvider);
    if (api == null || _checking) return;
    _checking = true;
    try {
      report(await api.ping());
    } finally {
      _checking = false;
    }
  }
}

final reachabilityProvider = NotifierProvider<ReachabilityController, bool>(
  ReachabilityController.new,
);
