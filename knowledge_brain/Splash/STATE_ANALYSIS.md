---
module: splash
last_updated: 2026-08-19
---

# Splash — State Analysis

## Riverpod providers

**None owned by this module.** `splash_screen.dart` uses no `Consumer`/`ConsumerStatefulWidget` —
it is a plain `StatefulWidget`. It does not watch any provider (including `appControlProvider`,
which it deliberately bypasses — see `CROSS_MODULE_MAP.md`).

## Local widget state (`_SplashScreenState`)

| Field | Type | Purpose |
|---|---|---|
| `_animationController` | `AnimationController` | drives the 800ms fade-in |
| `_fadeAnimation` | `Animation<double>` | derived from `_animationController` |
| `_versionInfo` | `AppVersionInfo?` | set when an update is detected (live or cached), consumed by `_showUpdateDialog()` |

No `setState()` calls exist in this file at all — the widget tree is static after first build;
all "state" is really just local `Future`/`async` control flow inside `_initializeApp()`, and the
only visible transition is navigation away from the screen (or the dialog painted on top of it).

## Secure storage keys touched (read-only from this module)

| Key (via `AppConfig`) | Read by |
|---|---|
| Token (`AppConfig.keyToken`, indirectly via `SessionManager.isAuthenticated()`) | `secure_storage_service.dart` |
| `AppConfig.keyIsMpinEnabled` | `SecureStorageService.isMpinEnabled()` |

Splash writes nothing to secure storage. It writes to **`SharedPreferences`** (not secure
storage — deliberate, since the cached payload is non-sensitive version/maintenance metadata):
key `cached_version_control` (`splash_screen.dart:155`).

## Model shapes consumed

`AppControlData` / `AppVersionInfo` / `PlatformVersionInfo` / `MaintenanceInfo` — all defined in
`core/models/app_control_model.dart` (not owned by this module; see that file for the full
`fromJson` shape). Splash reads `controlData.maintenance.isEnabled`, `controlData.versionInfo`,
and `versionInfo.current` (platform-specific block).
