import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';

/// Centralized service to manage screenshot and screen recording protection.
///
/// Behavior is controlled by [AppConfig.enableScreenshotProtection].
class ScreenshotSecurityService {
  static const _channel = MethodChannel('com.startgold.app/security');

  /// Initializes/syncs the screenshot protection state — called at app
  /// launch (with the default AppConfig.enableScreenshotProtection) and
  /// again whenever AppControlNotifier fetches a new value from the server.
  /// Always calls through so a server-driven flip to `false` actually
  /// clears native FLAG_SECURE, not just a flip to `true` that sets it.
  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod(
          'setScreenshotProtection',
          {'enabled': AppConfig.enableScreenshotProtection},
        );
      }
    } catch (e) {
      debugPrint('ScreenshotSecurityService: failed to set screen protection: $e');
    }
  }

  /// Secures the current screen. Called in sensitive screens (e.g. OTP, MPIN).
  static Future<void> secureScreen() async {
    if (kIsWeb) return;
    if (!AppConfig.enableScreenshotProtection) return;

    try {
      if (Platform.isAndroid) {
        await _channel.invokeMethod('setScreenshotProtection', {'enabled': true});
      }
    } catch (e) {
      debugPrint('ScreenshotSecurityService secureScreen error: $e');
    }
  }

  /// Releases the screen blur/protection. Called in sensitive screens' dispose.
  static Future<void> releaseScreen() async {
    // Maintained for backward compatibility.
    // Native FLAG_SECURE on Android and SceneDelegate black privacy overlay on iOS
    // automatically secure recent apps screen thumbnails.
  }
}
