---
module: auth
last_updated: 2026-08-19
---

# Business Rules — Auth Module

## RULE-AUTH-001: Mobile number must be exactly 10 digits
`Validators.validateMobile()` (`core/utils/validators.dart:2-7`) — regex `^[0-9]{10}$`. Gates the
"Initiate Secure Login" CTA enabled state in `LoginScreen` (`login_screen.dart:89-90, 357`). No country-code
length validation performed client-side — a `+1` (US, 10-digit) and `+91` (India, 10-digit) both pass the
same regex regardless of which is actually selected.

## RULE-AUTH-002: Mobile and OTP are RSA-encrypted before transmission; MPIN too
`AppConfig.sensitiveFields` (`core/config/app_config.dart:74-99`) includes `mobile`, `otp`, `mpin`,
`old_mpin`, `new_mpin`. `AppConfig.encryptedEndpoints` (`app_config.dart:47-71`) includes
`auth/generate-otp`, `auth/verify-otp`, `auth/generate-email-otp`, `auth/verify-email-otp`, `auth/register`,
`mpin/create`, `mpin/validate`, `mpin/change`, `mpin/reset`. The interceptor
(`core/security/api_interceptor.dart:165-182`) only encrypts fields present in `sensitiveFields` AND only for
requests whose path matches `encryptedEndpoints` — both conditions must hold. Confirms AGENTS.md §3's
expectation (mobile/otp/mpin encrypted) is correct for this module.

## RULE-AUTH-003: `auth/register-check` is NOT field-encrypted (gap vs. its sibling `auth/register`)
`register-check` is absent from `encryptedEndpoints` (`app_config.dart:47-71`) even though it carries the
same `mobile` field as `register`, which IS encrypted. Called from
`registration_screen.dart:531-539`. TLS still protects the wire, but this is an inconsistency worth a
backend/security conversation — not something to "fix" unilaterally client-side without confirming the
backend endpoint's own encryption expectations.

## RULE-AUTH-004: Email address itself is never encrypted, only the OTP verifying it
`email` is not in `sensitiveFields`. Both `auth/generate-email-otp` and `auth/verify-email-otp` are in
`encryptedEndpoints`, but since `email` isn't a sensitive field, only `otp` gets RSA-encrypted in those
calls (`core/services/auth_service.dart:98-126`).

## RULE-AUTH-005: New-user vs existing-user branching is server-driven, not client-inferred
The post-verify routing decision (`otp_screen.dart:401-489`) reads `is_new_user` and `mpin_enabled` directly
from the `verify-otp` response body — the client performs no local "have I seen this mobile before" check.
See MODULE_BRAIN.md §5 for the full 5-branch decision tree.

## RULE-AUTH-006: Email verification is mandatory before registration submission
`RegistrationScreen`'s "Confirm" button is disabled unless `_agreedToTerms && _emailVerified`
(`registration_screen.dart:122-123`). Editing the email field after verification silently revokes
`_emailVerified` (lines 55-59) — the user must re-verify. This is stricter than
`STARTGOLD_DOCUMENTATION.md` §3.5, which lists email as a plain input field with no mention of a
verification gate — confirmed drift, code is source of truth per AGENTS.md §10.

## RULE-AUTH-007: MPIN is 6 digits at creation; `/pin-entry` UI expects 4
`PinCreationScreen` uses `MpinNotifier.pinLength` (`core/services/mpin_service.dart:151`) = **6** as its loop
bound and in its UI copy (`pin_creation_screen.dart:84, 195-196`). `PinScreen` (`/pin-entry`) hardcodes
`length: 4` (`pin_screen.dart:117`) and gates its submit button on `.length == 4` (line 156). If `/pin-entry`
is ever reached with a 6-digit MPIN already set server-side, the UI would let the user submit a 4-digit guess
that can never match. See METHOD_INDEX.md "Notable inconsistency" — flagged, not fixed (route may be dead
code; unconfirmed).

## RULE-AUTH-008: OTP resend timer is 30 seconds, client-side only, duplicated in two places
Both `otp_screen.dart:64-74` and `email_otp_sheet.dart:66-76` implement an identical `Timer.periodic`
30-second countdown independently (no shared widget/mixin). No server-driven config value backs this
duration — changing it requires editing both files. Not a `savings/config`-style server value per AGENTS.md
§2's GST/denomination precedent; this is UI cosmetic timing, not a compliance-relevant value, but the
duplication itself is tech debt.

