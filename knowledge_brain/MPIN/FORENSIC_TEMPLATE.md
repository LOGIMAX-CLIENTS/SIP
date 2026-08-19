---
module: mpin
last_updated: 2026-08-19
---

# FORENSIC_TEMPLATE — MPIN

Symptom → check first → likely suspects. Use alongside `_SYSTEM/DIAGNOSTIC_PLAYBOOK.md` (not yet built) once it exists.

---

### 1. "App locks repeatedly even when foregrounded / immediately re-locks after unlocking"

**Check first**: is `AppLifecycleObserver._isLockScreenShowing` actually being reset? It's only reset in the `.then()` callback of `_pushMpinLockScreen` (`app_lifecycle_observer.dart:206-208`, fires when the pushed `/mpin` route is popped) or in the biometric-success branch (`:177`). If the MPIN screen is dismissed via any path that doesn't go through a normal `Navigator.pop` on that specific route instance (e.g. `pushNamedAndRemoveUntil(main)` from the default-verify branch, `mpin_screen.dart:737` — which **replaces** the route rather than popping it), the `.then()` callback may never fire, leaving `_isLockScreenShowing` stuck `true` and blocking all future lock attempts (opposite symptom) — or conversely, if it resets prematurely mid-flow, a second `resumed` event (e.g. two lifecycle callbacks firing close together, a known Android quirk) could push a second MPIN screen.

**Likely suspects**:
- Multiple rapid `paused`→`resumed` transitions (e.g. notification shade pull-down on some Android versions can fire lifecycle events) each calling `_checkAppLockOnResume()` — guarded by `_isLockScreenShowing`, but only if that flag is correctly true during the window.
- `suppressAppLock` static flag (`app_lifecycle_observer.dart:39`) left `true` after a payment-SDK flow exits abnormally (crash/force-close mid-payment) — would suppress *future* app-lock entirely, not cause repeated locking, but check this first if the opposite symptom ("app lock never triggers") is reported instead.
- `_pausedAt` not being cleared/reset correctly across two consecutive backgroundings if the MPIN screen itself is still on the stack when the app is backgrounded a second time.

---

### 2. "Biometric never prompts on app resume or on the MPIN screen"

**Check first**: `BiometricService.canUseBiometric()` (`biometric_service.dart:48-61`) — it requires **both** the stored `is_biometric_enabled` flag AND `deviceHasBiometric()` (which itself requires `isDeviceSupported()` AND at least one entry from `getAvailableBiometrics()`). If the device's enrolled fingerprint was removed in OS settings, this method **silently flips the stored flag back to `false`** (`:56-58`) — so a user who previously enabled biometric will see it vanish with no error message, on the very next check.

**Likely suspects**:
- Device has hardware but zero enrolled biometrics (`getAvailableBiometrics()` returns empty) — `deviceHasBiometric()` returns `false` regardless of the stored preference.
- On `mpin_screen.dart`, the `type` argument is one of `{withdrawal_pin, verify_only, app_lock, verify_after_reset}` — auto-trigger is intentionally skipped for these (`:99-106`); user must tap the fingerprint icon manually, and for `withdrawal_pin`/`verify_only`/`verify_after_reset` the icon itself is hidden entirely (`_buildBiometricHint`, `:641-647`) — biometric is **unreachable by design** for those three types, not a bug.
- On app-lock resume specifically, `_cachedBiometricEnabled` was populated during the *previous* `paused` event (`app_lifecycle_observer.dart:83`) — if biometric was enabled *while the app was already backgrounded* (not possible via normal UI, but relevant if investigating a race), the cached value could be stale for that one resume cycle.
- `local_auth` plugin-level failures (OS biometric lockout after too many failed system-level attempts, hardware busy) — `BiometricService.authenticate` swallows all exceptions to `false` (`:97-100`), so the failure is invisible from Dart-side logs alone; check `kDebugMode` `debugPrint` output for `[BiometricService] authenticate error: ...`.

---

### 3. "409 during verify doesn't force logout"

**Check first**: which of the three code paths in `MpinNotifier.verifyMpin` actually fired — add a breakpoint/log at `mpin_service.dart:217` (raw `DioException`), `:264` (`SessionInvalidatedFailure`), and separately check whether `api_interceptor.dart`'s own 409 handling (`:214-246` or the retry-path variants at `:322,355,438,464`) ran at all before the notifier's catch block. Per the code comment at `mpin_service.dart:264-267`, the `SessionInvalidatedFailure` branch is the one expected to actually fire in practice — if a raw 409 `DioException` reaches the notifier instead, it means `ApiClient` did **not** convert it, which would point at a change in `ApiClient`'s error-mapping rather than in this module.

