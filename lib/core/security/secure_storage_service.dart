import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

  /// App-lock idle timeout — how long the app must have been backgrounded
  /// before the MPIN/biometric lock screen shows on resume (see
  /// AppLifecycleObserver). Falls back to the server-provided default
  /// (AppConfig.mpinLockDefaultTimeoutSeconds) until the customer picks one
  /// on Profile > App Security.
  static Future<int> getMpinLockTimeoutSeconds() async {
    final value =
        await _storage.read(key: AppConfig.keyMpinLockTimeoutSeconds);
    return int.tryParse(value ?? '') ?? AppConfig.mpinLockDefaultTimeoutSeconds;
  }

  static Future<void> setMpinLockTimeoutSeconds(int seconds) async {
    await _storage.write(
        key: AppConfig.keyMpinLockTimeoutSeconds, value: seconds.toString());
  }

  static Future<bool> getOnboardingSeen() async {
    final value = await _storage.read(key: AppConfig.keyHasSeenOnboarding);
    return value == 'true';
  }

  static Future<void> setOnboardingSeen(bool seen) async {
    await _storage.write(
        key: AppConfig.keyHasSeenOnboarding, value: seen.toString());
  }

  /// Whether the "Let support know?" prompt (see
  /// manual_kyc_upload_screen.dart's _promptNotifySupport) has already been
  /// shown once — it's offered only on the customer's FIRST-EVER manual KYC
  /// upload, not on every subsequent one (a second document, or a resubmit
  /// after rejection).
  static Future<bool> getManualKycSupportPromptSeen() async {
    final value =
        await _storage.read(key: AppConfig.keyHasSeenManualKycSupportPrompt);
    return value == 'true';
  }

  static Future<void> setManualKycSupportPromptSeen(bool seen) async {
    await _storage.write(
        key: AppConfig.keyHasSeenManualKycSupportPrompt, value: seen.toString());
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
  static Future<void> logout() => _wipeExcept(const []);

  /// Keys that MUST survive every kind of logout.
  static const _deviceKeys = [
    'persistent_device_id',
    'persistent_device_type',
    AppConfig.keyHasSeenOnboarding,
    _installStampKey,
  ];

  /// When this install of the app happened — see [clearIfReinstalled].
  static const _installStampKey = 'app_install_stamp';

  /// Logs out a session left behind by a PREVIOUS install of the app.
  ///
  /// Uninstalling should take the stored token with it, but secure storage
  /// can outlive the app: the iOS Keychain always does, and on some Android
  /// devices the data comes back too. The reinstalled app then opened
  /// straight on the MPIN screen instead of Login. The install time
  /// (Android `firstInstallTime`; iOS: creation of the app's Documents
  /// folder) changes on every reinstall but not on updates, so a saved stamp
  /// that doesn't match means this data belongs to an earlier install.
  /// No saved stamp (first run, or users updating from before this check)
  /// just records it. Web has no install time and is skipped.
  /// Call once at startup, before reading the session.
  static Future<void> clearIfReinstalled() async {
    final installTime = (await PackageInfo.fromPlatform()).installTime;
    if (installTime == null) return;
    final stamp = installTime.millisecondsSinceEpoch.toString();
    final saved = await _storage.read(key: _installStampKey);
    if (saved == stamp) return;
    if (saved != null) await logout();
    await _storage.write(key: _installStampKey, value: stamp);
  }

  /// This device's app-lock choices — kept by [endExpiredSession].
  static const _appLockPrefKeys = [
    AppConfig.keyIsBiometricEnabled,
    AppConfig.keyMpinLockTimeoutSeconds,
  ];

  /// Ends a session that lapsed on its own — the server stopped accepting
  /// the refresh token, or mpin/validate answered SESSION_EXPIRED.
  ///
  /// Unlike [logout] (customer tapped Logout / deleted the account) and the
  /// 409 force-logout (signed in elsewhere), this keeps the customer's
  /// Biometric Login and Auto-Lock choices, so logging back in doesn't make
  /// them set those up again. The backend's refresh token only lasts a day
  /// from its last use, so any customer who skips a day lands here, very
  /// often on the first open after a Play Store update.
  /// The choices stay tagged with the customer who made them;
  /// [keepAppLockPrefsOnlyFor] drops them if a different customer logs in
  /// next. MPIN needs nothing kept here: verify-otp's `mpin_enabled` sets
  /// [isMpinEnabled] again on that login.
  static Future<void> endExpiredSession() async {
    final owner = await getCustomerId();
    if (owner == null || owner.isEmpty) {
      // Can't tell whose choices these are — don't carry them over.
      return logout();
    }
    await _wipeExcept(_appLockPrefKeys);
    if (await _storage.containsKey(key: AppConfig.keyIsBiometricEnabled) ||
        await _storage.containsKey(key: AppConfig.keyMpinLockTimeoutSeconds)) {
      await _storage.write(key: AppConfig.keyAppLockOwnerId, value: owner);
    }
  }

  /// Call on every OTP login or registration that identifies the customer,
  /// BEFORE their id is saved. Keeps the app-lock choices on this device
  /// only if they belong to [customerId]; a different customer starts with
  /// them off.
  static Future<void> keepAppLockPrefsOnlyFor(String customerId) async {
    final owner = await _storage.read(key: AppConfig.keyAppLockOwnerId) ??
        await getCustomerId();
    await _storage.delete(key: AppConfig.keyAppLockOwnerId);
    if (owner == null || owner == customerId) return;
    for (final key in _appLockPrefKeys) {
      await _storage.delete(key: key);
    }
  }

  static Future<void> _wipeExcept(List<String> extraKeys) async {
    // 1. Read values to preserve
    final preserved = <String, String>{};
    for (final key in [..._deviceKeys, ...extraKeys]) {
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

