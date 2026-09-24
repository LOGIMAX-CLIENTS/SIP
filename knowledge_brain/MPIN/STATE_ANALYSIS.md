---
module: mpin
last_updated: 2026-08-19
---

# STATE_ANALYSIS — MPIN

## Riverpod Providers

| Provider | Type | Defined | Consumed by |
|---|---|---|---|
| `mpinServiceProvider` | `Provider<MpinService>` | `core/services/mpin_service.dart:109` | `mpinProvider`, `change_mpin_screen.dart:116` (`ref.read(mpinServiceProvider)`) |
| `mpinProvider` | `StateNotifierProvider<MpinNotifier, MpinState>` | `core/services/mpin_service.dart:320-323` | `mpin_screen.dart` only (`ref.watch`/`ref.read`/`ref.listen` throughout). **Not** watched by `change_mpin_screen.dart`. |

No module-local providers exist — everything state-related lives in `core/services/mpin_service.dart`, consistent with AGENTS.md §1's guidance that cross-feature/global state belongs in `core/providers` (here, `core/services`, which for this module doubles as the state layer).

## `MpinState` shape (`core/services/mpin_service.dart:111-147`)

```dart
class MpinState {
  final String mpin;            // accumulated digits, cleared on error/success transitions
  final bool isComplete;        // true once mpin.length == MpinNotifier.pinLength (6)
  final bool isLoading;         // true during any in-flight setMpin/verifyMpin/resetMpin call
  final String? error;          // user-facing message, or the sentinel string 'SESSION_EXPIRED'
  final int failedAttempts;     // increments on each server-rejected verifyMpin() call
  final bool isLocked;          // true once failedAttempts >= 5
}
```

`copyWith` supports an explicit `clearError` bool (not just `error ?? this.error`) — necessary because `error` needs to be settable back to `null`, which a plain `??` pattern can't express.

**Not tracked in state**: which `type`/mode the screen is in (that lives entirely in `ModalRoute` arguments, re-read on every relevant callback — not cached in any provider or `State` field except transient locals like `_isMpinEnabledCount`/`_isBiometricEnabled` in `_MpinScreenState`). This means the mode is **not testable/inspectable via the provider alone** — any widget/golden test exercising `mpinProvider` in isolation cannot determine which mode is active without also controlling `ModalRoute` arguments.

## `change_mpin_screen.dart` local state (not in any provider)

```dart
_ChangePinStep _step;      // enterOld → enterNew → confirmNew (enum, change_mpin_screen.dart:15)
String _oldPin;
String _newPin;
String _currentInput;
bool _isLoading;
List<String> _shuffledNumbers;
```

Fully local `ConsumerState` fields — the 3-step wizard progress, both PIN values in flight, and the loading flag are never exposed outside this widget. This is appropriate per AGENTS.md §1 (screen-local UI state need not be a provider) but means a killed app mid-flow simply restarts the wizard from `enterOld` with no persistence — consistent with the doc's "Edge Cases: App killed during PIN setup → forces re-setup" pattern, though that specific claim in `STARTGOLD_DOCUMENTATION.md` was written about the `setup` type in `mpin_screen.dart`, not `change_mpin_screen.dart`; both share the same "in-memory only, restart-from-step-1" behavior by construction (no persistence layer for partial PIN-entry progress in either screen).

## Secure-storage keys touched (via `SecureStorageService`, keys defined in `AppConfig`)

| Key constant | Storage key string | Read by | Written by |
|---|---|---|---|
| `AppConfig.keyIsMpinEnabled` | `is_mpin_enabled` | `mpin_screen.dart:_loadMpinStatus` (`:70`), `app_router.dart` fallback, `splash_screen.dart`, `navigation_utils.dart`, `app_lifecycle_observer.dart` (cached) | `mpin_screen.dart:_handleAction` on every successful `setup`/`reset_pin`/verify (`:673,689,717`) — note: **all three** paths call `setMpinEnabled(true)`, including plain login-verify, which is a no-op if already `true` but means this flag is re-asserted on every login |
| `AppConfig.keyIsBiometricEnabled` | `is_biometric_enabled` | `BiometricService.canUseBiometric()` | `BiometricService.canUseBiometric()` — auto-disables (`setBiometricEnabled(false)`) if the device's enrolled biometrics were removed (`biometric_service.dart:56-58`) |
| `AppConfig.keyMobileNumber` | `mobile_number` | `mpin_screen.dart:_handleForgotPin` via `SecureStorageService.getMobile()` (`:768`) | Not written by this module (written during login/registration in `auth`) |
| (all keys) | — | — | `SecureStorageService.logout()` — called from `mpin_screen.dart`'s `SESSION_EXPIRED` handler (`:209`) to wipe everything before redirecting to `/login` |

No module file reads/writes the RSA public key cache (`keyServerPublicKey`) or FCM token cache directly — those are owned by `EncryptionService`/`NotificationService` respectively and only invoked, not managed, from here.

## Model Shapes

This module has **no dedicated model files** (no `models/` subfolder under `lib/features/mpin/`). All data is either:
- Primitive strings (`mpin`, `old_mpin`, `new_mpin`, `temp_token`, `mobile`) passed directly as `Map<String, dynamic>` request bodies in `MpinService`, or
- Raw `response.data` maps read ad hoc (`data['success']`, `data['error']['message']`, `data['error']['code']`) with no typed wrapper/DTO — every service method re-implements the same `success`/`error.message`/`error.code` parsing pattern inline (`mpin_service.dart:18-26,36-51,66-75,90-97`).

This is a candidate for a shared `ApiResponse<T>` or `Failure`-mapping helper if this pattern is duplicated across other modules — worth checking when building `_SYSTEM/MODULE_DEPENDENCIES.md`.
