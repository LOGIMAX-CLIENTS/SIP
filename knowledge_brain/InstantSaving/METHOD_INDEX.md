---
module: InstantSaving
last_updated: 2026-08-19
---

# InstantSaving — Method Index

Alphabetical by class. `file:line` is the definition site; "Callers" lists in-module call sites found by
grep (cross-module callers noted separately where relevant).

## `EncryptionService` (core/security/encryption_service.dart) — referenced, not owned by this module
See `CROSS_MODULE_MAP.md`.

## `HdfcPaymentHandler` (hdfc_payment_handler.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `launchPayment({purchase, confirmedAmountInr, paymentMethod, onLoadingStart, onLoadingEnd})` | 71 | Public entry. Sets `suppressAppLock=true`, validates `sdkPayload`/`merchantId`/`clientId`, pre-warms SDK, opens payment page. | `PaymentHandler._launchHdfc` (payment_handler.dart:225-232) |
| `_initiateHyperSDK(purchase)` | 125 | Calls `HyperSDK.initiate()` with `merchantId`/`clientId`/`hdfcEnvironment` (defaults `'production'`). | `launchPayment` (once per handler instance, `_isInitiated` guard) |
| `_initiateCallbackHandler(methodCall)` | 149 | Logs the initiate callback; no user-facing action. | `_initiateHyperSDK` |
| `_openPaymentPage(purchase, paymentMethod)` | 158 | Deep-copies `sdkPayload`, overrides `returnUrl` to `about:blank`, applies `payment_filter`/`paymentMethod` restriction if `paymentMethod` given, calls `HyperSDK.openPaymentPage()`. | `launchPayment` |
| `_hyperSDKCallbackHandler(methodCall)` | 235 | Dispatches SDK callbacks (`hide_loader`, `process_result`, `initiate_result`, `microapp_versions`). | Passed as callback to `openPaymentPage` |
| `_handleProcessResult(methodCall)` | 269 | Sets `suppressAppLock=false`. Parses `status`/`orderId`. `backpressed`/`user_aborted` with empty `orderId` → navigate straight to failure `PurchaseSuccessScreen`; otherwise (any status incl. success) → `_confirmAndNavigate`. | `_hyperSDKCallbackHandler` |
| `_confirmAndNavigate(orderId, {sdkStatus})` | 335 | `POST savings/confirm-payment`, then `Navigator.pushReplacement` to `PurchaseSuccessScreen` (success or failure data shape). | `_handleProcessResult` |

## `KycVerificationFlow` (features/kyc/kyc_flow.dart) — cross-module, invoked here

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `start(context, ref, {requestFrom, extraData})` → `Future<bool>` | 20 | Pushes `AppRouter.kyc` with `request_from` + `extraData` (amount, metal_id, rate, buy_type, weight). Refreshes `profileProvider` on completion. Returns `true` only when both PAN + Aadhaar approved. | `InstantSavingScreen._handleConfirmOrder` (instant_saving_screen.dart:1601) |

## `PaymentHandler` (payment_handler.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `startPayment({amount, metalId, rate, buyType, weight, couponCode, paymentMethod, onLoadingStart, onLoadingEnd})` | 81 | Public entry point. Registers Cashfree callbacks, sets `suppressAppLock=true`, calls `_initiatePurchase`. | `InstantSavingScreen._handleConfirmOrder` (3 call sites: KYC-done path 1619, PAYMENT path 1640, fallback path 1669) |
| `_initiatePurchase({amount, metalId, rate, buyType, weight, couponCode, paymentMethod})` | 132 | Computes `activeRate` (timer-locked if active, else passed-in `rate`). Computes `weightForApi` — grams mode: `weight.toStringAsFixed(4)`; amount mode: `((amount/(1+gstRate))/activeRate).toStringAsFixed(4)`. Calls `SavingService.initiatePurchase`. Resolves gateway from `purchase.paymentGateway`, falling back to `config.paymentMethods[paymentMethod]` if empty/unrecognized. Dispatches to `_launchHdfc`/`_launchRazorpay`/`_launchCashfree`. | `startPayment` |
| `_launchHdfc(purchase, confirmedAmount, paymentMethod)` | 222 | Delegates to `HdfcPaymentHandler.launchPayment`. | `_initiatePurchase` |
| `_launchRazorpay(purchase, confirmedAmount, paymentMethod)` | 239 | Delegates to `RazorpayPaymentHandler.launchPayment`. | `_initiatePurchase` |
| `_launchCashfree(purchase)` | 256 | Builds `CFSession`/`CFWebCheckoutPayment`, calls `CFPaymentGatewayService.doPayment()`. | `_initiatePurchase` |
| `_onCashfreeSuccess(orderId)` | 300 | Sets `suppressAppLock=false`, calls `_confirmAndNavigate(orderId)`. | Cashfree SDK callback |
| `_onCashfreeError(errorResponse, orderId)` | 310 | Sets `suppressAppLock=false`, calls `_confirmAndNavigate(orderId, wasError: true, ...)`. | Cashfree SDK callback |
| `_confirmAndNavigate(orderId, {wasError, fallbackErrorMsg})` | 326 | `POST savings/confirm-payment`, navigates to `PurchaseSuccessScreen`. `isSuccess = !wasError && response?['success']==true`. | `_onCashfreeSuccess`, `_onCashfreeError` |

