---
module: auth
brain_status: 🟢 (build round 1 — see COVERAGE_TRACKER.md)
last_updated: 2026-08-19
source_root: lib/features/auth/
---

# Auth Module Brain

## 1. Purpose & Scope

Owns mobile-number login, SMS OTP verification, email OTP verification (registration only), new-user
registration, and MPIN (app PIN) creation. It does **not** own MPIN *entry/verification on resume* (that's
`lib/features/mpin/mpin_screen.dart`, a sibling top-level feature) or KYC — this module hands off to those via
named routes only, with no direct Dart imports.

## 2. File Inventory (8 files, 100% read)

```
lib/features/auth/
├── controller/
│   └── auth_controller.dart          — AuthController (StateNotifier), authControllerProvider
├── login/
│   └── login_screen.dart             — /login
├── otp/
│   └── otp_screen.dart               — /otp
├── pin/
│   ├── pin_creation_screen.dart      — /mpin-creation (new-PIN setup, post-registration)
│   └── pin_screen.dart               — /pin-entry (existing-user PIN re-entry, distinct from /mpin)
└── registration/
    ├── email_otp_sheet.dart          — bottom sheet, mandatory email verification during registration
    ├── registration_screen.dart      — /registration
    └── registration_success_screen.dart — /registration-success
```

