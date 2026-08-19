# Module Brain — Notifications

> **Built**: 2026-08-19 (Round 1 — Build Mode) | **Complexity**: Low-Medium | **Status**: 🟢

---

## 1. Module Overview

Push-notification inbox. The module folder itself holds only ONE file — the screen. All state,
model, service, and provider logic for the inbox lives in the **core layer**
(`core/services/notification_service.dart`), because the badge count (`unreadCountProvider`) must be
readable from `Home` and other screens without importing a feature-internal file. FCM
(Firebase Cloud Messaging) plumbing is a **separate core service** (`core/services/fcm_service.dart`)
that acts purely as a **trigger** — it never feeds notification content directly into the inbox list;
it only wakes the app / navigates, and the screen always re-fetches from the API.

### File Map
| Layer | File | Purpose |
|---|---|---|
| Screen | `lib/features/notifications/notifications_screen.dart` | Inbox UI — list, swipe-to-delete, mark-all-read, empty/error/shimmer states |
| Core Service + State | `lib/core/services/notification_service.dart` | `AppNotification` model, `NotificationService` (API calls), `NotificationState`, `NotificationNotifier` (StateNotifier), `notificationProvider`, `unreadCountProvider`, FCM token registration |
| Core Push Handler | `lib/core/services/fcm_service.dart` | Firebase Cloud Messaging lifecycle: permission request, foreground/background/terminated message handling, local-notification display, tap navigation, token refresh |
| Route | `lib/routes/app_router.dart:105` (const `notifications = '/notifications'`), builder at `app_router.dart:302` | |
| Consumer | `lib/features/home/home_screen.dart` | Bell icon + badge (line ~1900-1918), badge refresh triggers (lines 45, 145, 184) |
| Trigger callers | `lib/features/mpin/mpin_screen.dart:749`, `lib/features/auth/pin/pin_creation_screen.dart:467` | FCM token registration after successful login/PIN creation |

### Connection Flow
```
App startup (main.dart:65) → FcmService.init() → permission request, channel setup,
  onMessage / onMessageOpenedApp / getInitialMessage listeners wired, onTokenRefresh listener wired

Login success (mpin_screen.dart / pin_creation_screen.dart)
  → FcmService.getToken() → NotificationService.registerFcmToken(token)
  → POST users/notifications/register-token (skipped if token unchanged, per SecureStorage dedup)

Push arrives (any app state)
  → foreground: FcmService._handleForegroundMessage → local notification shown manually (FCM does NOT
    auto-banner on Android when app is foreground)
  → background/terminated tap: FcmService._handleNotificationOpen / _onLocalNotifTap
  → both paths call _navigateToNotifications() → pushNamed(AppRouter.notifications)
  → NotificationsScreen.initState() → notificationProvider.notifier.load() → GET-via-POST
    users/notifications → fresh list rendered. FCM payload data is NEVER read as the data source.

Home badge
  → HomeScreen.initState() calls notificationProvider.notifier.refreshUnreadCount() on load, on
    pull-to-refresh, and on a post-purchase/withdrawal refresh listener (home_screen.dart:145,184)
  → unreadCountProvider (derived Provider<int> reading notificationProvider.unreadCount) is watched
    by the header widget → red badge over the bell icon, tap → AppRouter.notifications
```

---

## 2. Screens & Routes

| Screen | Route | File | Purpose |
|---|---|---|---|
| NotificationsScreen | `/notifications` | `lib/features/notifications/notifications_screen.dart` | Inbox: list, mark read (tap card), mark-all-read (header action, unread only), swipe-to-delete, pull-to-refresh |

Screen behavior:
- `initState` always calls `notificationProvider.notifier.load()` in a `addPostFrameCallback` —
  comment in code explicitly states "FCM is a trigger — always fetch fresh data from API on open"
  (`notifications_screen.dart:27-30`).
- "Mark All Read" trailing action in the `GradientHeader` only renders when
  `state.notifications.any((n) => !n.isRead)` AND not loading (`notifications_screen.dart:37,45`).
  Tapping it opens a confirm dialog before calling `markAllAsRead()`.
- Each card is a `Dismissible` (swipe left → delete), `confirmDismiss` calls
  `deleteNotification(id)` and only actually removes the card if the API call succeeded
  (`notifications_screen.dart:168-178`).
- Tapping an unread card calls `markAsRead(id)` (no navigation elsewhere — the notification itself
  carries no deep-link target in this implementation; `unconfirmed` whether a future `type`-based
  deep link is planned given the `_typeIcon`/`_typeColor` switch on `market/transaction/kyc/withdrawal/offer`).
- Three body states: shimmer list (loading), error card with Retry (fetch failed), empty state
  ("No Notifications Yet"), or the real list.

---

## 3. State & Providers Summary

Full detail in `STATE_ANALYSIS.md`. Headline: everything is a single `StateNotifierProvider`
(`notificationProvider` → `NotificationNotifier` → `NotificationState`) declared in the **core**
service file, not under `features/notifications/`. `unreadCountProvider` is a thin derived
`Provider<int>` so Home never has to depend on the full list state shape.

---

## 4. API Integrations

