---
module: InstantSaving
folder: lib/features/instant_saving/
last_updated: 2026-08-19
round: 1 (build)
files_read: 10/10 module files (full or near-full) + app_router.dart + ~12 core/cross-module files
---

# InstantSaving — Module Brain

One-time gold/silver purchase — **the core revenue screen** of startGOLD. User enters an amount (₹) or
weight (grams), the app converts between the two using a GST-aware formula and a live, timer-locked rate,
runs a KYC eligibility gate, then hands off to one of **three** payment gateways selected by the **backend**
per order: Cashfree (Web Checkout), HDFC SmartGateway (Juspay HyperSDK), or Razorpay. Confirmed by tracing
`payment_handler.dart` — do not assume Cashfree-only.

## Folder Inventory (10 files, ~5500 lines)

```
lib/features/instant_saving/
├── controller/
│   └── saving_controller.dart       Riverpod providers: savingConfigProvider, paymentMethodsProvider,
│                                     instantSavingControllerProvider (StateNotifier — lightly used, see STATE_ANALYSIS)
├── models/
│   └── saving_models.dart           SavingConfig, PaymentMethod, PaymentOrder, EligibilityResponse,
│                                     PurchaseInitiateResponse (multi-gateway response shape)
├── services/
│   └── saving_service.dart          SavingService (savings/* endpoints), PaymentService (payments/* endpoints)
├── instant_saving_screen.dart       route /instant-saving — 1958 lines. Amount entry, GST/weight conversion,
│                                     rate-lock timer UI, denomination chips, "Best Offer" silver-reward block,
│                                     breakdown bottom sheet, Pay Now → eligibility → KYC/payment handoff.
├── payment_handler.dart             PaymentHandler — centralized orchestrator. Calls savings/initiate, routes
│                                     to Cashfree/HDFC/Razorpay by `payment_gateway` field, confirms payment,
│                                     navigates to PurchaseSuccessScreen. THE live payment path (see Drift).
├── hdfc_payment_handler.dart        HdfcPaymentHandler — Juspay HyperSDK integration (pre-warm + openPaymentPage)
├── razorpay_payment_handler.dart    RazorpayPaymentHandler — razorpay_flutter SDK integration
├── screens/
│   ├── payment_methods_screen.dart  route /payment-methods — **[LEGACY, explicitly marked dead in a code
│   │                                 comment]**. Cashfree-only. Registered in app_router but never navigated
│   │                                 to by any live code path (see Drift).
│   └── purchase_success_screen.dart No dedicated route — always reached via `Navigator.pushReplacement` with
│                                     an anonymous `MaterialPageRoute` from one of the 3 payment handlers.
└── widgets/
    └── payment_method_sheet.dart    Bottom sheet — fetches `payments/methods`, lets user pick upi/card/
                                      netbanking BEFORE gateway launch (instrument hint, not gateway choice).
```

## Route Table (from `lib/routes/app_router.dart`)

| Constant | Path | Screen | Registered | Live? |
|---|---|---|---|---|
| `AppRouter.instantSaving` | `/instant-saving` | `InstantSavingScreen` | app_router.dart:73,163 | Yes — entry point |
| `AppRouter.paymentMethods` | `/payment-methods` | `PaymentMethodsScreen` | app_router.dart:88,249-260 | **No — dead route**, see Drift |
| `AppRouter.upiSelection` | `/upi-selection` | `UpiSelectionScreen` (physically lives in `withdrawal/screens/`) | app_router.dart:96,284 | Yes, for `eligibility.nextStep == 'UPI_LIST'` only |
| `AppRouter.kyc` | `/kyc` | `KycScreen` (dynamic hub) | app_router.dart:69,144-152 | Yes, for `eligibility.nextStep == 'KYC_REQUIRED'`, via `KycVerificationFlow.start()` |

`PurchaseSuccessScreen` has no route constant — reached only via `Navigator.pushReplacement(MaterialPageRoute(...))`
from `payment_handler.dart:353`, `hdfc_payment_handler.dart:363`, `razorpay_payment_handler.dart:246`, or the
legacy `payment_methods_screen.dart:104`.

## Architecture / Flow (as actually wired)

