---
module: splash
brain_status: 🔵 100% (built, verified)
last_updated: 2026-08-19
round: 1
---

# Splash — Module Brain

## 0. TL;DR

`splash` is a **single-file app-init gate**: `lib/features/splash/splash_screen.dart` (298 lines,
one `StatefulWidget`). It runs once at app launch (`AppRouter.splash` is `initialRoute` in
`lib/main.dart:96`), decides session/mpin/maintenance/update state, and replaces itself with
exactly one of: `/maintenance`, a blocking update dialog (stays on `/splash`), `/mpin`, or
`/login`. It has no controller, service, model, or provider of its own — it calls
`core/security/session_manager.dart`, `core/security/secure_storage_service.dart`, and
`core/services/app_control_service.dart` directly from the widget's `State`.

**Confirmed drift vs `STARTGOLD_DOCUMENTATION.md` §3.1 and the module's "first-run" framing**:
splash **never checks onboarding status**. There is no call to `SessionManager.hasSeenOnboarding()`
anywhere in `splash_screen.dart`, and a repo-wide grep confirms no code path anywhere navigates to
`AppRouter.onboarding` (see `Onboarding/MODULE_BRAIN.md` — that route is orphaned). Splash's
routing decision is purely: maintenance → update → (logged-in + mpin-enabled) → else login. This
matches `STARTGOLD_DOCUMENTATION.md`'s own bullet list (which likewise omits onboarding from the
routing logic) but contradicts the general "first-run gate" mental model implied by the module
registry description.

## 1. Inventory

| Path | Role |
|---|---|
| `lib/features/splash/splash_screen.dart` | Sole file. `StatefulWidget` + `SingleTickerProviderStateMixin`, `_SplashScreenState`. |

No `screens/`, `controller/`, `providers/`, `models/`, `services/`, or `widgets/` subfolders exist
under `lib/features/splash/` (confirmed via directory listing).

