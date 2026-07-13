import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:screen_protector/screen_protector.dart';
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
        await ScreenProtector.preventScreenshotOn();
        await ScreenProtector.protectDataLeakageWithBlur();
        if (Platform.isAndroid) {
          await _channel.invokeMethod('setScreenshotProtection', {'enabled': true});
        }
      } catch (e) {
        debugPrint('ScreenshotSecurityService: failed to enable screen protection: $e');
      }
    } else {
      try {
        await ScreenProtector.preventScreenshotOff();
        await ScreenProtector.protectDataLeakageWithBlurOff();
        if (Platform.isAndroid) {
          await _channel.invokeMethod('setScreenshotProtection', {'enabled': false});
        }
      } catch (e) {
        debugPrint('ScreenshotSecurityService: failed to disable screen protection: $e');
      }
    }
  }

  /// Secures the current screen. Called in sensitive screens (e.g. OTP, MPIN).
  static Future<void> secureScreen() async {
    if (kIsWeb) return;
    if (!AppConfig.enableScreenshotProtection) return;

    try {
      await ScreenProtector.preventScreenshotOn();
      await ScreenProtector.protectDataLeakageWithBlur();
    } catch (e) {
      debugPrint('ScreenshotSecurityService secureScreen error: $e');
    }
  }

  /// Releases the screen blur/protection. Called in sensitive screens' dispose.
  static Future<void> releaseScreen() async {
    if (kIsWeb) return;
    if (!AppConfig.enableScreenshotProtection) return;

    try {
      // Only remove the iOS blur overlay on dispose.
      // Do NOT call preventScreenshotOff() here as it removes FLAG_SECURE on
      // Android, making app content visible in the recent-apps switcher.
      await ScreenProtector.protectDataLeakageWithBlurOff();
    } catch (e) {
      debugPrint('ScreenshotSecurityService releaseScreen error: $e');
    }
  }
}
