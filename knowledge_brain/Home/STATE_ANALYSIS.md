---
module: Home
last_updated: 2026-08-19
---

# Home — State Analysis

## Providers Watched/Read by Home (none are defined inside `features/home/` — Home has no `providers/` folder)

### `core/providers/commodity_provider.dart`
- `enum CommodityType { gold, silver }` (`:4`)
- `CommodityNotifier extends StateNotifier<CommodityType>` (`:6-12`) — single method `setCommodity(type)`
- `commodityProvider = StateNotifierProvider<CommodityNotifier, CommodityType>` (`:14-17`) — initial state `CommodityType.gold`
- `selectedMetalIdProvider = Provider<String>` (`:26-41`) — derives real `id_metal` from `commoditiesProvider`
  (in `core/services/shared_service.dart:179`) by matching commodity name to `'gold'`/`'silver'`; falls back
  to hardcoded `'1'`/`'3'` while the commodities API is loading.

### `core/providers/market_provider.dart`
- `socketIOServiceProvider = Provider<NativeSocketService>` (`:8-13`) — recreated when
  `environmentProvider` changes; disposes the service on provider disposal.
- `marketRatesStreamProvider = StreamProvider<MarketRates>` (`:16-46`) — watches `commoditiesProvider` to
  push the real gold/silver IDs into the socket service (`updateCommodityConfig`), then calls
  `service.connect()` and returns `service.ratesStream`.
- `socketStatusProvider = StreamProvider<SocketStatus>` (`:49-52`) — not directly watched by Home.
- `marketStatusProvider = StreamProvider<Map<String,bool>>` (`:58-61`) — commodity-id → open/closed.

### `core/providers/timer_provider.dart`
- `TimerState { remainingSeconds, lockedRates, isMarketClosed }` (`:7-20`) —
  `isActive` getter requires `remainingSeconds > 0 && lockedRates != null && !isMarketClosed` (`:18-19`).
- `RateTimerNotifier extends StateNotifier<TimerState> with WidgetsBindingObserver` (`:22-119`) —
  re-evaluates the timer on `AppLifecycleState.resumed` (`:34-38`), i.e. backgrounding/foregrounding the app
  recalculates remaining time rather than freezing it.
- `sellRateTimerProvider` / `buyRateTimerProvider` (`:121-129`) — two independent
  `StateNotifierProvider<RateTimerNotifier, TimerState>` instances from the same class. Home only uses
  `sellRateTimerProvider`.

### `core/providers/home_dashboard_provider.dart`
- `homeServiceProvider = Provider<HomeService>` (`:7`)
- `homeDashboardProvider = FutureProvider<HomeDashboard?>` (`:9-19`) — returns `null` (no API call) when
  `userProvider` is null/has empty id; otherwise fetches keyed on `selectedMetalIdProvider`.

### `core/providers/portfolio_provider.dart`
- `CommodityPortfolio { totalInvested, currentValue, returns, returnsPercentage, balance, hasActiveAccount }`
  (`:6-31`), `.empty()` factory (`:23-30`).
- `PortfolioData { summary: CommodityPortfolio, isNewCustomer: bool }` (`:33-46`).
- `PortfolioNotifier extends StateNotifier<AsyncValue<PortfolioData>>` (`:48-92`) — constructor seeds state
  from `_portfolioCache` (module-level `Map<String, PortfolioData>`, `:97`) if available for the requested
  metal, else falls back to any cached metal's data, else `AsyncValue.loading()` — then immediately calls
  `fetchPortfolio()`. On error, keeps previous data visible if any (`:83-90`) rather than showing an error
  state when a prior successful fetch exists.
- `portfolioProvider = StateNotifierProvider.autoDispose<PortfolioNotifier, AsyncValue<PortfolioData>>`
  (`:99-109`) — `autoDispose` means switching away from Home (or the metal changing) can dispose and
  recreate the notifier; the module-level cache (`_portfolioCache`) is what prevents visible flicker across
  disposals.

### `core/providers/countdown_offer_provider.dart`
- `countdownOfferProvider = FutureProvider.autoDispose<CountdownOfferResponse>` (`:14-21`) — same
  user-null-guard pattern as `homeDashboardProvider`.

### `core/providers/user_provider.dart`
- `UserProfile { id, name, mobile, email, photoUrl, isNewUser, mpinEnabled, isKycVerified, isVip }` (`:4-26`)
  — `isKycVerified`/`isVip` are declared but not populated from `authControllerProvider.sessionData` in the
  `userProvider` body (`:28-56`) — always default `false`; **unconfirmed** whether they're set elsewhere.
