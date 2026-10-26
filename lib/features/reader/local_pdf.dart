import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import '../../core/models.dart';

/// A downloaded PDF opened with PDFium for on-device rendering.
///
/// Renders the same way the server does: each page at the width it will be
/// shown, not at full resolution, so a phone-sized page takes tens of
/// milliseconds. Repeat requests are served from Flutter's image cache, which
/// also folds two requests for the same page into one render (see
/// [LocalPageImage]).
class LocalPdf {
  LocalPdf._(this.document, this.key);

  final PdfDocument document;

  /// Identifies this file's contents in image-cache keys.
  final String key;

  static Future<LocalPdf> open(String path, {required String key}) async {
    await pdfrxFlutterInitialize();
    return LocalPdf._(await PdfDocument.openFile(path), key);
  }

  int get pageCount => document.pages.length;

  /// Width over height of a 1-based [page].
  double aspectRatio(int page) {
    final p = document.pages[page - 1];
    return p.height > 0 ? p.width / p.height : 0.75;
  }

  Future<ui.Image> render(int page, int width, {bool urgent = true}) async {
    final p = document.pages[page - 1];
    final height = (width * p.height / p.width).round();
    final image = await p.render(
      width: width,
      height: height,
      fullWidth: width.toDouble(),
      fullHeight: height.toDouble(),
      backgroundColor: 0xFFFFFFFF,
      priority: urgent ? PdfPageRenderPriority.high : PdfPageRenderPriority.normal,
    );
    if (image == null) throw StateError('Page $page could not be rendered');
    try {
      return await image.createImage();
    } finally {
      image.dispose();
    }
  }

  /// The PDF's own outline, in the server's table-of-contents shape.
  Future<List<TocEntry>> outline() async {
    List<TocEntry> convert(List<PdfOutlineNode> nodes, int level) => [
      for (final n in nodes)
        TocEntry(
          title: n.title,
          page: n.dest?.pageNumber ?? -1,
          level: level,
          children: convert(n.children, level + 1),
        ),
    ];
    return convert(await document.loadOutline(), 1);
  }

  Future<void> dispose() => document.dispose();
}
