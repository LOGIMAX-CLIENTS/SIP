---
module: mpin
last_updated: 2026-08-19
---

# METHOD_INDEX — MPIN

Alphabetical by class. Files outside `lib/features/mpin/` are marked `[core]`.

## `_ChangeMpinScreenState` (`lib/features/mpin/change_mpin_screen.dart`)

| Method | file:line | Callers | Notes |
|---|---|---|---|
| `_onBackspace()` | `:72` | backspace key `onTap` (`:354`) | Trims `_currentInput` |
| `_onKeyPressed(String key)` | `:61` | numeric key `onTap` (`:328`) | Appends digit; auto-fires `_processStep` after 200ms once 6 digits entered |
| `_processStep()` | `:78` | `_onKeyPressed` (via delayed callback) | 3-way switch on `_step` (`enterOld`/`enterNew`/`confirmNew`); confirmNew branch calls `MpinService.changeMpin` |
| `_shuffleKeypad()` | `:39` | `initState`, after every step transition | `List.shuffle()` (not `Random.secure()` — contrast with `mpin_screen.dart`, see STATE_ANALYSIS) |
| `_showSuccessAndPop()` | `:137` | `_processStep` confirmNew success | Shows dialog; "Done" pops dialog then pops screen (double `Navigator.pop`) |
| `_stepSubtitle` (getter) | `:53` | `build` | Per-step subtitle text |
| `_stepTitle` (getter) | `:45` | `build` | Per-step title text |
| `build(BuildContext)` | `:193` | Flutter framework | |

## `_MpinScreenState` (`lib/features/mpin/mpin_screen.dart`)

| Method | file:line | Callers | Notes |
|---|---|---|---|
| `_authenticateBiometric()` | `:110` | `_loadMpinStatus` (auto-trigger), fingerprint-icon `onTap` (`_buildBiometricHint`) | Branches post-success navigation on `type` (`authorize_withdrawal`/`verify_only`/`app_lock`/default→`main`) |
| `_buildAuroraOrb(...)` | `:612` | `build` (dark-mode background decoration) | Pure UI |
| `_buildBackspaceKey()` | `:949` | `build` keypad row | |
| `_buildBiometricHint()` | `:635` | `build` keypad row | Hides icon for `withdrawal_pin`/`verify_only`/`verify_after_reset` or when biometric unavailable |
| `_buildNumRow(List<String>)` | `:898` | `build` (keypad, 3 rows) | |
| `_buildNumberKey(String)` | `:905` | `_buildNumRow`, direct 4th-row call | Calls `mpinProvider.notifier.addKey` |
| `_handleAction()` | `:662` | CTA `onPressed`, auto-submit `ref.listen` (`:227-238`) | Central dispatcher: `setup`→`setMpin()`, `reset_pin`→`resetMpin()`, else→`verifyMpin()`. Owns all post-success navigation. |
| `_handleForgotPin()` | `:767` | "Forgot PIN?" `onTap` | Reads stored mobile, calls `AuthService.sendOtp(type: 'FORGOT_PIN')`, navigates to `/otp` with `actionType: 'forgot_pin'` (+`from_app_lock` if applicable) |
| `_loadMpinStatus()` | `:69` | `initState` post-frame callback | Reads `SecureStorageService.isMpinEnabled()` + `BiometricService.canUseBiometric()`; auto-triggers biometric unless `type` in `{withdrawal_pin, verify_only, app_lock, verify_after_reset}` |
| `_registerFcmTokenAfterLogin()` | `:749` | `_handleAction` (default/`verify_after_reset` success paths) | Fire-and-forget; swallows all errors |
| `_releaseScreen()` | `:180` | `dispose` | `ScreenshotSecurityService.releaseScreen()` |
| `_secureScreen()` | `:176` | `initState` | `ScreenshotSecurityService.secureScreen()` |
| `_shuffleKeypad()` | `:147` | `initState`, `didChangeAppLifecycleState(resumed)`, after every failed submit | Uses `Random.secure()` — explicit "banking-grade" comment (`:160`) |
| `_showSuccessDialog()` | `:848` | `_handleAction` (`authorize_withdrawal` success), `_authenticateBiometric` (`authorize_withdrawal` via biometric) | "Withdrawal Successful" dialog → `main` |
| `build(BuildContext)` | `:192` | Flutter framework | Wraps everything in `PopScope`; contains 2 `ref.listen` blocks (error/session-expiry, auto-submit) |
| `didChangeAppLifecycleState(AppLifecycleState)` | `:140` | `WidgetsBinding` (screen implements `WidgetsBindingObserver`) | Re-shuffles keypad on resume (independent of app-lock re-auth, which is handled by `AppLifecycleObserver` before this screen is even shown) |
| `dispose()` | `:184` | Flutter framework | Removes observer, releases screenshot lock |
| `initState()` | `:54` | Flutter framework | Registers observer, clears `mpinProvider` state, shuffles keypad, secures screen |

