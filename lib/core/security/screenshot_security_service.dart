import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// Centralized service to manage screenshot and screen recording protection.
///
/// Behavior is controlled by [AppConfig.enableScreenshotProtection], which is
/// driven by the admin "APP control Security" config row
/// (APP_CONTROL_SECURITY.enable_screenshot_protection) via `app/control`:
///   true  -> screenshots / screen recording blocked
///   false -> screenshots / screen recording allowed
class ScreenshotSecurityService {
  static const _channel = MethodChannel('com.startgold.app/security');

  /// Last server value, cached so a cold start applies the admin's setting
  /// immediately instead of waiting for the first `app/control` fetch.
  /// Not a secret — it's the same value every customer receives.
  static const _kPrefsKey = 'screenshot_protection_enabled';

  /// State last pushed to the platform — avoids re-applying the iOS secure
  /// layer on every poll (screen_protector's iOS layer must not be stacked).
  static bool? _applied;

  /// Loads the cached server value into [AppConfig.enableScreenshotProtection].
  /// Call before [initialize] at app launch. Keeps the secure default (true)
  /// when the server value has never been fetched.
  static Future<void> loadCachedSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getBool(_kPrefsKey);
      if (cached != null) AppConfig.enableScreenshotProtection = cached;
    } catch (e) {
      debugPrint('ScreenshotSecurityService: failed to load cached setting: $e');
    }
  }

  /// Applies a server-driven value: updates [AppConfig], caches it for the
  /// next launch and syncs native protection. Called by AppControlNotifier.
  static Future<void> applyServerSetting(bool enabled) async {
    AppConfig.enableScreenshotProtection = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kPrefsKey, enabled);
    } catch (e) {
      debugPrint('ScreenshotSecurityService: failed to cache setting: $e');
    }
    await initialize();
  }

  /// Initializes/syncs the screenshot protection state — called at app
  /// launch and again whenever the server value changes. Always syncs to
  /// the current flag so a flip to `false` actually clears native
  /// protection, not just a flip to `true` that sets it.
  static Future<void> initialize() async {
    if (kIsWeb) return;
    final enabled = AppConfig.enableScreenshotProtection;
    if (_applied == enabled) return;

    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod(
          'setScreenshotProtection',
          {'enabled': enabled},
        );
      } else if (Platform.isIOS) {
        // screen_protector attaches its secure layer to the key window, which
        // doesn't exist yet when main() runs before runApp — defer until the
        // first frame is on screen, otherwise the call silently does nothing.
        final binding = WidgetsBinding.instance;
        if (!binding.firstFrameRasterized) {
          binding.waitUntilFirstFrameRasterized.then((_) => initialize());
          return;
        }
        if (enabled) {
          await ScreenProtector.preventScreenshotOn();
        } else {
          await ScreenProtector.preventScreenshotOff();
        }
      }
      _applied = enabled;
    } catch (e) {
      debugPrint('ScreenshotSecurityService: failed to set screen protection: $e');
    }
  }

  /// Secures the current screen. Called in sensitive screens (e.g. OTP, MPIN).
  /// No-op when protection is disabled from the admin settings.
  static Future<void> secureScreen() async {
    if (kIsWeb) return;
    if (!AppConfig.enableScreenshotProtection) return;
    await initialize();
  }

  /// Releases the screen blur/protection. Called in sensitive screens' dispose.
  static Future<void> releaseScreen() async {
    // Maintained for backward compatibility. Protection is app-wide and
    // controlled only by the server flag, so leaving a screen never clears it.
  }
}
