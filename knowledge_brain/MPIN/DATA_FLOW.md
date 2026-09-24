---
module: mpin
last_updated: 2026-08-19
---

# DATA_FLOW — MPIN

## Flow 1: Login-mode Verify (untyped `type`, the common case)

```
auth/otp/otp_screen.dart:475
  Navigator.pushReplacementNamed(context, AppRouter.mpin, arguments: {'mobile': widget.mobile})
        │
        ▼
mpin_screen.dart:54 initState()
  → WidgetsBinding.addObserver(this)
  → Future.microtask: ref.read(mpinProvider.notifier).clear()          [mpin_service.dart:315]
  → addPostFrameCallback: _loadMpinStatus()                             [mpin_screen.dart:69]
  → _shuffleKeypad()  (Random.secure())                                 [:147]
  → _secureScreen()  → ScreenshotSecurityService.secureScreen()         [:176]
        │
        ▼
_loadMpinStatus() [:69]
  → SecureStorageService.isMpinEnabled()
  → BiometricService.canUseBiometric()                                  [biometric_service.dart:48]
  → type is null → NOT in the skip-list {withdrawal_pin, verify_only, app_lock, verify_after_reset}
  → auto-calls _authenticateBiometric() if biometric+mpin both enabled  [:105]
        │
        ▼ (user types 6 digits via keypad — or biometric succeeds first)
mpinProvider.notifier.addKey(digit) × 6                                 [mpin_service.dart:155]
  → state.isComplete = true once length==6
        │
        ▼
ref.listen auto-submit block [:227-238]
  → type is null → matches auto-submit allow-list → _handleAction()
        │
        ▼
_handleAction() [:662] → else branch (verify) [:712]
  → ref.read(mpinProvider.notifier).verifyMpin()                        [mpin_service.dart:194]
        → guard: isLoading||isLocked → early false if so
        → MpinService.verifyMpin(mpin)                                  [:30]
              → ApiClient.post('mpin/validate', data:{'mpin': mpin})
              → api_interceptor.dart: path in encryptedEndpoints → EncryptionService.encryptJson()
                  → 'mpin' in sensitiveFields → RSA-OAEP-SHA256 encrypt before send
              ← response: {success: bool, ...} (HTTP 200 always, per code comment :36)
        → success==true  → state.failedAttempts=0, isLoading=false, return true
        → success==false → failedAttempts++, isLocked = attempts>=5, error message set, return false
        → (network/DioException path — see Flow 2 for 409 handling)
        │
        ▼ success path
_handleAction() [:716]
  → SecureStorageService.setMpinEnabled(true)
  → type default branch [:733-738]:
      _registerFcmTokenAfterLogin()  (fire-and-forget: FcmService.getToken() → NotificationService.registerFcmToken()) [:749]
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.main, (route)=>false)
```

Failure path: `_shuffleKeypad()` called again (`:741`), PIN cleared by notifier, error toast shown via the other `ref.listen` block (`:199-222`) unless the error is a suppressed 409/SessionInvalidated case.

## Flow 2: App-Lock-mode Resume Flow

```
App backgrounded
  → AppLifecycleObserver.didChangeAppLifecycleState(paused)              [app_lifecycle_observer.dart:50]
      _pausedAt = DateTime.now()
      _preCacheSecurityState()  [:79]  (async, invisible — reads secure storage while user is leaving)
        → _cachedIsAuth = SessionManager.isAuthenticated()
        → _cachedMpinEnabled = SecureStorageService.isMpinEnabled()
        → _cachedBiometricEnabled = BiometricService.canUseBiometric()
      ref.read(socketIOServiceProvider).disconnect()
        │
        ▼
App resumed
  → didChangeAppLifecycleState(resumed) [:63]
      ClipboardSecurityService.clearClipboard()
      ref.read(socketIOServiceProvider).connect()
      _checkAppLockOnResume() [:105]  — fully synchronous guard chain:
        1. _isLockScreenShowing? → abort (already showing)
        2. suppressAppLock? → abort (payment SDK flow in progress)
        3. SessionManager.isForceLoggedOut? → abort (409 dialog owns the screen)
        4. !_cachedIsAuth? → abort (not logged in)
        5. !_cachedMpinEnabled? → abort (no MPIN configured)
        6. _pausedAt == null? → abort (cold start, never actually paused)
        7. currentRoute already '/mpin' or in {login, splash, onboarding, otp, registration, registration-success}? → abort
        │
        ▼ all guards pass
      _cachedBiometricEnabled == true?
        ├─ yes → _tryBiometricThenMpin(nav) [:170]
        │           BiometricService.authenticate(reason:'Verify your identity to continue')
        │           success → _isLockScreenShowing=false, DONE (no MPIN screen shown at all)
        │           fail/cancel/exception → _pushMpinLockScreen(nav)
        └─ no  → _pushMpinLockScreen(nav) [:193]
                    Future.microtask(() → nav.pushNamed('/mpin', arguments:{'type':'app_lock'}))
                    .then(_isLockScreenShowing = false)   ← fires when mpin screen is POPPED
        │
        ▼
mpin_screen.dart with type='app_lock'
  → _loadMpinStatus(): type IS in skip-list → does NOT auto-trigger biometric again
    (AppLifecycleObserver already tried biometric before pushing this screen)
  → isRootFlow = true (type=='app_lock') → PopScope blocks back-press entirely,
    shows "Please verify your PIN to continue" toast on back attempt [:264-271]
  → user enters PIN → auto-submit → _handleAction() → verifyMpin()
  → success → type=='app_lock' branch [:725-727]: Navigator.pop(context, true)
      → resolves the .then() in _pushMpinLockScreen → _isLockScreenShowing=false
      → user resumes exactly where they left off (nav stack untouched)
```

