---
module: auth
last_updated: 2026-08-19
---

# Forensic Template — Auth Module

Symptom → check-first → likely suspects, for the recurring bug categories in this module. Each entry cites
the exact file:line to open first.

## 1. "OTP never arrives" / "User never gets the SMS"

**Check first**: is `sendOtp()` actually returning `success:true`? Add a temporary breakpoint/log at
`core/services/auth_service.dart:285` (`AuthNotifier.sendOtp`, success branch) vs `:301`
(error branch) — if it's hitting the error branch, the SMS gateway was never invoked server-side and the
"OTP never arrives" report is actually a swallowed API error the user saw as a toast and possibly dismissed.

**Likely suspects**:
- RSA key not ready yet → `mobile` field either fails to encrypt (throws `StateError`,
  `core/security/encryption_service.dart:72-77`) or — check whether `fetchAndCachePublicKey()`
  (`api_interceptor.dart:38-89`) completed before this was the first sensitive request of the session; a cold
  start racing the key fetch is the classic cause.
- `device_id`/`device_type` (`core/services/device_id_service.dart:40-102`) resolving to unexpected values on
  a specific OEM device, causing server-side device-based OTP throttling to silently reject — check
  `AuthService.sendOtp` request body (`auth_service.dart:24-45`) in a network log.
- Server-side SMS provider issue — outside this codebase; confirm by checking if `verify-otp` with a
  known-test OTP still round-trips correctly (isolates network/encryption from SMS delivery).
- User is looking at the wrong screen state — `_timerSeconds` countdown (`otp_screen.dart:64-74`) is
  client-only and doesn't reflect actual SMS delivery; a slow SMS gateway and a "never arrives" bug look
  identical to the user for the first 30 seconds.

## 2. "User stuck in registration loop" (repeatedly sent back to `/registration`)

**Check first**: what does `verify-otp` actually return for `is_new_user` on the *second* login attempt for
this mobile? If the backend still reports `is_new_user:true` after a completed registration, the loop is
server-side state, not a client bug — check this before touching `otp_screen.dart:461-470`.

**Likely suspects**:
- Registration completed (`AuthService.register` succeeded, `auth_service.dart:128-174`) but `setPin()`
  (`mpin/create`) failed or the app was killed between the two calls (`pin_creation_screen.dart:392-464`,
  Step 1 vs Step 2) — this is the exact scenario `otp_screen.dart:478-486`'s branch 5 (`else` — existing
  user, no MPIN → `type:'setup'`) is designed to catch on the *next* login. If the user instead sees
  `/registration` again rather than a PIN-setup screen, the backend's `is_new_user` flag is likely still
  `true` even though a partial account record exists — a backend-side reconciliation gap, not a client bug.
- `_registerComplete` guard (`pin_creation_screen.dart:46, 405, 426`) is scoped to the widget instance —
  killing/backgrounding the app during PIN entry resets it, so on relaunch the user restarts at
  `/registration` from scratch (route args are gone) rather than resuming into PIN creation. Confirm whether
  the backend's `register` endpoint is idempotent for a repeat call with the same `mobile`/`temp_token` — if
  not, a second `register()` call from a fresh `RegistrationScreen` submission could itself error out
  (duplicate account), which is what actually traps the user.
- `temp_token` expired between OTP-verify and registration-submit (no visible client-side TTL/expiry check on
  `tempToken` anywhere in `registration_screen.dart` or `pin_creation_screen.dart`) — if the backend rejects
  an expired `temp_token`, check how `_handleRegistration`'s error-parsing (`registration_screen.dart:557-597`)
  surfaces that specific error message; if it falls into the generic fallback, the user sees a vague error
  and may retry into the same loop rather than restarting from `/login`.

## 3. "MPIN creation succeeds but next login fails" (existing user, PIN entry always rejected)

**Check first**: which endpoint actually failed — `mpin/create` (`mpin_service.dart:13-27`, "succeeds" per
the symptom) or a later `mpin/validate` (`mpin_service.dart:30-54`)? Confirm the PIN length being submitted
at creation time (6 digits, `MpinNotifier.pinLength`, `mpin_service.dart:151`) matches what the login-time PIN
entry screen collects and submits.

**Likely suspects**:
- **Route mismatch**: `otp_screen.dart`'s post-verify routing sends returning users to `AppRouter.mpin`
  (the separate `mpin` feature module, `/mpin`) for PIN verification, NOT to this module's `PinScreen`
  (`/pin-entry`). If some other code path (deep link, notification tap, etc.) instead routes the user to
  `/pin-entry`, they'd hit `PinScreen`'s hardcoded 4-digit input (`pin_screen.dart:117, 156`) against a
  6-digit MPIN created via `PinCreationScreen` — guaranteed mismatch. See BUSINESS_RULES RULE-AUTH-007.