`auth_controller.dart`'s `AuthController` is a thin subclass of `AuthNotifier` (defined in
`core/services/auth_service.dart:244`) — it adds only `setPin`/`verifyPin` (`controller/auth_controller.dart:9-42`,
delegating to `core/services/mpin_service.dart`'s `MpinService`). All OTP/registration logic lives in the
inherited `AuthNotifier`, i.e. **the "auth module" logic is split across `lib/features/auth/` and
`lib/core/services/auth_service.dart`** — read both.

## 3. Route Table

| Route constant | Path | Screen | Args (from `app_router.dart`) |
|---|---|---|---|
| `AppRouter.login` | `/login` | `LoginScreen` | none |
| `AppRouter.otp` | `/otp` | `OtpScreen` | `mobile` (required), `countryCode` (default `+91`), `idCountry` (default `101`), `otpReferenceId` — app_router.dart:132-141 |
| `AppRouter.registration` | `/registration` | `RegistrationScreen` | `mobile`, `tempToken` — app_router.dart:198-206 |
| `AppRouter.registrationSuccess` | `/registration-success` | `RegistrationSuccessScreen` | `fullName` — app_router.dart:288-293 |
| `AppRouter.mpinCreation` | `/mpin-creation` | `PinCreationScreen` | `mobile`, `fullName`, `email`, `dob`, `referralCode`, `tempToken` — app_router.dart:179-191 |
| `AppRouter.pinEntry` | `/pin-entry` | `PinScreen` | `mobile` — app_router.dart:192-197 |

Note: `AppRouter.mpin` (`/mpin`) is **not** in this module — it routes to `features/mpin/mpin_screen.dart`.
The OTP screen's post-verification logic (§5 below) pushes to `AppRouter.mpin`, not `pinEntry`, for both the
"existing user, has PIN" and "existing user, no PIN" cases. `pinEntry`/`PinScreen` (this module) appears to be
a legacy/alternate PIN-verify screen not currently reached from the OTP flow — **unconfirmed** which caller
uses it (no reference found inside `lib/features/auth/` or in the OTP routing branches).

## 4. Layering

`Screen (ConsumerStatefulWidget)` → `authControllerProvider` (Riverpod `StateNotifierProvider<AuthController,
AuthState>`, `controller/auth_controller.dart:45-49`) → `AuthService`/`MpinService` (`core/services/`) →
`ApiClient` (Dio, `core/network/api_client.dart`) → `ApiSecurityInterceptor`
(`core/security/api_interceptor.dart`). Screens never call `ApiClient` directly except
`registration_screen.dart:531` which reads `authServiceProvider` directly for `registerCheck` (bypasses the
`AuthNotifier` state wrapper — intentional, since register-check has its own local `_isSubmitting` loading
flag rather than using `authState.isLoading`).

## 5. Post-OTP-Verify Routing Decision (the core business logic of this module)

Implemented entirely in `otp/otp_screen.dart:_verifyOtp` (lines 401-489). After `verifyOtp()` succeeds, in
priority order:

1. `actionType == 'add_upi'` → `Navigator.pop(context, true)` (line 419) — this screen is also reused by a
   non-auth UPI-verification flow elsewhere in the app (caller not in this module).
2. `actionType == 'forgot_pin'` → push `AppRouter.mpin` with `type: 'reset_pin'`, `temp_token` (from
   `authState.data?['temp_token']` or fallback `access_token`), `mobile` (lines 424-454). If
   `from_app_lock == true`, uses `pushNamedAndRemoveUntil` (clears back-stack so user can't swipe back into
   the app); otherwise `pushReplacementNamed`.
3. `authState.data?['is_new_user'] == true` → `pushReplacementNamed(AppRouter.registration, ...)` (lines
   461-470), carrying `mobile` + `tempToken`.
4. `authState.data?['mpin_enabled'] == true` → `pushReplacementNamed(AppRouter.mpin, {'mobile': ...})`
   (lines 471-477) — normal returning-user login.
5. Else (existing user, no MPIN set) → `pushReplacementNamed(AppRouter.mpin, {'type': 'setup', 'mobile': ...})`
   (lines 478-486) — comment at line 479-481 flags this as covering "register succeeded but PIN creation
   failed or was interrupted."

All four flags (`is_new_user`, `mpin_enabled`, `temp_token`, `access_token`) come straight from the
`verify-otp` API response body (`data.data`) — there is no client-side derivation.

## 6. Security Posture (see BUSINESS_RULES.md for rule IDs)

- **Field encryption**: `mobile` and `otp` are in `AppConfig.sensitiveFields`
  (`core/config/app_config.dart:74-99`) and `users/auth/generate-otp` / `verify-otp` /
  `generate-email-otp` / `verify-email-otp` / `register` are in `AppConfig.encryptedEndpoints`
  (`app_config.dart:47-71`) — so the interceptor RSA-encrypts those fields automatically
  (`core/security/api_interceptor.dart:166-182`). **`mpin` is in `sensitiveFields`** and `mpin/create` /
  `mpin/validate` are in `encryptedEndpoints` — MPIN is encrypted too.
- **`users/auth/register-check` is NOT in `encryptedEndpoints`** (`app_config.dart:47-71`) — the
  pre-validation call made from `registration_screen.dart:532-539` (mobile, full_name, email, dob,
  referral_code, temp_token) goes over the wire **unencrypted** (still TLS-protected, but not RSA
  field-encrypted like its sibling `auth/register`). Flagged as drift/gap — see BUSINESS_RULES RULE-AUTH-011.
- **Screenshot/recording block**: only `otp/otp_screen.dart` calls
  `ScreenshotSecurityService.secureScreen()`/`releaseScreen()` (lines 56-62, wired in `initState`/`dispose`).
  Login, registration, and PIN-creation screens do **not** call it — narrower than
  AGENTS.md §3's blanket claim ("active on auth, OTP, MPIN... screens at minimum"). Flagged as drift — see
  BUSINESS_RULES RULE-AUTH-012.
- **PopScope back-navigation guards**: `LoginScreen` (`login_screen.dart:95-113`, double-back-to-exit),
  `RegistrationSuccessScreen` (`registration_success_screen.dart:32-33`, `canPop: false`, no handler — hard
  block), `OtpScreen` conditionally when `from_app_lock == true` (`otp_screen.dart:388-396`, hard block, no
  handler body). `RegistrationScreen`, `PinCreationScreen`, `PinScreen` use normal back (`NavigationUtils.safePop`)
  with no PopScope.
- **PIN keypad shuffle**: `PinCreationScreen._shuffleKeypad()` (`pin_creation_screen.dart:69-79`) randomizes
  digit positions with `Random.secure()` on every PIN-creation step — shoulder-surfing / recorded-tap mitigation.
  `PinScreen` (the `/pin-entry` route) uses a standard `Pinput` widget with **no** shuffle.
- **Clipboard**: all sensitive text fields (mobile, OTP, PIN, email in registration) use
  `contextMenuBuilder: SecureClipboard.none` to disable paste/copy context menu.

## 7. FCM Registration Timing

Fire-and-forget, non-blocking, only fired from the **new-user** path: `PinCreationScreen._handleSetPin()`
calls `_registerFcmToken()` (`pin_creation_screen.dart:438-440, 465-480`) *after* `setPin()` succeeds and
*before* navigating away. It's wrapped in `Future(() async {...})` with try/catch that only `debugPrint`s on
failure — never surfaces an error to the user or blocks navigation. `PinScreen` (existing-user PIN verify)
has **no** FCM registration call — token refresh registration instead relies on
`FcmService._onTokenRefreshed` (`core/services/fcm_service.dart:175-179`) firing independently whenever
Firebase rotates the token, and `NotificationService.registerFcmToken` (`core/services/notification_service.dart:116-146`)
dedupes against the last-registered token stored in `SecureStorageService.getFcmToken()`.

## 8. OTP Resend / Replay

- Resend timer: hardcoded `_timerSeconds = 30`, client-side only, no server-driven config found
  (`otp/otp_screen.dart:64-74`, `registration/email_otp_sheet.dart:66-76` — same pattern, separately
  implemented, not shared code).
- Resend calls `sendOtp(..., type: 'RESEND')` (`otp_screen.dart:80-85`) — same `generate-otp` endpoint with a
  `type` field distinguishing `LOGIN` vs `RESEND` (`core/services/auth_service.dart:24-45`).
  `otp_reference_id` from the resend response replaces the one held in `AuthState.data`
  (`otp_screen.dart:402-403` reads the latest one at verify time, falling back to the value passed in via
  route args) — so a resend correctly invalidates the old reference server-side and the client always
  verifies against the newest one.
- **No client-side OTP replay guard beyond that** — there is no rate-limiting, attempt-counter, or lockout
  visible in `otp_screen.dart`; unlike `MpinNotifier.verifyMpin()` (`core/services/mpin_service.dart:194-216`)
  which locks after 5 failed attempts, `AuthNotifier.verifyOtp` has no such counter. Any OTP-attempt
  throttling is server-side only (unconfirmed — no docs/response fields observed for it).

## 9. Top Risks / Things To Watch

1. `PinScreen` (`/pin-entry`) appears orphaned from the auth module's own navigation — verify with a repo-wide
   grep before removing or "fixing" it; something outside this module may still push it.
2. `register-check` unencrypted (§6) — confirm with backend team whether this is intentional (field values are
   non-final at that point) before treating it as a bug.
3. Screenshot protection is OTP-only, not "auth screens" broadly — MPIN creation screen shows a 4-digit PIN
   being typed with no `FLAG_SECURE`/blur; a screen-recording app could capture it.
4. `_registerComplete` bool guard in `PinCreationScreen` (line 46, 405, 426) prevents double-`register()` calls
   on PIN retry, but there is no equivalent guard preventing double-`register()` if the user backgrounds/kills
   the app between register-success and PIN-success — a partial-registration state that OTP-routing step 5
   (§5) is designed to recover from on next login.
5. Email verification in registration is **mandatory** (`_emailVerified` gates the Confirm button,
   `registration_screen.dart:123, 521-525`) — a UX-security tradeoff not mentioned in
   `STARTGOLD_DOCUMENTATION.md` §3.5 at all (see drift note in COVERAGE_TRACKER.md).

## 10. See Also

- `METHOD_INDEX.md` — every public method, file:line, callers.
- `DATA_FLOW.md` — 3 full request/response traces.
- `BUSINESS_RULES.md` — RULE-AUTH-001..015.
- `CROSS_MODULE_MAP.md` — `core/` dependency graph + Mermaid.
- `STATE_ANALYSIS.md` — providers, `AuthState` shape, secure-storage keys.
- `FORENSIC_TEMPLATE.md` — symptom → suspects.
