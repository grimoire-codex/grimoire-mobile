import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

/// Where the app keeps its files. Overridden in `main()`.
class StorageDirs {
  const StorageDirs({required this.data, required this.cache});

  /// Kept until the person deletes them: downloaded books.
  final Directory data;

  /// Safe for the OS to clear: rendered pages and covers from the server.
  final Directory cache;

  Directory get downloads => Directory(p.join(data.path, 'downloads'));
  Directory get pages => Directory(p.join(cache.path, 'pages'));
  Directory get images => Directory(p.join(cache.path, 'images'));
}

final storageDirsProvider = Provider<StorageDirs>(
  (ref) => throw UnimplementedError('storageDirsProvider must be overridden'),
);

/// Total size of every file under [dir], or 0 when it doesn't exist.
Future<int> directorySize(Directory dir) async {
  if (!await dir.exists()) return 0;
  var total = 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) total += await entity.length();
  }
  return total;
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 || value >= 100 ? 0 : 1)} ${units[unit]}';
}
