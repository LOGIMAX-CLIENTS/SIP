---
module: auth
last_updated: 2026-08-19
---

# Data Flow — Auth Module

## Flow 1: Mobile Entry → OTP Send

```
LoginScreen (login_screen.dart:296-333, TextField)
  → user types 10 digits, Validators.validateMobile() (core/utils/validators.dart:2-7) gates CTA enabled state
    (login_screen.dart:89-90)
  → tap "Initiate Secure Login" → _handleLogin() (login_screen.dart:498-528)
      guards double-tap via _navigating bool (line 499)
  → ref.read(authControllerProvider.notifier).sendOtp(mobile, countryCode, selectedCountryId)
      (login_screen.dart:501-505)
  → AuthNotifier.sendOtp() (core/services/auth_service.dart:274-339)
      state = isLoading:true (line 277)
      → AuthService.sendOtp() (auth_service.dart:24-45)
          appVersion via PackageInfo.fromPlatform() (line 15-22)
          POST users/auth/generate-otp
          body: {mobile, country_code, id_country, type:'LOGIN', device_id, device_type, appVersion}
      → ApiClient.post() (core/network/api_client.dart) → ApiSecurityInterceptor.onRequest()
          (core/security/api_interceptor.dart:92-185)
          'auth/generate-otp' is in AppConfig.encryptedEndpoints (app_config.dart:48)
          → EncryptionService.encryptJson(body) (encryption_service.dart:109-126)
              'mobile' is in AppConfig.sensitiveFields (app_config.dart:96) → RSA-OAEP-SHA256 encrypted
              country_code, id_country, type, device_id, device_type, appVersion sent PLAIN
      ← response {success:true, data:{otp_reference_id, ...}}
      onResponse() decrypts response if endpoint also in encryptedEndpoints (api_interceptor.dart:188-204)
  ← AuthNotifier sets state.data = data['data'], isLoading:false (auth_service.dart:285-287)
  ← _handleLogin() reads ref.read(authControllerProvider).data?['otp_reference_id'] (login_screen.dart:519)
  → 100ms Future.delayed "settle" pause (line 511, comment: lets AppControlWrapper release navigator locks)
  → navigatorKey.currentState!.pushNamed(AppRouter.otp, arguments:{mobile, countryCode, idCountry, otpReferenceId})
      (login_screen.dart:513-521) — uses the global navigatorKey, not context-scoped Navigator, so this works
      even if LoginScreen's own BuildContext is transient
  → app_router.dart:132-141 otp route builder reads args map into OtpScreen constructor params
```

**Error path**: any non-`success:true` response or `DioException` sets `state.error` with message extracted
from `error.message` (Map or String) or `message` fallback (auth_service.dart:289-337) → `LoginScreen`'s
`ref.listen<AuthState>` (line 80-84) shows it via `AppToast`. No navigation occurs; `_navigating` stays false
so the user can retry.

## Flow 2: OTP Verify → Post-Verification Routing Decision

