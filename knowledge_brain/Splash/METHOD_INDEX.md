---
module: splash
last_updated: 2026-08-19
---

# Splash — Method Index

Single class, no static/global functions outside it. All methods are `_SplashScreenState`
instance methods in `lib/features/splash/splash_screen.dart` unless noted.

| Method | File:Line | Purpose | Called by |
|---|---|---|---|
| `initState()` | `splash_screen.dart:31-48` | Sets up 800ms fade `AnimationController`, kicks off `_initializeApp()` | Flutter framework (widget mount) |
| `_initializeApp()` | `:50-135` | Full init sequence — session check, mpin check, app-control fetch, maintenance/version gating, final navigation | `initState()` |
| `_isLower(String a, String b)` | `:138-152` | Semantic 3-part version compare (`a < b`); returns `false` on parse error | `_initializeApp()` (`:99`), `_tryLoadCachedVersionInfo()` (`:193`) |
| `_cacheVersionInfo(Map raw)` | `:159-165` | Persists raw `app/control` JSON to `SharedPreferences` key `cached_version_control` so the update dialog survives a future offline launch | `_initializeApp()` (`:104`) |
| `_clearVersionCache()` | `:167-172` | Removes the cached version JSON once the user has updated | `_initializeApp()` (`:107`), `_tryLoadCachedVersionInfo()` (`:199`) |
| `_tryLoadCachedVersionInfo()` | `:176-206` | Re-runs the version check against the last cached `app/control` response when a live fetch fails or returns null | `_initializeApp()` (`:112`, `:116`) |
| `_showUpdateDialog()` | `:209-220` | Shows `AppUpdateDialog` on top of splash via the global `navigatorKey`, `forceUpdate: true` hardcoded | `_initializeApp()` (`:126`) |
| `dispose()` | `:223-226` | Disposes `_animationController` | Flutter framework (widget unmount) |
| `build(BuildContext)` | `:229-296` | Renders the 3-layer visual stack inside a `PopScope`/`Scaffold` | Flutter framework |

## External calls made by this module (not owned by `splash`, listed for traceability)

| Call | Defined in | Used at |
|---|---|---|
| `SessionManager.isAuthenticated()` | `core/security/session_manager.dart:18-22` | `splash_screen.dart:58` |
| `SecureStorageService.isMpinEnabled()` | `core/security/secure_storage_service.dart:26-29` | `splash_screen.dart:59` |
| `AppControlService().fetchAppControl()` | `core/services/app_control_service.dart:41-59` | `splash_screen.dart:79` |
| `AppControlData.fromJson(raw)` | `core/models/app_control_model.dart:191-210` | `splash_screen.dart:82`, `:183` |
| `PackageInfo.fromPlatform()` | `package_info_plus` (external package) | `splash_screen.dart:95`, `:187` |
| `AppUpdateDialog.show(...)` | `shared/widgets/app_update_dialog.dart:28-43` | `splash_screen.dart:213-217` |
