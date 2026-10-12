import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../security/secure_storage_service.dart';

/// Central service for all biometric-related logic.
///
/// Key design rule:
///   - NEVER rely solely on [canCheckBiometrics].
///   - ALWAYS use [getAvailableBiometrics] to confirm the user has enrolled
///     at least one fingerprint or face on the device.
class BiometricService {
  BiometricService._();

  static final LocalAuthentication _auth = LocalAuthentication();

  // ── Device-level checks ──────────────────────────────────────────────────

  /// Returns true if the device has AT LEAST ONE enrolled biometric
  /// (fingerprint, face, iris, etc.).
  ///
  /// Uses [getAvailableBiometrics] — the only reliable way to know whether
  /// the user has actually enrolled a biometric, not just that the hardware
  /// exists.
  static Future<bool> deviceHasBiometric() async {
    try {
      return await _enrolledBiometricPresent();
    } catch (e) {
      debugPrint('[BiometricService] deviceHasBiometric error: $e');
      return false;
    }
  }

  /// Like [deviceHasBiometric], but lets a platform error through so
  /// callers can tell "the OS couldn't answer" apart from "none enrolled".
  static Future<bool> _enrolledBiometricPresent() async {
    // First: confirm the device is capable at all.
    final isSupported = await _auth.isDeviceSupported();
    if (!isSupported) return false;

    // Second: confirm at least one biometric is ENROLLED.
    final enrolled = await _auth.getAvailableBiometrics();
    return enrolled.isNotEmpty;
  }

  // ── Combined flag (UI should use this) ───────────────────────────────────

  /// Returns the effective "can use biometric" flag:
  ///   canUseBiometric = biometricEnabled (storage) && deviceHasBiometric()
  ///
  /// Side-effect: if the stored flag is true but the device has NO enrolled
  /// biometric (e.g. user removed fingerprint from phone settings), this
  /// method automatically resets the stored flag to false. A platform error
  /// while checking only falls back to MPIN this time — it isn't proof the
  /// fingerprint was removed, so the customer's choice is kept.
  static Future<bool> canUseBiometric() async {
    final storedEnabled = await SecureStorageService.isBiometricEnabled();
    if (!storedEnabled) return false;

    final bool hasDevice;
    try {
      hasDevice = await _enrolledBiometricPresent();
    } catch (e) {
      debugPrint('[BiometricService] canUseBiometric check failed: $e');
      return false;
    }
    if (!hasDevice) {
      // Auto-disable: fingerprint was removed from device settings.
      debugPrint(
          '[BiometricService] Device biometrics removed — auto-disabling.');
      await SecureStorageService.setBiometricEnabled(false);
      return false;
    }
    return true;
  }

  // ── Enabling flow ────────────────────────────────────────────────────────

  /// Call this before allowing the user to enable biometric in Profile.
  ///
  /// Returns a [BiometricCheckResult] so the UI can show an appropriate
  /// message without containing any biometric logic itself.
  static Future<BiometricCheckResult> checkBeforeEnable() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        return BiometricCheckResult.notSupported;
      }
      final enrolled = await _auth.getAvailableBiometrics();
      if (enrolled.isEmpty) {
        return BiometricCheckResult.noneEnrolled;
      }
      return BiometricCheckResult.available;
    } catch (e) {
      debugPrint('[BiometricService] checkBeforeEnable error: $e');
      return BiometricCheckResult.notSupported;
    }
  }

  // ── Authentication ───────────────────────────────────────────────────────

  /// Prompt the system biometric dialog.
  /// Returns true only if the user successfully authenticates.
  static Future<bool> authenticate({required String reason}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
    } catch (e) {
      debugPrint('[BiometricService] authenticate error: $e');
      return false;
    }
  }
}

/// Result of a pre-enable biometric availability check.
enum BiometricCheckResult {
  /// Device supports biometrics AND at least one is enrolled.
  available,

  /// Hardware exists but NO biometric is enrolled on the device.
  noneEnrolled,

  /// Device has no biometric hardware or is not supported.
  notSupported,
}