```
OtpScreen (otp/otp_screen.dart) — receives mobile/countryCode/idCountry/otpReferenceId as constructor args
  → screenshot block enabled in initState via _secureScreen() (otp_screen.dart:56-58, 53)
  → Pinput onCompleted (6th digit) OR "Verify OTP" button → _verifyOtp(otp) (otp_screen.dart:401-489)
  → latestRefId = authState.data?['otp_reference_id'] ?? widget.otpReferenceId (line 403)
      (picks up a fresher ref id if a resend happened after the screen was pushed)
  → ref.read(authControllerProvider.notifier).verifyOtp(mobile, otp, latestRefId) (line 405-409)
  → AuthNotifier.verifyOtp() (core/services/auth_service.dart:341-403)
      → AuthService.verifyOtp() (auth_service.dart:47-96)
          POST users/auth/verify-otp
          body: {mobile, otp, otp_reference_id}
          → interceptor encrypts 'mobile' + 'otp' (both in sensitiveFields); otp_reference_id sent plain
          ← response {success:true, data:{access_token, refresh_token, mpin_enabled, is_new_user,
                       temp_token?, user:{id_customer, name|full_name, photo_url}}}
          ON SUCCESS (auth_service.dart:61-93), before returning:
            SecureStorageService.saveToken(access_token)
            SecureStorageService.saveRefreshToken(refresh_token)
            SessionManager.resetForceLogout()               ← clears any prior 409 force-logout flag
            SecureStorageService.setMpinEnabled(mpin_enabled == true)
            SecureStorageService.saveCustomerId / saveCustomerName / saveCustomerPhoto (if present)
            SecureStorageService.saveMobile(mobile)
      ← AuthNotifier sets state.isRegistered = !is_new_user, state.sessionData = data, state.data = data
        (auth_service.dart:352-358)
  ← _verifyOtp() reads args (route arguments, NOT the response) for actionType/from_app_lock, then reads
    authState.data for is_new_user/mpin_enabled/temp_token — ROUTING DECISION (otp_screen.dart:411-488):
      actionType=='add_upi'          → Navigator.pop(context, true)                         [line 418-421]
      actionType=='forgot_pin'       → AppRouter.mpin, {type:'reset_pin', temp_token, mobile,
                                        from_app_lock?}                                      [line 424-455]
      is_new_user==true              → AppRouter.registration, {mobile, tempToken}           [line 461-470]
      mpin_enabled==true              → AppRouter.mpin, {mobile}                              [line 471-477]
      else (existing user, no MPIN)  → AppRouter.mpin, {type:'setup', mobile}                 [line 478-486]
  → _releaseScreen() fires in dispose() when the screen is popped/replaced (otp_screen.dart:95-99)
```

**Resend sub-flow**: `_resendOtp()` (otp_screen.dart:76-92) clears the input, calls
`sendOtp(..., type:'RESEND')` (same `generate-otp` endpoint, `type` field flips server behavior), and on
success restarts the 30s timer + shows a success toast. The returned `otp_reference_id` overwrites
`AuthState.data`, which is why `_verifyOtp`'s `latestRefId` lookup (line 403) prefers state over the
originally-passed widget field — verifying against a stale reference id after a resend would fail
server-side otherwise.

## Flow 3: PIN Creation → Register → FCM Registration → Navigation