```
InstantSavingScreen (/instant-saving)
  amount/weight entry, GST-aware conversion, sellRateTimerProvider lock, denomination chips
      │ tap "Pay Now" → _showPaymentMethodSheet → PaymentMethodSheet (bottom sheet, picks upi/card/netbanking)
      │ tap "Proceed to Pay" → _handleConfirmOrder()
      ▼
  POST savings/check-eligibility (encrypted: mobile, amount_inr)
      │
      ├─ next_step == 'KYC_REQUIRED' → KycVerificationFlow.start() (kyc module, awaited)
      │     └─ on success (true) → PaymentHandler.startPayment(amount, rate, weight, ...)
      ├─ next_step == 'PAYMENT'      → PaymentHandler.startPayment(...) directly
      ├─ next_step == 'UPI_LIST'     → Navigator.pushNamed(AppRouter.upiSelection) [separate flow]
      └─ else                        → PaymentHandler.startPayment(...) (fallback)
      ▼
PaymentHandler.startPayment()
  AppLifecycleObserver.suppressAppLock = true
  POST savings/initiate (encrypted: mobile, amount_inr, weight) → PurchaseInitiateResponse.payment_gateway
      │
      ├─ "cashfree" → CFPaymentGatewayService.doPayment() (Web Checkout)
      ├─ "hdfc"     → HdfcPaymentHandler → HyperSDK.initiate() → HyperSDK.openPaymentPage()
      └─ "razorpay" → RazorpayPaymentHandler → Razorpay().open()
      ▼ (SDK callback: success / error / user-abort)
  AppLifecycleObserver.suppressAppLock = false
  POST savings/confirm-payment (order_id [+ gateway-specific fields])
      ▼
  Navigator.pushReplacement → PurchaseSuccessScreen (isSuccess true/false)
      │ "Back to Home" → pushNamedAndRemoveUntil(AppRouter.main) → 650ms later:
      │   portfolioProvider.fetchPortfolio(), invalidate(homeDashboardProvider), invalidate(profileProvider)
```

Full step-by-step with file:line is in `DATA_FLOW.md` — this is the highest-detail flow in the whole brain
per the build request.

## State Management (see `STATE_ANALYSIS.md` for full detail)

- `savingConfigProvider` — `FutureProvider.autoDispose<SavingConfig>` — `POST savings/config` — GST %, min/max,
  rate-lock durations, payment-method→gateway map.
- `amountDenominationsProvider` / `weightDenominationsProvider` — `POST users/shared/amount-denominations` /
  `weight-denominations` (note: NOT `savings/denominations/*` as the hand-written doc claims — see Drift).
- `sellRateTimerProvider` (`core/providers/timer_provider.dart`) — shared rate-lock timer, used for the
  "sell" side (platform sells to customer, i.e. the price the customer pays). Duration comes from
  `config.sellRateLockSeconds`, itself from `savings/config` — exact seconds value is server-driven and not
  hardcoded in the client; treat any specific number as unconfirmed without reading a live API response.
- `instantSavingControllerProvider` (`InstantSavingNotifier`) — defined in `saving_controller.dart` but its
  `setAmount`/`setTransactionData`/`setSelectedPaymentMethod` methods are **not called anywhere** in the
  screen or handlers found by grep — the screen manages amount/mode entirely via local `State` fields
  (`_amountController`, `_selectedAmount`, `_isAmountMode`). Likely dead/aspirational state.
- `countdownOfferProvider` (`core/providers/countdown_offer_provider.dart`) — drives the "Best Offer" free-
  silver-reward block, gold-only, shown when silver market is open.

## Top Risks / Anti-Patterns Found

1. **Rate can move between eligibility-check and payment-initiate, especially across a KYC detour.**
   `_handleConfirmOrder` captures `rate`/`totalPayable` once, before `check-eligibility`. If `nextStep ==
   'KYC_REQUIRED'`, the user goes through the full KYC hub (PAN + Aadhaar DigiLocker — can take minutes),
   then `PaymentHandler.startPayment` is called with the **original, pre-KYC** `amount` and `rate`. Inside
   `_initiatePurchase` (`payment_handler.dart:144-164`), the **weight** sent to `savings/initiate` is
   recomputed using whichever rate is `activeRate` *at that moment* (a freshly re-locked rate if the timer
   expired during KYC), while `amount_inr` stays the original pre-KYC rupee figure. No re-confirmation screen
   is shown to the user between KYC completion and gateway launch. See `FORENSIC_TEMPLATE.md` and
   `BUSINESS_RULES.md` RULE-INSTANTSAVING-006.
