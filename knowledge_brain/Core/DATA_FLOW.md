---
module: core/
last_updated: 2026-08-19
---

# Core — Data Flow

Five end-to-end flows, traced through actual code with file:line references.

## 1. Encrypted API Call Lifecycle (e.g. `savings/initiate`, `mpin/create`)

```
Feature screen/controller
  → core/services/<X>Service.method()          e.g. MpinService.setMpin (services/mpin_service.dart:13)
    → ApiClient().post(path, data: {...})       network/api_client.dart:53
      → Dio.post → interceptor chain: ApiSecurityInterceptor.onRequest  security/api_interceptor.dart:93
```

Inside `onRequest`:
1. **Force-logout gate** (`:103`) — if `SessionManager.isForceLoggedOut`, reject immediately with
   `DioExceptionType.cancel`, no network I/O.
2. **Offline check** (`:117`) — `Connectivity().checkConnectivity()`; reject with
   `DioExceptionType.connectionError` if none.
3. **RSA key readiness** (`:133`) — path checked against `AppConfig.encryptedEndpoints`
   (`config/app_config.dart:47`); if sensitive and `EncryptionService.isRsaReady` is false, a blocking
   `fetchAndCachePublicKey()` call runs first (`:38` — tries secure-storage cache via
   `EncryptionService.loadPublicKey`, then `GET crypto/public-key` over a **separate, cert-pinned** plain
   `Dio` instance built inline, `:48-61`).
4. **Bearer token attach** (`:141-163`) — skipped only for the explicit `unauthenticatedEndpoints` allowlist
   (`:144`), not a `path.contains('auth')` heuristic (deliberately, per the code comment — `auth/has-mpin`
   and `users/auth/referral/details` need the token despite containing "auth").
5. **Field encryption** (`:166-182`) — only if `isSensitive`; `EncryptionService.encryptJson` recurses the
   request map and RSA-OAEP-SHA256-encrypts any key in `AppConfig.sensitiveFields`
   (`config/app_config.dart:74`), leaving all other keys as plain text in the same payload.

Request proceeds through `CertificatePinning.setup(_dio)` (applied once at `ApiClient._internal()`,
`network/api_client.dart:29`) → HTTPS.

On success, `onResponse` (`security/api_interceptor.dart:189`) runs `decryptJson` on the body if the path is
in `encryptedEndpoints` — but `EncryptionService.decrypt` (`:101`) is a no-op passthrough, so this step does
not actually decrypt anything today (see BUSINESS_RULES RULE-CORE-004).

On failure, control passes to `onError` (`:208`) — see flows 2 and 3 below. If no error, the response
percolates back to `ApiClient.post`, which returns the raw `Response`; the service layer parses
`response.data['data']` and the caller gets a domain object or throws.

## 2. 401 → Silent Token Refresh

Entry: `ApiSecurityInterceptor.onError`, `:290-488`.

```
err.response.statusCode == 401
  ├─ SessionManager.isForceLoggedOut? → pass through (handler.next), no refresh attempted   :292
  ├─ _refreshLock already set (another 401 mid-refresh)?
  │     → await the same Completer<bool>                                                     :297-333
  │     → on success: build a fresh Dio, CertificatePinning.setup, retry original request
  │     → retry itself returns 409? → rejectAsSessionInvalidated (see flow 3)                :322
  ├─ refreshed within last 30s (_lastRefreshTime)?
  │     → skip a second refresh call, just retry with current token                          :336-364
  └─ else: first 401 in this window
        _refreshLock = Completer<bool>()                                                     :367
        POST users/auth/token/refresh { refresh: <refreshToken> }  (own cert-pinned Dio)      :389
        200 + access_token present:
          SecureStorageService.saveToken/saveRefreshToken                                     :409-411
          _lastRefreshTime = now; _refreshLock.complete(true); _refreshLock = null            :413-425
          retry original request with new Authorization header                                :427-444
            → 409 on retry? → rejectAsSessionInvalidated (refreshed token still carries an
              already-invalidated session_id — refresh endpoint doesn't check session validity) :438
        200 but no access_token / non-200 / DioException:
          _refreshLock.complete(false); _refreshLock = null; SessionManager.logout()          :449-486
```

Caller-side: `ApiClient.get/post` catches the eventual `DioException` and maps it via
`ApiFailureMapper.map` (`error/failures.dart:52`) → `AuthenticationFailure` if it still comes back
401/403 after the refresh attempt is exhausted.

## 3. 409 Session-Invalidated → Force Logout

Entry: `ApiSecurityInterceptor.onError`, `:214-259`, checked **before** the 401 branch (comment at `:212`
explains why: a stale-but-not-yet-refreshed token must not trigger a refresh attempt on top of an already
force-invalidated session).

```
err.response.statusCode == 409
  → accept explicit codes (error.code / code == "session_invalidated"/"SESSION_INVALIDATED")
    OR a bare 409 with no structured body (fail-closed default)                                :218-225
  → SessionManager.forceLogout()                                                                :237
      _isForceLoggedOut = true (was already true? → return false, dedup)                        session_manager.dart:32-37
      SecureStorageService.logout() — wipes all keys except persistent_device_id/
        persistent_device_type/hasSeenOnboarding                                                secure_storage_service.dart:117-141
  → isFirstTrigger == true → WidgetsBinding.addPostFrameCallback(SessionInvalidatedDialog.show)  :243
  → handler.reject(DioException(..., type: cancel))  — NOT handler.next(); no retry               :250
```

