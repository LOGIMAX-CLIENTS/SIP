import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

import '../../main.dart'; // navigatorKey
import '../../routes/app_router.dart';
import '../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SETUP CHECKLIST (do these once before this file will compile):
//
// 1. pubspec.yaml — add under dependencies:
//      firebase_core: ^3.6.0
//      firebase_messaging: ^15.1.3
//      flutter_local_notifications: ^17.2.2
//    Then: flutter pub get
//
// 2. android/settings.gradle.kts — add plugin declaration:
//      id("com.google.gms.google-services") version "4.4.2" apply false
//
// 3. android/app/build.gradle.kts — apply the plugin:
//      id("com.google.gms.google-services")
//
// 4. android/app/src/main/AndroidManifest.xml — add inside <manifest>:
//      <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
//
// 5. Place google-services.json at: android/app/google-services.json
//    (Download from Firebase Console → Project Settings → Your Android app)
//
// 6. main.dart — initialise Firebase BEFORE runApp:
//      import 'package:firebase_core/firebase_core.dart';
//      await Firebase.initializeApp();
//      await FcmService.init();
//
// iOS extra steps: see fcm_setup_guide.md Step 8
// ─────────────────────────────────────────────────────────────────────────────

/// Background handler — MUST be a top-level function (not inside a class).
/// Firebase is already initialised before this is called.
/// Do NOT navigate here — navigation happens only on user tap.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) debugPrint('[FCM] Background received: ${message.messageId}');
}

class FcmService {
  FcmService._();

  static final _messaging = FirebaseMessaging.instance;
  static final _localNotif = FlutterLocalNotificationsPlugin();

  static const _androidChannel = AndroidNotificationChannel(
    'startgold_high_importance',
    'StartGold Notifications',
    description: 'Gold/Silver alerts, transactions, and account updates',
    importance: Importance.high,
  );

  // ── Init ─────────────────────────────────────────────────────────────────

  /// Call once from main() AFTER Firebase.initializeApp().
  static Future<void> init() async {
    // 1. Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. Request permission (iOS mandatory, Android 13+)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    if (kDebugMode) {
      debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');
    }

    // 2b. iOS foreground presentation options (displays banner while app is open)
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Create Android high-importance channel
    await _localNotif
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // 4. Initialise flutter_local_notifications
    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _localNotif.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onLocalNotifTap,
    );

    // 5. FOREGROUND: FCM does NOT auto-show banner on Android.
    //    We show a local notification manually.
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 6. BACKGROUND tap: app was in background, user taps the notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);

    // 7. TERMINATED tap: app was closed, launched by tapping notification.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      // Delay 1s so navigatorKey is ready after app startup.
      Future.delayed(const Duration(seconds: 1),
          () => _handleNotificationOpen(initial));
    }

    // 8. Log device token (debug only — NEVER log in production)
    if (kDebugMode) {
      final token = await getToken();
      if (token != null) {
        final preview = token.length > 10 ? token.substring(0, 10) : token;
        debugPrint('[FCM] ──── Device Token ────');
        debugPrint('[FCM] $preview...');
        debugPrint('[FCM] ─────────────────────');
      }
    }

    // 9. Listen for token refresh — re-register with backend automatically
    _messaging.onTokenRefresh.listen(_onTokenRefreshed);
  }

  // ── Token ─────────────────────────────────────────────────────────────────

  /// Returns the FCM device token for this device.
  /// Pass this to NotificationService.registerFcmToken() after login.
  static Future<String?> getToken() async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        String? apns = await _messaging.getAPNSToken();
        if (apns == null) {
          if (kDebugMode) {
            debugPrint('[FCM] APNs token not yet available, retrying...');
          }
          for (int i = 0; i < 4; i++) {
            await Future.delayed(const Duration(seconds: 1));
            apns = await _messaging.getAPNSToken();
            if (apns != null) break;
          }
        }
        if (kDebugMode) {
          debugPrint(
              '[FCM] APNs Token status: ${apns != null ? "RECEIVED" : "NOT RECEIVED (Check APNs certs / physical device)"}');
        }
      }

      return await _messaging.getToken().timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          debugPrint('⚠️ [FCM] Token fetch timed out (APNs token pending)');
          return null;
        },
      );
    } catch (e) {
      debugPrint('⚠️ [FCM] Error getting token: $e');
      return null;
    }
  }

  /// Stream that emits whenever the FCM token is rotated by Firebase.
  static Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;

  // ── Private Handlers ──────────────────────────────────────────────────────

  /// App is FOREGROUND when FCM push arrives.
  /// FCM is silent on Android when foreground — we must display it manually.
  static void _handleForegroundMessage(RemoteMessage message) {
    if (kDebugMode) debugPrint('[FCM] Foreground: ${message.notification?.title}');
    final notification = message.notification;
    if (notification == null) return;

    _localNotif.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      // Payload carries FCM data so _onLocalNotifTap knows what to do.
      payload: jsonEncode(message.data),
    );
  }

  /// User TAPPED a notification (background or terminated state).
  /// Rule: FCM is a TRIGGER only — always navigate to /notifications
  /// and let the screen fetch fresh data from the API.
  static void _handleNotificationOpen(RemoteMessage message) {
    if (kDebugMode) debugPrint('[FCM] Opened from notification.');
    _navigateToNotifications();
  }

  /// User tapped a LOCAL notification (shown while app was foreground).
  static void _onLocalNotifTap(NotificationResponse response) {
    if (kDebugMode) debugPrint('[FCM] Local notification tapped.');
    _navigateToNotifications();
  }

  /// Called when Firebase rotates the device token.
  /// Re-registers the new token with the backend automatically.
  static void _onTokenRefreshed(String newToken) {
    if (kDebugMode) debugPrint('[FCM] Token refreshed — re-registering.');
    final service = NotificationService();
    service.registerFcmToken(newToken);
  }

  // ── Navigation ────────────────────────────────────────────────────────────

  /// Navigate to the NotificationsScreen.
  /// Screen always calls POST /users/notifications on open — FCM payload
  /// is NEVER used as data source, only as a trigger.
  static void _navigateToNotifications() {
    navigatorKey.currentState?.pushNamed(AppRouter.notifications);
  }

  /// Public helper — call from anywhere to manually navigate to notifications
  /// (e.g. from a nav bar icon tap or deep link).
  static void navigateToNotifications() => _navigateToNotifications();
}
