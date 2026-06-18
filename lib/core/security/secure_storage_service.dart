import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/app_config.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static Future<void> saveToken(String token) async {
    await _storage.write(key: AppConfig.keyAccessToken, value: token);
  }

  static Future<void> saveRefreshToken(String token) async {
    await _storage.write(key: AppConfig.keyRefreshToken, value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: AppConfig.keyAccessToken);
  }

  static Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConfig.keyRefreshToken);
  }

  static Future<bool> isMpinEnabled() async {
    final value = await _storage.read(key: AppConfig.keyIsMpinEnabled);
    return value == 'true';
  }

  static Future<void> setMpinEnabled(bool enabled) async {
    await _storage.write(
        key: AppConfig.keyIsMpinEnabled, value: enabled.toString());
  }

  static Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: AppConfig.keyIsBiometricEnabled);
    return value == 'true';
  }

  static Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
        key: AppConfig.keyIsBiometricEnabled, value: enabled.toString());
  }

  static Future<bool> getOnboardingSeen() async {
    final value = await _storage.read(key: AppConfig.keyHasSeenOnboarding);
    return value == 'true';
  }

  static Future<void> setOnboardingSeen(bool seen) async {
    await _storage.write(
        key: AppConfig.keyHasSeenOnboarding, value: seen.toString());
  }

  static Future<void> saveCustomerId(String id) async {
    await _storage.write(key: AppConfig.keyCustomerId, value: id);
  }

  static Future<String?> getCustomerId() async {
    return await _storage.read(key: AppConfig.keyCustomerId);
  }

  static Future<void> saveCustomerName(String name) async {
    await _storage.write(key: AppConfig.keyCustomerName, value: name);
  }

  static Future<String?> getCustomerName() async {
    return await _storage.read(key: AppConfig.keyCustomerName);
  }

  static Future<void> saveCustomerPhoto(String url) async {
    await _storage.write(key: AppConfig.keyCustomerPhoto, value: url);
  }

  static Future<String?> getCustomerPhoto() async {
    return await _storage.read(key: AppConfig.keyCustomerPhoto);
  }

  // ── RSA Public Key Cache ──────────────────────────────────────────────────
  static Future<void> saveServerPublicKey(String pem) async {
    await _storage.write(key: AppConfig.keyServerPublicKey, value: pem);
  }

  static Future<String?> getServerPublicKey() async {
    return await _storage.read(key: AppConfig.keyServerPublicKey);
  }
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> saveMobile(String mobile) async {
    await _storage.write(key: AppConfig.keyMobileNumber, value: mobile);
  }

  static Future<String?> getMobile() async {
    return await _storage.read(key: AppConfig.keyMobileNumber);
  }

  // ── FCM Token Cache ───────────────────────────────────────────────────────
  static Future<void> saveFcmToken(String token) async {
    await _storage.write(key: AppConfig.keyFcmToken, value: token);
  }

  static Future<String?> getFcmToken() async {
    return await _storage.read(key: AppConfig.keyFcmToken);
  }
  // ─────────────────────────────────────────────────────────────────────────

  /// Clears all session data but preserves keys that must survive
  /// across login/logout cycles (device identity, onboarding flag).
  ///
  /// **Why not `deleteAll()`?**
  /// DeviceIdService stores `persistent_device_id` and
  /// `persistent_device_type` in the same FlutterSecureStorage instance.
  /// Wiping them causes a new UUID to be generated on next login, making
  /// the server treat the same physical device as a "new device" — which
  /// triggers spurious 409 SESSION_INVALIDATED errors on other devices.
  static Future<void> logout() async {
    // Keys that MUST survive logout
    const preserveKeys = [
      'persistent_device_id',
      'persistent_device_type',
      AppConfig.keyHasSeenOnboarding,
    ];

    // 1. Read values to preserve
    final preserved = <String, String>{};
    for (final key in preserveKeys) {
      final value = await _storage.read(key: key);
      if (value != null && value.isNotEmpty) {
        preserved[key] = value;
      }
    }

    // 2. Wipe everything
    await _storage.deleteAll();

    // 3. Restore preserved keys
    for (final entry in preserved.entries) {
      await _storage.write(key: entry.key, value: entry.value);
    }
  }
}

