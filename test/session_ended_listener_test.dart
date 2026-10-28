import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/config/app_config.dart';
import 'package:startgold/core/security/session_ended_listener.dart';
import 'package:startgold/core/security/session_manager.dart';

/// An unsigned JWT is enough — the app never verifies its own token.
String jwt(Map<String, dynamic> payload) {
  String part(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(payload)}.signature';
}

// sha256("abc") — what the backend's hashlib.sha256(b"abc").hexdigest() sends.
const abcHash =
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

void main() {
  group('SessionEndedListener.sessionIdOf', () {
    test('reads the session_id claim', () {
      expect(SessionEndedListener.sessionIdOf(jwt({'session_id': 's-1'})),
          's-1');
    });

    test('is null for a missing token, a token without the claim, or junk',
        () {
      expect(SessionEndedListener.sessionIdOf(null), isNull);
      expect(SessionEndedListener.sessionIdOf(jwt({'user_id': 7})), isNull);
      expect(SessionEndedListener.sessionIdOf('not.a.jwt'), isNull);
      expect(SessionEndedListener.sessionIdOf('access'), isNull);
    });
  });

  group('SessionEndedListener.isThisSession', () {
    tearDown(() {
      SessionManager.endLogin();
      SessionManager.resetForceLogout();
    });

    void loggedInWithSession(String sessionId) {
      FlutterSecureStorage.setMockInitialValues({
        AppConfig.keyAccessToken: jwt({'session_id': sessionId}),
      });
    }

    test('matches the sha256 of this device\'s session_id', () async {
      loggedInWithSession('abc');
      expect(await SessionEndedListener.isThisSession(abcHash), isTrue);
    });

    test('ignores another device\'s session', () async {
      loggedInWithSession('xyz');
      expect(await SessionEndedListener.isThisSession(abcHash), isFalse);
    });

    test('ignores everything when logged out', () async {
      FlutterSecureStorage.setMockInitialValues({});
      expect(await SessionEndedListener.isThisSession(abcHash), isFalse);
    });

    test('ignores this device\'s old session while it is logging in again',
        () async {
      loggedInWithSession('abc');
      SessionManager.beginLogin();
      expect(await SessionEndedListener.isThisSession(abcHash), isFalse);
    });

    test('does nothing once a 409 has already logged it out', () async {
      loggedInWithSession('abc');
      await SessionManager.forceLogout();
      loggedInWithSession('abc');
      expect(await SessionEndedListener.isThisSession(abcHash), isFalse);
    });
  });
}
