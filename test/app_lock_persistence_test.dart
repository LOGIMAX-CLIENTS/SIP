import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/config/app_config.dart';
import 'package:startgold/core/security/api_interceptor.dart';
import 'package:startgold/core/security/secure_storage_service.dart';

void main() {
  const storage = FlutterSecureStorage();

  // A logged-in customer 42 with MPIN, biometric and a 5-min auto-lock.
  Map<String, String> loggedIn({String customerId = '42'}) => {
        AppConfig.keyAccessToken: 'access',
        AppConfig.keyRefreshToken: 'refresh',
        AppConfig.keyCustomerId: customerId,
        AppConfig.keyIsMpinEnabled: 'true',
        AppConfig.keyIsBiometricEnabled: 'true',
        AppConfig.keyMpinLockTimeoutSeconds: '300',
        'persistent_device_id': 'device-1',
      };

  group('SecureStorageService.endExpiredSession', () {
    test('ends the session but keeps biometric and auto-lock', () async {
      FlutterSecureStorage.setMockInitialValues(loggedIn());

      await SecureStorageService.endExpiredSession();

      expect(await SecureStorageService.getToken(), isNull);
      expect(await SecureStorageService.getRefreshToken(), isNull);
      expect(await SecureStorageService.getCustomerId(), isNull);
      expect(await SecureStorageService.isMpinEnabled(), isFalse);
      expect(await SecureStorageService.isBiometricEnabled(), isTrue);
      expect(await SecureStorageService.getMpinLockTimeoutSeconds(), 300);
      expect(await storage.read(key: 'persistent_device_id'), 'device-1');
      expect(await storage.read(key: AppConfig.keyAppLockOwnerId), '42');
    });

    test('wipes everything when it cannot tell whose choices they are',
        () async {
      FlutterSecureStorage.setMockInitialValues(
          loggedIn()..remove(AppConfig.keyCustomerId));

      await SecureStorageService.endExpiredSession();

      expect(await SecureStorageService.isBiometricEnabled(), isFalse);
      expect(await storage.read(key: AppConfig.keyMpinLockTimeoutSeconds),
          isNull);
      expect(await storage.read(key: AppConfig.keyAppLockOwnerId), isNull);
      expect(await storage.read(key: 'persistent_device_id'), 'device-1');
    });
  });

  test('logout still wipes biometric and auto-lock', () async {
    FlutterSecureStorage.setMockInitialValues(loggedIn());

    await SecureStorageService.logout();

    expect(await SecureStorageService.getToken(), isNull);
    expect(await SecureStorageService.isBiometricEnabled(), isFalse);
    expect(
        await storage.read(key: AppConfig.keyMpinLockTimeoutSeconds), isNull);
    expect(await storage.read(key: 'persistent_device_id'), 'device-1');
  });

  group('SecureStorageService.keepAppLockPrefsOnlyFor', () {
    test('the same customer logging back in gets their choices back',
        () async {
      FlutterSecureStorage.setMockInitialValues(loggedIn());
      await SecureStorageService.endExpiredSession();

      await SecureStorageService.keepAppLockPrefsOnlyFor('42');

      expect(await SecureStorageService.isBiometricEnabled(), isTrue);
      expect(await SecureStorageService.getMpinLockTimeoutSeconds(), 300);
      expect(await storage.read(key: AppConfig.keyAppLockOwnerId), isNull);
    });

    test('a different customer starts with them off', () async {
      FlutterSecureStorage.setMockInitialValues(loggedIn());
      await SecureStorageService.endExpiredSession();

      await SecureStorageService.keepAppLockPrefsOnlyFor('77');

      expect(await SecureStorageService.isBiometricEnabled(), isFalse);
      expect(await storage.read(key: AppConfig.keyMpinLockTimeoutSeconds),
          isNull);
      expect(await storage.read(key: AppConfig.keyAppLockOwnerId), isNull);
    });

    test('falls back to the stored customer id when nothing was tagged',
        () async {
      FlutterSecureStorage.setMockInitialValues(loggedIn());

      await SecureStorageService.keepAppLockPrefsOnlyFor('77');

      expect(await SecureStorageService.isBiometricEnabled(), isFalse);
    });

    test('a fresh install has nothing to drop', () async {
      FlutterSecureStorage.setMockInitialValues({});

      await SecureStorageService.keepAppLockPrefsOnlyFor('77');

      expect(await SecureStorageService.isBiometricEnabled(), isFalse);
    });
  });

  group('ApiSecurityInterceptor.isTransientRefreshFailure', () {
    bool transient(int? status, [Object? body]) =>
        ApiSecurityInterceptor.isTransientRefreshFailure(
            statusCode: status, body: body);
    Map<String, dynamic> failure(String code) => {
          'success': false,
          'error': {'code': code, 'message': '...'},
        };

    test('no answer from the server keeps the session', () {
      // Offline, timeout, TLS/pinning failure: Dio has no response at all.
      expect(transient(null), isTrue);
    });

    test('a 5xx keeps the session', () {
      expect(transient(500), isTrue);
      expect(transient(502), isTrue);
      expect(transient(503), isTrue);
    });

    test('a throttled refresh keeps the session', () {
      // The backend rewrites its 429 to HTTP 200.
      expect(transient(200, failure('TOO_MANY_REQUESTS')), isTrue);
      expect(transient(429), isTrue);
    });

    test('the server rejecting the refresh token ends it', () {
      expect(transient(401, failure('TOKEN_REFRESH_FAILED')), isFalse);
      expect(transient(401), isFalse);
      expect(transient(400), isFalse);
      expect(transient(403), isFalse);
      expect(transient(200, failure('TOKEN_REQUIRED')), isFalse);
      expect(transient(200, {'success': true, 'data': {}}), isFalse);
    });
  });
}
