---
module: auth
last_updated: 2026-08-19
---

# Method Index — Auth Module

Alphabetical within each class. "Callers" lists only callers found inside `lib/features/auth/`; callers
elsewhere in the app are noted as "external" where found via grep, else "none found".

## `AuthController` (`lib/features/auth/controller/auth_controller.dart`)
Extends `AuthNotifier` (see below) — adds two methods, inherits the rest.

| Method | Signature | Line | Calls | Callers |
|---|---|---|---|---|
| `setPin` | `Future<bool> setPin(String mobile, String pin)` | 9-24 | `MpinService().setMpin(pin)` | `pin_creation_screen.dart:430-432` |
| `verifyPin` | `Future<bool> verifyPin(String mobile, String pin)` | 27-42 | `MpinService().verifyMpin(pin)` | `pin_screen.dart:192-194` |

Provider: `authControllerProvider = StateNotifierProvider<AuthController, AuthState>(...)` — line 45-49.

## `AuthNotifier` (`lib/core/services/auth_service.dart`) — base class, inherited by `AuthController`

| Method | Signature | Line | Endpoint(s) | Callers (auth module) |
|---|---|---|---|---|
| `rehydrateFromStorage` | `Future<void> rehydrateFromStorage()` | 255-272 | none (reads SecureStorage) | called from own constructor (line 247); no external caller found |
| `sendOtp` | `Future<bool> sendOtp(String mobile, String countryCode, String idCountry, {String type = 'LOGIN'})` | 274-339 | `POST users/auth/generate-otp` | `login_screen.dart:501-505` (type=LOGIN implicit), `otp_screen.dart:80-85` (type='RESEND') |
| `verifyOtp` | `Future<bool> verifyOtp(String mobile, String otp, String otpReferenceId)` | 341-403 | `POST users/auth/verify-otp` | `otp_screen.dart:405-409` |
| `sendEmailOtp` | `Future<bool> sendEmailOtp(String email, {String? fullName})` | 405-459 | `POST users/auth/generate-email-otp` | `registration_screen.dart:488-493`, `email_otp_sheet.dart:93-95` (resend) |
| `verifyEmailOtp` | `Future<bool> verifyEmailOtp(String email, String otp, String otpReferenceId)` | 461-517 | `POST users/auth/verify-email-otp` | `email_otp_sheet.dart:107-109` |
| `register` | `Future<bool> register({required mobile, required fullName, required email, required tempToken, dob, referralCode})` | 519-587 | `POST users/auth/register` | `pin_creation_screen.dart:406-414` |
| `logout` | `Future<void> logout()` | 589-592 | none (calls `AuthService.logout()` → `SecureStorageService.logout()`) | none found in auth module (used elsewhere, e.g. settings/profile) |
| `clearError` | `void clearError()` | 594-596 | — | called in `initState`/`onChanged` of every auth screen |

Provider: `authProvider = StateNotifierProvider<AuthNotifier, AuthState>(...)` — line 599-602. Note:
`authControllerProvider` (used by all auth screens) and `authProvider` (this base provider) are **separate
provider instances** with independent state — screens all use `authControllerProvider`, so `authProvider`
appears unused by this module (possibly used elsewhere — unconfirmed, not grepped outside auth/).

## `AuthService` (`lib/core/services/auth_service.dart`) — service layer, no Riverpod state

| Method | Signature | Line | Endpoint | Side effects |
|---|---|---|---|---|
| `sendOtp` | `Future<Map> sendOtp({required mobile, countryCode, idCountry, type})` | 24-45 | `POST users/auth/generate-otp` | none |
| `verifyOtp` | `Future<Map> verifyOtp({required mobile, otp, otpReferenceId})` | 47-96 | `POST users/auth/verify-otp` | on success: saves access/refresh token, resets force-logout flag, saves `mpin_enabled`, `customer_id`, `customer_name`, `customer_photo`, `mobile` to SecureStorage (lines 60-93) |
| `sendEmailOtp` | `Future<Map> sendEmailOtp({required email, fullName})` | 98-110 | `POST users/auth/generate-email-otp` | none |
| `verifyEmailOtp` | `Future<Map> verifyEmailOtp({required email, otp, otpReferenceId})` | 112-126 | `POST users/auth/verify-email-otp` | none |
| `register` | `Future<Map> register({required mobile, fullName, email, tempToken, dob, referralCode})` | 128-174 | `POST users/auth/register` | on success: saves access/refresh token, `customer_id`, `customer_name`, `mobile` (lines 149-171) |
| `registerCheck` | `Future<Map> registerCheck({required mobile, fullName, email, tempToken, dob, referralCode})` | 178-200 | `POST users/auth/register-check` | none (pure validation call, no token/storage writes) |
| `logout` | `Future<void> logout()` | 202-204 | none | `SecureStorageService.logout()` |

Provider: `authServiceProvider = Provider<AuthService>((ref) => AuthService())` — line 209.

## `MpinService` (`lib/core/services/mpin_service.dart`) — used by `AuthController.setPin`/`verifyPin`

