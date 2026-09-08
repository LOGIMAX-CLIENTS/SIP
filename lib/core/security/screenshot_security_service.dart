import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../config/app_config.dart';

/// Centralized service to manage screenshot and screen recording protection.
///
/// Behavior is controlled by [AppConfig.enableScreenshotProtection].
class ScreenshotSecurityService {
  static const _channel = MethodChannel('com.startgold.app/security');

  /// Initializes the screenshot protection state at app launch.
  static Future<void> initialize() async {
    if (kIsWeb) return;

    if (AppConfig.enableScreenshotProtection) {
      try {
        if (Platform.isAndroid) {
          await _channel.invokeMethod('setScreenshotProtection', {'enabled': true});
        }
      } catch (e) {
        debugPrint('ScreenshotSecurityService: failed to enable screen protection: $e');
      }
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
