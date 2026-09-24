---
module: mpin
brain_status: 🟢 (≥80%, not yet manually spot-checked for 🔵)
last_updated: 2026-08-19
source_files_read: 2/2 feature files + 9 core/routes dependency files
---

# MPIN Module Brain

## 1. Purpose & Scope

`lib/features/mpin/` is the app's identity-verification gate. It contains exactly **2 files**:

| File | Lines | Role |
|---|---|---|
| `lib/features/mpin/mpin_screen.dart` | 970 | Single multi-purpose screen driven entirely by `ModalRoute` arguments (`type`, `mobile`, `temp_token`, `from_app_lock`). Handles verify, setup, reset, and several sub-flow variants. |
| `lib/features/mpin/change_mpin_screen.dart` | 365 | Standalone 3-step wizard (old → new → confirm) for an already-authenticated user changing their MPIN. Does not use `MpinNotifier`/`mpinProvider` — talks to `MpinService.changeMpin()` directly via local `StatefulWidget` state. |

Both screens use a **6-digit** PIN (`MpinNotifier.pinLength = 6`, `core/services/mpin_service.dart:151`; confirmed via UI copy "Create a **6-digit** PIN" `mpin_screen.dart:371` and "Enter your existing **6-digit** MPIN" `change_mpin_screen.dart:55`).

## 2. DRIFT vs STARTGOLD_DOCUMENTATION.md §3.8–3.9 — CONFIRMED

The hand-written doc is stale in three material ways:

1. **PIN length**: doc says "4-digit secure PIN input" (§3.8 Features). Actual code is **6-digit** everywhere (`mpin_screen.dart:414`, `:371`, `:373`, `change_mpin_screen.dart:55,62,254`). No 4-digit code path exists anywhere in the module.
2. **Mode count**: doc claims exactly **4 modes** (`login`, `app_lock`, `reset_pin`, `setup`). Actual code branches on **7 distinct `type` argument values** plus the untyped default — see §3 below. `verify_only`, `withdrawal_pin`, `authorize_withdrawal`, and `verify_after_reset` are entirely undocumented.
3. **API path prefix**: doc lists `POST users/mpin/validate`, `users/mpin/reset`, `users/mpin/change`. Actual `MpinService` calls (`core/services/mpin_service.dart:14,31,59,82`) hit `mpin/create`, `mpin/validate`, `mpin/change`, `mpin/reset` — **no `users/` prefix**. `ApiClient` (`core/network/api_client.dart:16-18`) does not add one; `AppConfig.baseUrl` already ends in `/api/v1/`. `AppConfig.encryptedEndpoints` (`core/config/app_config.dart:63-66`) also lists the un-prefixed paths, confirming the doc's `users/` prefix is wrong, not a Dio-level rewrite.

Everything else in the hand-written doc (encryption on `mpin`/`new_mpin`, biometric fallback, `PopScope` blocking, 409→force-logout, double-tap prevention) is **confirmed accurate** at a high level, though the mechanics are more nuanced than the doc implies (see §5, §6).

## 3. The Real Mode Model — 8 `type` values (not 4)

`mpin_screen.dart` has no `mode` field; behavior is entirely keyed off `args['type']` read fresh in `initState`/`build`/`_handleAction`/etc. (`ModalRoute.of(context)?.settings.arguments`).

| `type` value | Meaning | Entry point (who navigates in) | Action on submit | Exit |
|---|---|---|---|---|
| `null` (untyped) | Login verify / "toggle MPIN on" from Settings | `auth/otp/otp_screen.dart:475` (post-login-OTP), `splash/splash_screen.dart:71`, `settings/settings_screen.dart:49` (see §7 anti-pattern), `app_router.dart:404` fallback, `core/utils/navigation_utils.dart:40` fallback | `verifyMpin()` → `POST mpin/validate` | `pushNamedAndRemoveUntil(main)` + FCM token registration |
| `setup` | Create PIN (registration edge-case recovery, NOT the primary registration PIN-creation flow — that's `auth`'s `PinCreationScreen` at route `/mpin-creation`) | `auth/otp/otp_screen.dart:485` | `setMpin()` → `POST mpin/create` | `pushNamedAndRemoveUntil(main)` |
| `reset_pin` | Forgot-PIN: set new PIN after OTP-verified identity | `auth/otp/otp_screen.dart:447` (also self-navigated from within this screen, `mpin_screen.dart:703`) | `resetMpin(tempToken, mobile)` → `POST mpin/reset` | If `from_app_lock` → re-push mpin as `verify_after_reset` (`mpin_screen.dart:692`); else `pushReplacementNamed(mpin)` untyped |
| `app_lock` | App resumed from background, re-auth required | `core/security/app_lifecycle_observer.dart:203` | `verifyMpin()` | `Navigator.pop(context, true)` — preserves nav stack |
| `verify_only` | Identity check before showing sensitive Profile data | `profile/profile_screen.dart:84` | `verifyMpin()` | `Navigator.pop(context, true)` |
| `withdrawal_pin` | Authorize a withdrawal | `withdrawal/screens/withdrawal_confirmation_screen.dart:466` | `verifyMpin()` | `Navigator.pop(context, pin)` — returns raw PIN string to caller |
| `authorize_withdrawal` | Same intent as `withdrawal_pin` but shows an in-screen success dialog instead of popping | **No call site found anywhere in `lib/` outside `mpin_screen.dart` itself** (`mpin_screen.dart:122,348,520,541,718`) — unconfirmed whether this is dead code or reached via a path not covered by static grep (e.g. deep link) | `verifyMpin()` | `_showSuccessDialog()` → button navigates to `main` |
| `verify_after_reset` | Re-verify the just-created PIN after a reset-from-app-lock, before resuming | Self-navigated only, from `mpin_screen.dart:697` | `verifyMpin()` | FCM registration + `pushNamedAndRemoveUntil(main)` |

