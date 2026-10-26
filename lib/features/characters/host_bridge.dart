import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/api.dart';

/// The bridge between a sheet web view and the app (protocol version 1).
///
/// Grimoire's web client normally refreshes its access token itself with the
/// `grimoire_refresh` cookie. Inside the app it must not: refresh tokens are
/// single-use, so the web view and the app refreshing the same session would
/// look like a replay and revoke it. So the app exposes a JavaScript channel
/// named [hostChannelName]; a Grimoire that sees it asks the app for tokens
/// instead and marks itself with `window.__GRIMOIRE_HOST_AWARE__ = 1`.
///
/// Web → app messages (JSON strings on the channel):
///   `{"type": "token", "id": 3, "reason": "initial" | "expired"}`
///   `{"type": "close"}`
/// App → web replies run [replyScript]:
///   `window.__grimoireHost.resolve(3, "<token>" | null)`
const hostChannelName = 'GrimoireHostChannel';

const hostAwareCheck = 'window.__GRIMOIRE_HOST_AWARE__ === 1';

sealed class HostMessage {
  const HostMessage();

  /// Null for anything that isn't a well-formed message.
  static HostMessage? parse(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      switch (json['type']) {
        case 'token':
          final id = json['id'];
          if (id is! int) return null;
          return TokenRequest(id, json['reason'] == 'expired' ? 'expired' : 'initial');
        case 'close':
          return const CloseRequest();
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}

class TokenRequest extends HostMessage {
  const TokenRequest(this.id, this.reason);

  final int id;
  final String reason;
}

class CloseRequest extends HostMessage {
  const CloseRequest();
}

/// The JavaScript that answers token request [id]. The token is JSON-encoded,
/// so nothing in it can break out of the string.
String replyScript(int id, String? token) =>
    'window.__grimoireHost && window.__grimoireHost.resolve($id, ${jsonEncode(token)});';

/// Hands the web view access tokens from the app's own session.
class HostTokenBroker {
  HostTokenBroker(this.api);

  final GrimoireApi api;

  /// Null for API-key sessions, which have no token the web client could use.
  Future<String?> token(String reason) async {
    final session = api.session;
    if (session.usesApiKey) return null;
    if (reason == 'expired' || session.accessToken == null) {
      try {
        if (!await api.refresh()) return null;
      } on DioException {
        return null;
      }
    }
    return api.session.accessToken;
  }
}
