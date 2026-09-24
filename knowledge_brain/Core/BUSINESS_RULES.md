---
module: core/
last_updated: 2026-08-19
---

# Core — Business Rules

## RULE-CORE-001: A request is only touched by the security layer if its path matches `encryptedEndpoints`
Two independent gates decide encryption, not one. First, `AppConfig.encryptedEndpoints`
(`config/app_config.dart:47`, matched via `path.contains(e)`) decides whether a request is considered
"sensitive" at all — this controls RSA-key bootstrap timing, field encryption, and response "decryption"
attempts. A request to an endpoint not in this list is sent and received as plain JSON even if it happens to
contain a field name that's in `sensitiveFields` (e.g. a hypothetical `amount` field on a non-listed
endpoint would NOT be encrypted). Code: `security/api_interceptor.dart:133-134,193-194`.

## RULE-CORE-002: Within a sensitive request, only individually-named fields are encrypted
Second gate: `AppConfig.sensitiveFields` (`config/app_config.dart:74-99`) — `password`, `otp`, `login_pin`,
`transaction_pin`, `aadhaar_number`, `pan_number`, `pan`, `bank_account_number`, `account_no`, `ifsc_code`,
`upi_id`, `kyc_details`, `withdrawal_amount`, `payment_details`, `amount`, `amount_inr`, `payment_pin`,
`bank_details`, `mpin`, `old_mpin`, `new_mpin`, `mobile`, `weight`, `buy_rate`. `EncryptionService.encryptJson`
(`security/encryption_service.dart:109`) recurses into nested maps and lists, encrypting only keys matching
this exact list — sibling fields in the same payload stay plain text. Note `pan_number` has an inline
code comment "this is for testing" (`config/app_config.dart:80`) — verify with the backend team whether it's
still a live field name before removing it.

## RULE-CORE-003: 401 triggers a silent, deduplicated token refresh; 409 triggers an immediate, undismissable force-logout
- **401**: `ApiSecurityInterceptor.onError` (`security/api_interceptor.dart:290`) attempts exactly one
  `POST users/auth/token/refresh` per refresh window, using a static `Completer<bool>` lock so N concurrent
  401s share one refresh call and each retries with the resulting token. A refresh within the last 30
  seconds is skipped in favor of retrying with the already-current token (`:336`). If the refresh endpoint
  itself returns 200 with no access token, or fails, or throws — full logout (`SessionManager.logout()`).
- **409**: checked *before* 401 in the same `onError` (`:214`, comment at `:212` explains the ordering is
  deliberate) and never attempts a refresh. `SessionManager.forceLogout()` is deduplicated (only the first
  concurrent 409 shows the dialog, `session_manager.dart:32-37`) and sets a persistent
  `isForceLoggedOut` flag that the *request* interceptor checks on every subsequent call
  (`security/api_interceptor.dart:103`) — blocking them before any network I/O until a fresh login resets the
  flag (`SessionManager.resetForceLogout()`, called from `AuthService.verifyOtp:75`). **Never** treat a 409 as
  a normal error to catch-and-retry — `error/failures.dart`'s `SessionInvalidatedFailure` exists specifically
  so callers can swallow it without showing a duplicate error UI on top of the interceptor's own dialog.
- A refreshed token can still carry an already-invalidated `session_id` (the refresh endpoint doesn't check
  session validity) — every retry path after a successful refresh re-checks for 409 and routes to the same
  force-logout dialog instead of surfacing a confusing 401/generic error (`:322,356,438`).

## RULE-CORE-004: Client-side response decryption does not exist — despite the code path implying it does
`ApiSecurityInterceptor.onResponse` (`security/api_interceptor.dart:189`) runs `EncryptionService.decryptJson`
on every response from an `encryptedEndpoints` path and logs `"Response decrypted (AES-256)"` (`:200`), but
`EncryptionService.decrypt` (`security/encryption_service.dart:101`) is a literal pass-through: `return
encryptedText;` with the comment "Server responses are not encrypted in the current architecture." Treat any
future backend change toward encrypted response fields as requiring new client work, not something already
wired up — the current log message is misleading.

## RULE-CORE-005: RSA public key is fetched once, cached in secure storage, and never expires client-side
`EncryptionService` (`security/encryption_service.dart`) has no key-rotation or TTL logic. On cold start,
`ApiClient._internal()` fires `ApiSecurityInterceptor.fetchAndCachePublicKey()` (`network/api_client.dart:33`,
fire-and-forget). That method first tries the secure-storage cache (`EncryptionService.loadPublicKey`,
`:23`); only on a cache miss does it call `GET crypto/public-key` over a separate cert-pinned Dio instance
(`:48-61`). Once `isRsaReady` is true, it stays true for the life of the process — there is no code path that
re-fetches a rotated server key without an app restart or a call to `EncryptionService.clearKey()`
(`:60`, itself not observed as called anywhere in this pass). If the backend rotates its RSA key pair, already
-running app instances will keep encrypting with the stale public key until restarted.

