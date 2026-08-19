---
module: core/
last_updated: 2026-08-19
---

# Core — State Analysis

## Riverpod Providers (17 provider *files*, 30 distinct exported providers)

### `appControlProvider` — `providers/app_control_provider.dart`
- **Shape**: `AppControlState { AppControlData? data, bool isLoading, bool updateRequired, bool forceUpdate,
  bool showAlert, bool isMaintenance, String currentVersion }`. `AppControlData` wraps
  `AppVersionInfo?` (per-platform version+store-URL+force-update text), `AppAlert?` (banner: title/message/
  type/actionUrl), `MaintenanceInfo` (isEnabled/title/subtitle/expectedResume), `responsePlatform`,
  `dynamicSwitching`/`dynamicSwitchingPassword`.
- **Invalidation**: not `autoDispose` — lives for app session. Refreshed by `Timer.periodic` every 1 minute
  (`_kAlertPollInterval`) or every 30s while `isMaintenance` (`_kMaintenancePollInterval`, started/stopped
  explicitly). Also force-refreshed synchronously by `checkBeforeAction()` before critical transactions.
  Depends on `environmentProvider` (`ref.watch`, `:314,321`) — an environment switch tears down and rebuilds
  this provider (and its underlying `AppControlService`).

### `commodityProvider` / `selectedMetalIdProvider` — `providers/commodity_provider.dart`
- **Shape**: `CommodityType` enum (`gold`/`silver`) for `commodityProvider`; `selectedMetalIdProvider` derives
  the real backend `id_metal` string by matching `commoditiesProvider`'s fetched list against the selected
  type's name, falling back to hardcoded `'1'`/`'3'` only while that list is still loading.
- **Invalidation**: `commodityProvider` changes only via explicit `setCommodity()` calls (UI toggle).
  `selectedMetalIdProvider` recomputes whenever `commodityProvider` or `commoditiesProvider` changes.

### `connectivityProvider` — `providers/connectivity_provider.dart`
- **Shape**: `ConnectivityState { ConnectivityStatus status (online/offline/slow), bool isChecking }`.
- **Invalidation**: live-updates via `Connectivity().onConnectivityChanged` stream subscription (started in
  constructor); manual `recheck()` also available. Note: `ConnectivityStatus.slow` exists in the enum but no
  code path in this file ever sets it — always resolves to `online`/`offline` only.

### `countdownOfferProvider` — `providers/countdown_offer_provider.dart`
- **Shape**: `AsyncValue<CountdownOfferResponse>` (model defined in `features/home/models/countdown_offer_model.dart`
  — not read this pass in full, only its usage contract: `.disabled()` factory, `enabled`, `customerType`,
  `newOffer`/`existingOffer`).
