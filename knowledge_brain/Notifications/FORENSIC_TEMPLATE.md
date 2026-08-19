# Forensic Template — Notifications

Symptom → check first → likely suspects. Use alongside `DATA_FLOW.md` for the exact call chain and
`STATE_ANALYSIS.md` for provider/model shapes.

---

## Symptom: "Badge count on Home is wrong (stale, too high, too low, or stuck at 0)"

**Check first**: Which of the two write paths last ran — `load()`/`markAsRead()`/`markAllAsRead()`/
`deleteNotification()` (client-derived `unreadCount`) or `refreshUnreadCount()` (server-authoritative)?
Add a temporary log at `notification_service.dart:195-196,225,250` to see the last writer and value.

**Likely suspects**:
1. A push arrived while the user was on a screen other than Home/Notifications — badge won't update
   until the next `refreshUnreadCount()` call (Home init, pull-to-refresh, or post-purchase listener).
   See RULE-NOTIFICATIONS-003.
2. `fetchUnreadCount()`'s tolerant parser (`notification_service.dart:86-105`) misparsed an unexpected
   response shape and silently returned `0` — check `kDebugMode` logs `[Notification] parsed unread
   count: N` for what was actually parsed vs. what the server intended.
3. `markAsRead`/`markAllAsRead`/`deleteNotification` failed silently (empty catch blocks) — the
   optimistic local decrement never happened, so `unreadCount` still reflects the pre-action value
   even though the user believes the action succeeded.
4. Two devices/sessions: server-side unread count changed from another device's action, and this
   client hasn't called `refreshUnreadCount()` since.

---

## Symptom: "Notification list doesn't update after mark-read (card stays highlighted as unread)"

**Check first**: Did `markAsRead(id)`'s try block actually complete, or did the API call throw? The
catch block at `notification_service.dart:214-216` is empty — no log, no state change, no error.

**Likely suspects**:
1. API call to `POST users/notifications/read` failed (network, 401 refresh race, 409 session
   invalidation) — since the catch is silent, there's no visible signal; check network logs /
   `SecureLogger` output for the actual HTTP response.
2. `id` mismatch — `ValueKey(notif.id)` on the `Dismissible` vs. the `notification_id` sent in the
   request body; confirm both reference `AppNotification.id` consistently (they do in current code,
   but check after any refactor).
3. Screen wasn't rebuilt — confirm `ref.watch(notificationProvider)` (not `ref.read`) is used in
   `build()` (`notifications_screen.dart:35`) so the optimistic update actually triggers a rebuild.

---

## Symptom: "Push received but not in list" (or: notification shown in system tray but absent from inbox after tapping)

**Check first**: Confirm the inbox screen actually called `load()` on open — add a log at
`notifications_screen.dart:29`. Since FCM data is NEVER written into `NotificationState` (RULE-
NOTIFICATIONS-001), "not in list" almost always means the SERVER hasn't persisted the notification row
yet, or the fetch happened before the server-side write completed (race between push dispatch and the
DB write that backs `GET users/notifications`).

**Likely suspects**:
1. Server writes the `notification_log` row asynchronously AFTER dispatching the push — a fast app
   open (dispatch → tap → fetch, all within ~1s on a fast device/network) can beat the DB write.
   `unconfirmed` server-side ordering — verify with backend if this is reproducible.
2. `fetchNotifications()` only returns what `data['data']` contains as a `List` — if the server ever
   returns `data: null` or a non-list, the method returns `[]` silently (`notification_service.dart:56-61`)
   with no error surfaced — check raw response body.
3. The push itself never resulted in a server-side log row (e.g. `NotificationTemplate` missing on the
   backend, if it mirrors the sibling `fintect_application`'s pattern where `create_log()` silently
   no-ops on a missing template) — backend-side investigation, outside this repo.

---

## Symptom: "Mark All Read button doesn't appear even though there are unread notifications"

**Check first**: `hasUnread = state.notifications.any((n) => !n.isRead)` (`notifications_screen.dart:37`)
— this reads the CURRENTLY LOADED list, not `state.unreadCount`. If `unreadCount` was set by
`refreshUnreadCount()` to a nonzero value but the list itself (from a stale `load()`) shows all-read,
the button won't render even though the badge shows unread.

**Likely suspects**:
1. Stale list — `load()` wasn't called on this screen open (shouldn't happen given `initState`, but
   check if `ref.invalidate`/navigation caching skipped it).
2. `state.isLoading == true` suppresses the button even with unread items present — check if loading
   state is stuck (network hang with no timeout hit yet).

---

## Symptom: "FCM token never registers with backend / push not received on a specific device"

**Check first**: `SecureStorageService.getFcmToken()` vs. the current `FcmService.getToken()` — if
they already match, `registerFcmToken` intentionally skips the network call (`notification_service.dart:118-122`).
Clear the secure storage key or reinstall to force a fresh registration for testing.

**Likely suspects**:
1. `FcmService.init()` never ran — confirm `main.dart:65` executed and Firebase was initialized first
   (`FcmService.getToken()` requires Firebase init per the comment at `mpin_screen.dart:753`).
2. Registration call fires only after login (`mpin_screen.dart`, `pin_creation_screen.dart`) — a user
   who never completes login on this device never registers a token.
3. Silent catch in `registerFcmToken` (`notification_service.dart:143-145`) swallowed an error — check
   `kDebugMode` logs for `[FCM] Token registration failed: ...`.
4. `device_id`/`device_info` fields from `DeviceIdService` came back null/malformed, causing a
   server-side validation rejection that the client doesn't surface distinctly from any other failure.

---

## Symptom: "Foreground push doesn't show a banner on Android"

**Check first**: Confirm this is Android (iOS shows FCM foreground banners natively via
`presentAlert/presentBadge/presentSound` in `DarwinNotificationDetails`) — this is a known Android FCM
behavior, not necessarily a bug. Verify `FirebaseMessaging.onMessage` listener is registered
(`fcm_service.dart:92`) and the app has notification permission granted (`_messaging.requestPermission`
at init, `fcm_service.dart:68-72`).

**Likely suspects**:
1. `message.notification == null` (data-only message) — `_handleForegroundMessage` returns early if so
   (`fcm_service.dart:133`) since there's no title/body to show; a pure data payload requires the
   sender to also include a `notification` block, or the app needs custom handling (not currently
   implemented) to show data-only pushes in foreground.
2. Android notification channel not created (`_androidChannel` setup failed silently) —
   check `resolvePlatformSpecificImplementation` didn't return null on this device/OS version.
3. `POST_NOTIFICATIONS` runtime permission (Android 13+) not granted — `requestPermission()` covers
   iOS/Android 13+ but a user who denied it will receive no visible banner even though FCM delivery
   itself succeeded.
