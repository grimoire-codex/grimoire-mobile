import 'package:flutter/painting.dart';

import '../../core/api.dart';
import '../../core/disk_cache.dart';
import '../../core/models.dart';
import 'local_pdf.dart';
import 'page_images.dart';

enum ReadingSource {
  /// Pages rendered by the Grimoire server.
  server,

  /// Pages rendered on the phone from a downloaded copy.
  device,
}

/// Picks where pages come from.
///
/// Grimoire renders while it is reachable; a downloaded copy is the fallback
/// when it isn't, or the first choice when the person prefers on-device
/// rendering. Null means the book can't be read right now (offline and not
/// downloaded).
ReadingSource? chooseSource({
  required bool serverReachable,
  required bool downloaded,
  required bool preferDevice,
}) {
  if (downloaded && (preferDevice || !serverReachable)) return ReadingSource.device;
  if (serverReachable) return ReadingSource.server;
  return null;
}

/// Supplies page images for the reader, whichever side renders them.
abstract class PageSource {
  ReadingSource get kind;
  int get pageCount;

  /// The widest render worth asking for.
  int get maxWidth;

  /// Width over height of a 1-based page, when known before it loads.
  double? aspectRatio(int page);

  ImageProvider image(int page, int width, {bool urgent = true});

  Future<List<TocEntry>> toc();
}

class ServerPageSource extends PageSource {
  ServerPageSource({required this.api, required this.cache, required this.book});

  final GrimoireApi api;
  final DiskCache cache;
  final Book book;

  @override
  ReadingSource get kind => ReadingSource.server;

  @override
  int get pageCount => book.pageCount ?? 1;

  /// The server's own cap on `width` for a whole-page render.
  @override
  int get maxWidth => 3000;

  @override
  double? aspectRatio(int page) => null;

  @override
  ImageProvider image(int page, int width, {bool urgent = true}) => ServerPageImage(
    api: api,
    cache: cache,
    bookId: book.id,
    page: page,
    width: width.clamp(16, maxWidth),
    version: book.contentToken ?? 'none',
  );

  @override
  Future<List<TocEntry>> toc() => api.toc(book.id);
}

class DevicePageSource extends PageSource {
  DevicePageSource({required this.pdf, this.savedToc = const []});

  /// Owned by whoever opened it; the reader keeps it open across source
  /// switches so falling back is instant.
  final LocalPdf pdf;

  /// The server's table of contents, saved with the download.
  final List<TocEntry> savedToc;

  @override
  ReadingSource get kind => ReadingSource.device;

  @override
  int get pageCount => pdf.pageCount;

  /// PDFium has no hard cap, but a 4000px page is already ~64 MB of pixels.
  @override
  int get maxWidth => 4000;

  @override
  double? aspectRatio(int page) => pdf.aspectRatio(page);

  @override
  ImageProvider image(int page, int width, {bool urgent = true}) =>
      LocalPageImage(pdf: pdf, page: page, width: width.clamp(16, maxWidth), urgent: urgent);

  @override
  Future<List<TocEntry>> toc() async => savedToc.isNotEmpty ? savedToc : await pdf.outline();
}
