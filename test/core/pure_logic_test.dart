import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_mobile/core/models.dart';
import 'package:grimoire_mobile/core/pkce.dart';
import 'package:grimoire_mobile/core/storage.dart';
import 'package:grimoire_mobile/features/reader/page_images.dart';
import 'package:grimoire_mobile/features/reader/page_source.dart';
import 'package:grimoire_mobile/features/search/search_screen.dart';

void main() {
  group('chooseSource', () {
    test('Grimoire renders while reachable', () {
      expect(
        chooseSource(serverReachable: true, downloaded: true, preferDevice: false),
        ReadingSource.server,
      );
      expect(
        chooseSource(serverReachable: true, downloaded: false, preferDevice: true),
        ReadingSource.server,
      );
    });

    test('the download is the fallback offline', () {
      expect(
        chooseSource(serverReachable: false, downloaded: true, preferDevice: false),
        ReadingSource.device,
      );
    });

    test('preferring the device uses the download even online', () {
      expect(
        chooseSource(serverReachable: true, downloaded: true, preferDevice: true),
        ReadingSource.device,
      );
    });

    test('offline and not downloaded cannot be read', () {
      expect(chooseSource(serverReachable: false, downloaded: false, preferDevice: true), isNull);
    });
  });

  group('bucketWidth', () {
    test('rounds up to the step and clamps', () {
      expect(bucketWidth(1170), 1200);
      expect(bucketWidth(1200), 1200);
      expect(bucketWidth(1201), 1400);
      expect(bucketWidth(100), 400);
      expect(bucketWidth(9000), 3000);
      expect(bucketWidth(9000, max: 4000), 4000);
    });
  });

  group('PKCE', () {
    test('matches the RFC 7636 example', () {
      expect(
        Pkce.challengeFor('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('generates a 64-character verifier from the unreserved alphabet', () {
      final pkce = Pkce.generate(Random(1));
      expect(pkce.verifier, hasLength(64));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(pkce.verifier), isTrue);
      expect(pkce.challenge, Pkce.challengeFor(pkce.verifier));
      expect(pkce.challenge.contains('='), isFalse);
    });
  });

  group('models', () {
    test('a book detail reads its nested game system', () {
      final b = Book.fromJson({
        'id': 'b1',
        'title': 'Core Rules',
        'filename': 'core.pdf',
        'page_count': 320,
        'content_token': 't1',
        'game_system': {'id': 's1', 'name': 'Mothership'},
        'authors': ['A', 3],
      });
      expect(b.systemId, 's1');
      expect(b.systemName, 'Mothership');
      expect(b.isPdf, isTrue);
      expect(b.authors, ['A']);
      expect(Book.fromJson(b.toJson()).contentToken, 't1');
    });

    test('a search book match reads its flat system fields', () {
      final b = Book.fromJson({
        'id': 'b2',
        'title': 'Zine',
        'game_system': 'Cairn',
        'game_system_id': 's9',
        'mime_type': 'application/epub+zip',
      });
      expect(b.systemName, 'Cairn');
      expect(b.systemId, 's9');
      expect(b.isPdf, isFalse);
      expect(b.hasPages, isTrue);
      expect(
        Book.fromJson({'id': 'x', 'title': 't', 'mime_type': 'text/markdown'}).hasPages,
        isFalse,
      );
    });

    test('system detail stamps its books with the system', () {
      final d = SystemDetail.fromJson({
        'id': 's1',
        'name': 'Mothership',
        'container_kind': '',
        'books': [
          {'id': 'b1', 'title': 'Core', 'category': 'core'},
        ],
        'children': [
          {'id': 's2', 'name': 'Child', 'book_count': 2},
        ],
      });
      expect(d.books.single.systemName, 'Mothership');
      expect(d.children.single.bookCount, 2);
      expect(d.system.isContainer, isFalse);
    });

    test('the table of contents flattens depth-first', () {
      final toc = [
        TocEntry.fromJson({
          'title': 'One',
          'page': 1,
          'level': 1,
          'children': [
            {'title': 'One.a', 'page': 2, 'level': 2},
          ],
        }),
        const TocEntry(title: 'Two', page: 9),
      ];
      expect(TocEntry.flatten(toc).map((e) => e.title), ['One', 'One.a', 'Two']);
    });

    test('search results split books and page hits', () {
      final r = SearchResults.fromJson({
        'query': 'fireball',
        'results': [
          {'id': 'b1', 'title': 'Core', 'page_number': 42, 'snippet': 'a <mark>fireball</mark>'},
        ],
        'book_matches': [
          {'id': 'b2', 'title': 'Fireball Zine'},
        ],
      });
      expect(r.pages.single.page, 42);
      expect(r.books.single.title, 'Fireball Zine');
      expect(r.isEmpty, isFalse);
    });
  });

  test('snippets highlight marked matches and unescape entities', () {
    const highlight = TextStyle(fontWeight: FontWeight.bold);
    final spans = snippetSpans('Tom &amp; <mark>Jerry&#x27;s</mark> &lt;cat&gt;', highlight);
    expect(spans.map((s) => s.text), ['Tom & ', "Jerry's", ' <cat>']);
    expect(spans[1].style, highlight);
    expect(spans[0].style, isNull);
  });

  test('formatBytes', () {
    expect(formatBytes(512), '512 B');
    expect(formatBytes(1536), '1.5 KB');
    expect(formatBytes(250 * 1024 * 1024), '250 MB');
  });
}
