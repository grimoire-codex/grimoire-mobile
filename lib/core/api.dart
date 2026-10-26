import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'models.dart';
import 'session.dart';

const _userAgent = 'Grimoire Mobile';
const _refreshCookie = 'grimoire_refresh';

/// What the login screen needs to know about a server before signing in.
class ServerInfo {
  const ServerInfo({
    required this.initialized,
    required this.passwordAuth,
    required this.oidc,
    this.oidcMobile = false,
    this.oidcButtonText,
    this.loginMessage,
  });

  final bool initialized;
  final bool passwordAuth;
  final bool oidc;

  /// The server can hand an OIDC sign-in back to the app. Older servers
  /// don't report this; their SSO only completes in a web browser.
  final bool oidcMobile;
  final String? oidcButtonText;
  final String? loginMessage;
}

/// Where the server sends the system browser once OIDC sign-in finishes.
const oidcCallbackScheme = 'grimoire';
const oidcRedirectUri = '$oidcCallbackScheme://oauth';

/// Pulls one cookie's value out of a response's `Set-Cookie` headers.
String? extractCookie(List<String>? setCookies, String name) {
  if (setCookies == null) return null;
  for (final header in setCookies) {
    final pair = header.split(';').first.trim();
    final eq = pair.indexOf('=');
    if (eq > 0 && pair.substring(0, eq) == name) {
      final value = pair.substring(eq + 1);
      return value.isEmpty ? null : value;
    }
  }
  return null;
}

/// True for failures that mean "couldn't reach the server", as opposed to the
/// server answering with an error.
bool isNetworkError(Object error) =>
    error is DioException &&
    (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        (error.type == DioExceptionType.unknown && error.response == null));

/// A short message for a failed request, preferring the server's own words.
String describeError(Object error) {
  if (error is DioException) {
    if (isNetworkError(error)) return 'Could not reach the server.';
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'] ?? data['error'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    final code = error.response?.statusCode;
    if (code == 401) return 'Your sign-in has expired.';
    if (code == 403) return 'You do not have access to that.';
    if (code == 404) return 'Not found.';
    if (code != null) return 'The server answered $code.';
  }
  return '$error';
}

Dio _bareDio(String baseUrl) => Dio(
  BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'User-Agent': _userAgent},
  ),
);

