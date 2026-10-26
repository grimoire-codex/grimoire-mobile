import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/models.dart';
import '../../core/storage.dart';

enum DownloadStatus { queued, downloading, done, failed }

/// One book saved (or being saved) for offline reading.
class DownloadEntry {
  const DownloadEntry({
    required this.book,
    required this.serverUrl,
    this.status = DownloadStatus.queued,
    this.received = 0,
    this.total = 0,
    this.error,
    this.completedAt,
    this.toc = const [],
  });

  final Book book;

  /// Downloads belong to the server they came from; another server's books
  /// are hidden rather than deleted.
  final String serverUrl;
  final DownloadStatus status;
  final int received;
  final int total;
  final String? error;
  final DateTime? completedAt;
  final List<TocEntry> toc;

  bool get isDone => status == DownloadStatus.done;
  bool get isActive => status == DownloadStatus.queued || status == DownloadStatus.downloading;
  double? get progress => total > 0 ? received / total : null;

  DownloadEntry copyWith({
    Book? book,
    DownloadStatus? status,
    int? received,
    int? total,
    String? error,
    DateTime? completedAt,
    List<TocEntry>? toc,
  }) => DownloadEntry(
    book: book ?? this.book,
    serverUrl: serverUrl,
    status: status ?? this.status,
    received: received ?? this.received,
    total: total ?? this.total,
    error: error,
    completedAt: completedAt ?? this.completedAt,
    toc: toc ?? this.toc,
  );