## `PaymentMethodSheet` (widgets/payment_method_sheet.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `_buildMethodsList(methods)` | 184 | Merges API methods with `_defaultMethods` fallback, applies `allowedMethodIds` filter and `isRecurring` relabeling. | `build` |
| `_relabelForRecurring(method)` | 464 | Relabels `netbanking` → "eMandate (Netbanking)" — SIP-only, `isRecurring=false` for this module so it's a no-op here. | `_buildMethodsList` |
| `onProceed` callback (constructor param) | 40 | Fired on "Proceed to Pay" tap with the selected method id (`upi`/`card`/`netbanking`). | `InstantSavingScreen._showPaymentMethodSheet` → `_handleConfirmOrder` |

## `PaymentMethodsScreen` (screens/payment_methods_screen.dart) — **LEGACY, dead route**

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `_createPaymentOrder()` | 207 | Cashfree-only initiate + launch, no `suppressAppLock`. | Screen's own "Pay" button — unreachable in practice (see MODULE_BRAIN §Drift) |
| `_verifyPayment(orderId)` / `_onPaymentError(...)` | 90 / 166 | Cashfree callback → `savings/confirm-payment` → `PurchaseSuccessScreen`. | Cashfree SDK callback (only fires if this screen is ever reached) |
| `_handleRateExpiry()` / `_onRateUpdated(config)` | 326 / 337 | Re-locks rate on entry / on timer expiry. | `initState`, `ref.listen(sellRateTimerProvider)` |

## `RazorpayPaymentHandler` (razorpay_payment_handler.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `launchPayment({purchase, confirmedAmountInr, paymentMethod, onLoadingStart, onLoadingEnd})` | 77 | Sets `suppressAppLock=true`, builds Razorpay `options` (amount in **paise**: `(confirmedAmountInr*100).toInt()`), applies `_singleMethodConfig` instrument restriction, calls `Razorpay().open()`. | `PaymentHandler._launchRazorpay` |
| `_singleMethodConfig(method)` | 151 | Builds a Checkout `config.display` block restricting UI to one instrument (`show_default_blocks:false`). | `launchPayment` |
| `_handlePaymentSuccess(response)` | 179 | `_confirmAndNavigate` with `rzPaymentId`/`rzSignature`/`rzOrderId`. | Razorpay SDK event |
| `_handlePaymentError(response)` | 190 | `_confirmAndNavigate` with `fallbackErrorMsg`. | Razorpay SDK event |
| `_handleExternalWallet(response)` | 202 | Ends loading, clears SDK — no confirm call (wallet flow incomplete/pending). | Razorpay SDK event |
| `_confirmAndNavigate(orderId, {rzPaymentId, rzSignature, rzOrderId, fallbackErrorMsg})` | 212 | `POST savings/confirm-payment` with Razorpay verification fields, navigates to `PurchaseSuccessScreen`. | `_handlePaymentSuccess`, `_handlePaymentError` |

