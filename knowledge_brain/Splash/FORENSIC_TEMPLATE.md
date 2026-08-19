---
module: splash
last_updated: 2026-08-19
---

# Splash — Forensic Template

| Symptom | Check first | Likely suspects |
|---|---|---|
| App hangs on splash screen forever (never navigates) | Is `_initializeApp()` throwing outside its own try/catch blocks? Check `mounted` guard at `:121` — if the widget was disposed before the async chain finished, navigation is silently skipped. | An exception in `AppControlData.fromJson(raw)` (`:82`) that isn't caught by the surrounding `try` (unlikely — it is inside the same block) or a `PackageInfo.fromPlatform()` failure outside a try/catch during the version-check branch (`:95-96`, `:187-189` — these ARE inside outer try/catch, but verify). |
| Update dialog shows every single launch even after updating | `SharedPreferences` cache not cleared. Check `_clearVersionCache()` is actually reached — it only runs on the "not lower" branch (`:107`), never on the cache-fallback path unless `_tryLoadCachedVersionInfo()`'s own clear fires (`:199`). | Stale `cached_version_control` key; server `latest_version` misconfigured; device clock/version string malformed causing `_isLower` to always return true. |
| User with valid session lands on `/login` instead of `/mpin` | Re-check both `isAuthenticated()` AND `isMpinEnabled()` — RULE-SPLASH-004 requires both. | MPIN was reset/disabled server-side or locally without updating the secure-storage flag; secure storage read threw and was swallowed by the `try/catch` at `:57-62`, defaulting both to `false`. |
| Maintenance banner never appears despite server flag being on | Confirm `app/control` actually returned 200 with `data.maintenance.is_enabled: true` — a network failure here silently skips the maintenance branch entirely (RULE-SPLASH-005) and falls through to normal login/mpin routing. | `AppControlService.fetchAppControl()` returning `null` (timeout, non-200, malformed body) — the whole maintenance/version block is skipped in that case. |
| Splash is visibly shorter than 2s (looks like a flash) | Verify `minSplashDuration` await at `:119` actually executes — if `_initializeApp` returns/throws before reaching that line, the guarantee doesn't apply. | An unhandled exception between `:50` and `:119` bypassing the `await minSplashDuration` line entirely (would also likely surface as a crash, not just a fast splash). |
| Update dialog shows but "Update Now" does nothing | Check `versionInfo.current.storeUrl` is non-empty and a valid URL `canLaunchUrl` accepts. | Empty/missing `store_url` in the server's `app/control` response for the current platform block. |