## RULE-AUTH-009: Resend always re-verifies against the freshest `otp_reference_id`
`OtpScreen._verifyOtp` (`otp_screen.dart:401-403`) reads `otp_reference_id` from live `AuthState.data` first,
falling back to the reference id passed in via route arguments only if state doesn't have a fresher one. This
correctly prevents "verify against a stale/invalidated OTP reference" after a resend.

## RULE-AUTH-010: No client-side OTP attempt lockout (unlike MPIN)
`AuthNotifier.verifyOtp` (`auth_service.dart:341-403`) has no failed-attempt counter or lockout logic.
Contrast with `MpinNotifier.verifyMpin` (`core/services/mpin_service.dart:194-216`), which locks the UI after
5 failed attempts (`isLocked` flag, "ACCOUNT LOCKED" message). Any OTP brute-force protection is presumed
server-side — **unconfirmed** from client code alone.

## RULE-AUTH-011: FCM registration is fire-and-forget and only fires on the new-user registration path
`PinCreationScreen._registerFcmToken()` (`pin_creation_screen.dart:438-440, 465-480`) is called, not awaited,
only from the post-registration PIN-creation success path. Existing users verifying their PIN via `PinScreen`
(`/pin-entry`) trigger no FCM registration call in this module — token refresh relies entirely on
`FcmService.onTokenRefresh` firing independently on Firebase's own rotation schedule
(`core/services/fcm_service.dart:113-114, 175-179`). Matches AGENTS.md's "fire-and-forget FCM" pattern
expectation but is narrower in scope (new-user-only) than the hand-written doc implies.

## RULE-AUTH-012: Screenshot/recording block is OTP-screen-only within this module
Only `OtpScreen` calls `ScreenshotSecurityService.secureScreen()`/`releaseScreen()`
(`otp_screen.dart:56-62`, wired into `initState`/`dispose`). `LoginScreen`, `RegistrationScreen`,
`PinCreationScreen`, `PinScreen`, `EmailOtpSheet` do not. This is narrower than AGENTS.md §3's statement that
protection is "active on auth, OTP, MPIN, and payment screens at minimum" — flagged as drift for
`_SYSTEM/DANGER_ZONES.md` synthesis (a PIN being typed on `PinCreationScreen` is visible to a screen recorder).

## RULE-AUTH-013: Back-navigation is hard-blocked on 3 screens, soft-guarded on 1, unguarded elsewhere
Hard block (`PopScope(canPop:false)`, no exit path via back button): `RegistrationSuccessScreen`
(`registration_success_screen.dart:32-33`) and `OtpScreen` when reached via the app-lock forgot-PIN flow
(`otp_screen.dart:388-396`). Soft guard (double-back-to-exit-app pattern): `LoginScreen`
(`login_screen.dart:95-113`). Unguarded (falls back to `NavigationUtils.safePop`, which itself redirects to
`/mpin` or `/login` if there's nothing to pop — `core/utils/navigation_utils.dart:23-52`):
`RegistrationScreen`, `PinCreationScreen` (partial back within its own 2-step flow, see next rule),
`PinScreen`.

## RULE-AUTH-014: PIN-creation back button steps back within the flow before leaving the screen
`PinCreationScreen`'s back arrow (`pin_creation_screen.dart:155-168`) first un-confirms (returns from
"confirm PIN" step to "enter PIN" step, re-shuffling the keypad) before it will actually call
`NavigationUtils.safePop`. Prevents accidentally losing the whole registration+PIN flow from a single
mis-tap during the 2-step PIN entry.

## RULE-AUTH-015: Registration attempts are not double-submitted on PIN retry
`PinCreationScreen._registerComplete` (`pin_creation_screen.dart:46, 405, 426`) ensures `register()` (which
creates the account server-side) is called at most once per screen instance, even if the user mistypes the
PIN confirmation multiple times and retries `_handleSetPin()`. Only `setPin()` is retried on a PIN-mismatch
retry.