Route registration (external, per convention):
- `lib/routes/app_router.dart:44` — `import '../features/splash/splash_screen.dart';`
- `lib/routes/app_router.dart:64` — `static const String splash = '/splash';`
- `lib/routes/app_router.dart:129` — `splash: (context) => const SplashScreen(),`
- `lib/main.dart:96` — `initialRoute: AppRouter.splash` (the app's entry route).

## 2. Screen: SplashScreen

`splash_screen.dart:17-297`. `StatefulWidget`, `_SplashScreenState`
(`:24`, mixin `SingleTickerProviderStateMixin` for the fade animation).

| Attribute | Detail |
|---|---|
| Route | `/splash` (`AppRouter.splash`), also the app's `initialRoute` |
| State mgmt | Plain `setState`/field mutation — no Riverpod `Consumer` in this file |
| Providers watched | None |
| API calls | `AppControlService().fetchAppControl()` — instantiated directly in `_initializeApp()` (`:78`), **not** via a Riverpod provider (contrast with `core/providers/app_control_provider.dart`, which other screens use) |
| Encryption | None — `app/control` needs no auth and carries no sensitive fields |
| Navigation out | `Navigator.pushReplacementNamed` to one of `AppRouter.maintenance`, `AppRouter.mpin`, `AppRouter.login` (`:130-134`); or stays on `/splash` and shows a dialog if an update is required (`:125-128`) |
| Security | `PopScope(canPop: false)` — back press exits the app via `SystemNavigator.pop()` (`:232-238`). No screenshot-block call in this file (no sensitive data shown). |

### 2.1 Init sequence (`_initializeApp`, `:50-135`)

1. Start a 2000ms minimum-display timer in parallel (`minSplashDuration`, `:51-52`) — enforced at
   `:119` via `await minSplashDuration` before any navigation, so the branded splash is never
   flashed for less than 2s regardless of API latency.
2. `loggedIn = await SessionManager.isAuthenticated()` (`:58`) — true iff a non-empty token exists
   in secure storage AND the session wasn't force-logged-out (`session_manager.dart:18-22`).
3. `mpinEnabled = await SecureStorageService.isMpinEnabled()` (`:59`) — reads the
   `keyIsMpinEnabled` secure-storage flag (`secure_storage_service.dart:26-29`).
   Both calls are wrapped in one `try/catch` that silently swallows errors (`:57-62`) — a
   secure-storage read failure defaults both flags to `false`, i.e. falls through to `/login`.
4. `nextRoute` defaults to `AppRouter.login` (`:69`); becomes `AppRouter.mpin` only if **both**
   `loggedIn && mpinEnabled` (`:70-72`) — see RULE-SPLASH-004.
5. Fetch `app/control` via `AppControlService.fetchAppControl()` (`:78-79`, POST, no auth,
   `app_control_service.dart:41-59`). Wrapped in try/catch; a `null` response or thrown exception
   both fall through to `_tryLoadCachedVersionInfo()` (`:112`, `:116`) — see §2.3.
6. If a response was parsed (`AppControlData.fromJson`, `:82`):
   - **Maintenance gate** (`:85-88`): if `controlData.maintenance.isEnabled`, set
     `maintenanceArgs = {'resumeRoute': nextRoute}` (preserving the login-vs-mpin decision already
     computed) and overwrite `nextRoute = AppRouter.maintenance`.
   - **Version gate** (`:92-109`): only evaluated `if (versionInfo != null &&
     !controlData.maintenance.isEnabled)` — i.e. **maintenance always wins**; the update check is
     skipped entirely this launch if maintenance is on. Compares
     `PackageInfo.fromPlatform().version` against `versionInfo.current.latestVersion` via
     `_isLower()` (semantic 3-part compare, `:138-152`). If lower: `updateNeeded = true`, caches
     the raw JSON to `SharedPreferences` (`_cacheVersionInfo`, key `cached_version_control`,
     `:159-165`) so the dialog can still appear on a future launch even if `app/control` is
     unreachable. If not lower: clears that cache (`_clearVersionCache`, `:167-172`).
7. `await minSplashDuration` (`:119`), then:
   - If `updateNeeded && _versionInfo != null` → `_showUpdateDialog()` and **return** — stays on
     `/splash`, dialog painted on top (`:125-128`).
   - Else → `Navigator.pushReplacementNamed(context, nextRoute, arguments: maintenanceArgs)`
     (`:130-134`).

### 2.2 Update dialog (`_showUpdateDialog`, `:209-220`)

Uses the app-global `navigatorKey` (imported from `main.dart`, `:13`) via
`WidgetsBinding.instance.addPostFrameCallback` to get a `BuildContext` with a `Navigator` ancestor,
then calls `AppUpdateDialog.show(navContext, versionInfo: _versionInfo!, forceUpdate: true)`.
**`forceUpdate` is hardcoded `true`** regardless of the server's actual `AppVersionInfo.forceUpdate`
flag or the `minVersion`-vs-`latestVersion` distinction the model supports — see RULE-SPLASH-007.
`AppUpdateDialog` itself (`shared/widgets/app_update_dialog.dart`) blocks back-press
(`PopScope(canPop:false)` → `SystemNavigator.pop()` on Android, `:53-62`) and offers only an
"Update Now" CTA that opens the store URL via `url_launcher` (`:171-177`) — no dismiss path exists
once shown from splash.

### 2.3 Offline/failure fallback — cached version check

`_tryLoadCachedVersionInfo()` (`:176-206`) reads the same `SharedPreferences` cache written in
§2.1 step 6, re-parses it as `AppControlData`, and re-runs the identical `_isLower` comparison
against the **currently installed** version — so a user who updated since the cache was written
correctly clears the stale flag (`:197-201`) instead of being stuck showing an outdated dialog.
This path only runs the version check — it never re-evaluates maintenance from cache (maintenance
is time-sensitive and always requires a live fetch).

### 2.4 UI (visual only, `build`, `:229-296`)

3-layer `Stack`: full-bleed background image `assets/resources/splash_bg.png` (gradient fallback
on load error), a centered animated GIF `assets/resources/Splashscreen.gif` (static
`splash.png` fallback), and a footer SVG `assets/resources/splash_footer.svg`. Fade-in via
`AnimationController` (800ms, `Curves.easeIn`, `:34-46`).

## 3. Business Rules

See `BUSINESS_RULES.md` for the full RULE-SPLASH-NNN list (9 rules) — highlights: maintenance
strictly outranks the update dialog and the login/mpin decision (RULE-SPLASH-002/003); `/mpin`
requires **both** `isAuthenticated()` and `isMpinEnabled()` (RULE-SPLASH-004); app-control fetch
failures are silent and never block routing (RULE-SPLASH-005); onboarding is not part of the gate
at all (RULE-SPLASH-008).

## 4. Top Risks

1. **Onboarding is unreachable from splash** (and from anywhere else — see `Onboarding` brain).
   If product intends a first-run carousel, the wiring to check `hasSeenOnboarding()` here is
   simply absent — not broken, never built (or removed). `splash_screen.dart:50-135` has no such
   branch.
2. **`forceUpdate: true` hardcoded** in `_showUpdateDialog()` (`:213-217`) means every detected
   update is a hard block on splash, regardless of the server's soft/hard update intent
   (`AppVersionInfo.forceUpdate`, `PlatformVersionInfo.minVersion`) — those fields are parsed but
   unused by this call site. `core/providers/app_control_provider.dart` computes a real
   `forceUpdate` vs `updateRequired` distinction for its own consumer
   (`shared/widgets/app_control_wrapper.dart`), so the model/logic to do this correctly already
   exists elsewhere in the codebase; splash just doesn't use it.
3. **Direct service instantiation bypasses the provider layer.** `AppControlService()` is `new`'d
   directly in `_initializeApp()` (`:78`) instead of going through
   `core/providers/app_control_provider.dart`'s `appControlProvider`, which the rest of the app
   uses (`shared/widgets/app_control_wrapper.dart`, `shared/widgets/maintenance_gate.dart`,
   `maintenance_screen.dart`). This means splash's app-control fetch and the global
   `AppControlNotifier`'s fetch are two independent, uncoordinated network calls at startup — not
   a bug per se (splash needs a result before the provider tree is even built), but worth knowing
   before "simplifying" either call site.

## 5. See Also
- `METHOD_INDEX.md` — every method in `_SplashScreenState`, file:line, callers.
- `DATA_FLOW.md` — the full init → routing flow end to end.
- `BUSINESS_RULES.md` — RULE-SPLASH-001..009.
- `CROSS_MODULE_MAP.md` — deps on `core/`, `routes/`, `shared/`; Mermaid graph.
- `STATE_ANALYSIS.md` — local fields, no Riverpod state.
- `FORENSIC_TEMPLATE.md` — symptom → suspect entries.
- `COVERAGE_TRACKER.md` — Round 1 coverage.