Derived flag `isFromAppLock = args['from_app_lock'] == true` further modifies `reset_pin` behavior (treated as a "root flow" that blocks back-nav, same as `app_lock`) — see `mpin_screen.dart:247-251`.

## 4. Screen/Route Table

| Route constant | Path | Screen | Registered | Arguments consumed |
|---|---|---|---|---|
| `AppRouter.mpin` | `/mpin` | `MpinScreen` | `app_router.dart:142` | `type`, `mobile`, `temp_token`, `from_app_lock` |
| `AppRouter.changeMpin` | `/change-mpin` | `ChangeMpinScreen` | `app_router.dart:143` | none |

Note: `AppRouter.mpinCreation` (`/mpin-creation`, `app_router.dart:179-191`) resolves to `PinCreationScreen` in `features/auth/pin/` — **not** part of this module, despite the name. Registration's initial PIN creation is an `auth`-module concern; `mpin`'s `setup` type is a separate, narrower recovery path.

## 5. Security Mechanics (verified)

- **Encryption**: `mpin`, `old_mpin`, `new_mpin` are all in `AppConfig.sensitiveFields` (`core/config/app_config.dart:93-95`); `mpin/create|validate|change|reset` are all in `AppConfig.encryptedEndpoints` (`:63-66`). The interceptor (`core/security/api_interceptor.dart:133-134,170-177`) RSA-OAEP-SHA256-encrypts the whole payload via `EncryptionService.encryptJson` (`core/security/encryption_service.dart:109-126`) whenever the request path matches an encrypted endpoint — field selection is separate from endpoint selection (a matched endpoint encrypts only the fields present in `sensitiveFields`). `mobile` is also in `sensitiveFields`, so `resetMpin`'s optional `mobile` field is encrypted too.
- **Biometric fallback**: `BiometricService.authenticate()` (`core/services/biometric_service.dart:90-101`) wraps `local_auth` in a try/catch that returns `false` on any error (including user cancellation) — the caller never sees an exception, so the UI always falls back to showing the manual keypad. Two independent call sites: `mpin_screen.dart:_authenticateBiometric` (auto-triggered on screen open, and via manual fingerprint-icon tap) and `app_lifecycle_observer.dart:_tryBiometricThenMpin` (resume-triggered, pushes the MPIN screen on failure).
- **Screenshot block**: `mpin_screen.dart` calls `ScreenshotSecurityService.secureScreen()`/`releaseScreen()` in `initState`/`dispose` (`:176-189`). `change_mpin_screen.dart` does **not** call either — unconfirmed whether this is intentional (screen shows no PIN value, only dots) or an oversight; flag as inconsistent with AGENTS.md §3's "auth, OTP, MPIN, and payment screens at minimum" guidance.
- **Session/409**: `MpinNotifier.verifyMpin()` (`core/services/mpin_service.dart:194-293`) has three separate 409/session-expiry code paths — a `DioException` with `statusCode==409`, a caught `SessionInvalidatedFailure` (the more common real path since `ApiClient` converts interceptor rejections before they reach the notifier), and a body-level `SESSION_EXPIRED` code check covering HTTP 200 responses. All three intentionally set **no error string** on the 409/`SessionInvalidatedFailure` paths, deferring to the interceptor's own `SessionInvalidatedDialog` (`api_interceptor.dart:244,276`) to avoid a duplicate toast. The `SESSION_EXPIRED` body-code path is different — it sets `error: 'SESSION_EXPIRED'`, which `mpin_screen.dart`'s `ref.listen` (`:199-222`) catches, shows a toast, clears secure storage, and redirects to `/login`.
- **`PopScope` back-blocking** (`mpin_screen.dart:253-290`): `isRootFlow = type==null || type=='setup' || type=='app_lock' || (type=='reset_pin' && isFromAppLock) || type=='verify_after_reset'`. Root flows fully own back-press: `app_lock`/`reset_pin`-from-app-lock/`verify_after_reset` show a "please verify" toast and block exit entirely; the plain login/setup root flow instead does double-tap-to-exit-app (`SystemNavigator.pop()` on 2nd press within 2s). Non-root types (`verify_only`, `withdrawal_pin`, `authorize_withdrawal`, `reset_pin` without `from_app_lock`) allow a normal pop.
- **Double-submit guards**: three layers — (1) `MpinNotifier.verifyMpin/setMpin/resetMpin` each early-return `false` if `state.isLoading` (also `state.isLocked` for verify) (`mpin_service.dart:195,176,297`); (2) the CTA `onPressed` is `null` unless `isComplete && !isLocked` (`mpin_screen.dart:534-536`); (3) `CustomButton` itself disables `onPressed` whenever `isLoading` (`shared/widgets/custom_button.dart:67`). `change_mpin_screen.dart` has a weaker guard — no button, auto-submits via `Future.delayed(200ms)` once 6 digits are entered, gated by `_currentInput.length < pinLength`; no explicit `_isLoading` check on the keypad, but the natural full-length state prevents re-triggering. See FORENSIC_TEMPLATE for the theoretical gap.
- **Lockout**: client-side only — 5 failed `verifyMpin()` attempts sets `isLocked=true` with message "ACCOUNT LOCKED: Too many failed attempts. Contact support." (`mpin_service.dart:203-213`). There is no unlock path in this module (no countdown, no server unlock call) — the user is stuck until they escape via `_handleForgotPin` (still reachable — the CTA is disabled but "Forgot PIN?" isn't gated on `isLocked`).

## 6. App-Lock Integration (`core/security/app_lifecycle_observer.dart`)

Not part of the `mpin` folder but its primary trigger. On `paused`, pre-caches `SessionManager.isAuthenticated()`, `SecureStorageService.isMpinEnabled()`, `BiometricService.canUseBiometric()` synchronously-available for `resumed` (`:79-88`). On `resumed`, `_checkAppLockOnResume()` (`:105-166`) triggers only if: not already showing a lock screen, `suppressAppLock` is false (payment-SDK flows set this — AGENTS.md §3), `SessionManager.isForceLoggedOut` is false (409 dialog takes priority), cached auth+MPIN-enabled are both true, and `_pausedAt` was actually set (skips cold start). It also skips entirely if the current route is already `/mpin`, `/login`, `/splash`, `/onboarding`, `/otp`, `/registration`, or `/registration-success`. If biometric is enabled it tries biometric first (`_tryBiometricThenMpin`); any failure/cancel falls back to pushing `/mpin` with `type: 'app_lock'`.

## 7. Known Anti-Patterns / Open Questions

1. **`settings_screen.dart:47-51` possible bug (unconfirmed)**: navigates to `/mpin` with `arguments: {'mobile': mobile}` — **no `type` key** — with a comment claiming "it handles both setup and unlock based on isMpinEnabled flag." But `_handleAction()` (`mpin_screen.dart:662-744`) branches purely on `args['type']`; when `type` is absent it always calls `verifyMpin()` (login-verify path), never `setMpin()`. If a user has no MPIN set and toggles it on from Settings, this would attempt to *verify* a PIN that was never created rather than *create* one — worth live-testing before trusting the comment.
2. **`authorize_withdrawal` dead code (unconfirmed)**: referenced 5x in `mpin_screen.dart` but no navigator call site anywhere else in `lib/`. Either dead code left from a prior withdrawal-auth design, or reached via a path outside static grep coverage.
3. **`change_mpin_screen.dart` has no `ScreenshotSecurityService` call** — inconsistent with `mpin_screen.dart` and AGENTS.md §3's screenshot-block guidance for MPIN screens.
4. **Client-side-only lockout** — 5 failed attempts locks the UI locally (`isLocked` in `MpinState`) but this resets on screen rebuild/app restart (in-memory `StateNotifier` state, not persisted) — unconfirmed whether the server independently rate-limits `mpin/validate`.

## 8. Related Docs

`METHOD_INDEX.md` · `DATA_FLOW.md` · `BUSINESS_RULES.md` · `CROSS_MODULE_MAP.md` · `STATE_ANALYSIS.md` · `FORENSIC_TEMPLATE.md` · `COVERAGE_TRACKER.md` (this folder).