| API | Method (service) | Purpose |
|---|---|---|
| `POST users/notifications` | `NotificationService.fetchNotifications()` | Fetch notification list |
| `POST users/notifications/read` | `NotificationService.markAsRead(id)` | Mark single as read |
| `POST users/notifications/read-all` | `NotificationService.markAllAsRead()` | Mark all as read |
| `POST users/notifications/delete` | `NotificationService.deleteNotification(id)` | Delete (server-side; presumed soft-delete, unconfirmed — no evidence in this codebase, only the mobile-side effect is observed) |
| `POST users/notifications/unread-count` | `NotificationService.fetchUnreadCount()` | Badge count (tolerant parser — handles 5 possible response shapes, `notification_service.dart:86-105`) |
| `POST users/notifications/register-token` | `NotificationService.registerFcmToken(token)` | Registers FCM device token + device metadata; dedup via `SecureStorageService` stored token |

None of these endpoints appear in `AppConfig.encryptedEndpoints` (`lib/core/config/app_config.dart:47-71`)
— the notification payloads carry no field-level RSA encryption. This is consistent with the content
(id/title/message/type/is_read/created_at — no PII/financial fields).

---

## 5. Business Rules

See `BUSINESS_RULES.md` for the full RULE-NOTIFICATIONS-NNN list. Headline: FCM is trigger-only (never
a data source), unread count and unread badge are computed both server-side (`fetchUnreadCount`) and
client-side (`NotificationState.computedUnread`, `notification_service.dart:169`) — the two are NOT
always the same value; the screen and header use different providers for the two, see caveats in
`BUSINESS_RULES.md` RULE-NOTIFICATIONS-003.

---

## 6. Cross-Module Dependencies

Summary (full detail `CROSS_MODULE_MAP.md`): `Notifications` depends on `core/services/notification_service.dart`
(owns state — this module's screen is a pure consumer), `core/services/fcm_service.dart` (push
transport), `core/security/secure_storage_service.dart` (FCM token dedup storage),
`core/services/device_id_service.dart` (device metadata for token registration). `Home` depends on
`unreadCountProvider` and `AppRouter.notifications` for the bell badge — this is the primary reverse
dependency worth tracking since a change to `NotificationState`'s shape would silently break Home's
badge if the derived provider isn't kept in sync.

---

## 7. Known Risks / Top Risks

| Risk | Severity | Description |
|---|---|---|
| Two sources of truth for unread count | 🟡 Medium | `unreadCountProvider` reads `NotificationState.unreadCount` (server-reported, refreshed via `fetchUnreadCount()`), while the inbox screen also computes `state.notifications.any((n) => !n.isRead)` client-side for its own "has unread" checks. These can disagree if `load()` and `refreshUnreadCount()` are called at different times — see `BUSINESS_RULES.md` RULE-NOTIFICATIONS-003 and `FORENSIC_TEMPLATE.md` "badge count wrong". |
| Silent failure on mark-read / mark-all / delete-adjacent-count | 🟢 Low (by design) | `markAsRead`, `markAllAsRead` catch-and-swallow all errors (`notification_service.dart:213-217, 226-227`) — optimistic local update happens only on success; on failure the state silently doesn't change and no error is surfaced to the user. Intentional per comment ("list is still accurate from last load") but means a flaky mark-read tap gives no feedback. |
| `deleteNotification` return value drives UI truthiness | 🟢 Low | Returns `false` on any exception including a 409 (session invalidation, which the interceptor's dialog handles separately) — the `Dismissible.confirmDismiss` then keeps the card in place, which is correct UX, but the toast "Notification removed" only fires when `success == true` inside the screen (`notifications_screen.dart:173-176`), so there's no user-visible error for the failure case beyond the card snapping back. |
| Dead/unused `_androidChannel.description` in production log | 🟢 Low | `FcmService.init()` step 8 logs a **partial** device token in debug builds only (`fcm_service.dart:106-111`) — correctly gated by `kDebugMode`, no production leak. |
| FCM registration is fire-and-forget with no retry | 🟢 Low | If `registerFcmToken` fails (network blip right after login), there's no scheduled retry — the token re-registers only on the next `onTokenRefresh` event or next login. |

---

## 8. Drift vs `STARTGOLD_DOCUMENTATION.md` §3.33

The hand-written doc's 5-row API table (fetch/read/read-all/delete/unread-count) matches the live
code exactly. **Gap, not contradiction**: the doc does not mention `users/notifications/register-token`
(FCM token registration) or the FCM push-delivery mechanism (`fcm_service.dart`) at all — it documents
only the inbox CRUD surface. Flagged in `_OVERVIEW/BUILD_SUMMARY.md`.

---

## 9. See Also
- `METHOD_INDEX.md` — every public method, file:line, callers
- `DATA_FLOW.md` — end-to-end flows with file:line
- `BUSINESS_RULES.md` — RULE-NOTIFICATIONS-NNN
- `CROSS_MODULE_MAP.md` — Mermaid dependency graph
- `STATE_ANALYSIS.md` — Riverpod provider/model shapes
- `FORENSIC_TEMPLATE.md` — symptom → suspect lookup
- `COVERAGE_TRACKER.md` — round history