- `userProvider = Provider<UserProfile?>` (`:28-56`) — derives from `authControllerProvider.sessionData`;
  returns a minimal "New User" profile when `is_new_user == true`.

### `core/services/notification_service.dart` (state notifier lives here, not in a `providers/` file)
- `AppNotification { id, title, message, type, isRead, createdAt }` (`:9-45`).
- `NotificationState { notifications, isLoading, error, unreadCount }` (`:156-183`).
- `NotificationNotifier extends StateNotifier<NotificationState>` (`:185-255`) — `load()`, `markAsRead(id)`,
  `markAllAsRead()`, `deleteNotification(id)` (optimistic local updates before/after the API call),
  `refreshUnreadCount()` (used by Home).
- `notificationProvider` (`:257-260`), `unreadCountProvider = Provider<int>` derived from it (`:263-265`).

### Cross-feature providers Home also reads (see `CROSS_MODULE_MAP.md` for the layering violation)
- `savingConfigProvider = FutureProvider.autoDispose<SavingConfig>`
  (`features/instant_saving/controller/saving_controller.dart:8-11`) — `SavingConfig` fields:
  `minAmount, maxAmount, gst, sellRateLockSeconds, buyRateLockSeconds, paymentMethods`
  (`features/instant_saving/models/saving_models.dart:1-18`), populated from `POST savings/config`.
- `profileProvider` (`features/profile/profile_controller.dart:331`) — `ProfileState`/user fields including
  `referralMessage` (`:22,42,62,82,177`, populated from API `referral_message`).
- `selectedTabProvider = StateProvider<int>((ref) => 0)` (`features/main/main_screen.dart:23`).

## Home-Owned Models (`lib/features/home/models/`)

### `home_dashboard.dart`
| Class | Fields | Notes |
|---|---|---|
| `HomeDashboard` | `rateHistory?, investSection?, learningSection?, footerInfo?` | All nullable — API sections are independently optional (`:1-30`) |
| `RateHistory` | `title, startYear, startRate: num, endYear, endRate: num, highlightText` | `_parseRate` local helper accepts both string and numeric API values (`:49-65`) |
| `InvestSection` | `title, subtitle (default text), blocks: List<InvestBlock>` | `:68-85` |
| `InvestBlock` | `image?` | Single nullable field — asset path or network URL (`:87-97`) |
| `LearningSection` | `title, banners: List<LearningBanner>` | `:99-114` |
| `LearningBanner` | `id?, title?, image, url?` | `:116-137` |
| `FooterInfo` | `title, subtitle, compliance: List<ComplianceItem>, cin, copyright` | `:139-166` |
| `ComplianceItem` | `image, label` | `image` accepts both `image` and legacy `icon` JSON keys (`:169-180`) |

### `countdown_offer_model.dart`
| Class | Fields | Notes |
|---|---|---|
| `CountdownOfferResponse` | `enabled, customerType?, newOffer?, existingOffer?` | `fromJson` reads from `json['data']`; returns `.disabled()` on missing/`enabled:false` (`:8-60`) |
| `NewCustomerOffer` | `offerName, offerStartDate, offerEndDate, remainingDays/Hours/Minutes/Seconds, rewardPercentage, dailyPenaltyPercentage, benchmarkAmount, benchmarkPercentage, benchmarkEnabled, ctaText, descriptionTitle, descriptionBody, webviewUrl?` | Every field has a sane hardcoded default if the API omits it (`:103-126`) |
| `ExistingCustomerOffer` | `offerName, silverEarned, investDays, daysRemaining, currentRewardPercentage, offerEndDate, ctaText, webviewUrl?` | `:128-164` — `webviewUrl` can also come from `existing_offer.webview_url` OR be injected from the root/data-level `webview_url` if absent (`countdown_offer_model.dart:41-46`) |

## Secure Storage / Local Persistence

None found in this module's `.dart` files — Home does not read/write `flutter_secure_storage` or
`shared_preferences` directly; all "persistence" is either server-fetched or the in-memory
`_portfolioCache` (cleared on app restart, not persisted).

## Validation Baked Into Models

Minimal — this module's models are pure display DTOs with defensive `fromJson` (null-coalescing defaults,
`_parseRate`/type-tolerant parsing). No business-rule validation (min/max amounts, etc.) is performed in
Home's own models; that logic lives in `instant_saving`'s `SavingConfig`/`saving_controller.dart` (only
`sellRateLockSeconds` is consumed here).