409-during-resume-verify sub-case: if `verifyMpin()` hits a 409 (`mpin_service.dart:217-236` DioException branch, or `:264-277` `SessionInvalidatedFailure` branch — the latter is the actually-reached path since `ApiClient` converts interceptor rejections before the notifier's `DioException` catch clause sees them), no local error is set; the interceptor's own `SessionInvalidatedDialog.show()` (`api_interceptor.dart:244`) fires independently and takes over the screen. The MPIN screen itself is left showing an empty keypad with `isLoading=false` behind the dialog.

## Flow 3: Reset-PIN Flow (forgot-PIN, two variants)

```
"Forgot PIN?" tapped (visible only when type==null or type=='app_lock', :513)
  → _handleForgotPin() [:767]
      mobile = SecureStorageService.getMobile()  (redirect to /login if missing)
      isAppLock = currentArgs['type']=='app_lock'
      AuthService().sendOtp(mobile, countryCode:'+91', idCountry:'101', type:'FORGOT_PIN')
      on success → otpRefId = result.data.otp_reference_id
        ├─ isAppLock: pushNamedAndRemoveUntil('/otp', arguments:{..., actionType:'forgot_pin', from_app_lock:true})
        └─ else:      pushReplacementNamed('/otp', arguments:{..., actionType:'forgot_pin'})
        │
        ▼
[auth module OTP verify screen — not part of this brain — presumably produces temp_token]
        │
        ▼
otp_screen.dart:446-448 on successful OTP verify for actionType=='forgot_pin'
  → pushReplacementNamed('/mpin', arguments:{'type':'reset_pin', 'temp_token':..., 'mobile':..., 'from_app_lock': ...})
        │
        ▼
mpin_screen.dart, type='reset_pin'
  → isFromAppLock = args['from_app_lock']==true
  → isRootFlow = true if isFromAppLock (blocks back-nav w/ toast) else false (normal pop allowed)
  → "Forgot PIN?" hidden (showForgotPin requires type==null||'app_lock')
  → user enters new 6-digit PIN → auto-submit (reset_pin is in auto-submit allow-list, :234)
        │
        ▼
_handleAction() [:679] reset_pin branch
  → tempToken = args['temp_token'] ?? ''
  → mobile = args['mobile']
  → ref.read(mpinProvider.notifier).resetMpin(tempToken, mobile: mobile)   [mpin_service.dart:296]
        → MpinService.resetMpin(tempToken, newMpin, mobile: mobile)         [:80]
              → POST mpin/reset {temp_token, new_mpin, mobile?}
              → interceptor encrypts new_mpin + mobile (both in sensitiveFields); temp_token is NOT encrypted (not in sensitiveFields list)
        → success → resolve true
        → failure → Exception(server message) → state.error set, PIN cleared
        │
        ▼ success
  → SecureStorageService.setMpinEnabled(true)
  → fromAppLock?
      ├─ true:  pushNamedAndRemoveUntil('/mpin', arguments:{'type':'verify_after_reset','mobile':mobile})
      │           → user must immediately re-enter the PIN they just set (no biometric
      │             auto-trigger, no "Forgot PIN?", back-nav fully blocked — isRootFlow=true)
      │           → verifyMpin() success → _registerFcmTokenAfterLogin() → pushNamedAndRemoveUntil(main)
      └─ false: pushReplacementNamed('/mpin', arguments:{'mobile':mobile})   (untyped → normal login-verify flow, Flow 1)
```

## Notes on Encryption Boundary (all flows)

Payload encryption happens at the Dio-interceptor level (`api_interceptor.dart:170-177`), not inside `MpinService`/`MpinNotifier` — the service layer sends plain-text field maps; the interceptor rewrites `options.data` in place before the request leaves the device, gated on `AppConfig.encryptedEndpoints.any((e) => path.contains(e))` (`:133-134`). This means any future new field added to a `mpin/*` request body is automatically encrypted for free **only if its key name is also added to `AppConfig.sensitiveFields`** (`app_config.dart:74-99`) — adding a field to the request map alone does not encrypt it.
