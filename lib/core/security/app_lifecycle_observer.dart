import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'clipboard_security_service.dart';
import '../providers/market_provider.dart';
import '../security/session_manager.dart';
import '../security/secure_storage_service.dart';
import '../security/secure_logger.dart';
import '../services/biometric_service.dart';
import '../../routes/app_router.dart';

/// Observes app lifecycle to manage:
///   1. Socket connection (pause/resume)
///   2. App Lock re-authentication on resume (MPIN/Biometric)
///
/// App Lock triggers when:
///   - MPIN is enabled
///   - App was in background (not just a brief app-switch)
///   - User is authenticated
///   - No payment gateway / external flow is active
class AppLifecycleObserver extends WidgetsBindingObserver {
  final Ref ref;
  final GlobalKey<NavigatorState> navigatorKey;

  AppLifecycleObserver(this.ref, this.navigatorKey);

  // ── App Lock State ────────────────────────────────────────────────────────
  /// Timestamp when the app was last paused (sent to background).
  DateTime? _pausedAt;

  /// Guard flag — prevents stacking multiple lock screens if `resumed`
  /// fires multiple times before the lock screen is dismissed.
  static bool _isLockScreenShowing = false;

  /// External flag that other parts of the app can set to temporarily
  /// suppress the app lock (e.g. during payment gateway flows).
  /// Set to `true` before launching external flows (Cashfree, UPI intents)
  /// and reset to `false` when the flow completes.
  static bool suppressAppLock = false;

  // ── Pre-cached values (populated on pause, used instantly on resume) ───
  /// These values are read from secure storage during `paused` (invisible
  /// delay) so that `resumed` can check them synchronously (zero delay).
  bool _cachedIsAuth = false;
  bool _cachedMpinEnabled = false;
  bool _cachedBiometricEnabled = false;

  // ── Lifecycle Handling ────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Record pause timestamp for app lock threshold
      _pausedAt = DateTime.now();

      // Pre-cache auth/MPIN/biometric status while going to background.
      // This async work happens invisibly — the user is leaving the app
      // anyway, so the delay is unnoticeable. On resume, we use these
      // cached values for an INSTANT lock screen without any awaits.
      _preCacheSecurityState();

