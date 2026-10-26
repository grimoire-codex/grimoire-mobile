import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// A PKCE verifier/challenge pair (RFC 7636, S256).
///
/// The server binds the one-time sign-in code it sends to `grimoire://oauth`
/// to [challenge]; only the app holding [verifier] can exchange it, so an app
/// that intercepts the redirect gets nothing usable.
class Pkce {
  Pkce._(this.verifier) : challenge = challengeFor(verifier);

  factory Pkce.generate([Random? random]) => Pkce._(randomToken(64, random));

  final String verifier;
  final String challenge;

  static String challengeFor(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
}

/// A URL-safe random string of [length] characters from the PKCE alphabet.
String randomToken(int length, [Random? random]) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final rng = random ?? Random.secure();
  return List.generate(length, (_) => alphabet[rng.nextInt(alphabet.length)]).join();
}
