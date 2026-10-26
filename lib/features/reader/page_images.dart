import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../core/api.dart';
import '../../core/disk_cache.dart';
import 'local_pdf.dart';

/// Rounds a wanted pixel width up to a fixed step so that small layout
/// differences (rotation, system bars, zoom steps) share one render - on the
/// server's cache and on ours.
int bucketWidth(double pixels, {int max = 3000, int step = 200, int min = 400}) {
  final bucket = (pixels / step).ceil() * step;
  return bucket.clamp(min, max);
}

/// A page rendered by Grimoire, fetched through the authenticated client and
/// kept on disk keyed by the book's content token, which changes when the
/// file does.
@immutable
class ServerPageImage extends ImageProvider<ServerPageImage> {
  const ServerPageImage({
    required this.api,
    required this.cache,
    required this.bookId,
    required this.page,
    required this.width,
    required this.version,
  });

  final GrimoireApi api;
  final DiskCache cache;
  final String bookId;
  final int page;
  final int width;
  final String version;

  String get cacheKey => '$bookId/$version/$width/$page.img';

  @override
  Future<ServerPageImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ServerPageImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: cacheKey);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    var bytes = await cache.read(cacheKey);
    if (bytes == null) {
      bytes = await api.pageImage(bookId, page, width, version: version);
      await cache.write(cacheKey, bytes);
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is ServerPageImage &&
      other.bookId == bookId &&
      other.page == page &&
      other.width == width &&
      other.version == version;

  @override
  int get hashCode => Object.hash(bookId, page, width, version);
}

/// A page of a downloaded PDF rendered on the device.
@immutable
class LocalPageImage extends ImageProvider<LocalPageImage> {
  const LocalPageImage({
    required this.pdf,
    required this.page,
    required this.width,
    this.urgent = true,
  });

  final LocalPdf pdf;
  final int page;
  final int width;

  /// Rendering priority only; not part of the cache key.
  final bool urgent;

  @override
  Future<LocalPageImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(LocalPageImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        pdf.render(page, width, urgent: urgent).then((image) => ImageInfo(image: image)),
      );

  @override
  bool operator ==(Object other) =>
      other is LocalPageImage &&
      other.pdf.key == pdf.key &&
      other.page == page &&
      other.width == width;

  @override
  int get hashCode => Object.hash(pdf.key, page, width);
}

/// A cover or system image from the server, cached on disk.
@immutable
class ServerImage extends ImageProvider<ServerImage> {
  const ServerImage({required this.cache, required this.cacheKey, required this.fetch});

  ServerImage.bookCover(GrimoireApi api, DiskCache cache, String bookId)
    : this(cache: cache, cacheKey: 'book-$bookId.img', fetch: () => api.bookThumbnail(bookId));

  ServerImage.systemCover(GrimoireApi api, DiskCache cache, String systemId)
    : this(cache: cache, cacheKey: 'system-$systemId.img', fetch: () => api.systemCover(systemId));

  final DiskCache cache;
  final String cacheKey;
  final Future<Uint8List> Function() fetch;

  @override
  Future<ServerImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(ServerImage key, ImageDecoderCallback decode) =>
      MultiFrameImageStreamCompleter(codec: _load(decode), scale: 1, debugLabel: cacheKey);

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    var bytes = await cache.read(cacheKey);
    if (bytes == null) {
      bytes = await fetch();
      await cache.write(cacheKey, bytes);
    }
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) => other is ServerImage && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
