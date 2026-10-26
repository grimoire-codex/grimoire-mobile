import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/disk_cache.dart';
import '../../core/models.dart';
import '../../core/reachability.dart';
import '../../core/settings.dart';
import '../downloads/download_manager.dart';
import 'local_pdf.dart';
import 'page_source.dart';

/// The book is neither reachable on the server nor downloaded.
class ReaderUnavailable implements Exception {
  const ReaderUnavailable();

  @override
  String toString() => 'This book is not downloaded and the server can\'t be reached.';
}

class ReaderState {
  const ReaderState({
    required this.book,
    required this.source,
    required this.downloaded,
    this.fellBack = false,
  });

  final Book book;
  final PageSource source;
  final bool downloaded;

  /// True when the reader switched to the downloaded copy because the server
  /// stopped answering mid-read.
  final bool fellBack;
}

/// Owns one open book: where its pages come from, and switching between the
/// server and the downloaded copy as reachability changes.
class ReaderController extends AsyncNotifier<ReaderState> {
  ReaderController(this.bookId);

  final String bookId;
  LocalPdf? _pdf;

  @override
  Future<ReaderState> build() async {
    ref.onDispose(() {
      final pdf = _pdf;
      _pdf = null;
      if (pdf != null) unawaited(pdf.dispose());
    });
    ref.listen(reachabilityProvider, (previous, reachable) {
      if (!reachable) unawaited(_fallBack());
    });

    final download = ref.read(downloadsProvider.notifier).completed(bookId);
    final kind = chooseSource(
      serverReachable: ref.read(reachabilityProvider),
      downloaded: download != null,
      preferDevice: ref.read(settingsProvider).preferDeviceRendering,
    );
    if (kind == null) throw const ReaderUnavailable();
    if (kind == ReadingSource.device) return _deviceState(download!);
    try {
      return await _serverState(download);
    } catch (e) {
      if (download != null && isNetworkError(e)) return _deviceState(download, fellBack: true);
      rethrow;
    }
  }

  Future<ReaderState> _serverState(DownloadEntry? download) async {
    final api = ref.read(apiProvider);
    if (api == null) throw const ReaderUnavailable();
    final book = await api.book(bookId);
    return ReaderState(
      book: book,
      source: ServerPageSource(api: api, cache: ref.read(pageCacheProvider), book: book),
      downloaded: download != null,
    );
  }

  Future<ReaderState> _deviceState(DownloadEntry download, {bool fellBack = false}) async {
    final file = ref.read(downloadsProvider.notifier).fileFor(bookId);
    _pdf ??= await LocalPdf.open(
      file.path,
      key: '$bookId:${download.book.contentToken ?? download.completedAt}',
    );
    return ReaderState(
      book: download.book,
      source: DevicePageSource(pdf: _pdf!, savedToc: download.toc),
      downloaded: true,
      fellBack: fellBack,
    );
  }

  /// A server page failed to load. If it was the network, read on from the
  /// downloaded copy.
  void serverPageFailed(Object error) {
    if (isNetworkError(error)) unawaited(_fallBack());
  }

  Future<void> _fallBack() async {
    final current = state.value;
    if (current == null || current.source.kind != ReadingSource.server) return;
    final download = ref.read(downloadsProvider.notifier).completed(bookId);
    if (download == null) return;
    state = AsyncData(await _deviceState(download, fellBack: true));
  }

  /// Lets the reader pick a source by hand.
  Future<void> useSource(ReadingSource kind) async {
    final current = state.value;
    if (current == null || current.source.kind == kind) return;
    final download = ref.read(downloadsProvider.notifier).completed(bookId);
    if (kind == ReadingSource.device) {
      if (download != null) state = AsyncData(await _deviceState(download));
    } else {
      try {
        state = AsyncData(await _serverState(download));
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        ref.read(reachabilityProvider.notifier).report(false);
      }
    }
  }
}

final readerProvider = AsyncNotifierProvider.autoDispose
    .family<ReaderController, ReaderState, String>(ReaderController.new);

/// The server's bookmarks for a book.
final bookmarksProvider = FutureProvider.autoDispose.family<List<Bookmark>, String>((
  ref,
  bookId,
) async {
  final api = ref.watch(apiProvider);
  if (api == null) return const [];
  return api.bookmarks(bookId);
});