## `MpinNotifier extends StateNotifier<MpinState>` `[core]` (`lib/core/services/mpin_service.dart`)

| Method | file:line | Callers | Notes |
|---|---|---|---|
| `addKey(String key)` | `:155` | `mpin_screen.dart` `_buildNumberKey` | No-op if already at `pinLength` (6) |
| `backspace()` | `:165` | `mpin_screen.dart` `_buildBackspaceKey` | |
| `clear()` | `:315` | `mpin_screen.dart initState` (via `Future.microtask`) | Resets to fresh `MpinState()` |
| `resetMpin(String tempToken, {String? mobile})` | `:296` | `mpin_screen.dart _handleAction` (`reset_pin` branch) | Guards on `isLoading`; clears PIN state on error, not on success (state cleared by caller's `clear()`/navigation instead) |
| `setMpin()` | `:175` | `mpin_screen.dart _handleAction` (`setup` branch) | Guards on `isLoading` |
| `verifyMpin()` | `:194` | `mpin_screen.dart _handleAction` (default branch, all verify-style `type`s) | Guards on `isLoading \|\| isLocked`; 3-way error handling for 409/`SessionInvalidatedFailure`/`SESSION_EXPIRED`/generic; 5-strike lockout |

## `MpinService` `[core]` (`lib/core/services/mpin_service.dart`)

| Method | file:line | Callers | Endpoint | Notes |
|---|---|---|---|---|
| `changeMpin(String oldMpin, String newMpin)` | `:58` | `change_mpin_screen.dart _processStep` (direct, not via notifier) | `POST mpin/change` | Throws `Exception(msg)` on `success!=true` |
| `hasMpinSet()` | `:101` | **No call site found in `lib/`** (unconfirmed — possibly dead/reserved for a future flow) | `POST auth/has-mpin` | |
| `resetMpin(String tempToken, String newMpin, {String? mobile})` | `:80` | `MpinNotifier.resetMpin` | `POST mpin/reset` | |
| `setMpin(String mpin)` | `:13` | `MpinNotifier.setMpin` | `POST mpin/create` | |
| `verifyMpin(String mpin)` | `:30` | `MpinNotifier.verifyMpin` | `POST mpin/validate` | On body-level `SESSION_EXPIRED` code, synthesizes and throws a `DioException` with `statusCode: 401` so the notifier's catch block can classify it |

## `BiometricService` `[core]` (`lib/core/services/biometric_service.dart`)

| Method | file:line | Callers | Notes |
|---|---|---|---|
| `authenticate({required String reason})` | `:90` | `mpin_screen.dart _authenticateBiometric`, `app_lifecycle_observer.dart _tryBiometricThenMpin` | Swallows all exceptions → `false` |
| `canUseBiometric()` | `:48` | `mpin_screen.dart _loadMpinStatus`, `app_lifecycle_observer.dart _preCacheSecurityState` | Side-effect: auto-disables stored flag if device biometrics were removed |
| `checkBeforeEnable()` | `:69` | Outside this module (Settings biometric-toggle flow — not read in this pass) | |
| `deviceHasBiometric()` | `:25` | `canUseBiometric` | |

## `AppLifecycleObserver` `[core]` (`lib/core/security/app_lifecycle_observer.dart`)

| Method | file:line | Callers | Notes |
|---|---|---|---|
| `_checkAppLockOnResume()` | `:105` | `didChangeAppLifecycleState(resumed)` | Full guard chain — see MODULE_BRAIN §6 |
| `_preCacheSecurityState()` | `:79` | `didChangeAppLifecycleState(paused)` | |
| `_pushMpinLockScreen(NavigatorState)` | `:193` | `_checkAppLockOnResume`, `_tryBiometricThenMpin` fallback | Pushes `/mpin` with `type: 'app_lock'` |
| `_tryBiometricThenMpin(NavigatorState)` | `:170` | `_checkAppLockOnResume` | |
| `didChangeAppLifecycleState(AppLifecycleState)` | `:50` | Flutter framework | Also owns socket connect/disconnect + clipboard clear on resume (VAPT) |
| `resetLockFlag()` (static) | `:214` | Not called within this module's read files (escape hatch documented as available elsewhere) | |
