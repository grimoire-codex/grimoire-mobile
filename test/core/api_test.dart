import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grimoire_mobile/core/api.dart';
import 'package:grimoire_mobile/core/session.dart';

import '../support/fake_server.dart';

void main() {
  group('extractCookie', () {
    test('finds the named cookie among several headers', () {
      final headers = [
        'grimoire_session=abc; Path=/; HttpOnly',
        'grimoire_refresh=r1; Path=/api/auth; HttpOnly; SameSite=Strict',
      ];
      expect(extractCookie(headers, 'grimoire_refresh'), 'r1');
      expect(extractCookie(headers, 'grimoire_session'), 'abc');
    });

    test('is null when missing, empty (a cleared cookie) or no headers', () {
      expect(extractCookie(['other=1'], 'grimoire_refresh'), isNull);
      expect(extractCookie(['grimoire_refresh=; Max-Age=0'], 'grimoire_refresh'), isNull);
      expect(extractCookie(null, 'grimoire_refresh'), isNull);
    });
  });

  group('normalizeServerUrl', () {
    test('adds https, strips slashes and a pasted /api', () {
      expect(normalizeServerUrl('grimoire.example.com'), 'https://grimoire.example.com');
      expect(normalizeServerUrl(' http://10.0.0.5:9481/ '), 'http://10.0.0.5:9481');
      expect(normalizeServerUrl('https://g.example.com/api/'), 'https://g.example.com');
      expect(normalizeServerUrl(''), '');
    });
  });

  group('describeError', () {
    RequestOptions req() => RequestOptions(path: '/x');

    test('prefers the server detail', () {
      final e = DioException(
        requestOptions: req(),
        response: Response(requestOptions: req(), statusCode: 400, data: {'detail': 'Bad code'}),
      );
      expect(describeError(e), 'Bad code');
    });

    test('names network failures', () {
      final e = DioException.connectionError(requestOptions: req(), reason: 'down');
      expect(isNetworkError(e), isTrue);
      expect(describeError(e), 'Could not reach the server.');
    });

    test('falls back to the status code', () {
      final e = DioException(
        requestOptions: req(),
        response: Response(requestOptions: req(), statusCode: 404),
      );
      expect(isNetworkError(e), isFalse);
      expect(describeError(e), 'Not found.');
    });
  });

  group('signing in', () {
    late FakeServer server;
    setUp(() => server = FakeServer());

    test('login keeps the access token and the refresh cookie', () async {
      server.on('POST /api/auth/login', (r) async {
        expect(r.data, {'username': 'alice', 'password': 'pw'});
        return FakeResponse(
          200,
          json: {'token': 'a1', 'user': userJson()},
          headers: {
            'set-cookie': ['grimoire_refresh=r1; Path=/api/auth; HttpOnly'],
          },
        );
      });
      final s = await GrimoireApi.login('https://grimoire.test', 'alice', 'pw', dio: server.dio());
      expect(s.accessToken, 'a1');
      expect(s.refreshToken, 'r1');
      expect(s.user!.username, 'alice');
      expect(s.usesApiKey, isFalse);
    });

    test('an API key is checked against /api/auth/me', () async {
      server.on('GET /api/auth/me', (r) async {
        expect(r.headers['X-API-Key'], 'grim_k');
        return FakeResponse(200, json: userJson());
      });
      final s = await GrimoireApi.loginWithApiKey(
        'https://grimoire.test',
        'grim_k',
        dio: server.dio(),
      );
      expect(s.usesApiKey, isTrue);
      expect(s.user!.id, 'u1');
    });

    test('probe reads setup state and sign-in options', () async {
      server.on(
        'GET /api/auth/status',
        (_) async => FakeResponse(200, json: {'initialized': true}),
      );
      server.on(
        'GET /api/auth/config',
        (_) async => FakeResponse(
          200,
          json: {
            'password_auth_enabled': false,
            'oidc_enabled': true,
            'oidc_mobile_enabled': true,
            'oidc_button_text': 'Authentik',
          },
        ),
      );
      final info = await GrimoireApi.probe('https://grimoire.test', dio: server.dio());
      expect(info.initialized, isTrue);
      expect(info.passwordAuth, isFalse);
      expect(info.oidcMobile, isTrue);
      expect(info.oidcButtonText, 'Authentik');
    });

    test('an older server reports no mobile OIDC', () async {
      server.on(
        'GET /api/auth/status',
        (_) async => FakeResponse(200, json: {'initialized': true}),
      );
      server.on(
        'GET /api/auth/config',
        (_) async => FakeResponse(200, json: {'oidc_enabled': true}),
      );
      final info = await GrimoireApi.probe('https://grimoire.test', dio: server.dio());
      expect(info.oidc, isTrue);
      expect(info.oidcMobile, isFalse);
    });

    test('OIDC starts with a PKCE challenge and the app redirect', () {
      final url = GrimoireApi.oidcLoginUrl('https://g.test', challenge: 'C', state: 'S');
      expect(url.path, '/api/auth/openid/login');
      expect(url.queryParameters, {
        'redirect_uri': 'grimoire://oauth',
        'code_challenge': 'C',
        'code_challenge_method': 'S256',
        'state': 'S',
      });
    });

    test('the OIDC code is exchanged with the verifier', () async {
      server.on('POST /api/auth/openid/mobile-token', (r) async {
        expect(r.data, {'code': 'one-time', 'code_verifier': 'V'});
        return FakeResponse(
          200,
          json: {'token': 'a1', 'user': userJson()},
          headers: {
            'set-cookie': ['grimoire_refresh=r9; Path=/api/auth'],
          },
        );
      });
      final s = await GrimoireApi.exchangeOidcCode(
        'https://grimoire.test',
        'one-time',
        'V',
        dio: server.dio(),
      );
      expect(s.accessToken, 'a1');
      expect(s.refreshToken, 'r9');
    });
  });

  group('session client', () {
    late FakeServer server;
    late List<Session> rotated;
    late int expired;
    late List<bool> reachability;

    GrimoireApi client({String? apiKey}) {
      rotated = [];
      expired = 0;
      reachability = [];
      return GrimoireApi(
        Session(
          baseUrl: 'https://grimoire.test',
          accessToken: apiKey == null ? 'old' : null,
          refreshToken: apiKey == null ? 'r1' : null,
          apiKey: apiKey,
          user: null,
        ),
        dio: server.dio(),
        onSessionChanged: rotated.add,
        onSessionExpired: () => expired++,
        onReachable: reachability.add,
      );
    }

    setUp(() => server = FakeServer());

    test('sends the bearer token', () async {
      server.on('GET /api/auth/me', (r) async {
        expect(r.headers['Authorization'], 'Bearer old');
        return FakeResponse(200, json: userJson());
      });
      await client().me();
      expect(reachability, [true]);
    });

    test('sends an API key instead of a token', () async {
      server.on('GET /api/auth/me', (r) async {
        expect(r.headers['X-API-Key'], 'grim_k');
        expect(r.headers.containsKey('Authorization'), isFalse);
        return FakeResponse(200, json: userJson());
      });
      await client(apiKey: 'grim_k').me();
    });

    test('concurrent 401s share one refresh, then replay with the new token', () async {
      var refreshes = 0;
      server.on('POST /api/auth/refresh', (r) async {
        refreshes++;
        expect(r.headers['Cookie'], 'grimoire_refresh=r1');
        expect(r.headers.containsKey('Authorization'), isFalse);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return FakeResponse(
          200,
          json: {'token': 'new', 'user': userJson()},
          headers: {
            'set-cookie': ['grimoire_refresh=r2; Path=/api/auth'],
          },
        );
      });
      server.on('GET /api/auth/me', (r) async {
        if (r.headers['Authorization'] == 'Bearer new') {
          return FakeResponse(200, json: userJson());
        }
        return FakeResponse(
          401,
          json: {'detail': 'expired'},
          headers: {
            'x-token-expired': ['1'],
          },
        );
      });

      final api = client();
      final users = await Future.wait([api.me(), api.me(), api.me()]);
      expect(users, hasLength(3));
      expect(refreshes, 1);
      expect(api.session.accessToken, 'new');
      expect(api.session.refreshToken, 'r2');
      expect(rotated.single.refreshToken, 'r2');
      expect(expired, 0);
    });

    test('a refused refresh ends the session', () async {
      server.on(
        'POST /api/auth/refresh',
        (_) async => FakeResponse(401, json: {'detail': 'revoked'}),
      );
      server.on('GET /api/auth/me', (_) async => FakeResponse(401, json: {'detail': 'expired'}));
      final api = client();
      await expectLater(api.me(), throwsA(isA<DioException>()));
      expect(expired, 1);
      expect(rotated, isEmpty);
    });

    test('going offline is not signing out', () async {
      server.offline = true;
      final api = client();
      await expectLater(api.me(), throwsA(isA<DioException>()));
      expect(expired, 0);
      expect(reachability, [false]);
      expect(await api.ping(), isFalse);
    });

    test('ping is unauthenticated', () async {
      server.on('GET /api/health', (r) async {
        expect(r.headers.containsKey('Authorization'), isFalse);
        return FakeResponse(200, json: {'status': 'ok'});
      });
      expect(await client().ping(), isTrue);
    });

    test('page images are fetched at the requested width and version', () async {
      server.on('GET /api/books/b1/page/3', (r) async {
        expect(r.uri.queryParameters, {'width': '1200', 'v': 'tok'});
        return FakeResponse(200, bytes: [1, 2, 3]);
      });
      expect(await client().pageImage('b1', 3, 1200, version: 'tok'), [1, 2, 3]);
    });

    test('a missing table of contents is empty, not an error', () async {
      expect(await client().toc('b1'), isEmpty);
    });

    test('logout replays the refresh cookie', () async {
      String? cookie;
      server.on('POST /api/auth/logout', (r) async {
        cookie = r.headers['Cookie'] as String?;
        return FakeResponse(200, json: {'ok': true});
      });
      await client().logout();
      expect(cookie, 'grimoire_refresh=r1');
    });
  });
}
