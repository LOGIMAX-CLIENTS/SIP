---
module: splash
last_updated: 2026-08-19
---

# Splash — Business Rules

| ID | Rule | Code |
|---|---|---|
| RULE-SPLASH-001 | Splash is shown for a minimum of 2000ms regardless of how fast the init sequence (session check + app-control fetch) completes. | `splash_screen.dart:51-52`, awaited at `:119` |
| RULE-SPLASH-002 | Maintenance state takes absolute priority over both the update dialog and the login/mpin routing decision — if `maintenance.isEnabled`, the version check is skipped entirely for this launch and the user is sent straight to `/maintenance`. | `splash_screen.dart:85-94` |
| RULE-SPLASH-003 | The blocking update dialog is only evaluated when maintenance is OFF (`:94` condition `!controlData.maintenance.isEnabled`). | `splash_screen.dart:92-109` |
| RULE-SPLASH-004 | Routing to `/mpin` requires **both** `SessionManager.isAuthenticated() == true` **and** `SecureStorageService.isMpinEnabled() == true`. Any other combination (not logged in, or logged in but mpin never set — e.g. app killed mid-registration before PIN creation) routes to `/login`. | `splash_screen.dart:69-72`, comment at `:65-68` |
| RULE-SPLASH-005 | `app/control` fetch failures (network error, non-200, or thrown exception) are silent — the app never blocks routing on this call. On failure it falls back to a locally cached version-check result (if any) and proceeds with the already-computed login/mpin route. | `splash_screen.dart:110-117` |
| RULE-SPLASH-006 | Version comparison is semantic (major.minor.patch), missing segments are treated as `0`, and any parse error is treated as "not lower" — i.e. malformed version strings never force an update. | `splash_screen.dart:138-152` |
| RULE-SPLASH-007 | The update dialog shown from splash always uses `forceUpdate: true`, regardless of the server's actual `AppVersionInfo.forceUpdate` flag or the soft/hard-update distinction the model otherwise supports (`minVersion` vs `latestVersion`). Any detected update is a hard block on this screen. **Unconfirmed whether intentional** — contrast with `core/providers/app_control_provider.dart`, which computes a real `forceUpdate` vs `updateRequired` split for its own consumer. | `splash_screen.dart:213-217` vs `core/providers/app_control_provider.dart:168-190` |
| RULE-SPLASH-008 | Onboarding status is never checked during the splash routing decision. No call to `SessionManager.hasSeenOnboarding()` exists in this file, and no code path anywhere in `lib/` navigates to `AppRouter.onboarding` (repo-wide grep confirmed, see `Onboarding/MODULE_BRAIN.md`). | `splash_screen.dart:50-135` (absence), confirmed via grep |
| RULE-SPLASH-009 | Back press during splash exits the app immediately — no confirmation, no "press again" pattern (unlike `main`'s home-tab double-tap-to-exit). | `splash_screen.dart:232-238` |
