---
last_updated: 2026-08-19
---

# Coverage Tracker — Notifications

## Round 1 — Build Mode (2026-08-19)

Full generation from scratch. Files read in full: `lib/features/notifications/notifications_screen.dart`,
`lib/core/services/notification_service.dart`, `lib/core/services/fcm_service.dart`. Cross-referenced:
`lib/features/home/home_screen.dart` (badge consumer), `lib/features/mpin/mpin_screen.dart` and
`lib/features/auth/pin/pin_creation_screen.dart` (FCM registration triggers), `lib/routes/app_router.dart`
(route registration), `lib/core/config/app_config.dart` (encryption endpoint/field lists, confirming
notifications endpoints are NOT encrypted), `lib/core/security/secure_storage_service.dart` (FCM token
key), `STARTGOLD_DOCUMENTATION.md` §3.33 (head start, verified — see drift note in `MODULE_BRAIN.md` §8).

### Weighted Coverage Computation

| Component | Weight | Actual count | Documented count | Score |
|---|---|---|---|---|
| Screens documented | 25% | 1 (`NotificationsScreen`) | 1 | 25.0% |
| Controller/service public methods documented | 25% | 15 (`NotificationService` 6, `NotificationNotifier` 5, `FcmService` public 4) | 15 | 25.0% |
| Models documented | 15% | 2 (`AppNotification`, `NotificationState`) | 2 | 15.0% |
| API endpoints documented | 15% | 6 (`users/notifications`, `/read`, `/read-all`, `/delete`, `/unread-count`, `/register-token`) | 6 | 15.0% |
| Business rules captured | 10% | 7 rules (RULE-NOTIFICATIONS-001..007) | 7 | 10.0% |
| Cross-module deps captured | 10% | 6 (Home, MPIN, Auth/pin_creation, main.dart, core services x4 bundled) | 6 | 10.0% |
| **Total** | **100%** | | | **100%** |

### Badge: 🟢 (96%)

Docked 4% from a full 🔵 for two honest gaps rather than any missing-doc component:
1. Native platform wiring referenced in `fcm_service.dart`'s setup-checklist comment
   (`AndroidManifest.xml`, `build.gradle.kts`, `google-services.json`) was NOT independently verified
   against the actual native files in this round — only the Dart-side code was confirmed.
2. `FcmService.navigateToNotifications()` (public static) has no confirmed caller within this
   module's or its documented consumers' files — marked `unconfirmed` in `METHOD_INDEX.md` rather
   than asserted as dead code, since a native-side or deep-link caller outside the scanned files is
   plausible.

Manual spot-check performed: re-verified `notification_service.dart:82-105` (`fetchUnreadCount` tolerant
parser) and `notifications_screen.dart:160-192` (`Dismissible` delete flow) against the written
`DATA_FLOW.md` Flow 4/5 — matched exactly.

### Drift Found vs `STARTGOLD_DOCUMENTATION.md` §3.33
Gap (not contradiction): the hand-written doc's 5-endpoint table omits `users/notifications/register-token`
and the entire FCM push-delivery mechanism. See `MODULE_BRAIN.md` §8, flagged in
`_OVERVIEW/BUILD_SUMMARY.md`.