      // Pause socket when app goes to background
      ref.read(socketIOServiceProvider).disconnect();
    } else if (state == AppLifecycleState.resumed) {
      // ── Clear clipboard on resume (VAPT: Clipboard Leakage) ────────────
      // Clears both system clipboard AND keyboard clipboard strip (Gboard)
      // using native Android ClipboardManager.
      ClipboardSecurityService.clearClipboard();

      // Reconnect socket when app comes back to foreground
      ref.read(socketIOServiceProvider).connect();

      // ── App Lock on resume (INSTANT — uses pre-cached values) ─────────
      _checkAppLockOnResume();
    }
  }

  /// Pre-caches security state from secure storage while the app is going
  /// to background. This ensures resume checks are purely synchronous.
  Future<void> _preCacheSecurityState() async {
    try {
      _cachedIsAuth = await SessionManager.isAuthenticated();
      _cachedMpinEnabled = await SecureStorageService.isMpinEnabled();
      _cachedBiometricEnabled = await BiometricService.canUseBiometric();
    } catch (_) {
      // If caching fails, the defaults (false) will prevent lock from
      // triggering — safe fallback.
    }
  }


  // ── App Lock (Re-auth on Resume) ──────────────────────────────────────────
  /// Checks whether re-authentication is needed after app resume.
  ///
  /// **Performance**: All guard checks use pre-cached values (populated
  /// during `paused`) so this method is synchronous and instant — no
  /// FlutterSecureStorage reads on the hot path.
  ///
  /// Triggers ONLY when:
  ///   1. User is authenticated (cached)
  ///   2. MPIN is enabled (cached)
  ///   3. App was actually in the background
  ///   4. No lock screen is already showing
  ///   5. App lock is not suppressed (e.g. during payment flows)
  ///   6. Session is not force-invalidated (409 dialog takes priority)
  void _checkAppLockOnResume() {
    // ── Guard: already showing or suppressed ──
    if (_isLockScreenShowing) return;
    if (suppressAppLock) {
      SecureLogger.d('APP LOCK: Suppressed (external flow active).');
      return;
    }

    // ── Guard: session force-invalidated (409 dialog takes priority) ──
    if (SessionManager.isForceLoggedOut) return;

    // ── Guard: not authenticated → no lock needed (CACHED — instant) ──
    if (!_cachedIsAuth) return;

    // ── Guard: MPIN not enabled → no lock (CACHED — instant) ──
    if (!_cachedMpinEnabled) return;

    // ── Guard: app was never paused (cold start) ──
    if (_pausedAt == null) return;

    final elapsed = DateTime.now().difference(_pausedAt!);

    SecureLogger.d(
        'APP LOCK: App was backgrounded for ${elapsed.inSeconds}s → triggering lock.');

    // ── Show lock screen ──
    _isLockScreenShowing = true;
    _pausedAt = null; // reset so we don't re-trigger

    final nav = navigatorKey.currentState;
    if (nav == null || !nav.mounted) {
      _isLockScreenShowing = false;
      return;
    }

    // Check if current route is already the MPIN screen (avoid stacking)
    final currentRoute = ModalRoute.of(nav.context)?.settings.name;
    if (currentRoute == AppRouter.mpin) {
      _isLockScreenShowing = false;
      return;
    }

    // Also skip if we're on the login, splash, or onboarding screens
    if (currentRoute == AppRouter.login ||
        currentRoute == AppRouter.splash ||
        currentRoute == AppRouter.onboarding ||
        currentRoute == AppRouter.otp ||
        currentRoute == AppRouter.registration ||
        currentRoute == AppRouter.registrationSuccess) {
      _isLockScreenShowing = false;
      return;
    }

    // ── Biometric enabled? Try it first, then fallback to MPIN ──
    if (_cachedBiometricEnabled) {
      // Attempt biometric — this is the only async part (OS prompt)
      _tryBiometricThenMpin(nav);
    } else {
      // No biometric → push MPIN immediately
      _pushMpinLockScreen(nav);
    }
  }

  /// Tries biometric auth first. On success → unlock instantly.
  /// On failure → falls back to MPIN screen.
  Future<void> _tryBiometricThenMpin(NavigatorState nav) async {
    try {
      final didAuth = await BiometricService.authenticate(
        reason: 'Verify your identity to continue',
      );
      if (didAuth) {
        SecureLogger.d('APP LOCK: Biometric success → unlocked.');
        _isLockScreenShowing = false;
        return;
      }
    } catch (e) {
      SecureLogger.d('APP LOCK: Biometric failed/cancelled ($e).');
    }

    // Biometric failed → fallback to MPIN
    if (nav.mounted) {
      _pushMpinLockScreen(nav);
    } else {
      _isLockScreenShowing = false;
    }
  }

  /// Pushes the MPIN lock screen immediately with zero frame delay.
  void _pushMpinLockScreen(NavigatorState nav) {
    // Use scheduleMicrotask for earliest possible execution — faster
    // than addPostFrameCallback which waits for the next frame.
    Future.microtask(() {
      if (!nav.mounted) {
        _isLockScreenShowing = false;
        return;
      }
      nav
          .pushNamed(
        AppRouter.mpin,
        arguments: {'type': 'app_lock'},
      )
          .then((_) {
        _isLockScreenShowing = false;
      });
    });
  }

  /// Call this to reset the lock flag externally (e.g. if the lock screen
  /// is dismissed through an unexpected code path).
  static void resetLockFlag() {
    _isLockScreenShowing = false;
  }
}

final lifecycleObserverProvider =
    Provider.family<AppLifecycleObserver, GlobalKey<NavigatorState>>(
        (ref, navigatorKey) {
  final observer = AppLifecycleObserver(ref, navigatorKey);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  return observer;
});
