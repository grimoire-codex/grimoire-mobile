import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_mobile/core/api.dart';
import 'package:grimoire_mobile/core/models.dart';
import 'package:grimoire_mobile/core/session.dart';
import 'package:grimoire_mobile/features/characters/host_bridge.dart';

import '../support/fake_server.dart';

void main() {
  group('HostTokenBroker', () {
    late FakeServer server;
    late int refreshes;

    GrimoireApi api({String? apiKey, String? token = 'a1'}) => GrimoireApi(
      Session(
        baseUrl: 'https://grimoire.test',
        accessToken: apiKey == null ? token : null,
        refreshToken: apiKey == null ? 'r1' : null,
        apiKey: apiKey,
      ),
      dio: server.dio(),
    );

    setUp(() {
      server = FakeServer();
      refreshes = 0;
      server.on('POST /api/auth/refresh', (_) async {
        refreshes++;
        return FakeResponse(
          200,
          json: {'token': 'a2', 'user': userJson()},
          headers: {
            'set-cookie': ['grimoire_refresh=r2; Path=/api/auth'],
          },
        );
      });
    });

    test('hands over the current token at start-up without refreshing', () async {
      expect(await HostTokenBroker(api()).token('initial'), 'a1');
      expect(refreshes, 0);
    });

    test('refreshes on behalf of the web view when its token expired', () async {
      final client = api();
      expect(await HostTokenBroker(client).token('expired'), 'a2');
      expect(refreshes, 1);
      expect(client.session.refreshToken, 'r2');
    });

    test('refreshes when the app has no access token yet', () async {
      expect(await HostTokenBroker(api(token: null)).token('initial'), 'a2');
    });

    test('gives nothing for an API-key session or when the server is down', () async {
      expect(await HostTokenBroker(api(apiKey: 'grim_k')).token('initial'), isNull);
      server.offline = true;
      expect(await HostTokenBroker(api()).token('expired'), isNull);
    });
  });

  group('host messages', () {
    test('parse token and close requests', () {
      final token = HostMessage.parse('{"type":"token","id":3,"reason":"expired"}');
      expect(token, isA<TokenRequest>());
      expect((token! as TokenRequest).id, 3);
      expect((token as TokenRequest).reason, 'expired');
      final initial = HostMessage.parse('{"type":"token","id":1}') as TokenRequest;
      expect(initial.reason, 'initial');
      expect(HostMessage.parse('{"type":"close"}'), isA<CloseRequest>());
    });

    test('ignore anything malformed', () {
      expect(HostMessage.parse('not json'), isNull);
      expect(HostMessage.parse('[1]'), isNull);
      expect(HostMessage.parse('{"type":"token","id":"x"}'), isNull);
      expect(HostMessage.parse('{"type":"other"}'), isNull);
    });

    test('replies encode the token safely', () {
      expect(
        replyScript(3, 'a"b'),
        r'window.__grimoireHost && window.__grimoireHost.resolve(3, "a\"b");',
      );
      expect(replyScript(4, null), contains('resolve(4, null)'));
      expect(hostChannelName, 'GrimoireHostChannel');
      expect(hostAwareCheck, 'window.__GRIMOIRE_HOST_AWARE__ === 1');
    });
  });

  test('a character summary reads ownership, portrait and status', () {
    final c = Character.fromJson({
      'id': 'c1',
      'name': 'Vex',
      'schema_name': 'D&D 5e (2014)',
      'campaign_name': 'Curse of Strahd',
      'owned': false,
      'owner_name': 'sam',
      'status': 'dead',
      'portrait_path': 'portraits/c1.webp',
      'portrait_version': 3,
    });
    expect(c.owned, isFalse);
    expect(c.hasPortrait, isTrue);
    expect(c.portraitVersion, 3);
    expect(c.status, 'dead');
    expect(Character.fromJson({'id': 'c2', 'name': 'X'}).hasPortrait, isFalse);
  });

  test('the client lists characters', () async {
    final server = FakeServer()
      ..on(
        'GET /api/characters',
        (_) async => FakeResponse(
          200,
          json: [
            {'id': 'c1', 'name': 'Vex', 'schema_ref': 's'},
          ],
        ),
      );
    final client = GrimoireApi(
      const Session(baseUrl: 'https://grimoire.test', accessToken: 'a'),
      dio: server.dio(),
    );
    expect((await client.characters()).single.name, 'Vex');
  });
}
