---
module: core/
last_updated: 2026-08-19
---

# Core — Forensic Template

Symptom → check first → likely suspects, for bugs whose root cause is plausibly in `core/`.

## 1. "User gets logged out randomly / session invalidated dialog appears with no obvious cause"

**Check first**: reproduce with `SecureLogger` debug output visible (`kDebugMode` build) and look for
`SESSION INVALIDATED: 409 Conflict` lines in `security/api_interceptor.dart`'s `onError`. Also check whether
the user has the app open on a second device — RULE-CORE-009 notes 409 is the backend's concurrent-session
signal.

**Likely suspects**:
- Genuine concurrent login elsewhere (working as designed — `session_manager.dart:32`, `api_interceptor.dart:214`).
- `SecureStorageService.logout()`'s preserved-key list (`persistent_device_id`) got out of sync with the
  server's device registration somehow, making the server think it's a new device each launch → spurious
  409s (RULE-CORE-009's whole reason for existing).
- A refreshed token retry coming back 409 (`api_interceptor.dart:322,356,438`) — the *original* 401 was
  legitimate token expiry, but the refreshed token still carried an already-invalidated `session_id`. Check
  logs for `TOKEN REFRESH: Success` immediately followed by a second 409 log line.
- `_refreshLock` Completer bug: if a future edit ever calls `.complete()` twice on the same Completer (the
  code has an explicit comment at `api_interceptor.dart:420-423` warning against this), the app would hang,
  not force-logout — different symptom, but check this code path if refresh-related hangs are also reported.

## 2. "Encrypted field rejected by server / login-register/OTP/KYC/payment call fails with a validation error the UI can't explain"

**Check first**: confirm the failing endpoint's path is actually in `AppConfig.encryptedEndpoints`
(`config/app_config.dart:47`) — if it's NOT in that list, the "sensitive" fields are being sent as **plain
text**, which could itself be the validation failure if the backend expects ciphertext. If it IS in the
list, confirm the specific field name is spelled exactly as the backend expects inside
`AppConfig.sensitiveFields` (`:74`) — a field encrypted under the wrong key name will silently pass through
unencrypted (`EncryptionService.encryptJson` only touches keys it recognizes) while the backend rejects it as
plaintext where ciphertext was expected, or vice versa.

**Likely suspects**:
- RSA public key not ready yet when the request fired: check for `ENCRYPTION: RSA key not available. Cannot
  encrypt sensitive data.` in logs — `EncryptionService.encrypt` throws `StateError` in that case
  (`:75`), and `onRequest`'s try/catch around encryption (`api_interceptor.dart:178-180`) just logs
  `ENCRYPTION ERROR` and lets the **unencrypted** request through via `handler.next(options)` — i.e. a
  missing key does not block the request, it silently sends plaintext for a field the server expects
  encrypted.
- Stale cached public key: if the backend rotated its RSA key pair, this client has no rotation logic
  (RULE-CORE-005) — every encrypted request will fail server-side decryption until the app restarts or
  `EncryptionService.clearKey()` is invoked and the key re-fetched.
- Field genuinely present in the request payload but nested one level deeper/shallower than
  `encryptJson`'s recursion expects it — re-check the exact payload shape being sent for that specific
  endpoint against what `encryptJson` (`security/encryption_service.dart:109`) actually walks (top-level map,
  nested maps, and lists-of-maps — not e.g. a map nested inside a list nested inside another list, if such a
  shape exists).

## 3. "Live gold/silver rates stop updating / stuck on a stale value"

**Check first**: check `socketStatusProvider` in the running app (or logs for `NativeSocket:` lines) — is
the socket `connected`, `disconnected`, or cycling `error`→reconnect? Also check whether
`marketStatusProvider` shows the commodity as closed (expected — not a bug — outside market hours).

**Likely suspects**:
- App was backgrounded: `AppLifecycleObserver` explicitly disconnects the socket on `paused`
  (`app_lifecycle_observer.dart:62`) — if `resumed` didn't fire correctly (rare Flutter lifecycle edge case)
  the socket stays disconnected. Check whether `connect()` log line appears on the resume in question.
- Reconnect loop with a fixed 5-second delay (`native_socket_service.dart:125`, NOT exponential backoff
  despite `_OVERVIEW/SYSTEM_ARCHITECTURE.md`'s claim — see MODULE_BRAIN Known Gaps #4) — if the WS endpoint
  is unreachable, this retries forever every 5s without ever giving up or surfacing a persistent error state
  beyond `SocketStatus.error`.
- `_handleRateUpdate`'s `isSignificantChange` gate (`market_rates.dart:177`, not read in full this pass) may
  be suppressing emissions the UI expected to see — check the actual threshold if rates look "frozen" while
  the socket is confirmed connected and receiving frames.
- `commoditiesProvider` (backend `id_metal` lookup) failed or is still loading, so `updateCommodityConfig`
  never ran with real IDs — the socket may be filtering frames against the wrong hardcoded fallback IDs
  ('1'/'3') if the real backend IDs differ.
- Grace-period false-negative: if the market is genuinely open but the server is slow to send the first
  `5|...` status frame, `_inferClosedAfterGracePeriod` (`:223`) marks it closed after 1 second — check
  whether this fired before the real status frame arrived (race condition between the 1s timer and network
  latency).

## 4. "Rate-lock timer flickers / restarts unexpectedly / shows wrong remaining seconds"

**Check first**: is this happening exactly at a timer expiry boundary? The code has a documented historical
bug (`timer_provider.dart:81-103` comment) about a false-positive "market closed" shake at exactly this
moment — if it's back, something re-introduced timestamp-based closure inference into
`RateTimerNotifier._refreshAndRestart`.

**Likely suspects**:
- A new edit added back a `latestRate.timestamp` vs. timer-start comparison — explicitly forbidden by the
  in-code postmortem comment. Market-closed state must only come from `marketStatusProvider`.
- App resumed from background mid-countdown: `didChangeAppLifecycleState` recalculates on resume
  (`:34-38`) using wall-clock `_targetEndTime`, which is correct behavior — but if the *screen* is also
  independently calling `startOrRefresh` on its own resume/rebuild, the two triggers could race.
- Two different timer providers (`sellRateTimerProvider` vs `buyRateTimerProvider`) accidentally being read
  from the same screen when only one should apply to the current buy/sell context.

## 5. "App-lock (MPIN/biometric) doesn't trigger after backgrounding, or triggers when it shouldn't (e.g. during a payment flow)"

**Check first**: check `AppLifecycleObserver.suppressAppLock` — was it set `true` before a payment SDK
launch and is there a code path (early return, exception before the `finally`) where it never gets reset to
`false`? Per AGENTS.md §3 this suppression is intentional and must not be "fixed" by removal — the bug, if
any, is in a flow that sets it but fails to clear it.

**Likely suspects**:
- `suppressAppLock` stuck `true` from a previous payment flow that errored out without resetting it —
  every subsequent resume will skip app-lock silently, a real security regression (MPIN never re-prompts).
- Cached values from `_preCacheSecurityState()` are stale/wrong because the six-guard check in
  `_checkAppLockOnResume()` (`:105-166`) is entirely synchronous and pre-cached at `paused` time — if MPIN
  was disabled *while the app was in the background* (shouldn't be possible via this app, but check any
  server-driven force-disable path), the cached `true` would still trigger a lock screen incorrectly, or
  vice versa.
- Currently on `AppRouter.mpin`/`login`/`splash`/`onboarding`/`otp`/`registration*` — the guard list at
  `:148-156` intentionally skips app-lock on these routes; verify the actual current route name matches one
  of these constants exactly (a renamed route constant elsewhere would silently break this skip-list).

## 6. "Root-detection false positive — a legitimate, non-rooted device gets the CompromisedDeviceScreen"

**Check first**: which of the 7 (Android) / 7 (iOS) layers in `RootDetectionService` fired? Add temporary
logging per-layer (none of the 7+7 checks currently log which specific layer matched — only the final
boolean is used by `main.dart:37`) to isolate it, since `isDeviceCompromised()` has no bypass/allowlist.

**Likely suspects**:
- Android Layer 7 (`Process.run('which', ['su'])`, `:103`) — some non-rooted OEM Android builds/emulators
  ship a `which` binary that returns unexpected output, or a custom ROM has a harmless `su` stub.
- iOS Layer 3 (sandbox write-escape test to `/private/jailbreak_test_*`, `:176-183`) — this creates and
  deletes a real file; if it fails for a reason *other* than sandbox restriction (e.g. transient disk-full,
  simulator quirk) the catch-all swallows it as "not detected," so this one is unlikely to false-positive,
  but worth checking simulator/CI builds specifically since simulators are not truly sandboxed the same way.
- iOS Layer 6 (`DYLD_INSERT_LIBRARIES` env var, `:207-209`) — some legitimate debugging/profiling tools
  (including Xcode's own instrumentation in certain configurations) set this variable; a QA device running
  under a profiler could false-positive.
- Since detection is a 7-layer OR with no per-layer confidence weighting, there's no way today to
  distinguish "one weak signal fired" from "five strong signals fired" — this is a genuine design tradeoff
  (favors false-positive over false-negative), not a bug, but worth knowing when triaging a user report of
  being blocked.
