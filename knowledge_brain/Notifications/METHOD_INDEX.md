# Method Index — Notifications

Alphabetical by class. All files under `lib/core/services/` (state/service co-located with the model,
not under `lib/features/notifications/`) except the screen class.

---

## `AppNotification` (model) — `lib/core/services/notification_service.dart`

| Method | File:Line | Purpose | Callers |
|---|---|---|---|
| `AppNotification.fromJson(Map)` | `notification_service.dart:26` | Deserialize one list item from `users/notifications` response | `NotificationService.fetchNotifications` |
| `copyWith({bool? isRead})` | `notification_service.dart:37` | Immutable update helper (used for optimistic read-state flips) | `NotificationNotifier.markAsRead`, `.markAllAsRead` |

## `NotificationService` — `lib/core/services/notification_service.dart`

| Method | File:Line | Endpoint | Purpose | Callers |
|---|---|---|---|---|
| `fetchNotifications()` | `notification_service.dart:53` | `POST users/notifications` | Fetch inbox list | `NotificationNotifier.load` |
| `markAsRead(int id)` | `notification_service.dart:65` | `POST users/notifications/read` | Mark one read | `NotificationNotifier.markAsRead` |
| `markAllAsRead()` | `notification_service.dart:71` | `POST users/notifications/read-all` | Mark all read | `NotificationNotifier.markAllAsRead` |
| `deleteNotification(int id)` | `notification_service.dart:76` | `POST users/notifications/delete` | Delete one | `NotificationNotifier.deleteNotification` |
| `fetchUnreadCount()` | `notification_service.dart:82` | `POST users/notifications/unread-count` | Badge count, tolerant 5-shape parser | `NotificationNotifier.refreshUnreadCount` |
| `registerFcmToken(String token)` | `notification_service.dart:116` | `POST users/notifications/register-token` | Register device FCM token (dedup via SecureStorage) | `mpin_screen.dart:757`, `pin_creation_screen.dart:473`, `FcmService._onTokenRefreshed:178` |

## `NotificationNotifier extends StateNotifier<NotificationState>` — `lib/core/services/notification_service.dart`

| Method | File:Line | Purpose | Callers |
|---|---|---|---|
| `load()` | `notification_service.dart:190` | Full list fetch, sets `isLoading`, computes `unreadCount` from list | `notifications_screen.dart:29` (initState), `:143` (pull-to-refresh), `:447` (retry button) |
| `markAsRead(int id)` | `notification_service.dart:202` | API call + optimistic local flip; swallows errors | `notifications_screen.dart:202` (card tap when unread) |
| `markAllAsRead()` | `notification_service.dart:219` | API call + optimistic local flip-all; swallows errors | `notifications_screen.dart:126` (confirm dialog) |
| `deleteNotification(int id)` | `notification_service.dart:229` | API call; removes from list ONLY on success; returns bool | `notifications_screen.dart:170` (`Dismissible.confirmDismiss`) |
| `refreshUnreadCount()` | `notification_service.dart:246` | Badge-only refresh (does not touch the list) | `home_screen.dart:45,145,184` |

## Providers — `lib/core/services/notification_service.dart`

| Provider | File:Line | Type | Purpose |
|---|---|---|---|
| `notificationServiceProvider` | `notification_service.dart:151` | `Provider<NotificationService>` | DI for the service |
| `notificationProvider` | `notification_service.dart:257` | `StateNotifierProvider<NotificationNotifier, NotificationState>` | Main inbox state, watched by the screen |
| `unreadCountProvider` | `notification_service.dart:263` | `Provider<int>` | Thin derived badge-count provider, watched by `Home` header |

## `NotificationsScreen` (+ `_NotificationsScreenState`) — `lib/features/notifications/notifications_screen.dart`

| Method | File:Line | Purpose |
|---|---|---|
| `initState()` | `notifications_screen.dart:24` | Post-frame `load()` call |
| `build()` | `notifications_screen.dart:34` | Header + Mark-All-Read trailing action + body state switch |
| `_onMarkAllRead()` | `notifications_screen.dart:94` | Confirm dialog → `markAllAsRead()` |
| `_buildList(state, isDark)` | `notifications_screen.dart:140` | `RefreshIndicator` + `ListView.separated` |
| `_buildDismissibleCard(notif, isDark)` | `notifications_screen.dart:160` | Swipe-to-delete wrapper, calls `deleteNotification` in `confirmDismiss` |
| `_buildCard(notif, isDark)` | `notifications_screen.dart:196` | Card UI, tap-to-mark-read when unread |
| `_buildShimmerList()` / `_buildShimmerCard()` | `notifications_screen.dart:317,327` | Loading skeleton |
| `_buildEmpty(isDark)` | `notifications_screen.dart:397` | Empty state |
| `_buildError(error, isDark)` | `notifications_screen.dart:431` | Error state + Retry → `load()` |
| `_typeIcon(String type)` / `_typeColor(String type)` | `notifications_screen.dart:458,475` | Maps `type` string (`market/transaction/kyc/withdrawal/offer`, else default) to icon/color |

## `FcmService` — `lib/core/services/fcm_service.dart`

| Method | File:Line | Purpose | Callers |
|---|---|---|---|
| `init()` (static) | `fcm_service.dart:63` | One-time setup: background handler, permission request, Android channel, `flutter_local_notifications` init, foreground/opened/initial-message listeners, token-refresh listener | `main.dart:65` |
| `getToken()` (static) | `fcm_service.dart:121` | Returns current FCM token | `mpin_screen.dart:755`, `pin_creation_screen.dart:471`, `init()` debug log |
| `onTokenRefresh` (static getter) | `fcm_service.dart:124` | Stream of token rotations | Not directly subscribed outside `init()`'s own listener wiring |
| `navigateToNotifications()` (static, public) | `fcm_service.dart:192` | Public wrapper for manual nav (e.g. nav bar icon, deep link) | `unconfirmed` — no call site found in this module's files; likely intended for external callers |
| `_firebaseMessagingBackgroundHandler` (top-level fn) | `fcm_service.dart:43` | Required top-level background isolate entry point; logs only | Registered via `FirebaseMessaging.onBackgroundMessage` |
| `_handleForegroundMessage(RemoteMessage)` | `fcm_service.dart:130` | Manually shows a local notification (Android doesn't auto-banner in foreground) | `FirebaseMessaging.onMessage` listener |
| `_handleNotificationOpen(RemoteMessage)` | `fcm_service.dart:162` | Background/terminated tap → navigate to inbox | `FirebaseMessaging.onMessageOpenedApp` listener, `getInitialMessage()` path |
| `_onLocalNotifTap(NotificationResponse)` | `fcm_service.dart:168` | Foreground-shown local notification tap → navigate to inbox | `flutter_local_notifications` `onDidReceiveNotificationResponse` |
| `_onTokenRefreshed(String)` | `fcm_service.dart:175` | Re-registers rotated token with backend | `_messaging.onTokenRefresh` listener |
| `_navigateToNotifications()` | `fcm_service.dart:186` | `navigatorKey.currentState?.pushNamed(AppRouter.notifications)` | All tap/open handlers above |
