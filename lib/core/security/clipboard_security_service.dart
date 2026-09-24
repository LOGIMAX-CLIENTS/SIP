import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Native clipboard security service.
///
/// Uses a MethodChannel to call Android's native ClipboardManager
/// which clears the clipboard at the OS level — including the
/// keyboard's clipboard suggestion strip (Gboard, Samsung Keyboard, etc.)
///
/// IMPORTANT: On Android 13+, Flutter's `Clipboard.setData()` triggers
/// the system "Copied to clipboard" overlay. We MUST avoid it on Android
/// and use only the native `clearPrimaryClip()` which clears silently.
class ClipboardSecurityService {
  static const _channel = MethodChannel('com.startgold.app/security');

  /// Clears the system clipboard silently without triggering
  /// the Android 13+ "Copied" overlay.
  ///
  /// - Android: Uses native `ClipboardManager.clearPrimaryClip()` (silent)
  /// - iOS: Uses Flutter's `Clipboard.setData('')` (no overlay on iOS)
  /// - Web: Uses Flutter's `Clipboard.setData('')`
  ///
  /// Call this on app launch and every time the app resumes from background.
  static Future<void> clearClipboard() async {
    if (kIsWeb) {
      // Web: Flutter-level clear only
      await Clipboard.setData(const ClipboardData(text: ''));
      return;
    }

    if (Platform.isAndroid) {
      // Android: Use ONLY the native method channel.
      // Do NOT call Clipboard.setData() — it triggers the "Copied"
      // overlay on Android 13+ (API 33+).
      try {
        await _channel.invokeMethod('clearClipboard');
      } catch (e) {
        debugPrint('ClipboardSecurity: Native clear failed: $e');
      }
    } else {
      // iOS / other platforms: Flutter-level clear (no overlay issue)
      await Clipboard.setData(const ClipboardData(text: ''));
    }
  }
}