Any concurrent in-flight request that also gets 409 hits the same branch; `forceLogout()`'s dedup means only
the *first* one shows the dialog. From this point, `ApiSecurityInterceptor.onRequest`'s force-logout gate
(flow 1, step 1) blocks every subsequent request with zero network I/O until a fresh login calls
`SessionManager.resetForceLogout()` (`services/auth_service.dart:75`, inside `AuthService.verifyOtp`).

Downstream, `ApiClient.get/post`'s catch maps the `cancel`-type exception with the "Session invalidated"
string to `SessionInvalidatedFailure` (`error/failures.dart:65`) so callers can swallow it silently instead
of showing a duplicate error toast on top of the dialog — see e.g. `MpinNotifier.verifyMpin`'s explicit
`on SessionInvalidatedFailure catch` (`services/mpin_service.dart:264`).

## 4. Session/App-Lock Validation on App Resume

Entry: `AppLifecycleObserver.didChangeAppLifecycleState`, `security/app_lifecycle_observer.dart:50`.

```
AppLifecycleState.paused
  _pausedAt = DateTime.now()                                                                     :53
  _preCacheSecurityState() — async, invisible while backgrounding:
    _cachedIsAuth = SessionManager.isAuthenticated()                                              :81
    _cachedMpinEnabled = SecureStorageService.isMpinEnabled()                                     :82
    _cachedBiometricEnabled = BiometricService.canUseBiometric()                                  :83
  ref.read(socketIOServiceProvider).disconnect()  — pause the live-rate socket                    :62

AppLifecycleState.resumed
  ClipboardSecurityService.clearClipboard()  — VAPT clipboard-leakage mitigation                  :67
  ref.read(socketIOServiceProvider).connect()  — resume the socket                                :70
  _checkAppLockOnResume():                                                                        :105
    guard: _isLockScreenShowing → return (no stacking)                                            :107
    guard: suppressAppLock → return (payment-SDK flow in progress)                                :108
    guard: SessionManager.isForceLoggedOut → return (409 dialog takes priority)                   :114
    guard: !_cachedIsAuth → return (not logged in, cached from pause)                              :117
    guard: !_cachedMpinEnabled → return (MPIN not enabled, cached)                                :120
    guard: _pausedAt == null → return (cold start, never actually paused)                         :123
    guard: currentRoute already mpin/login/splash/onboarding/otp/registration* → return            :141-156
    → _cachedBiometricEnabled? _tryBiometricThenMpin(nav) : _pushMpinLockScreen(nav)               :159-165
        biometric success → unlocked instantly                                                     :176
        biometric failure/cancel → _pushMpinLockScreen(nav) fallback                                :186
        _pushMpinLockScreen: Future.microtask → nav.pushNamed(AppRouter.mpin,
          arguments: {'type': 'app_lock'})                                                         :193-209
```

All six guards are evaluated synchronously against pre-cached values — the only async work on the resume
hot path is the biometric OS prompt itself, by design (doc comment at `:92-96`).

## 5. Live Rate Socket Connection Lifecycle

Entry: `marketRatesStreamProvider`, `providers/market_provider.dart:16`, first watched by any screen (e.g.
home dashboard, withdrawal, instant saving).

```
ref.watch(marketRatesStreamProvider)
  → socketIOServiceProvider creates/reuses NativeSocketService singleton per-provider-scope             :8-13
  → watches commoditiesProvider (GET users/shared/commodities) for real gold/silver id_metal values      :20-41
    → service.updateCommodityConfig(goldId, goldName, silverId, silverName)  native_socket_service.dart:56
  → service.connect()                                                                                     :44
      WebSocketChannel.connect(Uri.parse(EnvironmentService.wsUrl), protocols: [<fixed proto string>])   :80-82
      await _channel.ready → SocketStatus.connected                                                       :86-88
      _channel.stream.listen(_handleRateUpdate, onError → reconnect, onDone → reconnect)                  :91-104
      1s grace-period timer: if no explicit "5|" status frame arrives, infer CLOSED from zero rates        :108-111,223-253
  → _handleRateUpdate(rawData) per message, split on '\n', each line split on '|':                        :130-211
      parts[0] == '5' → market-status frame: 5|commodity_id|commodity_name|status(0/1)                    :148
        status change → update _commodityOpenStatus map, emit on marketStatusController
        commodity just closed → zero out only that commodity's rates (other metal's rates preserved)      :162-183
      parts[0] == '3' → rate frame, parsed by MarketRates.fromRawString                                   :195-207
        (format: 3|id|name|buy|sell|... — see features/market/models/market_rates.dart:61)
        emitted only if MarketRates.isSignificantChange(previous) is true                                 :204
  → ratesStream replays the last known rate to new subscribers immediately (async* yield _lastRate)        :22-27
```

Disconnect path: `AppLifecycleObserver` calls `.disconnect()` on `paused` (flow 4) — cancels reconnect/grace
timers, closes the channel, emits `SocketStatus.disconnected`. Reconnect: any `onError`/`onDone` from the
channel schedules a 5-second `_scheduleReconnect` retry (`:119-128`) — a fixed delay, not exponential
backoff (contradicts `_OVERVIEW/SYSTEM_ARCHITECTURE.md`'s "exponential-backoff retry" claim — flag as drift).
`socketIOServiceProvider`'s `ref.onDispose` calls `.dispose()` (`:11`), which also closes all three
`StreamController`s.

Downstream consumer: `providers/timer_provider.dart`'s `RateTimerNotifier.startOrRefresh` reads
`ref.read(marketRatesStreamProvider).valueOrNull` (`:46`) to lock a rate for the configured countdown window
— see BUSINESS_RULES RULE-CORE-006 for the rate-lock contract and why market-closed detection was
deliberately removed from the timer's own logic (code comment at `timer_provider.dart:81-103`).
