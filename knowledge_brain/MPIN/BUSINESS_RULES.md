---
module: mpin
last_updated: 2026-10-12
---

# BUSINESS_RULES — MPIN

## RULE-MPIN-001: PIN length is 6 digits, not 4
`MpinNotifier.pinLength = 6` (`lib/core/services/mpin_service.dart:151`). Both `mpin_screen.dart` (`:414` keypad indicator loop) and `change_mpin_screen.dart` (`:254` keypad indicator loop) key off this constant. UI copy confirms: "Create a 6-digit PIN" (`mpin_screen.dart:371`), "Enter your existing 6-digit MPIN" (`change_mpin_screen.dart:55`). Supersedes `STARTGOLD_DOCUMENTATION.md` §3.8's "4-digit" claim.

## RULE-MPIN-002: All MPIN payload fields are RSA-encrypted before transmission
`mpin`, `old_mpin`, `new_mpin` are listed in `AppConfig.sensitiveFields` (`lib/core/config/app_config.dart:93-95`); `mpin/create`, `mpin/validate`, `mpin/change`, `mpin/reset` are listed in `AppConfig.encryptedEndpoints` (`:63-66`). `api_interceptor.dart:170-177` calls `EncryptionService.encryptJson()` on the full request body for any matched endpoint. `temp_token` (used in `reset_pin`) is **not** in `sensitiveFields` and is sent in plain text.

## RULE-MPIN-003: Server response is always HTTP 200; success/failure is an application-level flag
Both `MpinService.verifyMpin` (`mpin_service.dart:36`) and `changeMpin`/`setMpin`/`resetMpin` explicitly comment and code around "Server returns HTTP 200 even on failure — must check app-level flag" — callers must check `data['success']`, not rely on HTTP status, except for the synthesized 401 (see RULE-MPIN-004).

## RULE-MPIN-004: A `SESSION_EXPIRED` code inside a 200 response is manually escalated to a 401 DioException
`MpinService.verifyMpin` (`mpin_service.dart:39-51`) checks `data.error.code` / `data.data.code` for `'SESSION_EXPIRED'` on an otherwise-200 response and synthesizes a `DioException(statusCode: 401)` to force it through the standard error-handling path in `MpinNotifier.verifyMpin`, which then sets `state.error = 'SESSION_EXPIRED'` — consumed by `mpin_screen.dart`'s `ref.listen` (`:199-222`) to toast, end the session with `SessionManager.endExpiredSession()` (keeps biometric/auto-lock — RULE-MPIN-015), and redirect to `/login`.

