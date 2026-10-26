import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Everything needed to talk to one Grimoire server as one user.
///
/// A session authenticates with either a JWT pair or an API key. The JWT pair
/// is the access token plus the `grimoire_refresh` cookie value the server
/// sets on sign-in; the app replays that cookie by hand when it refreshes.
class Session {
  const Session({
    required this.baseUrl,
    this.accessToken,
    this.refreshToken,
    this.apiKey,
    this.user,
  });

  final String baseUrl;
  final String? accessToken;
  final String? refreshToken;
  final String? apiKey;
  final User? user;

  bool get usesApiKey => apiKey != null && apiKey!.isNotEmpty;

  Session copyWith({String? accessToken, String? refreshToken, User? user}) => Session(
    baseUrl: baseUrl,
    accessToken: accessToken ?? this.accessToken,
    refreshToken: refreshToken ?? this.refreshToken,
    apiKey: apiKey,
    user: user ?? this.user,
  );

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    baseUrl: json['base_url'] as String,
    accessToken: json['access_token'] as String?,
    refreshToken: json['refresh_token'] as String?,
    apiKey: json['api_key'] as String?,
    user: json['user'] is Map<String, dynamic>
        ? User.fromJson(json['user'] as Map<String, dynamic>)
        : null,
  );

  Map<String, dynamic> toJson() => {
    'base_url': baseUrl,
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'api_key': apiKey,
    'user': user?.toJson(),
  };
}

/// Normalises what a person types into the server field: adds `https://`
/// when no scheme is given and drops trailing slashes and a pasted `/api`.
String normalizeServerUrl(String input) {
  var url = input.trim();
  if (url.isEmpty) return url;
  if (!url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/api')) url = url.substring(0, url.length - 4);
  return url;
}

/// Persists the session in the platform keychain / keystore.
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'grimoire.session';
  final FlutterSecureStorage _storage;

  Future<Session?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FormatException {
      return null;
    }
  }

  Future<void> save(Session session) =>
      _storage.write(key: _key, value: jsonEncode(session.toJson()));

  Future<void> clear() => _storage.delete(key: _key);
}
