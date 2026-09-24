---
module: auth
last_updated: 2026-08-19
---

# State Analysis — Auth Module

## Riverpod Providers

| Provider | Type | File:line | Consumed by |
|---|---|---|---|
| `authControllerProvider` | `StateNotifierProvider<AuthController, AuthState>` | `controller/auth_controller.dart:45-49` | all 6 auth screens (`ref.watch`/`ref.read` throughout) |
| `authProvider` | `StateNotifierProvider<AuthNotifier, AuthState>` | `core/services/auth_service.dart:599-602` | **not referenced anywhere found in `lib/features/auth/`** — a separate, seemingly-unused (from this module's perspective) instance of the same state shape. Possibly consumed elsewhere in the app (unconfirmed, not grepped app-wide). |
| `authServiceProvider` | `Provider<AuthService>` | `auth_service.dart:209` | `registration_screen.dart:531` (direct service read, bypassing the notifier) |
| `mpinServiceProvider` | `Provider<MpinService>` | `core/services/mpin_service.dart:109` | not read via provider by this module — `AuthController` and `RegistrationScreen`/`PinCreationScreen` both instantiate `MpinService()` directly (`auth_controller.dart:12, 30`) rather than `ref.read(mpinServiceProvider)` |
| `countryCodesProvider` | `FutureProvider.autoDispose<List<CountryCode>>` | `core/services/shared_service.dart:171-175` | `login_screen.dart:68, 87, 275` |
| `appControlProvider` | (see `core/providers/app_control_provider.dart:318`) | — | `login_screen.dart:229` (dev env-switcher gate) |
| `environmentProvider` | state provider, current env string | `core/providers/environment_provider.dart` | `login_screen.dart:629, 672, 692` |

## `AuthState` Shape (`core/services/auth_service.dart:211-242`)

```dart
class AuthState {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? data;         // transient result of the last successful call
  final Map<String, dynamic>? sessionData;  // persisted across the notifier's lifetime
  final bool? isRegistered;
}
```

No dedicated request/response **model classes** exist in this module — every API interaction uses raw
`Map<String, dynamic>` on both the request-building side (`auth_service.dart`'s `data: {...}` literals) and
the response-reading side (`data['data']?['is_new_user']` style access throughout `otp_screen.dart`,
`pin_creation_screen.dart`, `registration_screen.dart`). This means:
- No compile-time safety on response field names/types — a backend rename of `is_new_user` would fail
  silently (defaults to `false` via `?? false` / `== true` patterns) rather than throwing.
- `AuthState.data` is overwritten by every successful call (`sendOtp`, `verifyOtp`, `sendEmailOtp`,
  `verifyEmailOtp`, `register` all do `data: data['data']` on success) — so it's a single mutable "last
  response" slot shared across very different call types. A screen reading `authState.data?['otp_reference_id']`
  after a `register()` call, for example, would get whatever `register`'s response happened to contain (not
  present per `auth_service.dart:128-174`'s response shape, so it'd be `null`) rather than an error. Screens
  are individually careful to read the right key after the right call, but there's no type system enforcing
  it.

`AuthState.sessionData` is set by `rehydrateFromStorage()` (line 255-272, on notifier construction) and by
`verifyOtp`/`register` on success (`sessionData: data['data']`) — used to reconstruct `{mobile, user:
{id_customer, name, photo_url}}` after an app restart, without a fresh API call.

## Secure-Storage Keys Touched By This Module

All via `SecureStorageService` (`core/security/secure_storage_service.dart`), backed by
`flutter_secure_storage` (AES/Keychain), keyed by constants in `core/config/app_config.dart`:

| Key constant | Storage key string | Written by (auth module) | Read by (auth module) |
|---|---|---|---|
| `keyAccessToken` | `access_token` | `auth_service.dart:66` (post verify-otp), `:154` (post register) | not read directly by auth screens (read by interceptor for `Authorization` header) |
| `keyRefreshToken` | `refresh_token` | `auth_service.dart:69` (post verify-otp), `:157` (post register) | not read directly by auth screens |
| `keyIsMpinEnabled` | `is_mpin_enabled` | `auth_service.dart:77` (post verify-otp, from `mpin_enabled` field), `pin_creation_screen.dart:436` (`setMpinEnabled(true)` post PIN-create) | `otp_screen.dart` reads via `authState.data?['mpin_enabled']` (API response, not storage) — storage copy is for splash/other screens, not re-read within this module |
| `keyCustomerId` | `customer_id` | `auth_service.dart:80-81` (post verify-otp), `:160-161` (post register) | — |
| `keyCustomerName` | `customer_name` | `auth_service.dart:83-86` (post verify-otp, `name` or `full_name` fallback), `:164-167` (post register) | — |
| `keyCustomerPhoto` | `customer_photo` | `auth_service.dart:88-89` (post verify-otp only — `register` response has no photo field) | — |
| `keyMobileNumber` | `mobile_number` | `auth_service.dart:91-92` (post verify-otp), `:169-170` (post register) | — |
| `keyFcmToken` | `fcm_token` | not written by auth module directly (written by `NotificationService.registerFcmToken`, `notification_service.dart:141`, invoked from `pin_creation_screen.dart:473`) | `notification_service.dart:118` (dedup check) |
| — (logout) | `logout()` wipes all keys except `persistent_device_id`, `persistent_device_type`, `keyHasSeenOnboarding` | `otp_screen.dart:208` — called when the user taps "Edit" during the forgot-PIN-from-app-lock flow, before returning to `/login` | — |

`keyServerPublicKey` (RSA PEM cache) is touched by `EncryptionService`/interceptor, not directly by this
module, but every encrypted call this module makes depends on it being populated.

## Local (non-Riverpod) Widget State

| Screen | Local state | Purpose |
|---|---|---|
| `LoginScreen` | `_mobileController`, `_countryCode`, `_selectedCountryId`, `_navigating`, `_lastBackPressTime`, `_longPressTimer` | form input, double-tap/double-back guards, hidden dev dialog long-press timer |
| `OtpScreen` | `_otpController`, `_timerSeconds`, `_timer` | OTP input, resend countdown |
| `RegistrationScreen` | `_nameController`, `_emailController`, `_dobController`, `_referralController`, `_agreedToTerms`, `_isSubmitting`, `_emailVerified`, `_isVerifyingEmail`, `_verifiedEmail` | form inputs + submit gating |
| `EmailOtpSheet` | `_otpController`, `_otpReferenceId` (mutable, refreshed on resend), `_timerSeconds`, `_timer` | email OTP input, resend countdown |
| `PinCreationScreen` | `_isConfirming`, `_registerComplete`, `_pin`, `_confirmPin`, `_shuffledNumbers` | 2-step PIN flow, keypad shuffle, register-once guard |
| `PinScreen` | `_pinController` | PIN input |

None of this local state is persisted or shared cross-screen — it all resets on screen dispose, which is why
the module relies on `AuthState.data`/`sessionData` (Riverpod, survives navigation) to carry
`otp_reference_id`, `temp_token`, `is_new_user`, `mpin_enabled` between screens rather than passing everything
through route arguments alone (though route arguments are also used redundantly in several places, e.g.
`otpReferenceId` is both a route arg AND re-read from state — see DATA_FLOW.md Flow 2).
