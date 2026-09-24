---
module: core/
last_updated: 2026-08-19
scope: every public class + public method/getter across all 47 files in lib/core/
---

# Core — Method Index

Alphabetical by class. `file:line` is the definition site. "Callers" is best-effort — confirmed via grep for
cross-file/cross-feature references where noted; otherwise inferred from the architecture (e.g. "every
core/services/*.dart via ApiClient()"). Static-const-only classes (`AppConfig`, `AppConstants`) are omitted
(no methods). Private (`_`-prefixed) helpers are omitted except where they materially affect callers'
understanding.

## AppControlData / AppVersionInfo / PlatformVersionInfo / AppAlert / MaintenanceInfo
`core/models/app_control_model.dart`
| Member | Location | Callers |
|---|---|---|
| `PlatformVersionInfo.fromJson` | `:24` | `AppVersionInfo.fromJson` |
| `AppVersionInfo.fromJson` | `:69` | `AppControlData.fromJson` |
| `AppVersionInfo.current` (getter) | `:94` | `AppControlNotifier._fetch` (`providers/app_control_provider.dart:174`) |
| `AppAlert.fromJson` | `:118` | `AppControlData.fromJson` |
| `AppAlert.isMaintenance` (getter) | `:127` | `AppControlNotifier._fetch`/`checkBeforeAction` |
| `MaintenanceInfo.fromJson` | `:144` | `AppControlData.fromJson` |
| `AppControlData.isPlatformMatch` (getter) | `:180` | `AppControlNotifier._fetch` |
| `AppControlData.fromJson` | `:191` | `AppControlNotifier._fetch`, `.checkBeforeAction` |

## AppControlNotifier / AppControlState
`core/providers/app_control_provider.dart`
| Member | Location | Callers |
|---|---|---|
| `initialize` | `:70` | `shared/widgets/app_control_wrapper.dart` (splash/app boot) |
| `ensureInitialized` | `:78` | build()-time safety net, same wrapper |
| `startMaintenancePolling` | `:86` | `shared/widgets/maintenance_gate.dart` |
| `checkBeforeAction` | `:232` | `shared/widgets/maintenance_gate.dart` — pre-action gate before payment/withdrawal/SIP-create |
| `dismissUpdate` | `:216` | update-available dialog (feature UI, not grepped this round) |
| `dismissAlert` | `:222` | alert-banner UI |
| `refresh` | `:286` | manual pull-to-refresh paths |

## ApiClient
`core/network/api_client.dart`
| Member | Location | Callers |
|---|---|---|
| `ApiClient()` factory (singleton) | `:12` | every `core/services/*.dart` that talks to the backend (13 of 13 service files) |
| `updateBaseUrl` | `:36` | `services/environment_service.dart:64` (`setEnvironment`) |
| `get` | `:40` | not observed in this pass — `post` is the dominant verb used by every service |
| `post` | `:53` | `AuthService`, `ContentService`, `HomeService`, `MpinService`, `NotificationService`, `PortfolioService`, `SharedService` |

## ApiFailureMapper
`core/error/failures.dart`
| Member | Location | Callers |
|---|---|---|
| `map(DioException)` | `:52` | `ApiClient.get`/`.post` catch blocks (`network/api_client.dart:47,63`); `MpinNotifier.verifyMpin` catch (`services/mpin_service.dart:255`) |

## ApiSecurityInterceptor
`core/security/api_interceptor.dart`
| Member | Location | Callers |
|---|---|---|
| `fetchAndCachePublicKey` (static) | `:38` | `ApiClient._internal()` constructor (`network/api_client.dart:33`, fire-and-forget bootstrap); re-invoked defensively from its own `onRequest` (`:137`) for sensitive endpoints if key not yet ready |
| `onRequest` | `:93` | Dio interceptor chain (automatic, every outbound request) |
| `onResponse` | `:189` | Dio interceptor chain (automatic, every response) |
| `onError` | `:208` | Dio interceptor chain (automatic, every failed response) |

## AppLifecycleObserver
`core/security/app_lifecycle_observer.dart`
| Member | Location | Callers |
|---|---|---|
| `didChangeAppLifecycleState` | `:50` | Flutter `WidgetsBinding` (automatic, via `lifecycleObserverProvider`) |
| `resetLockFlag` (static) | `:214` | escape hatch for unexpected lock-screen dismissal paths (not grepped — documented as intentional callback) |
| `suppressAppLock` (static field) | `:39` | set by payment/UPI-intent flows before launching Cashfree/HyperSDK/Razorpay (per AGENTS.md §3), reset after |
| `lifecycleObserverProvider` | `:219` | `main.dart:80` (`MyApp.build`) |

## AppLogger — **dead code**
`core/utils/logger.dart`
| Member | Location | Callers |
|---|---|---|
| `d` / `e` / `i` / `sensitive` | `:5,11,21,26` | only `core/network/interceptors.dart` (itself unused — see below) |

## AuthInterceptor — **dead code, not registered on any Dio instance**
`core/network/interceptors.dart`
| Member | Location | Callers |
|---|---|---|
| `onRequest` / `onResponse` / `onError` | `:8,21,29` | none — grep confirms this class is defined but never constructed anywhere in `lib/` |

## AuthNotifier / AuthState
`core/services/auth_service.dart`
| Member | Location | Callers |
|---|---|---|
| `rehydrateFromStorage` | `:255` | own constructor; re-called externally after forgot-PIN flow overwrites `sessionData` (per doc comment) |
| `sendOtp` | `:274` | `features/auth` OTP-request screens (not re-verified this pass) |
| `verifyOtp` | `:341` | `features/auth` OTP screen |
| `sendEmailOtp` / `verifyEmailOtp` | `:405,461` | `features/auth` email-verification screens |
| `register` | `:519` | `features/auth` registration screen |
| `logout` | `:589` | logout action (settings/profile) |
| `clearError` | `:594` | auth screens' error-dismiss UI |
| **Note** | | `AuthController` (`features/auth/controller/auth_controller.dart:5`) `extends AuthNotifier` and is the provider actually watched by `core/providers/user_provider.dart` (`authControllerProvider`, not `authProvider`) |

## AuthService
`core/services/auth_service.dart`
| Member | Location | Callers |
|---|---|---|
| `sendOtp` | `:24` | `AuthNotifier.sendOtp` |
| `verifyOtp` | `:47` | `AuthNotifier.verifyOtp` — also persists tokens, resets force-logout flag (`SessionManager.resetForceLogout()`, `:75`) |
| `sendEmailOtp` / `verifyEmailOtp` | `:98,112` | `AuthNotifier` counterparts |
| `register` | `:128` | `AuthNotifier.register` |
| `registerCheck` | `:178` | pre-validation before PIN-creation navigation (feature screen, not re-verified) |
| `logout` | `:202` | `AuthNotifier.logout` |

## BiometricService
`core/services/biometric_service.dart`
| Member | Location | Callers |
|---|---|---|
| `deviceHasBiometric` | `:25` | `canUseBiometric` |
| `canUseBiometric` | `:48` | `AppLifecycleObserver._preCacheSecurityState` (`security/app_lifecycle_observer.dart:83`) |
| `checkBeforeEnable` | `:69` | Profile/Settings biometric-toggle screen (not re-verified) |
| `authenticate` | `:90` | `AppLifecycleObserver._tryBiometricThenMpin` (`:172`) |

## CertificatePinning
`core/security/certificate_pinning.dart`
| Member | Location | Callers |
|---|---|---|
| `init` (static) | `:43` | `main.dart:62` (startup, loads cached pins) |
| `updatePins` (static) | `:67` | `AppControlNotifier._fetch` (`providers/app_control_provider.dart:126`) — server-pushed pin rotation |
| `setup` (static) | `:85` | `ApiClient._internal()` (`:29`), `ApiSecurityInterceptor.fetchAndCachePublicKey` (`:59`), and every ad-hoc refresh/retry `Dio()` instance created inline in `ApiSecurityInterceptor.onError` |
| `clearCache` (static) | `:257` | not observed as called this pass — documented for logout path, verify before relying on it firing |

## ClipboardSecurityService
`core/security/clipboard_security_service.dart`
| Member | Location | Callers |
|---|---|---|
| `clearClipboard` (static) | `:25` | `main.dart:56` (cold start), `AppLifecycleObserver.didChangeAppLifecycleState` (`:67`, every resume) |

## Commodity / CountryCode / AmountDenomination / WeightDenomination
`core/services/shared_service.dart`
| Member | Location | Callers |
|---|---|---|
| `CountryCode.fromJson` | `:20` | `SharedService.getCountryCodes` |
| `Commodity.fromJson` | `:42` | `SharedService.getCommodities` |
| `AmountDenomination.fromJson` / `WeightDenomination.fromJson` | `:60,77` | `SharedService.getAmountDenominations`/`.getWeightDenominations` |

## CommodityNotifier
`core/providers/commodity_provider.dart`
| Member | Location | Callers |
|---|---|---|
| `setCommodity` | `:9` | Gold/Silver toggle UI (`home`, `withdrawal`, `instant_saving` screens — confirmed via `commodity_provider` import grep) |

## ConnectivityNotifier
`core/providers/connectivity_provider.dart`
| Member | Location | Callers |
|---|---|---|
| `recheck` | `:58` | offline-banner retry actions (not re-verified this pass) |

## ContentService
`core/services/content_service.dart`
| Member | Location | Callers |
|---|---|---|
| `getOnboardingContent` | `:8` | `onboardingContentProvider` (`:147`) |
| `getTermsAndConditions` / `getPrivacyPolicy` / `getAboutUs` / `getContactUs` / `getRefundPolicy` | `:22,33,55,66,77` | matching `*Provider` in same file, consumed by `features/content` screens |
| `getFAQs` | `:44` | `faqsProvider` (`:161`), `features/support` FAQ screen |
| `_extractContentMap` / `_extractFaqList` (private) | `:95,119` | tolerate multiple backend response shapes — see BUSINESS_RULES |

## DeviceIdService
`core/services/device_id_service.dart`
| Member | Location | Callers |
|---|---|---|
| `getDeviceId` (static) | `:40` | `AuthService.sendOtp`/`.register`/`.registerCheck`, `NotificationService.registerFcmToken` |
| `getDeviceType` (static) | `:81` | same callers as `getDeviceId` |
| `getDeviceInfo` (static) | `:109` | `NotificationService.registerFcmToken` (`:126`) |

## DeviceService — **unused, duplicate of DeviceIdService**
`core/services/device_service.dart`
| Member | Location | Callers |
|---|---|---|
| `getDeviceId` | `:7` | none found via grep |

## EncryptionService
`core/security/encryption_service.dart`
| Member | Location | Callers |
|---|---|---|
| `loadPublicKey` (static) | `:23` | `ApiSecurityInterceptor.fetchAndCachePublicKey` (`:42`) |
| `setPublicKeyFromServer` (static) | `:39` | `ApiSecurityInterceptor.fetchAndCachePublicKey` (`:71`) |
| `isRsaReady` (static getter) | `:57` | `ApiSecurityInterceptor.fetchAndCachePublicKey`/`.onRequest` (`:39,135,175`) |
| `clearKey` (static) | `:60` | not observed as called this pass (documented for logout — verify) |
| `encrypt` | `:69` | `encryptJson` |
| `decrypt` | `:101` (**no-op passthrough**) | `decryptJson` |
| `encryptJson` (static) | `:109` | `ApiSecurityInterceptor.onRequest` (`:172`) |
| `decryptJson` (static) | `:129` | `ApiSecurityInterceptor.onResponse` (`:199`) |

## EnvironmentService
`core/services/environment_service.dart`
| Member | Location | Callers |
|---|---|---|
| `initialize` (static) | `:27` | `main.dart:25`, before `runApp` |
| `setEnvironment` (static) | `:49` | environment-switcher (staging/production toggle, likely a dev/settings screen — `dynamic_switching`/`dynamic_switching_password` fields in `AppControlData` suggest server-gated access) |

## FcmService
`core/services/fcm_service.dart`
| Member | Location | Callers |
|---|---|---|
| `init` (static) | `:63` | `main.dart:65` |
| `getToken` (static) | `:121` | internal debug log (`:107`); expected caller per doc comment is login/registration success flow (not grepped this pass) |
| `onTokenRefresh` (static stream getter) | `:124` | `_onTokenRefreshed` internal listener (`:114`) |
| `navigateToNotifications` (static) | `:192` | nav-bar bell icon / deep links (feature UI, not re-verified) |

## HomeService
`core/services/home_service.dart`
| Member | Location | Callers |
|---|---|---|
| `getHomeDashboard` | `:9` | `homeDashboardProvider` (`providers/home_dashboard_provider.dart:9`) |
| `getCountdownOffer` | `:28` | `countdownOfferProvider` (`providers/countdown_offer_provider.dart:20`) |

## KycValidator
`core/utils/kyc_validator.dart`
| Member | Location | Callers |
|---|---|---|
| `validateAadhaar` / `validatePAN` / `validateMobile` / `validateUPI` | `:2,9,16,24` | `features/kyc` form fields (not re-verified line-by-line this pass) |
| `validateGeneric` | `:31` | generic regex-driven form fields |

## LanguageCache
`core/localization/language_cache.dart`
| Member | Location | Callers |
|---|---|---|
| `saveLocale` / `getLocale` | `:8,13` | not observed as called this pass — `LanguageNotifier` uses `SharedPreferences` directly instead of this class (duplication) |
| `saveRemoteTranslations` / `getRemoteTranslations` | `:18,25` | would back `LanguageService.fetchMegaTranslations`, but that method's body is commented out — effectively unused |

## LanguageNotifier
`core/localization/language_provider.dart`
| Member | Location | Callers |
|---|---|---|
| `setLanguage` | `:44` | language-picker UI (`features/settings`, not re-verified) |
| `translate` | `:50` | `LocalizationHelper.tr` extension (`:81`), used app-wide as `ref.tr(...)` |

## LanguageService — **effectively unused (body commented out)**
`core/localization/language_service.dart`
| Member | Location | Callers |
|---|---|---|
| `fetchMegaTranslations` | `:4` | none — always returns `null`; real network call is commented out |

## LduiParser — **dead code, zero call sites**
`core/ldui/ldui_parser.dart`
| Member | Location | Callers |
|---|---|---|
| `parse` (static) | `:23` | none found via grep — see MODULE_BRAIN Known Gaps #1 |

## MarketRates-related providers
`core/providers/market_provider.dart` — see Provider Index below.

## MaskingUtils
`core/utils/masking_utils.dart`
| Member | Location | Callers |
|---|---|---|
| `maskMobile` / `maskBankAccount` / `maskPan` / `maskEmail` | `:11,39,47,56` | display-only masking on Profile/KYC/withdrawal screens (not re-verified line-by-line) |

## MpinNotifier / MpinState
`core/services/mpin_service.dart`
| Member | Location | Callers |
|---|---|---|
| `addKey` / `backspace` | `:155,165` | MPIN keypad UI |
| `setMpin` | `:175` | PIN-creation flow after registration |
| `verifyMpin` | `:194` | app-lock (`AppLifecycleObserver._pushMpinLockScreen` target), login-MPIN, withdrawal-confirm MPIN |
| `resetMpin` | `:296` | forgot-PIN flow |
| `clear` | `:315` | keypad reset after failed attempt / navigation away |

## MpinService
`core/services/mpin_service.dart`
| Member | Location | Callers |
|---|---|---|
| `setMpin` | `:13` | `MpinNotifier.setMpin` (`:179`); also called directly by `AuthController.setPin` (`features/auth/controller/auth_controller.dart:13`) |
| `verifyMpin` | `:30` | `MpinNotifier.verifyMpin` (`:198`); also `AuthController.verifyPin` (`:31`) |
| `changeMpin` | `:58` | Settings "change PIN" flow (not re-verified) |
| `resetMpin` | `:80` | `MpinNotifier.resetMpin` (`:300`) |
| `hasMpinSet` | `:101` | splash/login routing decision (not re-verified this pass) |

## NativeSocketService
`core/network/native_socket_service.dart`
| Member | Location | Callers |
|---|---|---|
| `updateCommodityConfig` | `:56` | `marketRatesStreamProvider` (`providers/market_provider.dart:39`), whenever `commoditiesProvider` resolves |
| `connect` | `:74` | `marketRatesStreamProvider` (auto-connect on first watch, `:44`); `AppLifecycleObserver` on resume (`:70`) |
| `disconnect` | `:213` | `AppLifecycleObserver` on pause (`:62`); internally by `_scheduleReconnect` |
| `dispose` | `:255` | `socketIOServiceProvider`'s `ref.onDispose` (`:11`) |

## NavigationUtils
`core/utils/navigation_utils.dart`
| Member | Location | Callers |
|---|---|---|
| `safePop` | `:23` | screens that may be the sole navigator-stack entry (e.g. OTP reached via `pushReplacementNamed` from Forgot-PIN — per doc comment) |

## NotificationNotifier / NotificationService
`core/services/notification_service.dart`
| Member | Location | Callers |
|---|---|---|
| `AppNotification.fromJson` | `:26` | `NotificationService.fetchNotifications` |
| `fetchNotifications` | `:53` | `NotificationNotifier.load` (`:193`) |
| `markAsRead` / `markAllAsRead` / `deleteNotification` | `:65,71,76` | `NotificationNotifier` counterparts (`:204,221,231`) |
| `fetchUnreadCount` | `:82` | `NotificationNotifier.refreshUnreadCount` (`:248`) |
| `registerFcmToken` | `:116` | `FcmService._onTokenRefreshed` (`:177`); expected also post-login (not grepped this pass) |
| `load` | `:190` | Notifications screen `initState` (not re-verified) |
| `markAsRead` / `markAllAsRead` / `deleteNotification` (notifier) | `:202,219,229` | Notifications screen actions |
| `refreshUnreadCount` | `:246` | nav-bar badge polling (not re-verified) |

## PortfolioNotifier / PortfolioService
`core/providers/portfolio_provider.dart`, `core/services/portfolio_service.dart`
| Member | Location | Callers |
|---|---|---|
| `CommodityPortfolio.empty` / `PortfolioData.empty` | `providers/portfolio_provider.dart:23,42` | default/error states |
| `PortfolioNotifier.fetchPortfolio` | `:67` | own constructor; re-invoked implicitly when `portfolioProvider` is rebuilt (metal/customer change) |
| `PortfolioService.getPortfolioSummary` | `services/portfolio_service.dart:8` | `PortfolioNotifier.fetchPortfolio` (`:80`) |

## RateTimerNotifier / TimerState
`core/providers/timer_provider.dart`
| Member | Location | Callers |
|---|---|---|
| `startOrRefresh` | `:41` | `withdrawal` and `instant_saving` screens (confirmed via `timer_provider` import grep — `withdrawal_screen.dart`, `withdrawal_confirmation_screen.dart`, `instant_saving_screen.dart`, `payment_methods_screen.dart`, `payment_handler.dart`) |
| `clear` | `:107` | same screens, on navigation-away / purchase-complete |
| `didChangeAppLifecycleState` | `:34` | Flutter `WidgetsBinding` (automatic — re-evaluates timer on resume) |

## RootDetectionService
`core/security/root_detection_service.dart`
| Member | Location | Callers |
|---|---|---|
| `isDeviceCompromised` (static) | `:13` | `main.dart:37` — sole call site, gates whether `runApp` ever reaches the normal `MyApp` widget tree |

## ScreenshotSecurityService
`core/security/screenshot_security_service.dart`
| Member | Location | Callers |
|---|---|---|
| `initialize` (static) | `:14` | `main.dart:53`; `AppControlNotifier._fetch` (`:136`, when server toggles `security.enable_screenshot_protection`) |
| `secureScreen` (static) | `:41` | `features/auth/otp/otp_screen.dart`, `features/mpin/mpin_screen.dart` (confirmed via grep) |
| `releaseScreen` (static) | `:54` | same screens, `dispose()` |

## SecureLogger
`core/security/secure_logger.dart`
| Member | Location | Callers |
|---|---|---|
| `d` / `e` | `:7,14` | throughout `core/security/*.dart` and `core/network/native_socket_service.dart` |
| `logRequest` / `logResponse` / `logError` | `:23,34,46` | `ApiSecurityInterceptor.onRequest`/`.onResponse`/`.onError` (`:98,190,209`) |

## SecureStorageService
`core/security/secure_storage_service.dart`
| Member | Location | Callers |
|---|---|---|
| `saveToken` / `getToken` | `:10,18` | `AuthService.verifyOtp`, `ApiSecurityInterceptor` (attach header, post-refresh save) |
| `saveRefreshToken` / `getRefreshToken` | `:14,22` | same refresh flow |
| `isMpinEnabled` / `setMpinEnabled` | `:26,31` | `AppLifecycleObserver._preCacheSecurityState`, `AuthService.verifyOtp` |
| `isBiometricEnabled` / `setBiometricEnabled` | `:36,41` | `BiometricService.canUseBiometric`, Settings toggle |
| `getOnboardingSeen` / `setOnboardingSeen` | `:46,51` | `SessionManager.hasSeenOnboarding`/`.setOnboardingSeen` |
| `saveCustomerId`/`getCustomerId`, `saveCustomerName`/`getCustomerName`, `saveCustomerPhoto`/`getCustomerPhoto` | `:56-78` | `AuthService.verifyOtp`/`.register`, `AuthNotifier.rehydrateFromStorage` |
| `saveServerPublicKey` / `getServerPublicKey` | `:81,85` | `EncryptionService.setPublicKeyFromServer`/`.loadPublicKey` |
| `saveMobile` / `getMobile` | `:90,94` | `AuthService.verifyOtp`, `AuthNotifier.rehydrateFromStorage` |
| `saveFcmToken` / `getFcmToken` | `:99,103` | `NotificationService.registerFcmToken` |
| `logout` | `:117` | `SessionManager.logout`/`.forceLogout` |

## SessionManager
`core/security/session_manager.dart`
| Member | Location | Callers |
|---|---|---|
| `isForceLoggedOut` (static getter) | `:16` | `ApiSecurityInterceptor.onRequest` (`:103`), `AppLifecycleObserver._checkAppLockOnResume` (`:114`) |
| `isAuthenticated` | `:18` | `AppLifecycleObserver._preCacheSecurityState`, `NavigationUtils._navigateToFallback` |
| `logout` | `:25` | `ApiSecurityInterceptor.onError` (401 refresh-failed path) |
| `forceLogout` | `:32` | `ApiSecurityInterceptor.onError` (409 path, deduplicated) |
| `resetForceLogout` | `:41` | `AuthService.verifyOtp` (`:75`, fresh-login clears force-logout) |
| `hasSeenOnboarding` / `setOnboardingSeen` | `:45,50` | splash routing / onboarding-complete action |

## SharedService
`core/services/shared_service.dart`
| Member | Location | Callers |
|---|---|---|
| `getCountryCodes` | `:88` | `countryCodesProvider` (`:172`), auth mobile-entry screen |
| `getCommodities` | `:115` | `commoditiesProvider` (`:179`) — feeds `selectedMetalIdProvider`, `marketRatesStreamProvider` |
| `getAmountDenominations` / `getWeightDenominations` | `:134,151` | `amountDenominationsProvider`/`weightDenominationsProvider` (`:184,191`) |

## Validators
`core/utils/validators.dart`
| Member | Location | Callers |
|---|---|---|
| `validateMobile` / `validateOTP` / `validateEmail` | `:2,9,15` | auth/login form fields (not re-verified line-by-line) |

---

## Top-Level Riverpod Providers (not class methods, but public API)

| Provider | File:line | Kind |
|---|---|---|
| `appControlProvider` | `providers/app_control_provider.dart:318` | `StateNotifierProvider<AppControlNotifier, AppControlState>` |
| `commodityProvider` | `providers/commodity_provider.dart:14` | `StateNotifierProvider<CommodityNotifier, CommodityType>` |
| `selectedMetalIdProvider` | `providers/commodity_provider.dart:26` | `Provider<String>` |
| `connectivityProvider` | `providers/connectivity_provider.dart:67` | `StateNotifierProvider<ConnectivityNotifier, ConnectivityState>` |
| `countdownOfferProvider` | `providers/countdown_offer_provider.dart:14` | `FutureProvider.autoDispose<CountdownOfferResponse>` |
| `environmentProvider` | `providers/environment_provider.dart:4` | `StateProvider<String>` |
| `homeServiceProvider` / `homeDashboardProvider` | `providers/home_dashboard_provider.dart:7,9` | `Provider` / `FutureProvider<HomeDashboard?>` |
| `socketIOServiceProvider` | `providers/market_provider.dart:8` | `Provider<NativeSocketService>` |
| `marketRatesStreamProvider` | `providers/market_provider.dart:16` | `StreamProvider<MarketRates>` |
| `socketStatusProvider` | `providers/market_provider.dart:49` | `StreamProvider<SocketStatus>` |
| `marketStatusProvider` | `providers/market_provider.dart:58` | `StreamProvider<Map<String,bool>>` |
| `portfolioProvider` | `providers/portfolio_provider.dart:99` | `StateNotifierProvider.autoDispose<PortfolioNotifier, AsyncValue<PortfolioData>>` |
| `sellRateTimerProvider` / `buyRateTimerProvider` | `providers/timer_provider.dart:121,126` | `StateNotifierProvider<RateTimerNotifier, TimerState>` |
| `userProvider` | `providers/user_provider.dart:28` | `Provider<UserProfile?>` |
| `lifecycleObserverProvider` | `security/app_lifecycle_observer.dart:219` | `Provider.family<AppLifecycleObserver, GlobalKey<NavigatorState>>` |
| `languageProvider` | `localization/language_provider.dart:74` | `StateNotifierProvider<LanguageNotifier, LanguageState>` |
| `authServiceProvider` / `authProvider` | `services/auth_service.dart:209,599` | `Provider<AuthService>` / `StateNotifierProvider<AuthNotifier, AuthState>` — **`authProvider` had no confirmed consumers this pass** |
| `contentServiceProvider` + 6 `*Provider` FutureProviders | `services/content_service.dart:144-176` | CMS content screens |
| `mpinServiceProvider` / `mpinProvider` | `services/mpin_service.dart:109,320` | `Provider<MpinService>` / `StateNotifierProvider<MpinNotifier, MpinState>` |
| `notificationServiceProvider` / `notificationProvider` / `unreadCountProvider` | `services/notification_service.dart:151,257,263` | notification stack |
| `portfolioServiceProvider` | `services/portfolio_service.dart:46` | `Provider<PortfolioService>` |
| `sharedServiceProvider` + `countryCodesProvider`/`commoditiesProvider`/`amountDenominationsProvider`/`weightDenominationsProvider` | `services/shared_service.dart:169-195` | lookup-data providers |

**Total distinct public providers: 30** (across 10 provider files + provider declarations embedded in 7
service files).
