---
module: splash
last_updated: 2026-08-19
---

# Splash — Data Flow

## Flow 1: App cold start → routing decision (the only flow this module has)

```
main.dart:96  MaterialApp(initialRoute: AppRouter.splash)
   │
   ▼
SplashScreen.initState()                              splash_screen.dart:31
   │  starts 800ms fade AnimationController
   ▼
_initializeApp()                                       splash_screen.dart:50
   │
   ├─ Future.delayed(2000ms)  ─────────────────────────► minSplashDuration (awaited later, :119)
   │
   ├─ SessionManager.isAuthenticated()                  session_manager.dart:18
   │     └─ SecureStorageService.getToken() != null/empty, and !_isForceLoggedOut
   ├─ SecureStorageService.isMpinEnabled()               secure_storage_service.dart:26
   │
   ├─ nextRoute = (loggedIn && mpinEnabled) ? AppRouter.mpin : AppRouter.login   :69-72
   │
   ├─ AppControlService().fetchAppControl()              app_control_service.dart:41
   │     POST app/control  { platform: "android"|"ios"|"web" }   — no auth header
   │     │
   │     ├─ 200 + Map body → raw
   │     │     └─ AppControlData.fromJson(raw)             app_control_model.dart:191
   │     │           ├─ maintenance.isEnabled? ──yes──► nextRoute = AppRouter.maintenance
   │     │           │                                    maintenanceArgs = {resumeRoute: <prior nextRoute>}
   │     │           └─ else, versionInfo present? ──yes──► compare currentVersion vs latestVersion
   │     │                     lower? → updateNeeded=true, cache raw JSON (SharedPreferences)
   │     │                     not lower? → clear cached JSON
   │     │
   │     └─ null / DioException → _tryLoadCachedVersionInfo()
   │                                  reads cached JSON, re-runs the same version compare
   │                                  against the CURRENT installed version
   │
   ├─ await minSplashDuration                              :119  (guarantees ≥2s on screen)
   │
   └─ updateNeeded && _versionInfo != null ?
         ├─ YES → _showUpdateDialog()  (stays on /splash, AppUpdateDialog painted on top)
         └─ NO  → Navigator.pushReplacementNamed(nextRoute, arguments: maintenanceArgs)
                     nextRoute ∈ { AppRouter.maintenance, AppRouter.mpin, AppRouter.login }
```

## Flow 2: Maintenance screen resume (handoff — see Maintenance module)

`splash_screen.dart:87` passes `{'resumeRoute': nextRoute}` as route arguments when redirecting to
`/maintenance`. `nextRoute` here is whatever the login/mpin decision from step "nextRoute =
(loggedIn && mpinEnabled)..." already resolved to — i.e. splash's maintenance redirect is the one
call site that preserves the session-aware target. See `Maintenance/DATA_FLOW.md` for what happens
next (polling, auto-resume).

## Flow 3: Update dialog CTA (handoff — external)

`_showUpdateDialog()` → `AppUpdateDialog.show()` → user taps "Update Now" →
`url_launcher.launchUrl(versionInfo.current.storeUrl, mode: externalApplication)`
(`shared/widgets/app_update_dialog.dart:171-177`) — leaves the app entirely (opens Play
Store/App Store). There is no in-app continuation; the dialog blocks back-press so the only way
back into the app pre-update is force-closing/relaunching, which re-runs Flow 1 from scratch.

## No API-driven UI state beyond the single `app/control` call

Splash renders no data — its only network dependency is the one `app/control` fetch above. No
loading/error widgets are shown in this screen (the fade-in animation plus 2s minimum display
duration substitutes for any explicit loading UI).
