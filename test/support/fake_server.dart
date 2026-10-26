import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// A canned response for [FakeServer].
class FakeResponse {
  FakeResponse(this.status, {Object? json, this.bytes, this.headers = const {}})
    : body = json == null ? null : jsonEncode(json);

  final int status;
  final String? body;
  final List<int>? bytes;
  final Map<String, List<String>> headers;
}

typedef Handler = Future<FakeResponse> Function(RequestOptions request);

/// Routes requests to handlers by "METHOD /path" and records every request.
class FakeServer implements HttpClientAdapter {
  final routes = <String, Handler>{};
  final requests = <RequestOptions>[];

  /// When set, every request fails as if the network were down.
  bool offline = false;

  void on(String route, Handler handler) => routes[route] = handler;

  Dio dio([String baseUrl = 'https://grimoire.test']) =>
      Dio(BaseOptions(baseUrl: baseUrl))..httpClientAdapter = this;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final handler = routes['${options.method} ${options.uri.path}'];
    if (handler == null) return ResponseBody.fromString('{"detail":"Not Found"}', 404);
    final r = await handler(options);
    final headers = {
      ...r.headers,
      if (r.body != null) 'content-type': ['application/json'],
    };
    if (r.bytes != null) {
      return ResponseBody.fromBytes(r.bytes!, r.status, headers: headers);
    }
    return ResponseBody.fromString(r.body ?? '', r.status, headers: headers);
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> userJson([String name = 'alice']) => {
  'id': 'u1',
  'username': name,
  'role': 'player',
  'display_name': null,
};