| Method | Signature | Line | Endpoint |
|---|---|---|---|
| `setMpin` | `Future<void> setMpin(String mpin)` | 13-27 | `POST mpin/create` |
| `verifyMpin` | `Future<bool> verifyMpin(String mpin)` | 30-54 | `POST mpin/validate` |
| `changeMpin` | `Future<bool> changeMpin(String oldMpin, String newMpin)` | 58-76 | `POST mpin/change` — not called from auth module (used by `features/mpin/change_mpin_screen.dart`, outside this module) |
| `resetMpin` | `Future<void> resetMpin(String tempToken, String newMpin, {mobile})` | 80-98 | `POST mpin/reset` — not called from auth module (forgot-PIN flow lands on `/mpin` in the `mpin` module, not here) |
| `hasMpinSet` | `Future<bool> hasMpinSet()` | 101-104 | `POST auth/has-mpin` — not called from auth module |

## Screen widgets — key private methods

### `LoginScreen` (`login/login_screen.dart`)
| Method | Line | Purpose |
|---|---|---|
| `_handleLogin` | 498-528 | Guards double-tap via `_navigating`; calls `sendOtp`; on success, 100ms settle delay, then `navigatorKey.currentState!.pushNamed(AppRouter.otp, ...)` carrying `otp_reference_id` from response |
| `_buildCountryPicker` | 426-496 | Renders dynamic country list from `countryCodesProvider` |
| `_showSecretCodeDialog` / `_showEnvironmentSelectionDialog` | 530-785 | Hidden dev-only environment switcher (staging/production), triggered by 5s long-press on "Phone Number*" label when `appControlProvider.data.dynamicSwitching == true`; password from `dynamicSwitchingPassword` config or fallback `'0998'` (line 233) |

### `OtpScreen` (`otp/otp_screen.dart`)
| Method | Line | Purpose |
|---|---|---|
| `_startTimer` | 64-74 | 30s countdown, `Timer.periodic` |
| `_resendOtp` | 76-92 | Clears field, calls `sendOtp(type: 'RESEND')`, restarts timer on success |
| `_secureScreen` / `_releaseScreen` | 56-62 | Screenshot/recording block, called in `initState`/`dispose` |
| `_verifyOtp` | 401-489 | Full post-verification routing decision — see MODULE_BRAIN.md §5 |

### `RegistrationScreen` (`registration/registration_screen.dart`)
| Method | Line | Purpose |
|---|---|---|
| `_verifyEmail` | 479-516 | Validates email format, calls `sendEmailOtp`, opens `showEmailOtpSheet`, sets `_emailVerified` on success |
| `_handleRegistration` | 518-605 | Calls `AuthService.registerCheck` directly (not via `AuthController`); on `success:true` navigates to `mpinCreation` with all collected fields; parses nested `error.message` (Map or String) from both success-false JSON and `DioException` responses |
| email-edit listener | 55-59 | Invalidates `_emailVerified` if the email text changes after verification |

### `EmailOtpSheet` (`registration/email_otp_sheet.dart`)
| Method | Line | Purpose |
|---|---|---|
| `_resendOtp` | 89-104 | Re-sends email OTP, refreshes `_otpReferenceId` from response |
| `_verifyOtp` | 106-115 | Calls `verifyEmailOtp`; `Navigator.pop(context, true)` on success |
| (design note) | 85-87 | Comment explains this sheet deliberately has no `ref.listen<AuthState>` for errors — parent `RegistrationScreen` already listens on the same shared provider, avoiding duplicate toasts |

### `PinCreationScreen` (`pin/pin_creation_screen.dart`)
| Method | Line | Purpose |
|---|---|---|
| `_shuffleKeypad` | 69-79 | `Random.secure()` Fisher-Yates shuffle of 0-9 keypad, re-run on every step transition |
| `_onKeyPressed` | 83-109 | Appends digit; auto-advances Enter→Confirm step or auto-fires `_handleSetPin` at 4th digit (`MpinNotifier.pinLength`, defined in `core/services/mpin_service.dart:151`, = 6 — **note**: constant says 6 but UI labels say "4-digit PIN"; see BUSINESS_RULES drift note) |
| `_handleSetPin` | 392-464 | Confirms PIN match → calls `register()` (guarded by `_registerComplete` to prevent double-submit on retry) → calls `setPin()` → `SecureStorageService.setMpinEnabled(true)` → `_registerFcmToken()` (fire-and-forget) → navigates to `registrationSuccess` (if `fullName` non-empty) or straight to `home` |
| `_registerFcmToken` | 465-480 | Fire-and-forget FCM token fetch + `NotificationService.registerFcmToken`, swallows all errors |

### `PinScreen` (`pin/pin_screen.dart`)
| Method | Line | Purpose |
|---|---|---|
| `_handleVerifyPin` | 190-205 | Calls `verifyPin`; on success `pushNamedAndRemoveUntil(AppRouter.home)`; on failure clears the Pinput field |

## Notable inconsistency

`PinCreationScreen` uses `MpinNotifier.pinLength` (value **6**, `core/services/mpin_service.dart:151`) as its
loop bound (`pin_creation_screen.dart:84, 94, 195-196, 211`), but its own UI copy says `'Set Your\nSecurity
PIN'` / `'Create a ${MpinNotifier.pinLength}-digit PIN'` — so the *displayed* length is correctly
interpolated as 6, not hardcoded 4. `PinScreen` (`/pin-entry`), by contrast, hardcodes `length: 4` in its
`Pinput` widget (`pin_screen.dart:117`) and checks `_pinController.text.length == 4` (line 156) — a **length
mismatch** between the two PIN screens (6-digit creation vs 4-digit entry UI) if `PinScreen` is ever actually
reached in this flow. Given §3's note that `PinScreen` looks unreferenced from this module's own navigation,
this may be dead/stale code — flagged, not fixed.