## RULE-MPIN-005: A 409 (session invalidated) never surfaces a local error — the interceptor dialog owns it
`MpinNotifier.verifyMpin`'s `DioException` 409 branch (`mpin_service.dart:224-236`) and its `SessionInvalidatedFailure` catch clause (`:264-277`) both deliberately leave `state.error` unset, explicitly to avoid a duplicate toast stacked on top of `SessionInvalidatedDialog` (shown by `api_interceptor.dart:244,276`). `ApiClient` converts the interceptor's rejected `DioException` into a `SessionInvalidatedFailure` before it reaches the notifier, so in practice the `SessionInvalidatedFailure` branch — not the raw `DioException` 409 branch — is the one that actually fires (per the code's own comment at `:264-267`).

## RULE-MPIN-006: 5 failed verify attempts locks the screen client-side
`MpinNotifier.verifyMpin` (`mpin_service.dart:203-213`): on a `success:false` response, `failedAttempts` increments; at `>=5`, `isLocked=true` and the message becomes "ACCOUNT LOCKED: Too many failed attempts. Contact support." The CTA button is disabled while `isLocked` (`mpin_screen.dart:534`), and `verifyMpin()`/`setMpin()`/`resetMpin()` all early-return on `isLocked`/`isLoading` guards. This lock state lives only in the Riverpod `StateNotifier` — it is not persisted, so it resets on app restart or screen recreation. Whether the server independently rate-limits `mpin/validate` is unconfirmed from the client code alone.

## RULE-MPIN-007: Keypad digit order is randomized every render pass using `Random.secure()`
`mpin_screen.dart:_shuffleKeypad()` (`:147-174`) explicitly uses `Random.secure()` "for banking-grade security" (code comment `:160`) via a Fisher-Yates shuffle, re-invoked on `initState`, every `AppLifecycleState.resumed`, and after every failed submit. `change_mpin_screen.dart:_shuffleKeypad()` (`:39-43`) instead uses plain `List.shuffle()` (Dart's default, non-cryptographic `Random()`) — an inconsistency between the two screens in the same module (both exist to defeat shoulder-surfing/screen-recording of tap coordinates).

## RULE-MPIN-008: Biometric is auto-triggered on screen open only for verify-style modes, and never for `app_lock`
`mpin_screen.dart:_loadMpinStatus` (`:91-106`) auto-calls `_authenticateBiometric()` when biometric+MPIN are both enabled AND `type` is none of `{withdrawal_pin, verify_only, app_lock, verify_after_reset}`. The `app_lock` exclusion is intentional — `AppLifecycleObserver` (`app_lifecycle_observer.dart:158-165`) already attempted biometric before ever pushing the MPIN screen; re-prompting here would double-prompt the user.

## RULE-MPIN-009: `PopScope` back-navigation behavior is mode-dependent, not a single blanket rule
`isRootFlow = type==null || type=='setup' || type=='app_lock' || (type=='reset_pin' && from_app_lock) || type=='verify_after_reset'` (`mpin_screen.dart:248-251`). Root flows fully intercept back-press: `app_lock`/`reset_pin`-from-app-lock/`verify_after_reset` block exit entirely with an info toast; the untyped login/`setup` root flow instead allows exit via double-tap-within-2-seconds (`SystemNavigator.pop()`). Non-root types (`verify_only`, `withdrawal_pin`, `authorize_withdrawal`, plain `reset_pin`) get a normal `Navigator.pop`.

## RULE-MPIN-010: "Forgot PIN?" is visible only in login-verify and app-lock contexts
`showForgotPin = routeType == null || routeType == 'app_lock'` (`mpin_screen.dart:513`) — hidden for `setup`, `reset_pin`, `verify_only`, `withdrawal_pin`, `authorize_withdrawal`, `verify_after_reset`. It remains tappable even when `isLocked` is true (the link's `onTap` is not gated on lock state), making it the escape hatch from RULE-MPIN-006's client-side lockout.

## RULE-MPIN-011: New PIN must differ from the old PIN (Change-MPIN flow only)
`change_mpin_screen.dart:_processStep` `enterNew` case (`:89-95`): if the newly entered PIN equals `_oldPin`, the step is rejected in-place with a toast "New PIN must be different from current PIN." — no server round-trip. This check does not exist in the `reset_pin` flow (`mpin_screen.dart`/`MpinService.resetMpin`) — a forgot-PIN reset can reuse the old PIN with no client-side check (server-side enforcement unconfirmed).

## RULE-MPIN-012: Confirm-PIN mismatch returns the user to the "enter new PIN" step, not to "enter old PIN"
`change_mpin_screen.dart:_processStep` `confirmNew` case (`:104-113`): on mismatch, resets `_currentInput` and `_step` back to `enterNew` (not all the way to `enterOld`) — `_oldPin` is preserved across the retry.

## RULE-MPIN-013: FCM token registration is fire-and-forget and never blocks or fails a login
`_registerFcmTokenAfterLogin()` (`mpin_screen.dart:749-764`) wraps `FcmService.getToken()` + `NotificationService.registerFcmToken()` in an un-awaited `Future` with its own try/catch — errors are logged in debug mode only and never surface to the user or block navigation to `main`. Called only from the untyped default and `verify_after_reset` success paths — not from `setup`, `app_lock`, `verify_only`, `withdrawal_pin`, or `authorize_withdrawal`.

## RULE-MPIN-014: Default Auto-Lock is 30 minutes (1800s), and the server's value wins
A customer who never picked an Auto-Lock time follows `APP_CONTROL_MPIN_LOCK.default_timeout_seconds`
(from `POST app/control`, applied to `AppConfig.mpinLockDefaultTimeoutSeconds` by `app_control_provider.dart`
on every poll). The pre-fetch fallbacks — `AppConfig.mpinLockDefaultTimeoutSeconds` (`app_config.dart`) and
`MpinLockConfig.defaults` (`app_control_model.dart`) — are 1800, matching the backend's coded
`DEFAULT_MPIN_LOCK`. The live config row overrides all of these, so changing the default in production is a
config edit (admin → Configuration → `APP_CONTROL_MPIN_LOCK`), not an app release. Once a customer picks a
value it is stored per-customer (`profile/mpin-lock-timing`) and the default no longer applies to them.

## RULE-MPIN-015: Biometric Login and Auto-Lock survive a lapsed session, not a deliberate or security logout
(PM-STG-0452, "Biometric & MPIN reset after Play Store update".) There are two kinds of logout. `SecureStorageService.logout()`
wipes everything except device identity and is used for the Logout button, account deletion, the 409
force-logout and the forgot-PIN "Edit number" escape. `SecureStorageService.endExpiredSession()` is used when
the refresh token is rejected (4xx, or 200 with no token, or none stored) and for mpin/validate's
`SESSION_EXPIRED`. It ends the session too, but keeps `is_biometric_enabled` and `mpin_lock_timeout_seconds`,
tagging them with the customer id (`app_lock_owner_customer_id`). On the next verify-otp or register that names the
customer, `keepAppLockPrefsOnlyFor(id)` keeps them for the same customer and deletes them for anyone else. If
no customer id was stored, it falls back to a full `logout()`. MPIN itself needs nothing kept: verify-otp's
`mpin_enabled` re-seeds `is_mpin_enabled`. So after the same customer logs back in with OTP, the untyped MPIN
screen auto-prompts biometric again (RULE-MPIN-008). A refresh that gets no answer, a 5xx, or the backend's
throttle (HTTP 200 with `TOO_MANY_REQUESTS`) no longer ends the session at all
(`ApiSecurityInterceptor.isTransientRefreshFailure`, RULE-CORE-003).

Why the session lapses so often: backend `SIMPLE_JWT` gives a 15-minute access token and a 1-day refresh token,
and each refresh resets that day (`fintect_application` `config/settings.py`; `TokenRefreshView` calls
`set_exp()` without the `CUSTOMER_LOGIN_SECURITY` override). Anyone who doesn't open the app for a day must log
in with OTP again, and the first open after a Play Store update is usually such a case. Before this rule, that
re-login also wiped biometric/auto-lock, which is what PM-STG-0452 reported. The backend never resets an MPIN
or ends a session because of `appVersion`/`device_id`. Its only "MPIN off" state is the 5-wrong-attempts lock
(`ccr_status=2`), and verify-otp reports that as `mpin_enabled=false`, so the app routes to `setup`.

Separately, `BiometricService.canUseBiometric()` only auto-disables the stored flag when the OS answers "no
screen lock / nothing enrolled". If `local_auth` throws, it falls back to MPIN for that attempt and keeps the
customer's choice. Tests: `test/app_lock_persistence_test.dart`.
