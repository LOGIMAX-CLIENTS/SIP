---
module: InstantSaving
last_updated: 2026-08-19
---

# InstantSaving — State Analysis

## Riverpod Providers Owned by This Module

| Provider | Type | Definition | Purpose |
|---|---|---|---|
| `savingServiceProvider` | `Provider<SavingService>` | `saving_controller.dart:5` | Plain DI for `SavingService` (no state). |
| `paymentServiceProvider` | `Provider<PaymentService>` | `saving_controller.dart:6` | Plain DI for `PaymentService`. |
| `savingConfigProvider` | `FutureProvider.autoDispose<SavingConfig>` | `saving_controller.dart:8-11` | `POST savings/config` — GST %, min/max, rate-lock durations, gateway map. Re-invalidated on screen entry and on Invest-tab re-select. |
| `paymentMethodsProvider` | `FutureProvider.autoDispose<List<PaymentMethod>>` | `saving_controller.dart:13-16` | `POST payments/methods` — feeds `PaymentMethodSheet`. |
| `instantSavingControllerProvider` | `StateNotifierProvider<InstantSavingNotifier, InstantSavingState>` | `saving_controller.dart:62-65` | Holds `amount`, `transactionId`, `kycRequired`, `selectedPaymentMethod` — **defined but its mutator methods (`setAmount`, `setTransactionData`, `setSelectedPaymentMethod`) have no call sites found anywhere in the module.** The screen manages equivalent state locally instead (see below). Likely dead/aspirational — do not assume this provider reflects the live purchase flow's actual amount or selected method. |

## `InstantSavingState` shape (`saving_controller.dart:18-44`)