/// Client for one signed-in Grimoire session.
///
/// Mirrors the web client's auth handling: an expired access token (a 401
/// carrying `X-Token-Expired`) is refreshed once and the request replayed, and
/// concurrent 401s share a single refresh because refresh tokens are
/// single-use - two parallel exchanges would revoke the whole session.
class GrimoireApi {
  GrimoireApi(
    Session session, {
    Dio? dio,
    this.onSessionChanged,
    this.onSessionExpired,
    this.onReachable,
  }) : _session = session,
       _dio = dio ?? _bareDio(session.baseUrl) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: _attachAuth,
        onResponse: (response, handler) {
          onReachable?.call(true);
          handler.next(response);
        },
        onError: _onError,
      ),
    );
  }

  final Dio _dio;
  Session _session;
  Future<bool>? _refreshing;

  /// Called with the new session whenever tokens rotate.
  final void Function(Session session)? onSessionChanged;

  /// Called when the session can no longer be refreshed.
  final void Function()? onSessionExpired;

  /// Called after each request with whether the server answered at all.
  final void Function(bool reachable)? onReachable;

  Session get session => _session;
  String get baseUrl => _session.baseUrl;

  // ---- Signing in (no session yet) ----

  static Future<ServerInfo> probe(String baseUrl, {Dio? dio}) async {
    final client = dio ?? _bareDio(baseUrl);
    final status = await client.get<Map<String, dynamic>>('/api/auth/status');
    final config = await client.get<Map<String, dynamic>>('/api/auth/config');
    final c = config.data ?? const {};
    return ServerInfo(
      initialized: status.data?['initialized'] as bool? ?? true,
      passwordAuth: c['password_auth_enabled'] as bool? ?? true,
      oidc: c['oidc_enabled'] as bool? ?? false,
      oidcMobile: c['oidc_mobile_enabled'] as bool? ?? false,
      oidcButtonText: c['oidc_button_text'] as String?,
      loginMessage: c['custom_login_message'] as String?,
    );
  }

  static Future<Session> login(String baseUrl, String username, String password, {Dio? dio}) async {
    final client = dio ?? _bareDio(baseUrl);
    final response = await client.post<Map<String, dynamic>>(
      '/api/auth/login',
      data: {'username': username, 'password': password},
    );
    return Session(
      baseUrl: baseUrl,
      accessToken: response.data?['token'] as String?,
      refreshToken: extractCookie(response.headers['set-cookie'], _refreshCookie),
      user: User.fromJson(response.data?['user'] as Map<String, dynamic>),
    );
  }

  /// The page that starts an OIDC sign-in in the system browser.
  static Uri oidcLoginUrl(String baseUrl, {required String challenge, required String state}) =>
      Uri.parse('$baseUrl/api/auth/openid/login').replace(
        queryParameters: {
          'redirect_uri': oidcRedirectUri,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );

  /// Trades the one-time code from the OIDC redirect for a session.
  static Future<Session> exchangeOidcCode(
    String baseUrl,
    String code,
    String verifier, {
    Dio? dio,
  }) async {
    final client = dio ?? _bareDio(baseUrl);
    final response = await client.post<Map<String, dynamic>>(
      '/api/auth/openid/mobile-token',
      data: {'code': code, 'code_verifier': verifier},
    );
    return Session(
      baseUrl: baseUrl,
      accessToken: response.data?['token'] as String?,
      refreshToken: extractCookie(response.headers['set-cookie'], _refreshCookie),
      user: User.fromJson(response.data?['user'] as Map<String, dynamic>),
    );
  }

  static Future<Session> loginWithApiKey(String baseUrl, String apiKey, {Dio? dio}) async {
    final client = dio ?? _bareDio(baseUrl);
    final response = await client.get<Map<String, dynamic>>(
      '/api/auth/me',
      options: Options(headers: {'X-API-Key': apiKey}),
    );
    return Session(baseUrl: baseUrl, apiKey: apiKey, user: User.fromJson(response.data!));
  }

  // ---- Auth plumbing ----

  void _attachAuth(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra['noAuth'] != true) {
      if (_session.usesApiKey) {
        options.headers['X-API-Key'] = _session.apiKey;
      } else if (_session.accessToken != null) {
        options.headers['Authorization'] = 'Bearer ${_session.accessToken}';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(DioException err, ErrorInterceptorHandler handler) async {
    onReachable?.call(!isNetworkError(err));
    final options = err.requestOptions;
    final canRefresh =
        err.response?.statusCode == 401 &&
        options.extra['noAuth'] != true &&
        options.extra['retried'] != true &&
        !_session.usesApiKey &&
        _session.refreshToken != null;
    if (!canRefresh) {
      if (err.response?.statusCode == 401 && options.extra['noAuth'] != true) {
        onSessionExpired?.call();
      }
      return handler.next(err);
    }
    final bool refreshed;
    try {
      refreshed = await refresh();
    } on DioException {
      // The server went away mid-refresh; surface the original failure.
      return handler.next(err);
    }
    if (!refreshed) {
      onSessionExpired?.call();
      return handler.next(err);
    }
    options.extra['retried'] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Exchanges the refresh token for a new access token. Concurrent callers
  /// share one exchange.
  Future<bool> refresh() => _refreshing ??= _doRefresh().whenComplete(() {
    _refreshing = null;
  });

  Future<bool> _doRefresh() async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/auth/refresh',
        options: Options(
          headers: {'Cookie': '$_refreshCookie=${_session.refreshToken}'},
          extra: {'noAuth': true},
        ),
      );
      final token = response.data?['token'] as String?;
      if (token == null) return false;
      _session = _session.copyWith(
        accessToken: token,
        refreshToken: extractCookie(response.headers['set-cookie'], _refreshCookie),
        user: response.data?['user'] is Map<String, dynamic>
            ? User.fromJson(response.data!['user'] as Map<String, dynamic>)
            : null,
      );
      onSessionChanged?.call(_session);
      return true;
    } on DioException catch (e) {
      // Offline is not the same as signed out: keep the refresh token so the
      // next attempt can succeed once the server is reachable again.
      if (isNetworkError(e)) rethrow;
      return false;
    }
  }

  Future<void> logout() async {
    if (_session.usesApiKey || _session.refreshToken == null) return;
    await _dio.post<void>(
      '/api/auth/logout',
      options: Options(
        headers: {'Cookie': '$_refreshCookie=${_session.refreshToken}'},
        extra: {'noAuth': true},
      ),
    );
  }

  // ---- Reachability ----

  /// Unauthenticated, cheap readiness probe.
  Future<bool> ping() async {
    try {
      final response = await _dio.get<dynamic>(
        '/api/health',
        options: Options(
          extra: {'noAuth': true},
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 4),
        ),
      );
      return response.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  // ---- Library ----

  Future<User> me() async {
    final r = await _dio.get<Map<String, dynamic>>('/api/auth/me');
    return User.fromJson(r.data!);
  }

  Future<List<GameSystem>> systems() async {
    final r = await _dio.get<List<dynamic>>(
      '/api/systems',
      queryParameters: {'sort': 'name', 'order': 'asc'},
    );
    return [for (final s in r.data ?? const []) GameSystem.fromJson(s as Map<String, dynamic>)];
  }

  Future<SystemDetail> system(String id) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/api/systems/$id',
      queryParameters: {'book_sort': 'category'},
    );
    return SystemDetail.fromJson(r.data!);
  }

  Future<Book> book(String id) async {
    final r = await _dio.get<Map<String, dynamic>>('/api/books/$id');
    return Book.fromJson(r.data!);
  }

  Future<List<Book>> recentlyAdded({int limit = 20}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/api/books',
      queryParameters: {'sort': 'added_at', 'order': 'desc', 'limit': limit},
    );
    return [
      for (final b in (r.data?['books'] as List? ?? const []))
        Book.fromJson(b as Map<String, dynamic>),
    ];
  }

  Future<List<TocEntry>> toc(String bookId) async {
    try {
      final r = await _dio.get<List<dynamic>>('/api/books/$bookId/toc');
      return [for (final e in r.data ?? const []) TocEntry.fromJson(e as Map<String, dynamic>)];
    } on DioException catch (e) {
      // Formats without a table of contents answer 404.
      if (e.response?.statusCode == 404) return const [];
      rethrow;
    }
  }

  Future<SearchResults> search(String query, {int limit = 40}) async {
    final r = await _dio.get<Map<String, dynamic>>(
      '/api/search',
      queryParameters: {'q': query, 'limit': limit},
    );
    return SearchResults.fromJson(r.data!);
  }

  // ---- Characters ----

  /// Your own characters plus those in campaigns you belong to.
  Future<List<Character>> characters() async {
    final r = await _dio.get<List<dynamic>>('/api/characters');
    return [for (final c in r.data ?? const []) Character.fromJson(c as Map<String, dynamic>)];
  }

  // ---- Bookmarks ----

  Future<List<Bookmark>> bookmarks(String bookId) async {
    final r = await _dio.get<List<dynamic>>('/api/bookmarks', queryParameters: {'book_id': bookId});
    return [for (final b in r.data ?? const []) Bookmark.fromJson(b as Map<String, dynamic>)];
  }

  Future<Bookmark> addBookmark(String bookId, int page, {String? label}) async {
    final r = await _dio.post<Map<String, dynamic>>(
      '/api/bookmarks',
      data: {'book_id': bookId, 'page_number': page, 'label': ?label},
    );
    return Bookmark.fromJson(r.data!);
  }

  Future<void> deleteBookmark(String id) => _dio.delete<void>('/api/bookmarks/$id');

  // ---- Binary content ----

  Future<Uint8List> _bytes(String path, [Map<String, dynamic>? query]) async {
    final r = await _dio.get<List<int>>(
      path,
      queryParameters: query,
      options: Options(
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );
    final data = r.data!;
    return data is Uint8List ? data : Uint8List.fromList(data);
  }

  /// A page rendered by the server (WebP, or a comic's stored image).
  Future<Uint8List> pageImage(String bookId, int page, int width, {String? version}) =>
      _bytes('/api/books/$bookId/page/$page', {'width': width, 'v': ?version});

  Future<Uint8List> bookThumbnail(String bookId) => _bytes('/api/books/$bookId/thumbnail');

  Future<Uint8List> systemCover(String systemId) => _bytes('/api/systems/$systemId/cover');

  Future<Uint8List> characterPortrait(String characterId, {int? version}) =>
      _bytes('/api/characters/$characterId/portrait', {'v': ?version});

  /// Streams the original file to [savePath].
  Future<void> downloadFile(
    String bookId,
    String savePath, {
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) => _dio.download(
    '/api/books/$bookId/file',
    savePath,
    onReceiveProgress: onProgress,
    cancelToken: cancelToken,
    options: Options(receiveTimeout: const Duration(minutes: 5)),
  );
}