  factory DownloadEntry.fromJson(Map<String, dynamic> json) {
    final status = DownloadStatus.values.asNameMap()[json['status']] ?? DownloadStatus.failed;
    // Anything mid-flight when the app last stopped was interrupted.
    final interrupted = status != DownloadStatus.done;
    return DownloadEntry(
      book: Book.fromJson(json['book'] as Map<String, dynamic>),
      serverUrl: json['server_url'] as String,
      status: interrupted ? DownloadStatus.failed : status,
      received: interrupted ? 0 : (json['total'] as int? ?? 0),
      total: json['total'] as int? ?? 0,
      error: interrupted ? 'Interrupted' : null,
      completedAt: DateTime.tryParse(json['completed_at'] as String? ?? ''),
      toc: [
        for (final t in (json['toc'] as List? ?? const []))
          TocEntry.fromJson(t as Map<String, dynamic>),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'book': book.toJson(),
    'server_url': serverUrl,
    'status': status.name,
    'total': total,
    'completed_at': completedAt?.toIso8601String(),
    'toc': [for (final t in toc) t.toJson()],
  };
}

/// Saves PDFs for offline reading and remembers them in a JSON manifest.
///
/// Each book lives in `downloads/<id>/` as `book.pdf` plus `cover.webp`, so
/// the offline library has covers too. The file is written to a `.part` file
/// and renamed on completion, so a half-finished download is never opened.
class DownloadManager extends Notifier<Map<String, DownloadEntry>> {
  static const maxConcurrent = 2;

  final _cancelTokens = <String, CancelToken>{};
  final _queue = <String>[];
  int _running = 0;

  StorageDirs get _dirs => ref.read(storageDirsProvider);
  File get _manifest => File(p.join(_dirs.downloads.path, 'manifest.json'));

  Directory dirFor(String bookId) => Directory(p.join(_dirs.downloads.path, bookId));
  File fileFor(String bookId) => File(p.join(dirFor(bookId).path, 'book.pdf'));
  File coverFor(String bookId) => File(p.join(dirFor(bookId).path, 'cover.webp'));

  @override
  Map<String, DownloadEntry> build() {
    final manifest = File(p.join(ref.watch(storageDirsProvider).downloads.path, 'manifest.json'));
    if (!manifest.existsSync()) return {};
    try {
      final raw = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      return {
        for (final e in (raw['books'] as List? ?? const []))
          if (e is Map<String, dynamic>) '${(e['book'] as Map)['id']}': DownloadEntry.fromJson(e),
      };
    } on FormatException {
      return {};
    }
  }

  /// The finished download of [bookId], if any.
  DownloadEntry? completed(String bookId) {
    final entry = state[bookId];
    return entry != null && entry.isDone ? entry : null;
  }

  /// Queues [book] for download. Only PDFs can be read offline.
  void download(Book book) {
    final api = ref.read(apiProvider);
    if (api == null || !book.isPdf) return;
    final existing = state[book.id];
    if (existing != null && existing.isActive) return;
    _set(DownloadEntry(book: book, serverUrl: api.baseUrl));
    _queue.add(book.id);
    _pump();
  }

  void cancel(String bookId) {
    _queue.remove(bookId);
    _cancelTokens.remove(bookId)?.cancel();
    final entry = state[bookId];
    if (entry != null && !entry.isDone) _remove(bookId);
  }

  Future<void> delete(String bookId) async {
    cancel(bookId);
    _remove(bookId);
    final dir = dirFor(bookId);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes every download from [serverUrl], or from all servers when null.
  Future<void> deleteAll({String? serverUrl}) async {
    for (final entry in state.values.toList()) {
      if (serverUrl == null || entry.serverUrl == serverUrl) {
        await delete(entry.book.id);
      }
    }
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      final id = _queue.removeAt(0);
      _running++;
      unawaited(
        _run(id).whenComplete(() {
          _running--;
          _pump();
        }),
      );
    }
  }

  Future<void> _run(String bookId) async {
    final api = ref.read(apiProvider);
    final entry = state[bookId];
    if (api == null || entry == null) return;
    final token = CancelToken();
    _cancelTokens[bookId] = token;
    final dir = dirFor(bookId);
    final part = File('${fileFor(bookId).path}.part');
    try {
      await dir.create(recursive: true);
      _set(entry.copyWith(status: DownloadStatus.downloading));

      // Fresh detail carries the content token that keys staleness checks.
      final book = await api.book(bookId);
      final toc = await api.toc(bookId);
      if (book.hasThumbnail) {
        try {
          await coverFor(bookId).writeAsBytes(await api.bookThumbnail(bookId));
        } on DioException {
          // A missing cover is cosmetic.
        }
      }

      var lastReported = DateTime.fromMillisecondsSinceEpoch(0);
      await api.downloadFile(
        bookId,
        part.path,
        cancelToken: token,
        onProgress: (received, total) {
          final now = DateTime.now();
          if (now.difference(lastReported).inMilliseconds < 250 && received != total) {
            return;
          }
          lastReported = now;
          final current = state[bookId];
          if (current != null) {
            _set(
              current.copyWith(received: received, total: total > 0 ? total : (book.fileSize ?? 0)),
              persist: false,
            );
          }
        },
      );
      final current = state[bookId];
      if (current == null) {
        // Cancelled just as the last byte arrived.
        await part.delete();
        return;
      }
      await part.rename(fileFor(bookId).path);
      final size = await fileFor(bookId).length();
      _set(
        current.copyWith(
          book: book,
          toc: toc,
          status: DownloadStatus.done,
          received: size,
          total: size,
          completedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (await part.exists()) await part.delete();
      if (e is DioException && CancelToken.isCancel(e)) return;
      final current = state[bookId];
      if (current != null) {
        _set(current.copyWith(status: DownloadStatus.failed, error: describeError(e)));
      }
    } finally {
      _cancelTokens.remove(bookId);
    }
  }

  void _set(DownloadEntry entry, {bool persist = true}) {
    state = {...state, entry.book.id: entry};
    if (persist) _persist();
  }

  void _remove(String bookId) {
    state = {...state}..remove(bookId);
    _persist();
  }

  void _persist() {
    final books = [
      for (final e in state.values)
        if (e.isDone) e.toJson(),
    ];
    try {
      _manifest.parent.createSync(recursive: true);
      final tmp = File('${_manifest.path}.tmp');
      tmp.writeAsStringSync(jsonEncode({'version': 1, 'books': books}), flush: true);
      tmp.renameSync(_manifest.path);
    } on FileSystemException {
      // Leave the previous manifest in place.
    }
  }
}

final downloadsProvider = NotifierProvider<DownloadManager, Map<String, DownloadEntry>>(
  DownloadManager.new,
);

/// Downloads that belong to the server currently signed in to.
final serverDownloadsProvider = Provider<List<DownloadEntry>>((ref) {
  final server = ref.watch(authProvider.select((s) => s?.baseUrl));
  final entries = ref.watch(downloadsProvider).values.where((e) => e.serverUrl == server).toList()
    ..sort((a, b) => a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()));
  return entries;
});