**Likely suspects**:
- `SessionManager.forceLogout()` deduplicates via `_isForceLoggedOut` (`session_manager.dart:32-37`) — if some *other* concurrent request already triggered force-logout and reset in an unexpected order, `isFirstTrigger` could be `false` here, silently skipping the dialog for *this* 409 (by design, to avoid duplicate dialogs — but confirm the dialog fired at all for the first trigger).
- The server response body doesn't match any of the three code-shape checks the interceptor/service look for (`data['error']['code']`, `data['code']`, bare 409 with non-Map body) — if the backend changed its 409 error-body shape, `_extractServerMessage`/the `isSessionInvalidated` boolean in `api_interceptor.dart:218-222` could evaluate `false` unexpectedly, though the `data is! Map` fallback (`:225`) should still catch a fully bare 409.
- Verify the interceptor is even reached — if a raw `Dio()` instance were used instead of the shared `ApiClient` singleton (AGENTS.md §4 violation), no interceptor chain would run at all. `MpinService` correctly uses `ApiClient()` (`mpin_service.dart:9`), so this is a check for regressions, not a current suspect.

---

### 4. "MPIN encryption seems to be missing / server rejects with a decryption error"

**Check first**: `EncryptionService.isRsaReady` (`encryption_service.dart:57`) — if the RSA public key hasn't loaded yet (first launch, or `crypto/public-key` fetch failed), `api_interceptor.dart:135-137` attempts a last-chance synchronous fetch, but if that also fails, the request proceeds **unencrypted** for a sensitive endpoint (verify actual interceptor behavior on fetch failure — this brain has not traced that exact branch to its end; treat as unconfirmed and re-check `api_interceptor.dart` lines beyond 137 if this symptom occurs).

**Likely suspects**:
- New field added to an `mpin/*` request body without also adding its key to `AppConfig.sensitiveFields` (`app_config.dart:74-99`) — per RULE-MPIN-002/DATA_FLOW's encryption-boundary note, adding a field to the Dart map alone does **not** encrypt it; the field name must independently exist in `sensitiveFields`.
- Public-key cache staleness after a server-side key rotation — `EncryptionService.clearKey()` exists for logout but check whether a rotation event on a *still-logged-in* session is handled (not traced in this pass).

---

### 5. "Toggling MPIN on from Settings fails immediately / shows 'Invalid PIN'"

**Check first**: `settings_screen.dart:47-51` pushes `/mpin` with `arguments: {'mobile': mobile}` — no `type` key. Confirm in `mpin_screen.dart:_handleAction` (`:662-744`) which branch this actually reaches: since `type` is `null`, it falls into the **verify** branch (`:712`, calls `verifyMpin()` → `POST mpin/validate`), not the setup branch (`:668`, `setMpin()` → `POST mpin/create`). If the user has no MPIN configured server-side yet, `mpin/validate` should have nothing to validate against and would be expected to fail every attempt.

**Likely suspects**: this is MODULE_BRAIN §7 anti-pattern #1 — the `settings_screen.dart` code comment claims dual setup/unlock behavior "based on isMpinEnabled flag" but no such branching exists in `mpin_screen.dart`. Reproduce by: fresh account with `is_mpin_enabled=false` → Settings → toggle MPIN on → observe whether `mpin/create` or `mpin/validate` is actually called (network log). If confirmed, the fix is either (a) `settings_screen.dart` should pass `type: 'setup'` when `!_isMpinEnabled`, or (b) `mpin_screen.dart`'s untyped branch should itself check `_isMpinEnabledCount` and route to `setMpin()` when false — resolve by reading `settings_screen.dart` in full (not read in this pass beyond lines 20-60) plus a live-app test before changing either file.

---

### 6. "Change MPIN screen leaks PIN digits on screen recording / screenshot"

**Check first**: `change_mpin_screen.dart` has no `ScreenshotSecurityService.secureScreen()`/`releaseScreen()` calls anywhere in the file (confirmed absent — contrast with `mpin_screen.dart:176-189`). This is MODULE_BRAIN §7 anti-pattern #3.

**Likely suspects**: none needed — this is a confirmed gap, not a mystery. Fix would be adding the same `initState`/`dispose` pair used in `mpin_screen.dart`, gated the same way (unconditional, not behind `AppConfig.enableScreenshotProtection` which currently defaults `false` anyway per `app_config.dart:39` — worth separately confirming whether `ScreenshotSecurityService.secureScreen()` itself checks that flag before this fix is prioritized).