- MPIN was created correctly, but `verifyMpin()`'s SESSION_EXPIRED / 409 handling
  (`mpin_service.dart:30-54`, `217-278` in the parallel `MpinNotifier.verifyMpin`) is misclassifying a normal
  wrong-PIN response as a session issue — check the exact response body shape from the backend against the
  `errorCode == 'SESSION_EXPIRED'` check (`mpin_service.dart:40-41`).
- Device/session was force-logged-out (409) between PIN creation and the next app open — check
  `SessionManager.isForceLoggedOut` (`session_manager.dart:16`) and whether
  `SecureStorageService.logout()` wiped the freshly-set `is_mpin_enabled`/`access_token` before the user ever
  got to try logging back in.

## 4. "User sees the wrong screen after tapping the push notification / resuming the app"

**Check first**: is this actually an auth-module issue, or `NavigationUtils.safePop`'s fallback logic
(`core/utils/navigation_utils.dart:23-52`) kicking in because the navigator stack was empty at the point of
resume? `safePop` sends unauthenticated users to `/login` and authenticated+MPIN-enabled users to `/mpin` —
if that decision looks wrong, check `SessionManager.isAuthenticated()` (`session_manager.dart:18-22`, purely
"is there a non-empty token in storage") and `SecureStorageService.isMpinEnabled()`
(`secure_storage_service.dart:26-29`) independently; a token can be present but stale (not yet 401'd) while
`is_mpin_enabled` is correct, producing a technically-consistent-but-surprising routing choice.

**Likely suspects**:
- Stale `is_mpin_enabled` flag — only ever written by `auth_service.dart:76-78` (from `verify-otp` response)
  and `pin_creation_screen.dart:436` (hardcoded `true` after PIN creation). If a user disables MPIN in
  Settings (outside this module) and that flow doesn't call `SecureStorageService.setMpinEnabled(false)`, this
  module's routing logic (and `NavigationUtils`' fallback) would still think MPIN is required.
- FCM notification tap always routes to `AppRouter.notifications` (`fcm_service.dart:160-165, 186-187`), never
  directly into an auth screen — if a user reports landing on a login/PIN screen "from a notification," the
  actual cause is more likely a concurrent 409 force-logout (`api_interceptor.dart:214-259`) firing around
  the same time, not the notification tap itself.

## 5. "Registration form silently does nothing when I tap Confirm"

**Check first**: is `_emailVerified` actually `true`? The Confirm button's `onPressed` is `null` (visually
disabled but developers/testers sometimes miss the disabled-vs-error distinction) whenever
`!_agreedToTerms || !_emailVerified` (`registration_screen.dart:122-123`) — this is not a bug, it's
RULE-AUTH-006, but is the #1 support-ticket-shaped complaint for this screen since the doc
(`STARTGOLD_DOCUMENTATION.md` §3.5) doesn't mention the mandatory-email-verify gate at all.

**Likely suspects**:
- User never tapped "Verify" next to the email field, or verified a *different* email than the one currently
  in the field (`_emailController` listener at `registration_screen.dart:55-59` silently revokes
  `_emailVerified` on any edit after verification — including autofill/autocorrect touching the field).
- `_formKey.currentState!.validate()` (line 519) failing on DOB or name validators, but the user's eye is on
  the email "Verified" badge and doesn't notice a small red field-level error elsewhere in the scrollable form.

## 6. "FCM push notifications never arrive for a newly registered user"

**Check first**: did `_registerFcmToken()` actually run to completion? It's fire-and-forget
(`pin_creation_screen.dart:440, 465-480`) — the navigation to `registrationSuccess`/`home` happens
immediately regardless of whether the token fetch/POST succeeded. Check `SecureStorageService.getFcmToken()`
(`secure_storage_service.dart:103-105`) — if it's still `null` after registration, the fire-and-forget call
either threw (swallowed at `pin_creation_screen.dart:476-477`, only `debugPrint`'d) or `FcmService.getToken()`
(`fcm_service.dart:121`) itself returned `null` (common on first-run before Firebase permission prompt
resolves, or on emulators without Play Services).

**Likely suspects**:
- Firebase permission not yet granted at the moment of registration (`FcmService.init()`'s
  `requestPermission` call, `fcm_service.dart:68-72`, races with the fire-and-forget registration call if
  `init()` hasn't finished by the time `PinCreationScreen` fires it) — token fetch would return `null` and
  the registration silently no-ops.
- `NotificationService.registerFcmToken`'s dedup check (`notification_service.dart:118-122`) comparing
  against a stale cached token from a *previous* install/user on the same device (secure storage wasn't fully
  wiped) — new token never actually POSTed because it "matches" a leftover cached value that's actually for
  a different account.
