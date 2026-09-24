# State Analysis — Notifications

---

## Riverpod Providers

| Provider | Type | File:Line | Scope | Notes |
|---|---|---|---|---|
| `notificationServiceProvider` | `Provider<NotificationService>` | `notification_service.dart:151` | App-wide singleton (per Riverpod container) | Simple DI, no override seen |
| `notificationProvider` | `StateNotifierProvider<NotificationNotifier, NotificationState>` | `notification_service.dart:257` | App-wide | The single source of truth for both the inbox list AND the badge count |
| `unreadCountProvider` | `Provider<int>` | `notification_service.dart:263` | App-wide | Derived: `ref.watch(notificationProvider).unreadCount` — thin projection so Home doesn't need the full list |

No `family` providers, no `autoDispose` — state persists for the app session (until process death),
consistent with "cached badge count that should survive navigating away from the inbox screen".

## Model Shapes

### `AppNotification` (`notification_service.dart:9-45`)
| Field | Type | Source key | Notes |
|---|---|---|---|
| `id` | `int` | `id` | Defaults to `0` if missing |
| `title` | `String` | `title` | Defaults to `''` |
| `message` | `String` | `message` | Defaults to `''` |
| `type` | `String` | `type` | Drives icon/color in the UI (`market/transaction/kyc/withdrawal/offer`, else default bell icon) |
| `isRead` | `bool` | `is_read` | Accepts either boolean `true` or integer `1` (`json['is_read'] == true \|\| json['is_read'] == 1`) — defensive against a backend that may serialize booleans as 0/1 |
| `createdAt` | `String` | `created_at` | Rendered as-is (no client-side date parsing/formatting — `unconfirmed` whether the server already formats this for display) |

No `toJson()` on `AppNotification` — it's a read-only/display model; the app never sends a full
notification object back to the server, only `notification_id`.

### `NotificationState` (`notification_service.dart:156-183`)
| Field | Type | Default | Notes |
|---|---|---|---|
| `notifications` | `List<AppNotification>` | `[]` | |
| `isLoading` | `bool` | `false` | |
| `error` | `String?` | `null` | Set from `e.toString()` — raw exception text (see Risk below) |
| `unreadCount` | `int` | `0` | Dual-write source, see `BUSINESS_RULES.md` RULE-NOTIFICATIONS-003 |
| `computedUnread` (getter) | `int` | — | `notifications.where((n) => !n.isRead).length` — declared but **not referenced anywhere** in the screen or Home (`grep` found only the declaration); the screen instead inlines the same `.any((n) => !n.isRead)` check directly (`notifications_screen.dart:37`). Minor dead-code / duplication. |

### Risk: raw exception text surfaced to `NotificationState.error`
`load()` does `state = state.copyWith(isLoading: false, error: e.toString())` — this is a raw Dart/Dio
exception string, not a mapped `Failure` type per AGENTS.md §5 ("map API/network errors to a `Failure`
type at the service layer, don't let raw `DioException`s leak into widgets"). In practice the screen
doesn't even display `state.error`'s text (`_buildError` shows a static "Failed to load notifications"
message and ignores the `error` string parameter's content), so there's no current UI leak, but the
raw string is available in state if a future screen change reads it directly.
- Code: `lib/core/services/notification_service.dart:197-198`, `lib/features/notifications/notifications_screen.dart:439-443`.

## Secure Storage Keys Touched

| Key | Constant | Read by | Written by |
|---|---|---|---|
| FCM device token | `AppConfig.keyFcmToken` | `NotificationService.registerFcmToken` (dedup check) | `NotificationService.registerFcmToken` (after successful registration) |

No MPIN/biometric/session data touched by this module — it only reads/writes the one FCM token key.

## Local (non-Riverpod) State

`_NotificationsScreenState` holds no local mutable state beyond the widget tree itself — all data
comes from `ref.watch(notificationProvider)`. `NomineeScreen`-style form controllers are not present
here (no form in this module).
