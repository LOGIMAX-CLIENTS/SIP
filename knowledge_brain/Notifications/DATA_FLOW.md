# Data Flow — Notifications

---

## Flow 1: Screen open → fetch list → render

```
NotificationsScreen.initState()                                   notifications_screen.dart:28-30
  └─ WidgetsBinding.addPostFrameCallback
       └─ ref.read(notificationProvider.notifier).load()          notification_service.dart:190
            ├─ state = copyWith(isLoading: true, error: null)
            ├─ NotificationService.fetchNotifications()            notification_service.dart:53
            │    └─ ApiClient.post('users/notifications')
            │         └─ response.data['data'] (List) → AppNotification.fromJson per item
            ├─ unread = list.where(!isRead).length
            └─ state = copyWith(notifications: list, isLoading: false, unreadCount: unread)

build() re-runs (ref.watch(notificationProvider))                  notifications_screen.dart:35
  └─ state.isLoading ? shimmer : state.error != null ? error card
     : state.notifications.isEmpty ? empty state : _buildList(state)
```
Error path: any thrown exception in `fetchNotifications()` is caught in `load()`,
`state.error = e.toString()` → `_buildError()` renders with a Retry button that re-calls `load()`.

---

## Flow 2: Mark single as read (tap unread card)

```
_buildCard onTap (only if !notif.isRead)                           notifications_screen.dart:200-203
  └─ ref.read(notificationProvider.notifier).markAsRead(notif.id)  notification_service.dart:202
       ├─ NotificationService.markAsRead(id)
       │    └─ ApiClient.post('users/notifications/read', {'notification_id': id})
       ├─ [on success] optimistic local update:
       │    updated = notifications.map(n => n.id==id ? n.copyWith(isRead:true) : n)
       │    state = copyWith(notifications: updated, unreadCount: updated.where(!isRead).length)
       └─ [on exception] caught, swallowed — state unchanged, no error surfaced
```
Note: this updates `NotificationState.unreadCount` **client-side** from the mutated list — it does
NOT call `fetchUnreadCount()`. The Home badge (`unreadCountProvider`) reads this same
`NotificationState.unreadCount` field, so it updates immediately and consistently on this specific
path (unlike the drift scenario in Flow 4 below).

---

## Flow 3: Mark all as read

```
GradientHeader trailing "Mark All Read" (visible only if hasUnread && !isLoading)  notifications_screen.dart:45
  └─ _onMarkAllRead() → confirm AlertDialog → onPressed: Confirm
       └─ ref.read(notificationProvider.notifier).markAllAsRead()  notification_service.dart:219
            ├─ NotificationService.markAllAsRead()
            │    └─ ApiClient.post('users/notifications/read-all')  (no body)
            ├─ [on success] updated = notifications.map(n => n.copyWith(isRead:true))
            │    state = copyWith(notifications: updated, unreadCount: 0)
            └─ [on exception] swallowed silently — UI shows no error, list may still show unread cards
```

---

## Flow 4: Delete (swipe) — success/failure branches, badge NOT reconciled with server

```
Dismissible.confirmDismiss (swipe endToStart)                      notifications_screen.dart:168-178
  └─ ref.read(notificationProvider.notifier).deleteNotification(notif.id)  notification_service.dart:229
       ├─ NotificationService.deleteNotification(id)
       │    └─ ApiClient.post('users/notifications/delete', {'notification_id': id})
       ├─ [on success] updated = notifications.where(n.id != id)
       │    state = copyWith(notifications: updated, unreadCount: updated.where(!isRead).length)
       │    return true → Dismissible actually removes the card, AppToast "Notification removed"
       └─ [on exception] return false → Dismissible animates the card back into place, no toast
```

---

## Flow 5: Badge count refresh (Home) — separate code path from the inbox list

```
HomeScreen.initState() / pull-to-refresh / post-purchase listener   home_screen.dart:45,145,184
  └─ ref.read(notificationProvider.notifier).refreshUnreadCount()  notification_service.dart:246
       ├─ NotificationService.fetchUnreadCount()                    notification_service.dart:82
       │    └─ ApiClient.post('users/notifications/unread-count')
       │         └─ tolerant parse: {"data":{"count"|"unread_count"}} | {"data":N}
       │                            | top-level {"count"|"unread_count"}
       └─ state = copyWith(unreadCount: count)   ← OVERWRITES whatever the list-derived count was

HomeScreen header widget                                            home_screen.dart:1116
  └─ ref.watch(unreadCountProvider) → Provider<int> reading NotificationState.unreadCount
       └─ badge renders if unreadCount > 0, bell tap → Navigator.pushNamed(AppRouter.notifications)
```
**Key coupling**: `unreadCountProvider` and the inbox screen's list both read/write the SAME
`NotificationState.unreadCount` field via the SAME `notificationProvider`. There is no separate
"badge state" — this is intentional (single source), but it means whichever of `load()` /
`refreshUnreadCount()` / `markAsRead()` / `markAllAsRead()` / `deleteNotification()` ran **most
recently** wins. If Home calls `refreshUnreadCount()` (server-authoritative) after the inbox screen
already did a client-side optimistic mark-read, the two won't diverge as long as the server is
consistent — but if a push notification arrives and increments the server-side count while the app
is foregrounded on some OTHER screen, the badge only updates on the next explicit
`refreshUnreadCount()` call (Home init / pull-to-refresh / the post-purchase listener) — there is no
FCM-driven live badge increment.

---

## Flow 6: Push notification delivery (FCM) — trigger-only, never a data source

```
Push arrives at device (any app state: foreground / background / terminated)

FOREGROUND:
  FirebaseMessaging.onMessage → FcmService._handleForegroundMessage    fcm_service.dart:130
    └─ flutter_local_notifications.show(...) manually (Android does not auto-banner FCM in foreground)
       payload: jsonEncode(message.data)   ← carried but only used to detect a tap happened, not parsed
    └─ [user taps the local notification] onDidReceiveNotificationResponse → _onLocalNotifTap
         └─ _navigateToNotifications() → pushNamed(AppRouter.notifications)
              └─ NotificationsScreen mounts → Flow 1 (fresh API fetch) — FCM data discarded

BACKGROUND (app in background, user taps system tray notification):
  FirebaseMessaging.onMessageOpenedApp → _handleNotificationOpen        fcm_service.dart:162
    └─ _navigateToNotifications() → same as above

TERMINATED (app was closed, launched via notification tap):
  FcmService.init() → _messaging.getInitialMessage() → if non-null,
    Future.delayed(1s) → _handleNotificationOpen(initial)                fcm_service.dart:98-103
    (1s delay is so navigatorKey is attached after app startup)
```
No code path in this module ever reads `message.data` or `message.notification` fields into
`NotificationState` — the inbox is ALWAYS populated by `GET users/notifications`, never by the push
payload itself. This is stated explicitly in code comments at both `notifications_screen.dart:27-30`
and `fcm_service.dart:159-161,184-185`.