## RULE-CORE-006: Rate-lock timer holds a snapshotted rate for a server-configured duration; it does not independently detect market closure
`RateTimerNotifier.startOrRefresh(durationSeconds)` (`providers/timer_provider.dart:41`) locks whatever
`marketRatesStreamProvider` last emitted and counts down `durationSeconds` (caller-supplied — this module
does not hardcode the duration; per AGENTS.md §2, do not invent a specific number without a config
citation, and none was found in `core/` — the duration is passed in by the calling screen). On expiry it
calls `_refreshAndRestart()` → `startOrRefresh` again with the same duration, re-locking whatever rate is
current at that moment. A large removed-code comment (`:81-103`) documents that an earlier
timestamp-comparison approach for detecting "market closed" was deliberately deleted because it produced a
visible UI "shake" false-positive when the socket went quiet while the market was still open. Market
open/closed state is sourced exclusively from `marketStatusProvider` (the socket's explicit `5|...` frames,
see DATA_FLOW #5) — never re-add timestamp-based closure inference to this notifier.

## RULE-CORE-007: Root/jailbreak detection blocks the entire app before it renders, with no bypass path
`RootDetectionService.isDeviceCompromised()` (`security/root_detection_service.dart:13`) runs once in
`main()` before `runApp` (`main.dart:34-48`). If it returns true, `runApp` is called with
`CompromisedDeviceScreen` as the sole `MaterialApp.home` and `main()` returns immediately — the normal
`ProviderScope`/`MyApp` tree is never constructed. Detection uses 7 independent layers on Android (package
check, su-binary paths, Magisk artifacts, Frida `/proc/self/maps` scan, Xposed/LSPosed scan, root-package
directories, `which su` process execution) and 7 on iOS (package check, jailbreak file/dir paths, sandbox
write-escape test, Frida port 27042 probe, Cycript port 8556 probe, `DYLD_INSERT_LIBRARIES`/`_MSSafeMode` env
vars, symlink-target checks) — any single positive layer is sufficient to block. Any exception during a
layer's check is swallowed and treated as "not detected by that layer" (fail-open per-layer, but the overall
7-layer OR means one clean layer among many hooked ones can still catch it).

## RULE-CORE-008: KYC-required errors are a distinct failure type, detected by `error.code == 'KYC_REQUIRED'` ahead of generic 401/403 handling
`ApiFailureMapper.map` (`error/failures.dart:91-98`) extracts `errorCode` from the response body before
checking status code, so a `KYC_REQUIRED` code wins even on an HTTP 403 that would otherwise map to
`AuthenticationFailure`. Per the class doc comment (`:39-46`), today this is only observed on SIP-create and
withdrawal-initiate; any endpoint that starts returning the same code is covered automatically since the
check is code-based, not path-based. Confirmed consumers: `features/withdrawal/screens/withdrawal_screen.dart`,
`features/sip/screens/auto_savings_screen.dart`, `features/kyc/screens/kyc_screen.dart`,
`features/instant_saving/instant_saving_screen.dart`, `features/kyc/kyc_flow.dart`.

## RULE-CORE-009: Logout preserves device identity and onboarding state; it does not wipe everything
`SecureStorageService.logout()` (`security/secure_storage_service.dart:117-141`) explicitly preserves
`persistent_device_id`, `persistent_device_type` (both owned by `DeviceIdService`), and
`AppConfig.keyHasSeenOnboarding` across a `deleteAll()` + restore. Rationale in the code comment: wiping the
device ID would make the next login look like a brand-new device to the backend, which triggers spurious 409
`SESSION_INVALIDATED` errors on the user's *other* logged-in devices. Do not "simplify" this to a bare
`deleteAll()`.

## RULE-CORE-010: Maintenance/alert gating is polled globally but re-checked fresh before any critical action
`AppControlNotifier` (`providers/app_control_provider.dart`) polls `POST app/control` every 1 minute normally
(`_kAlertPollInterval`, `:13`) and every 30 seconds while maintenance is active (`_kMaintenancePollInterval`,
`:14`, started via `startMaintenancePolling`). Separately, `checkBeforeAction()` (`:232`) performs an
uncached, synchronous-to-the-caller fetch specifically meant to be awaited immediately before a
payment/withdrawal/SIP-create action, so a maintenance window that started in the last few seconds still
blocks the action rather than waiting for the next poll tick. On network failure, `checkBeforeAction` fails
open (`MaintenanceGateResult.clear`, `:236-238,280-283`) — client-side connectivity issues never block a
transaction on their own.

## RULE-CORE-011: Screenshot/recording protection is a runtime-toggleable global flag, not a per-screen opt-in list
`AppConfig.enableScreenshotProtection` (`config/app_config.dart:39`) starts `false` and is flipped by
`AppControlNotifier._fetch()` whenever the `app/control` response's `data.security.enable_screenshot_protection`
boolean differs from the current value (`providers/app_control_provider.dart:130-138`), immediately calling
`ScreenshotSecurityService.initialize()` to apply/remove `FLAG_SECURE` (Android) or the blur overlay (iOS)
app-wide. Individual screens (`otp_screen.dart`, `mpin_screen.dart` confirmed via grep) additionally call
`secureScreen()`/`releaseScreen()` in `initState`/`dispose` — but both are no-ops if the global flag is off
(`screenshot_security_service.dart:43,56`). `releaseScreen()` deliberately never calls
`preventScreenshotOff()` — only `protectDataLeakageWithBlurOff()` — because doing so on Android would remove
`FLAG_SECURE`, making content visible in the recent-apps switcher (`:59-61`).

## RULE-CORE-012: Withdrawal weight limits are hardcoded client-side constants, not server config
`AppConstants.minWithdrawalGrams = 0.001`, `maxWithdrawalGrams = 100.0`, `amountDecimalLimit = 4`
(`constants/app_constants.dart:64-66`) — unlike GST/tax/denomination values (which AGENTS.md §2 confirms are
server-driven via `savings/config`/`savings/denominations/*`), these withdrawal bounds live as static Dart
constants in `core/`. Per AGENTS.md §2, treat this as tech debt to flag if touched, not a pattern to copy —
verify against the actual server-side withdrawal validation contract before relying on these as authoritative.