2. **Weight precision mismatch between UI display and payload.** The screen's breakdown (`_computeBreakdown`,
   `instant_saving_screen.dart:1304-1334`) truncates (floor) grams to 6 decimals. `PaymentHandler
   ._initiatePurchase` (and the legacy screen's `_createPaymentOrder`) independently recompute weight via
   `.toStringAsFixed(4)` — **4 decimals, rounded, not truncated**, and it's a second independent calculation,
   not a reuse of the value shown to the user. See RULE-INSTANTSAVING-005.
3. **`SavingConfig.type` ("inclusive"/"exclusive") is parsed but never read** anywhere in the module — the
   actual inclusive/exclusive GST behavior is hardcoded to `_isAmountMode` (₹ mode = back-out GST from total;
   grams mode = add GST on top of metal value), not driven by this config field. Dead data / potential drift
   if the backend ever changes semantics expecting the client to branch on it.
4. **`payment_methods_screen.dart` is dead code reachable only by direct route/deep-link.** It's explicitly
   marked `[LEGACY]` in its own file header, has no `AppLifecycleObserver.suppressAppLock` call (unlike all
   three live handlers), and is Cashfree-only (no HDFC/Razorpay branch). If anything ever calls
   `Navigator.pushNamed(AppRouter.paymentMethods, ...)` again (the call sites are currently commented out in
   `instant_saving_screen.dart:1636,1665`), payments routed through it silently lose app-lock suppression and
   multi-gateway support. Flag for deletion or explicit deprecation once confirmed unused for one more release
   cycle.
5. **No client-side order-cancellation path.** `SavingService.cancelOrder()` (`saving_service.dart:81-86`,
   POST `savings/cancel_order`) is defined but never called anywhere in this module — there is no UI action
   that lets a user explicitly abandon an initiated order before/instead of completing payment.
6. **Portfolio refresh is button-triggered, not automatic**, on the success screen — `purchase_success_screen
   .dart:500-507` only calls `portfolioProvider.fetchPortfolio()` / invalidates `homeDashboardProvider` and
   `profileProvider` when the user taps "Back to Home", 650ms after navigating away. If the app is killed or
   backgrounded from the success screen before that tap, local cached portfolio state does not reflect the
   just-completed purchase until the next natural refresh.
7. **Screenshot protection is app-wide, not per-screen**, for this module — no `ScreenshotSecurityService
   .secureScreen()`/`.releaseScreen()` call anywhere in `instant_saving/`. Relies entirely on the global
   `AppConfig.enableScreenshotProtection` toggle set once at app launch.

## Drift vs `STARTGOLD_DOCUMENTATION.md` §3.11–3.12

| Doc claim | Live code |
|---|---|
| `GET savings/config`, `GET savings/denominations/amount`, `GET savings/denominations/weight` | All calls in this app go through `ApiClient.post(...)` — every "API Integration" in the doc's table is actually a **POST**, including config. Denomination endpoints are `POST users/shared/amount-denominations` / `.../weight-denominations` (`shared_service.dart:134-166`), **not** `savings/denominations/*` as documented. |
| "GST calculation (+3%)" presented as a fixed rate | GST % is a live field (`gst`) in the `savings/config` response, parsed as a double (`saving_models.dart:31`). `3.0` only appears in the codebase as a **UI fallback constant** used before config has loaded (`instant_saving_screen.dart:769`, `payment_handler.dart:161`) — the actual server-configured value is unconfirmed client-side; do not treat 3% as authoritative. |
| §3.12 "Payment Methods Screen … Launches Cashfree/Razorpay payment SDK … Handles payment callbacks" as the live gateway-launch screen | This screen (`payment_methods_screen.dart`) is dead code — explicitly marked `[LEGACY]` in its own header comment, superseded by `PaymentHandler` (`payment_handler.dart`). The live flow never navigates to it (only commented-out `Navigator.pushNamed` calls remain in `instant_saving_screen.dart`). It is also missing HDFC/Razorpay support and the `suppressAppLock` call the live handlers all have. |
| Doc lists only Cashfree/Razorpay for this screen | Live `PaymentHandler` routes to **three** gateways: Cashfree, HDFC SmartGateway (Juspay HyperSDK), and Razorpay, selected by the `payment_gateway` field the backend returns from `savings/initiate` (`payment_handler.dart:199-214`). |
| "Rate locked for configured duration" | Confirmed — but the lock is on the **shared** `sellRateTimerProvider` (`core/providers/timer_provider.dart`), the same timer instance/type used by `withdrawal`'s `buyRateTimerProvider`. Duration is `config.sellRateLockSeconds` from `savings/config`; exact seconds not hardcoded/visible without inspecting a live response. |
| "KYC gate before payment" | Confirmed — `savings/check-eligibility` → `next_step == 'KYC_REQUIRED'` → `KycVerificationFlow.start()` pushes the unified PAN+Aadhaar hub (`kyc` module), same entry point SIP/Withdrawal use. |

See root cause detail for each row in `DATA_FLOW.md` and `BUSINESS_RULES.md`.

## Where to Look Next

- Exact conversion/GST math with every rounding step: `BUSINESS_RULES.md` RULE-INSTANTSAVING-001..004.
- Full request/response shapes and encrypted-field list per endpoint: `DATA_FLOW.md`, `STATE_ANALYSIS.md`.
- Cross-module dependency graph (KYC, core/security, 3 payment SDKs): `CROSS_MODULE_MAP.md`.
- Bug-investigation starting points: `FORENSIC_TEMPLATE.md`.
