import 'secure_storage_service.dart';

class SessionManager {
  /// ── Force Logout Guard ───────────────────────────────────────────────────
  /// When a 409 SESSION_INVALIDATED response is received, this flag is set
  /// to `true` so that:
  ///   1. All subsequent API calls are immediately rejected (no network I/O).
  ///   2. The 409 handler only fires once (deduplication across concurrent
  ///      API calls that all return 409 simultaneously).
  ///
  /// The flag is reset ONLY after a successful fresh login clears the session.
  static bool _isForceLoggedOut = false;

  /// Whether the session was force-invalidated by the server (409 Conflict).
  /// Check this in the request interceptor to block further API calls.
  static bool get isForceLoggedOut => _isForceLoggedOut;

  static Future<bool> isAuthenticated() async {
    if (_isForceLoggedOut) return false;
    String? token = await SecureStorageService.getToken();
    return token != null && token.isNotEmpty;
  }

  /// Standard logout — user-initiated (Logout button, account deletion).
  static Future<void> logout() async {
    await SecureStorageService.logout();
  }

  /// The session lapsed (refresh token rejected / SESSION_EXPIRED) — ends it
  /// but keeps this device's biometric and auto-lock choices for the same
  /// customer's next login. See [SecureStorageService.endExpiredSession].
  static Future<void> endExpiredSession() async {
    await SecureStorageService.endExpiredSession();
  }

  /// Force logout — triggered by 409 SESSION_INVALIDATED.
  /// Sets the force-logout flag and clears all stored data.
  /// Returns `false` if already force-logged-out (deduplication).
  static Future<bool> forceLogout() async {
    if (_isForceLoggedOut) return false; // already handled
    _isForceLoggedOut = true;
    await SecureStorageService.logout();
    return true;
  }

  /// Resets the force-logout flag. Call this when the user successfully
  /// completes a fresh login (OTP verified + tokens saved).
  static void resetForceLogout() {
    _isForceLoggedOut = false;
  }

  static Future<bool> hasSeenOnboarding() async {
    final value = await SecureStorageService.getOnboardingSeen();
    return value == true;
  }

  static Future<void> setOnboardingSeen() async {
    await SecureStorageService.setOnboardingSeen(true);
  }
}
