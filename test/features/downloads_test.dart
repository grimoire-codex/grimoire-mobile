import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_mobile/core/api.dart';
import 'package:grimoire_mobile/core/auth.dart';
import 'package:grimoire_mobile/core/disk_cache.dart';
import 'package:grimoire_mobile/core/models.dart';
import 'package:grimoire_mobile/core/session.dart';
import 'package:grimoire_mobile/core/storage.dart';
import 'package:grimoire_mobile/features/downloads/download_manager.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class MockApi extends Mock implements GrimoireApi {}

const server = 'https://grimoire.test';

Book pdf(String id, {String token = 't1'}) => Book(
  id: id,
  title: 'Book $id',
  filename: '$id.pdf',
  mimeType: 'application/pdf',
  contentToken: token,
  hasThumbnail: true,
);

void main() {
  late Directory tmp;
  late MockApi api;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        storageDirsProvider.overrideWithValue(
          StorageDirs(
            data: Directory(p.join(tmp.path, 'data')),
            cache: Directory(p.join(tmp.path, 'cache')),
          ),
        ),
        initialSessionProvider.overrideWithValue(const Session(baseUrl: server, accessToken: 'a')),
        apiProvider.overrideWithValue(api),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle(ProviderContainer c, String id) async {
    for (var i = 0; i < 100; i++) {
      final e = c.read(downloadsProvider)[id];
      if (e == null || !e.isActive) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    fail('download of $id never finished');
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('grimoire-test');
    api = MockApi();
    when(() => api.baseUrl).thenReturn(server);
    when(() => api.book(any())).thenAnswer((i) async => pdf(i.positionalArguments[0] as String));
    when(() => api.toc(any())).thenAnswer((_) async => const [TocEntry(title: 'Intro', page: 1)]);
    when(() => api.bookThumbnail(any())).thenAnswer((_) async => Uint8List.fromList([9]));
    when(
      () => api.downloadFile(
        any(),
        any(),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((i) async {
      final path = i.positionalArguments[1] as String;
      final onProgress = i.namedArguments[#onProgress] as void Function(int, int)?;
      onProgress?.call(2, 4);
      await File(path).writeAsBytes([1, 2, 3, 4]);
      onProgress?.call(4, 4);
    });
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('a download saves the file, cover and contents, and survives a restart', () async {
    final c = container();
    c.read(downloadsProvider.notifier).download(pdf('b1'));
    expect(c.read(downloadsProvider)['b1']!.isActive, isTrue);
    await settle(c, 'b1');

    final manager = c.read(downloadsProvider.notifier);
    final entry = manager.completed('b1')!;
    expect(entry.total, 4);
    expect(entry.toc.single.title, 'Intro');
    expect(entry.serverUrl, server);
    expect(manager.fileFor('b1').readAsBytesSync(), [1, 2, 3, 4]);
    expect(manager.coverFor('b1').existsSync(), isTrue);
    expect(File('${manager.fileFor('b1').path}.part').existsSync(), isFalse);

    // A fresh container reads the manifest back.
    final again = container();
    final restored = again.read(downloadsProvider)['b1']!;
    expect(restored.isDone, isTrue);
    expect(restored.book.contentToken, 't1');
    expect(again.read(serverDownloadsProvider).single.book.id, 'b1');
  });

  test('only PDFs are downloaded', () {
    final c = container();
    c
        .read(downloadsProvider.notifier)
        .download(const Book(id: 'e1', title: 'Epub', mimeType: 'application/epub+zip'));
    expect(c.read(downloadsProvider), isEmpty);
  });

  test('a failed download reports why and leaves no partial file', () async {
    when(
      () => api.downloadFile(
        any(),
        any(),
        onProgress: any(named: 'onProgress'),
        cancelToken: any(named: 'cancelToken'),
      ),
    ).thenAnswer((i) async {
      await File(i.positionalArguments[1] as String).writeAsBytes([1]);
      throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/file'),
        reason: 'down',
      );
    });
    final c = container();
    final manager = c.read(downloadsProvider.notifier);
    manager.download(pdf('b2'));
    await settle(c, 'b2');
    final entry = c.read(downloadsProvider)['b2']!;
    expect(entry.status, DownloadStatus.failed);
    expect(entry.error, 'Could not reach the server.');
    expect(manager.completed('b2'), isNull);
    expect(File('${manager.fileFor('b2').path}.part').existsSync(), isFalse);
  });

  test('delete removes the files and the entry', () async {
    final c = container();
    final manager = c.read(downloadsProvider.notifier);
    manager.download(pdf('b3'));
    await settle(c, 'b3');
    await manager.delete('b3');
    expect(c.read(downloadsProvider), isEmpty);
    expect(manager.dirFor('b3').existsSync(), isFalse);
    expect(container().read(downloadsProvider), isEmpty);
  });

  test('downloads from another server are hidden, not lost', () async {
    final c = container();
    c.read(downloadsProvider.notifier).download(pdf('b4'));
    await settle(c, 'b4');

    final other = ProviderContainer(
      overrides: [
        storageDirsProvider.overrideWithValue(c.read(storageDirsProvider)),
        initialSessionProvider.overrideWithValue(const Session(baseUrl: 'https://other.test')),
        apiProvider.overrideWithValue(null),
      ],
    );
    addTearDown(other.dispose);
    expect(other.read(downloadsProvider), contains('b4'));
    expect(other.read(serverDownloadsProvider), isEmpty);
  });

  test('an interrupted download is not mistaken for a finished one', () {
    final entry = DownloadEntry.fromJson({
      'book': pdf('b5').toJson(),
      'server_url': server,
      'status': 'downloading',
      'total': 10,
    });
    expect(entry.status, DownloadStatus.failed);
    expect(entry.error, 'Interrupted');
  });

  group('DiskCache', () {
    test('round-trips bytes and misses cleanly', () async {
      final cache = DiskCache(Directory(p.join(tmp.path, 'pages')));
      expect(await cache.read('b/t/1200/1.img'), isNull);
      await cache.write('b/t/1200/1.img', Uint8List.fromList([1, 2]));
      expect(await cache.read('b/t/1200/1.img'), [1, 2]);
      expect(await cache.size(), 2);
      await cache.clear();
      expect(await cache.size(), 0);
    });

    test('prune drops the least recently used files first', () async {
      final cache = DiskCache(Directory(p.join(tmp.path, 'pages')));
      for (final name in ['old', 'mid', 'new']) {
        await cache.write(name, Uint8List(10));
      }
      final root = cache.root.path;
      File(p.join(root, 'old')).setLastModifiedSync(DateTime(2020));
      File(p.join(root, 'mid')).setLastModifiedSync(DateTime(2021));
      await cache.prune(20);
      expect(File(p.join(root, 'old')).existsSync(), isFalse);
      expect(File(p.join(root, 'mid')).existsSync(), isTrue);
      expect(File(p.join(root, 'new')).existsSync(), isTrue);
    });
  });
}