## `SavingService` (services/saving_service.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `getSavingConfig()` → `SavingConfig` | 8 | `POST savings/config`. | `savingConfigProvider` (saving_controller.dart:8-11) |
| `checkEligibility({customerId, metalId, mobile, amount, rate, couponCode})` → `EligibilityResponse` | 16 | `POST savings/check-eligibility` — encrypted endpoint. | `InstantSavingScreen._handleConfirmOrder` (instant_saving_screen.dart:1583) |
| `initiatePurchase({customerId, metalId, mobile, buyType, amount, rate, weight, couponCode, paymentMethod})` → `PurchaseInitiateResponse` | 37 | `POST savings/initiate` — encrypted endpoint. | `PaymentHandler._initiatePurchase`, legacy `PaymentMethodsScreen._createPaymentOrder` |
| `confirmPayment(orderId, {razorpayPaymentId, razorpaySignature, razorpayOrderId})` → raw `Map` | 66 | `POST savings/confirm-payment`. | All 3 handlers' `_confirmAndNavigate`, legacy screen's `_verifyPayment`/`_onPaymentError` |
| `cancelOrder(orderId)` → raw `Map` | 81 | `POST savings/cancel_order`. | **No callers found in this module — dead method.** |

## `PaymentService` (services/saving_service.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `getPaymentMethods()` → `List<PaymentMethod>` | 92 | `POST payments/methods`. | `paymentMethodsProvider` (saving_controller.dart:13-16) → `PaymentMethodSheet` |
| `createOrder({amount, methodId, transactionId})` → `PaymentOrder` | 102 | `POST payments/create-order`. | **No callers found — dead method** (legacy `PaymentOrder`/`payment_url` flow, superseded by `savings/initiate`). |
| `verifyPaymentStatus(orderId)` → `String` | 115 | `POST payments/status`. | **No callers found — dead method.** |

## `InstantSavingScreen` (instant_saving_screen.dart) — key private methods only (widget-builder methods omitted)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `initState` | 51 | Applies deep-link `initialAmount` arg; on first frame, clears + restarts `sellRateTimerProvider` with fresh live rate (unless market closed); invalidates `savingConfigProvider`/denomination providers. | Flutter lifecycle |
| `_computeBreakdown(market, type, configAsync)` → `Map<String,double>` | 1304 | GST-aware amount↔weight breakdown — see `BUSINESS_RULES.md` RULE-INSTANTSAVING-001/002 for the exact formula. | `_showBreakdownSheet`, `_buildBottomAction` |
| `_showBreakdownSheet(...)` | 1336 | Shows `_BreakdownSheet` (private `StatelessWidget`, same file) with computed totals; its "Pay Now" closes the sheet and calls `_showPaymentMethodSheet`. | Footer "₹Amount" dropdown tap |
| `_showPaymentMethodSheet(market, type, totalPayable, config, grams)` | 1530 | Shows `PaymentMethodSheet`; `onProceed` → `_handleConfirmOrder`. | `_showBreakdownSheet`'s Pay Now, footer "Pay Now" pill |
| `_handleConfirmOrder(market, type, totalPayable, config, [grams, paymentMethod])` | 1550 | The orchestration method — see `MODULE_BRAIN.md` flow diagram and `DATA_FLOW.md` for full trace. Calls `checkEligibility`, branches on `next_step`, invokes `KycVerificationFlow.start` and/or `PaymentHandler.startPayment`. | Pay Now / breakdown sheet Pay Now |
| `_trunc6(v)` / `_trunc2(v)` (static) | 1698 / 1699 | Floor-truncation helpers — 6dp for weight, 2dp for money. **Not rounding.** | `_computeBreakdown`, `_buildAmountInputCard`, `_buildBestOfferBlock` |

## `PurchaseSuccessScreen` (screens/purchase_success_screen.dart)

| Method | Line | Purpose | Callers |
|---|---|---|---|
| `_buildBottomButton(context, isSuccess)` | 481 | "Back to Home" (success): `pushNamedAndRemoveUntil(AppRouter.main)`, then 350ms → switch to Home tab, then 650ms → `portfolioProvider.fetchPortfolio()` + invalidate `homeDashboardProvider`/`profileProvider`. "Try Again" (failure): same navigation, switches to Invest tab instead, **no portfolio refresh**. | Screen's own bottom button |