- **Invalidation**: `autoDispose` `FutureProvider` — watches `userProvider`; returns `.disabled()` immediately
  (no API call) for `null`/empty-id users, otherwise fetches fresh on every re-watch (login/logout,
  navigation away-and-back since it's `autoDispose`).

### `environmentProvider` — `providers/environment_provider.dart`
- **Shape**: bare `StateProvider<String>`, seeded from `EnvironmentService.currentEnv` ('staging'/'production').
- **Invalidation**: only via direct `ref.read(environmentProvider.notifier).state = ...` (not observed as
  called from `core/` itself — presumably a dev/settings environment-switcher UI in `features/auth` per
  `login_screen.dart` import).

### `homeDashboardProvider` — `providers/home_dashboard_provider.dart`
- **Shape**: `AsyncValue<HomeDashboard?>` (model in `features/home/models/home_dashboard.dart`, not read in
  full this pass).
- **Invalidation**: plain `FutureProvider` (not autoDispose) — watches `userProvider` (returns `null`
  immediately on logout, no 401 call) and `selectedMetalIdProvider` (re-fetches on gold/silver switch).

### `socketIOServiceProvider` / `marketRatesStreamProvider` / `socketStatusProvider` / `marketStatusProvider` — `providers/market_provider.dart`
- **Shape**: `NativeSocketService` singleton per provider-container scope; `MarketRates` stream (gold/silver
  buy/sell/change/percentage + timestamp); `SocketStatus` enum (connecting/connected/disconnected/error);
  `Map<String,bool>` per-commodity open/closed status.
- **Invalidation**: `socketIOServiceProvider` watches `environmentProvider` — an environment switch tears down
  and recreates the socket service (`ref.onDispose` calls `.dispose()`). `marketRatesStreamProvider` is
  re-derived (commodity IDs updated, `connect()` called) whenever `commoditiesProvider` resolves/changes.

### `portfolioProvider` — `providers/portfolio_provider.dart`
- **Shape**: `AsyncValue<PortfolioData>`, `PortfolioData { CommodityPortfolio summary, bool isNewCustomer }`,
  `CommodityPortfolio { totalInvested, currentValue, returns, returnsPercentage, balance (grams),
  hasActiveAccount }`.
- **Invalidation**: `autoDispose` `StateNotifierProvider`, keyed implicitly by `(idMetal, idCustomer)` since
  those are read via `ref.watch(selectedMetalIdProvider)`/`ref.watch(userProvider)` inside the provider
  builder. A **module-level in-memory cache** (`_portfolioCache`, keyed by `idMetal`, `:97`) survives
  provider disposal/recreation specifically to prevent a loading-skeleton flicker when toggling Gold↔Silver
  tabs — this cache is NOT cleared on logout (a stale previous user's portfolio numbers could theoretically
  flash before the fresh fetch resolves on a different account on the same device session; verify if this
  matters for the product's multi-account-on-one-device scenario).

### `sellRateTimerProvider` / `buyRateTimerProvider` — `providers/timer_provider.dart`
- **Shape**: `TimerState { int remainingSeconds, MarketRates? lockedRates, bool isMarketClosed }`,
  `isActive` getter = `remainingSeconds > 0 && lockedRates != null && !isMarketClosed`.
- **Invalidation**: not autoDispose; each is an independent `RateTimerNotifier` instance (two separate
  timers for buy vs sell flows). State changes only via explicit `startOrRefresh(duration)` / `clear()` calls
  from the withdrawal/instant-saving screens, plus automatic re-evaluation on `AppLifecycleState.resumed`
  (`didChangeAppLifecycleState`, mixed in via `WidgetsBindingObserver`).

### `userProvider` — `providers/user_provider.dart`
- **Shape**: `UserProfile { id, name, mobile, email, photoUrl?, isNewUser, mpinEnabled, isKycVerified,
  isVip }`. **Note**: `isKycVerified` and `isVip` are declared fields with `false` defaults but nothing in
  this file's `fromJson`-equivalent mapping (`:32-53`) ever sets them from the API response — they are
  effectively always `false` from this provider (verify whether some other code path overwrites them, or
  whether they're dead fields).
- **Invalidation**: plain `Provider` (not a notifier) — recomputes reactively whenever
  `authControllerProvider`'s state changes (login/logout/registration). Returns `null` when no session data
  exists.

### `languageProvider` — `localization/language_provider.dart`
- **Shape**: `LanguageState { currentLocale (default 'en'), translations (empty map today), isLoading }`.
- **Invalidation**: `setLanguage()` persists to `SharedPreferences` (note: NOT secure storage — acceptable
  per AGENTS.md §3, language is a "pure UI pref"). `_init()` currently hardcodes `currentLocale: 'en'` on
  every app start regardless of any previously saved locale — the persisted `selected_locale` key is written
  by `setLanguage()` but never read back on init (dead read path — `LanguageCache.getLocale()` exists but
  nothing calls it).

## Secure-Storage Keys (all via `flutter_secure_storage`, `security/secure_storage_service.dart` unless noted)

| Key (constant) | Value | Written by | Read by | Survives `logout()`? |
|---|---|---|---|---|
| `access_token` (`keyAccessToken`) | JWT-style bearer token | `AuthService.verifyOtp/.register`, token-refresh path | `ApiSecurityInterceptor.onRequest`, retry paths | No |
| `refresh_token` (`keyRefreshToken`) | refresh token | same | `ApiSecurityInterceptor.onError` (401 refresh) | No |
| `mobile_number` (`keyMobileNumber`) | last logged-in mobile | `AuthService.verifyOtp` | `AuthNotifier.rehydrateFromStorage`, `NavigationUtils` fallback logic (indirectly via `SessionManager`) | No |
| `is_mpin_enabled` (`keyIsMpinEnabled`) | `'true'`/`'false'` string | `AuthService.verifyOtp`, MPIN-setup flow | `AppLifecycleObserver._preCacheSecurityState`, `NavigationUtils` | No |
| `is_biometric_enabled` (`keyIsBiometricEnabled`) | `'true'`/`'false'` string | Settings biometric toggle | `BiometricService.canUseBiometric` (self-heals to `false` if device biometric was removed) | No |
| `customer_id` (`keyCustomerId`) | numeric customer ID (string) | `AuthService.verifyOtp/.register` | `AuthNotifier.rehydrateFromStorage`, `portfolioProvider` (via `userProvider.id`) | No |
| `customer_name` (`keyCustomerName`) | display name | same | `AuthNotifier.rehydrateFromStorage` | No |
| `customer_photo` (`keyCustomerPhoto`) | photo URL | `AuthService.verifyOtp` | `AuthNotifier.rehydrateFromStorage` | No |
| `server_public_key` (`keyServerPublicKey`) | cached RSA PEM | `EncryptionService.setPublicKeyFromServer` | `EncryptionService.loadPublicKey` (startup) | No |
| `fcm_token` (`keyFcmToken`) | last-registered FCM device token | `NotificationService.registerFcmToken` | same (dedup check before re-registering) | No |
| `hasSeenOnboarding` (`keyHasSeenOnboarding`) | `'true'`/`'false'` string | `SessionManager.setOnboardingSeen` | `SessionManager.hasSeenOnboarding` | **Yes** (explicit preserve list) |
| `persistent_device_id` | UUID or hardware ID | `DeviceIdService.getDeviceId` (first call) | `AuthService.sendOtp/.register`, `NotificationService.registerFcmToken` | **Yes** (explicit preserve list — prevents spurious 409s on other devices) |
| `persistent_device_type` | `'android'`/`'ios'`/`'web'`/`'other'` | `DeviceIdService.getDeviceType` | same | **Yes** |
| `ssl_cert_pins` | JSON-encoded pin array | `CertificatePinning.updatePins` (server-pushed) | `CertificatePinning.init` (startup cache load) | Not cleared by `SecureStorageService.logout()` — only by `CertificatePinning.clearCache()`, which is documented for logout but not confirmed as actually called anywhere this pass |

`SecureStorageService.logout()` (`:117-141`) performs a `deleteAll()` then restores only the three explicitly
preserved keys — every other key above (including the RSA public key cache and FCM token) is wiped on both
normal and force logout, meaning a fresh login re-fetches the RSA key and re-registers the FCM token.

## Shared Models (used across `core/` and consumed by features)

### `AppControlModel` family — `core/models/app_control_model.dart`
- `PlatformVersionInfo { latestVersion, minVersion, storeUrl, title, message, buttonText }` — one instance
  each for `android`/`ios`, with legacy top-level-field fallback support for backward compat with an older
  API shape.
- `AppVersionInfo { forceUpdate, android, ios }`, `.current` getter picks the right platform block (defaults
  to `android` on web).
- `AppAlert { isActive, title, message, type ('info'|'warning'|'maintenance'), actionUrl?, actionLabel? }`,
  `.isMaintenance` getter.
- `MaintenanceInfo { isEnabled, title, subtitle, expectedResume? }`.
- `AppControlData { versionInfo?, alert?, maintenance, responsePlatform, dynamicSwitching,
  dynamicSwitchingPassword? }` — top-level response wrapper for `POST app/control`, `.isPlatformMatch` getter
  guards against applying a mismatched platform's version/alert config.

### `UserProfile` — `core/providers/user_provider.dart` (see provider section above — not a `fromJson` model,
constructed inline from `authControllerProvider`'s raw session map).

### `CommodityPortfolio` / `PortfolioData` — `core/providers/portfolio_provider.dart` (see provider section).

### Feature-owned models consumed by `core/` (see CROSS_MODULE_MAP.md violations)
- `MarketRates` (`features/market/models/market_rates.dart`) — `goldBuy/goldSell/goldChange/goldPercentage`,
  `silverBuy/silverSell/silverChange/silverPercentage`, `timestamp`, `currency`. `.fromRawString` parses the
  pipe-delimited socket frame; `.isSignificantChange` gates whether a new frame triggers a stream emission
  (exact threshold not read this pass — see `market_rates.dart:177` if precision matters for a future task).
- `HomeDashboard` (`features/home/models/home_dashboard.dart`) — not read in full this pass.
- `CountdownOfferResponse`/`CountdownOfferNewOffer`/`CountdownOfferExistingOffer`
  (`features/home/models/countdown_offer_model.dart`) — not read in full this pass.

## Non-Riverpod Static State (module-level singletons/flags)

| Holder | State | Reset condition |
|---|---|---|
| `SessionManager._isForceLoggedOut` | bool | `resetForceLogout()` on fresh login only |
| `ApiSecurityInterceptor._refreshLock` / `._lastRefreshTime` | `Completer<bool>?` / `DateTime?` | cleared after each refresh attempt completes; `_lastRefreshTime` provides a 30s "recently refreshed" window |
| `EncryptionService._rsaPublicKey` / `._rsaReady` | `RSAPublicKey?` / bool | `clearKey()` (not confirmed called) |
| `CertificatePinning._activePins` | `List<String>` | re-seeded from `AppConfig.allowedCertFingerprints` fallback by `clearCache()`; otherwise persists for process lifetime once loaded/updated |
| `AppLifecycleObserver.suppressAppLock` / `._isLockScreenShowing` | bool (static) | payment-flow code sets/clears `suppressAppLock`; `_isLockScreenShowing` self-resets after the MPIN/biometric flow completes or via `resetLockFlag()` |
| `DeviceIdService._cachedId` / `._cachedType` / `._cachedDeviceInfo` | in-memory cache | process lifetime only (backed by persisted secure-storage keys above) |
| `_portfolioCache` (module-level `Map` in `portfolio_provider.dart:97`) | `Map<String, PortfolioData>` | process lifetime; not cleared on logout (see note above) |