```
RegistrationScreen (after registerCheck succeeds — see Flow 4) pushes AppRouter.mpinCreation with
  {fullName, mobile, email, dob, referralCode, tempToken} (registration_screen.dart:545-556)
  → app_router.dart:179-191 builds PinCreationScreen with those args

PinCreationScreen (pin/pin_creation_screen.dart)
  → custom keypad, 2-step (PIN entry → confirm), MpinNotifier.pinLength == 6 digits
      (core/services/mpin_service.dart:151), keypad re-shuffled each step (Random.secure(),
      pin_creation_screen.dart:69-79)
  → both steps complete, PINs match → _handleSetPin() (pin_creation_screen.dart:392-464)
  Step 1 — register (skipped if _registerComplete already true from a prior failed PIN attempt, line 405):
    → ref.read(authControllerProvider.notifier).register(mobile, fullName, email, tempToken, dob, referralCode)
        (line 406-414)
    → AuthNotifier.register() (auth_service.dart:519-587)
        → AuthService.register() (auth_service.dart:128-174)
            POST users/auth/register
            body: {mobile, full_name, email, dob, referral_code, temp_token, device_id, device_type}
            → interceptor encrypts 'mobile' only (full_name/email/dob/referral_code/temp_token/device_id/
              device_type are NOT in sensitiveFields — sent plain)
            ← response {success:true, data:{access_token, refresh_token, user:{...}}}
            ON SUCCESS: saves access/refresh token, customer_id, customer_name, mobile to SecureStorage
              (auth_service.dart:150-171)
    if !registerSuccess → toast error, return (stays on confirm-PIN step, user can retry — _registerComplete
      still false so register() will be retried on next confirm)
    else → _registerComplete = true (line 426, prevents double POST /register on subsequent PIN retries)
  Step 2 — set PIN:
    → ref.read(authControllerProvider.notifier).setPin(mobile, pin) (line 430-432)
    → AuthController.setPin() (controller/auth_controller.dart:9-24)
        → MpinService().setMpin(pin) (core/services/mpin_service.dart:13-27)
            POST mpin/create, body:{mpin}
            → interceptor encrypts 'mpin' (mpin/create is in encryptedEndpoints, 'mpin' is in sensitiveFields)
            server always returns HTTP 200; throws Exception(server message) if success!=true
  if pinSuccess:
    → SecureStorageService.setMpinEnabled(true) (pin_creation_screen.dart:436)
    → _registerFcmToken() — FIRE AND FORGET, does not await (line 440, 465-480):
        Future(() async {
          token = await FcmService.getToken()        (core/services/fcm_service.dart:121)
          if token != null:
            await NotificationService().registerFcmToken(token)  (core/services/notification_service.dart:116-146)
                POST users/notifications/register-token
                body: {fcm_token, device_id, device_type, device_model, device_name, os, os_version,
                       manufacturer, brand, hardware_id}
                dedup check: skips POST if token == SecureStorageService.getFcmToken() cached value (line 118-122)
                on success: SecureStorageService.saveFcmToken(token) (line 141)
          catch → debugPrint only, swallowed — never surfaces to UI, never blocks navigation
        })
    → IMMEDIATELY (does not await the Future above) navigates:
        fullName.isNotEmpty → pushReplacementNamed(AppRouter.registrationSuccess, {fullName})
        else                → pushNamedAndRemoveUntil(AppRouter.home, (route)=>false)
  if !pinSuccess:
    → toast 'Failed to set PIN...', resets local _pin/_confirmPin/_isConfirming to restart PIN entry
      (register step is NOT retried — _registerComplete stays true, only setPin is retried)
```

**Timing note**: FCM registration is a genuine fire-and-forget — the `_registerFcmToken()` call is not
`await`ed (`pin_creation_screen.dart:440`), so navigation to `registrationSuccess`/`home` happens on the same
event-loop turn, before the FCM token fetch/POST has any chance to complete. If FCM registration fails, the
user is never told and the app proceeds normally; a later app open won't retry it (no periodic re-registration
sweep found in this module — only `FcmService.onTokenRefresh` naturally re-fires on Firebase's own token
rotation cadence, not on every app open).

## Flow 4: Registration Form → register-check (unencrypted) → PIN Creation Handoff

```
RegistrationScreen — user fills name/DOB/email, must tap "Verify" next to email → _verifyEmail()
  (registration_screen.dart:479-516): sendEmailOtp() → showEmailOtpSheet() (bottom sheet, verifies via
  users/auth/verify-email-otp) → sets _emailVerified=true only on confirmed verification.
"Confirm" button is disabled until _agreedToTerms && _emailVerified (line 122-123, canSubmit).
_handleRegistration() (registration_screen.dart:518-605):
  → ref.read(authServiceProvider).registerCheck(mobile, fullName, email, tempToken, dob, referralCode)
      (line 531-539) — NOTE: calls AuthService directly, bypassing AuthController/AuthNotifier's isLoading
      state; screen manages its own _isSubmitting flag instead (line 39, 527, 603)
  → POST users/auth/register-check — 'auth/register-check' is NOT in AppConfig.encryptedEndpoints
      (app_config.dart:47-71) → payload sent PLAIN (TLS only, no RSA field encryption), unlike its sibling
      POST users/auth/register which DOES encrypt 'mobile'
  result['success']==true → pushReplacementNamed(AppRouter.mpinCreation, {fullName, mobile, email, dob,
      referralCode, tempToken}) — hands off into Flow 3 above
  else → parses nested error.message (Map values.first with brackets stripped, or String, or top-level
      message) and shows via AppToast (lines 557-573, plus a near-identical DioException catch block
      575-597 — duplicated error-parsing logic, not shared with AuthNotifier's own parsing in auth_service.dart)
```
