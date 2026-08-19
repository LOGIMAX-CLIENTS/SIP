---
module: maintenance
last_updated: 2026-08-19
---

# Maintenance — Business Rules

| ID | Rule | Code |
|---|---|---|
| RULE-MAINTENANCE-001 | The maintenance screen has no manual retry control. Resume is fully automatic via background polling only — the "Checking status automatically…" row is decorative (spinner + text, no tap target). | `maintenance_screen.dart:222-240` (absence of any `onTap`/`InkWell`/`ElevatedButton` confirmed by full-file read) |
| RULE-MAINTENANCE-002 | On mount, the screen starts a 30-second fast poll of `app/control` via `appControlProvider.notifier.startMaintenancePolling()`. | `maintenance_screen.dart:57-59` → `core/providers/app_control_provider.dart:14-15`, `:86-90` |
| RULE-MAINTENANCE-003 | Independently of the screen-local 30s poll, a global 60-second poll runs app-wide for the entire session once `AppControlWrapper` (which wraps the whole `MaterialApp`) initializes `appControlProvider` at startup. Both timers run concurrently while this screen is visible. | `core/providers/app_control_provider.dart:13`, `:92-95`; `shared/widgets/app_control_wrapper.dart:35-37`; `main.dart:114` |
| RULE-MAINTENANCE-004 | When `AppControlState.isMaintenance` transitions to `false` (detected on any poll tick, either timer), the screen navigates exactly once — guarded by a local `_hasNavigated` flag — via `pushNamedAndRemoveUntil(resumeRoute, (route) => false)`, which clears the entire navigation stack. | `maintenance_screen.dart:36`, `:70-78` |
| RULE-MAINTENANCE-005 | `resumeRoute` is a required constructor argument with three distinct call sites, two of which disagree with the third about session-preservation: `splash_screen.dart` passes the already-computed login/mpin decision (session-aware); `maintenance_gate.dart` (currently unused, zero call sites) and `app_control_wrapper.dart` (the mid-session global redirect) both hardcode `resumeRoute: AppRouter.login` regardless of the user's actual prior route or still-valid session token. A maintenance interruption detected mid-session (e.g. while browsing Home) resumes the user at `/login`, not back into the app. **Unconfirmed** whether intentional. | `splash_screen.dart:86-87` vs `maintenance_gate.dart:39-43` vs `app_control_wrapper.dart:56-60` |
| RULE-MAINTENANCE-006 | Back press exits the app on Android; is a no-op (route still blocked) on iOS. The route is never actually popped by the framework on either platform — `WillPopScope`'s callback always returns `false`. | `maintenance_screen.dart:81-86`, `:98-99` |
| RULE-MAINTENANCE-007 | All displayed copy (title, subtitle, expected-resume time) is server-driven from `MaintenanceInfo`, with hardcoded English fallback strings ("Under Maintenance", "We're upgrading our systems to serve you better.") used when the server sends empty fields. `expectedResume` is optional and its display row is omitted entirely if absent/empty. | `core/models/app_control_model.dart:131-158`; `maintenance_screen.dart:154-172`, `:183-217` |
