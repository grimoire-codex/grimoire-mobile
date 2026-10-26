import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'storage.dart';

/// A directory of cached bytes keyed by relative path, trimmed oldest-first.
///
/// Server page renders are immutable for a given (book, content token, width,
/// page), exactly as the server's own cache treats them, so a hit never needs
/// revalidating.
class DiskCache {
  DiskCache(this.root);

  final Directory root;

  File _file(String key) => File(p.join(root.path, key));

  Future<Uint8List?> read(String key) async {
    final file = _file(key);
    try {
      final bytes = await file.readAsBytes();
      // Touch so pruning keeps recently read pages.
      unawaitedSetModified(file);
      return bytes;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> write(String key, Uint8List bytes) async {
    final file = _file(key);
    try {
      await file.parent.create(recursive: true);
      // Write then rename, so a crash never leaves a truncated image behind.
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      await tmp.rename(file.path);
    } on FileSystemException {
      // A full disk just means no cache hit next time.
    }
  }

  Future<int> size() => directorySize(root);

  Future<void> clear() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  /// Deletes least-recently-used files until the cache fits in [maxBytes].
  Future<void> prune(int maxBytes) async {
    if (!await root.exists()) return;
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final stat = await entity.stat();
        files.add((entity, stat));
        total += stat.size;
      }
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= maxBytes) break;
      try {
        await file.delete();
        total -= stat.size;
      } on FileSystemException {
        // Already gone.
      }
    }
  }
}

void unawaitedSetModified(File file) {
  file.setLastModified(DateTime.now()).catchError((_) {});
}

/// Rendered pages from the server.
final pageCacheProvider = Provider<DiskCache>(
  (ref) => DiskCache(ref.watch(storageDirsProvider).pages),
);

/// Book covers and system art from the server.
final imageCacheProvider = Provider<DiskCache>(
  (ref) => DiskCache(ref.watch(storageDirsProvider).images),
);

/// Page renders kept on disk before the oldest are dropped.
const pageCacheLimitBytes = 512 * 1024 * 1024;