```dart
class InstantSavingState {
  final double amount;               // default 0 — never set by any observed call site
  final String? transactionId;       // never set
  final bool kycRequired;            // default false — never set
  final PaymentMethod? selectedPaymentMethod;  // never set
}
```
Immutable, `copyWith`-based, standard Riverpod `StateNotifier` pattern — but functionally unused. If a future
change wires this up, note it was previously dead so downstream assumptions ("this always reflects the
current screen amount") should not be made without re-verifying call sites.

## Screen-local state (`_InstantSavingScreenState`, `instant_saving_screen.dart:42-49`)

This is where the *actual* live entry state lives, as a plain `State` (not Riverpod):

| Field | Type | Purpose |
|---|---|---|
| `_amountController` | `TextEditingController` | The raw text field backing store for amount/weight entry. |
| `_selectedAmount` | `String` | Mirrors `_amountController.text` — used for denomination-chip selection comparison and passed through to `_computeBreakdown`. |
| `_isAmountMode` | `bool` | `true` = "Buy in Rupees", `false` = "Buy in Grams". Toggling clears the input and re-seeds from the popular denomination of the new mode. |
| `_isProcessing` | `bool` | Drives the full-screen "Processing Payment..." overlay (line 285-380) and disables Pay Now / breakdown Pay Now while `true`. |
| `_pulseController` (`AnimationController`) | Decorative pulse animation, 2s repeat-reverse — not state-flow-relevant. |

## Shared/Core Providers Consumed

| Provider | Owner | Consumed for |
|---|---|---|
| `commodityProvider` / `CommodityType` | `core/providers/commodity_provider.dart` | Gold/Silver toggle — global, shared with Home/Withdrawal/SIP. |
| `selectedMetalIdProvider` | `core/providers/commodity_provider.dart` | Resolves the real `id_metal` string sent to every `savings/*` call, from `commoditiesProvider` with `'1'`/`'3'` fallback. |
| `commoditiesProvider` | `core/services/shared_service.dart` | `POST users/shared/commodities` — non-autoDispose, app-session-lived. |
| `amountDenominationsProvider` / `weightDenominationsProvider` | `core/services/shared_service.dart` | `FutureProvider.autoDispose`, keyed implicitly by `selectedMetalIdProvider` (re-fetches on commodity switch). |
| `sellRateTimerProvider` | `core/providers/timer_provider.dart` | The rate-lock `TimerState { remainingSeconds, lockedRates, isMarketClosed }`. Shared type with `buyRateTimerProvider` (used by `withdrawal`), but this module always uses the `sell` instance. |
| `marketRatesStreamProvider` | `core/providers/market_provider.dart` | `StreamProvider<MarketRates>` — live socket rates, source for the timer's lock snapshot and the closed-market fallback display. |
| `marketStatusProvider` | `core/providers/market_provider.dart` | `StreamProvider<Map<String,bool>>` — per-commodity-id open/closed flags from socket status frames. |
| `userProvider` | `core/providers/user_provider.dart` | Logged-in user's `id`/`mobile`/`email` — email used only by Razorpay's `prefill`. |
| `selectedTabProvider` | `features/main/main_screen.dart` (re-exported/used cross-module) | Bottom-nav tab index — read/set to navigate to Home or Invest tab, and to detect "Invest tab re-selected" for a config refresh. |
| `countdownOfferProvider` | `core/providers/countdown_offer_provider.dart` | Best-Offer block data — `FutureProvider.autoDispose`, returns `CountdownOfferResponse.disabled()` for unauthenticated users. |
| `portfolioProvider`, `homeDashboardProvider`, `profileProvider` | `core/providers/portfolio_provider.dart`, `core/providers/home_dashboard_provider.dart`, `features/profile/profile_controller.dart` | Refreshed only from `PurchaseSuccessScreen`'s "Back to Home" action, not automatically on purchase success. |

## Model Shapes (`saving_models.dart`)

| Model | Fields | Notes |
|---|---|---|
| `SavingConfig` | `minAmount`, `maxAmount`, `gst` (double), `type` (String, unused — see BUSINESS_RULES-003), `sellRateLockSeconds`, `buyRateLockSeconds` (int, unused by this module), `paymentMethods` (`Map<String,String>`, gateway-resolution fallback) | `fromJson` defaults all numerics to `0`/`0.0` if the key is absent — a malformed/partial `savings/config` response silently yields a config that blocks all purchases (min/max both 0) rather than throwing. |
| `PaymentMethod` | `id`, `name`, `icon`, `description` (legacy fields) + `iconUrl`, `subtitle`, `badgeIcons` (v2 API fields) | Dual-shape model supporting both old and new `payments/methods` response formats. |
| `PaymentOrder` | `paymentUrl`, `orderId` | Belongs to the **dead** `PaymentService.createOrder()` path — not used by the live `savings/initiate` flow. |
| `EligibilityResponse` | `nextStep` (String, default `'PAYMENT'` if `next_step` absent) | Drives the entire branch in `_handleConfirmOrder` — an absent/malformed field defaults to skipping KYC entirely and going straight to payment. |
| `PurchaseInitiateResponse` | `orderId`, `sessionId`, `environment`, `message`, `amountInr`, `weight`, `ratePerGram`, `paymentGateway` (default `'cashfree'`), `sdkPayload`/`merchantId`/`clientId`/`hdfcEnvironment` (HDFC), `rzOrderId`/`keyId` (Razorpay) | All fields nullable/defaulted — no field is required by the model itself; validation of required-for-gateway fields happens downstream in each handler (e.g. `HdfcPaymentHandler.launchPayment` throws if `sdkPayload`/`merchantId`/`clientId` are null/empty). |

## Secure Storage / Persistent State Touched

None directly — this module reads (never writes) `SecureStorageService`-backed state indirectly via
`ApiClient`'s auth-token attachment (`api_interceptor.dart`) and `EncryptionService`'s cached RSA public key.
No MPIN, biometric flag, or token is read/written by any file under `lib/features/instant_saving/`.

## Lifecycle / Disposal Notes

- `savingConfigProvider`, `paymentMethodsProvider`, `amountDenominationsProvider`, `weightDenominationsProvider`,
  `countdownOfferProvider` are all `.autoDispose` — they re-fetch every time the screen (or the sheet, for
  `paymentMethodsProvider`) is entered/re-watched, by design (rate/config freshness matters for a
  financial screen). `commoditiesProvider` is deliberately **not** `.autoDispose` so `selectedMetalIdProvider`
  always has a resolved `id_metal` ready on first paint without a loading gap.
- `sellRateTimerProvider` is a long-lived `StateNotifierProvider` (not autoDispose) — its `RateTimerNotifier`
  registers a `WidgetsBindingObserver` and recalculates on `AppLifecycleState.resumed`
  (`timer_provider.dart:33-39`), so backgrounding the app during Instant Saving does not leave a stale
  countdown; it re-evaluates against wall-clock time on resume.
