---
module: mpin
last_updated: 2026-08-19
---

# BUSINESS_RULES — MPIN

## RULE-MPIN-001: PIN length is 6 digits, not 4
`MpinNotifier.pinLength = 6` (`lib/core/services/mpin_service.dart:151`). Both `mpin_screen.dart` (`:414` keypad indicator loop) and `change_mpin_screen.dart` (`:254` keypad indicator loop) key off this constant. UI copy confirms: "Create a 6-digit PIN" (`mpin_screen.dart:371`), "Enter your existing 6-digit MPIN" (`change_mpin_screen.dart:55`). Supersedes `STARTGOLD_DOCUMENTATION.md` §3.8's "4-digit" claim.

## RULE-MPIN-002: All MPIN payload fields are RSA-encrypted before transmission
`mpin`, `old_mpin`, `new_mpin` are listed in `AppConfig.sensitiveFields` (`lib/core/config/app_config.dart:93-95`); `mpin/create`, `mpin/validate`, `mpin/change`, `mpin/reset` are listed in `AppConfig.encryptedEndpoints` (`:63-66`). `api_interceptor.dart:170-177` calls `EncryptionService.encryptJson()` on the full request body for any matched endpoint. `temp_token` (used in `reset_pin`) is **not** in `sensitiveFields` and is sent in plain text.

## RULE-MPIN-003: Server response is always HTTP 200; success/failure is an application-level flag
Both `MpinService.verifyMpin` (`mpin_service.dart:36`) and `changeMpin`/`setMpin`/`resetMpin` explicitly comment and code around "Server returns HTTP 200 even on failure — must check app-level flag" — callers must check `data['success']`, not rely on HTTP status, except for the synthesized 401 (see RULE-MPIN-004).

## RULE-MPIN-004: A `SESSION_EXPIRED` code inside a 200 response is manually escalated to a 401 DioException
`MpinService.verifyMpin` (`mpin_service.dart:39-51`) checks `data.error.code` / `data.data.code` for `'SESSION_EXPIRED'` on an otherwise-200 response and synthesizes a `DioException(statusCode: 401)` to force it through the standard error-handling path in `MpinNotifier.verifyMpin`, which then sets `state.error = 'SESSION_EXPIRED'` — consumed by `mpin_screen.dart`'s `ref.listen` (`:199-222`) to toast, wipe secure storage, and redirect to `/login`.

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
