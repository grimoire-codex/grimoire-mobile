import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth.dart';
import '../../core/models.dart';
import '../../core/reachability.dart';
import '../downloads/download_manager.dart';

final systemsProvider = FutureProvider.autoDispose<List<GameSystem>>((ref) async {
  final api = ref.watch(apiProvider);
  if (api == null) return const [];
  return api.systems();
});

final recentlyAddedProvider = FutureProvider.autoDispose<List<Book>>((ref) async {
  final api = ref.watch(apiProvider);
  if (api == null) return const [];
  return api.recentlyAdded();
});

final systemDetailProvider = FutureProvider.autoDispose.family<SystemDetail, String>((
  ref,
  id,
) async {
  final api = ref.watch(apiProvider);
  if (api == null) throw StateError('Not signed in');
  return api.system(id);
});

/// A book's details: from the server when reachable, otherwise from its
/// download, so a downloaded book's page works offline.
final bookProvider = FutureProvider.autoDispose.family<Book, String>((ref, id) async {
  final saved = ref.read(downloadsProvider)[id]?.book;
  final api = ref.watch(apiProvider);
  if (api == null || !ref.read(reachabilityProvider)) {
    if (saved != null) return saved;
    throw StateError('This book is not downloaded and the server can\'t be reached.');
  }
  try {
    return await api.book(id);
  } catch (_) {
    if (saved != null) return saved;
    rethrow;
  }
});
