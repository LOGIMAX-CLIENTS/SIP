# Business Rules — Notifications

---

### RULE-NOTIFICATIONS-001: FCM is a trigger only, never a data source
The inbox NEVER renders content from an FCM `RemoteMessage` payload. Every tap/open path
(`_handleForegroundMessage` local-notif tap, `_handleNotificationOpen`, `getInitialMessage`) resolves
to `_navigateToNotifications()`, and `NotificationsScreen.initState()` unconditionally calls
`notificationProvider.notifier.load()` which re-fetches from `POST users/notifications`.
- Code: `lib/features/notifications/notifications_screen.dart:27-30`,
  `lib/core/services/fcm_service.dart:159-161,184-185`.

### RULE-NOTIFICATIONS-002: Foreground pushes must be shown manually
FCM does not auto-display a system banner on Android while the app is in the foreground. The app
must call `flutter_local_notifications.show(...)` itself inside `onMessage`, using a dedicated
high-importance Android channel (`startgold_high_importance`).
- Code: `lib/core/services/fcm_service.dart:53-58,130-157`.

### RULE-NOTIFICATIONS-003: Unread count has two computation paths that can disagree
`NotificationState.unreadCount` is set from two independent sources: (a) client-derived from the
fetched list in `load()`, `markAsRead()`, `markAllAsRead()`, `deleteNotification()`; (b)
server-authoritative from `fetchUnreadCount()` in `refreshUnreadCount()` (used by Home). Whichever
ran most recently wins — there is no reconciliation/merge logic. A push arriving while the user is on
a screen other than Home or Notifications will not update the badge until the next explicit
`refreshUnreadCount()` call (Home `initState`, pull-to-refresh, or the post-purchase/withdrawal
listener at `home_screen.dart:145,184`).
- Code: `lib/core/services/notification_service.dart:190-254`.

### RULE-NOTIFICATIONS-004: FCM token registration is deduplicated and fire-and-forget
`registerFcmToken(token)` compares against the token cached via `SecureStorageService.getFcmToken()`
and skips the network call if unchanged. Registration failures are caught and logged, never surfaced
to the user or retried on a timer — the next opportunity is the next `onTokenRefresh` event or next
login.
- Code: `lib/core/services/notification_service.dart:116-146`.

### RULE-NOTIFICATIONS-005: Optimistic UI updates only commit on server success
`markAsRead`, `markAllAsRead` mutate local state ONLY inside the `try` block after the API call
succeeds — a failed call leaves `NotificationState` untouched (no rollback needed because nothing was
applied), but also surfaces no error to the user (both catch blocks are empty).
`deleteNotification` follows the same success-gated pattern but DOES propagate a `bool` return so the
`Dismissible` widget can decide whether to actually remove the card or snap it back.
- Code: `lib/core/services/notification_service.dart:202-244`.

### RULE-NOTIFICATIONS-006: No field-level encryption on this module's payloads
None of the six `users/notifications*` endpoints appear in `AppConfig.encryptedEndpoints`
(`lib/core/config/app_config.dart:47-71`). Request/response bodies (notification id/title/message/
type/is_read/created_at, FCM token + device metadata) are sent as plain JSON over the standard
TLS + certificate-pinned channel — no RSA-OAEP field encryption applies here, consistent with AGENTS.md
§3's scope (password/otp/mpin/pan/aadhaar/bank/amount fields).
- Code: `lib/core/config/app_config.dart:47-71` (absence), `lib/core/services/notification_service.dart:53-146`.

### RULE-NOTIFICATIONS-007: Mark-all-read action is gated on client-visible unread state
The "Mark All Read" header button only renders when `state.notifications.any((n) => !n.isRead)` is
true AND the screen isn't currently loading — it is derived from the currently-loaded list, not from
`unreadCount` (which could theoretically be nonzero from a stale `refreshUnreadCount()` call while the
list itself shows zero unread after a fresh `load()`).
- Code: `lib/features/notifications/notifications_screen.dart:37,45`.
