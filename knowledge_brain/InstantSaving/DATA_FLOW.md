---
module: InstantSaving
last_updated: 2026-08-19
note: This is the highest-priority DATA_FLOW.md in the brain — InstantSaving is the core revenue screen.
      Every step below is traced to file:line in live code, not inferred from the hand-written doc.
---

# InstantSaving — Data Flow

## Flow 1: Screen load → live rate lock → denomination seed

```
InstantSavingScreen.initState (instant_saving_screen.dart:51-93)
  │
  ├─ WidgetsBinding.instance.addPostFrameCallback:
  │    read commodityProvider → entryCommodityId ('1' gold / '3' silver)
  │    read marketStatusProvider → if commodity is NOT closed:
  │       sellRateTimerProvider.notifier.clear()                          (timer_provider.dart:107-111)
  │       sellRateTimerProvider.notifier.startOrRefresh(config.sellRateLockSeconds)
  │         → reads marketRatesStreamProvider (live socket rate) and freezes it in TimerState.lockedRates
  │           (timer_provider.dart:41-59) — this is the "rate lock"
  │    ref.invalidate(savingConfigProvider)          → re-triggers POST savings/config
  │    ref.invalidate(amountDenominationsProvider)   → re-triggers POST users/shared/amount-denominations
  │    ref.invalidate(weightDenominationsProvider)   → re-triggers POST users/shared/weight-denominations
  ▼
build() (instant_saving_screen.dart:102 onward)
  │  ref.listen(savingConfigProvider) → if config loaded and timer NOT active → startOrRefresh(sellRateLockSeconds)
  │  ref.listen(commodityProvider)    → on Gold/Silver switch: clear input, clear+restart timer
  │  ref.listen(marketStatusProvider) → on closed→open transition: clear+restart timer (fresh rate)
  │  ref.listen(marketRatesStreamProvider) → race-condition guard: if timer locked a 0.0 rate (arrived before
  │     first socket price frame), restart as soon as a non-zero rate lands (instant_saving_screen.dart:198-223)
  │  ref.listen(amountDenominationsProvider / weightDenominationsProvider) → seed the input field with the
  │     `is_popular` denomination's value once data arrives (instant_saving_screen.dart:225-260)
  ▼
displayRates = isMarketClosed ? liveMarket : (timerState.lockedRates ?? liveMarket)   (line 277-280)
  → the price shown to the user, and the rate all downstream math uses, is the LOCKED rate whenever the
    market is open and the timer is active; only falls back to the raw live socket rate when the market is
    closed or before the first lock completes.
```

**Rate lock duration**: sourced from `SavingConfig.sellRateLockSeconds` (`saving_models.dart:6,33`),
itself parsed from the `sell_rate_lock_seconds` field of the `POST savings/config` response
(`saving_service.dart:8-14`). **The exact numeric value is server-driven and not visible in client source —
unconfirmed without inspecting a live API response.** The client has no hardcoded fallback for this value
(`SavingConfig.fromJson` defaults it to `0` if absent, which `RateTimerNotifier.startOrRefresh` treats as
"do nothing", `timer_provider.dart:42`).

## Flow 2: Amount/weight entry → GST-aware conversion (the single most important calculation in this module)

Two independent call sites compute the same conversion with the **same formula** but at different precision
truncation stages — both must be understood together.

### 2a. Live inline conversion + validation (while typing) — `_buildAmountInputCard`, lines 754-981

```
inputVal = double.tryParse(_amountController.text) ?? 0.0
gstRate  = configAsync.valueOrNull?.gst ?? 3.0          // 3.0 = UI-safety fallback ONLY, real value is server-driven
rate     = type==gold ? market.goldSell : market.silverSell   (the LOCKED rate from Flow 1)

if _isAmountMode (user typed ₹):
    goldValue  = _trunc2( inputVal / (1 + gstRate/100) )        // back out GST from the typed total
    conversion = _trunc6( goldValue / rate )                    // → grams shown as "x.xxxxxxgm" hint
else (user typed grams):
    conversion = _trunc2( inputVal * rate )                     // → ₹ shown as hint (GST NOT added here —
                                                                 //   this is a display-only estimate, differs
                                                                 //   from the authoritative breakdown below)
```
`instant_saving_screen.dart:761-774`.

Inline min/max validation (`instant_saving_screen.dart:780-795`): if amount mode, `comparable = inputVal`
directly; if grams mode, `comparable = inputVal * rate` (no GST added) — compared against
`config.minAmount`/`config.maxAmount`. **Note**: this grams-mode comparison excludes GST, while the
authoritative breakdown below (2b) computes the true GST-inclusive total for the same input — for values near
a min/max boundary in grams mode, the inline error message and the footer's `isInvalid` (which uses the
GST-inclusive breakdown) can theoretically disagree for one render frame. Not confirmed as a live bug, but
the two code paths are not unified.

### 2b. Authoritative breakdown (drives Pay Now / breakdown sheet) — `_computeBreakdown`, lines 1304-1334

```
gstRate = config.gst / 100
rate    = locked rate for current commodity

if _isAmountMode:
    totalPayable = _trunc2(inputVal)                     // user's typed ₹ IS the GST-inclusive total
    metalValue   = _trunc2( totalPayable / (1 + gstRate) )
    gstAmount    = _trunc2( totalPayable - metalValue )
    grams        = rate>0 ? _trunc6( metalValue / rate ) : 0.0
else (grams mode):
    grams        = _trunc6(inputVal)
    metalValue   = _trunc2( grams * rate )
    gstAmount    = _trunc2( metalValue * gstRate )
    totalPayable = _trunc2( metalValue + gstAmount )
```
Truncation helpers (`instant_saving_screen.dart:1698-1699`) are **floor-based, not round-based**:
`_trunc2(v) = floor(v*100)/100`, `_trunc6(v) = floor(v*1000000)/1000000`.

`isInvalid` gate for the Pay Now button and breakdown sheet: `totalPayable < config.minAmount ||
totalPayable > config.maxAmount || totalPayable <= 0` (`instant_saving_screen.dart:1395-1397`,
1352-1355 in the sheet).

**`SavingConfig.type`** (`"inclusive"`/`"exclusive"`, `saving_models.dart:5,32`) is parsed from the API but
**never read** anywhere in this computation — the inclusive-vs-exclusive behavior is hardcoded to
`_isAmountMode`, not driven by this config field. See `BUSINESS_RULES.md` RULE-INSTANTSAVING-003.

GST %: `config.gst` — a `double` parsed via `double.tryParse(json['gst']?.toString() ?? '0') ?? 0.0`
(`saving_models.dart:31`) from the `savings/config` response's `gst` field. **The live numeric value is
server-driven; the `3.0` literal seen throughout the code (`instant_saving_screen.dart:769,1033`,
`payment_handler.dart:161`, legacy `payment_methods_screen.dart:231`) is only a pre-load UI fallback, never
the source of truth.** Treat any claim of "GST is 3%" as unconfirmed without a live `savings/config` response.

## Flow 3: Pay Now → payment-method pick → eligibility check → KYC gate

```
User taps footer "Pay Now" pill (enabled only if !isInvalid && !_isProcessing)
  → _showPaymentMethodSheet(market, type, totalPayable, config, grams)   (line 1465-1466)
  → showModalBottomSheet(PaymentMethodSheet(onProceed: (method) => _handleConfirmOrder(..., method)))
                                                                          (line 1530-1548)
       PaymentMethodSheet fetches paymentMethodsProvider → POST payments/methods (widgets/payment_method_sheet.dart)
       User picks upi/card/netbanking (default preselected: 'upi', line 72), taps "Proceed to Pay"
  ▼
_handleConfirmOrder(market, type, totalPayable, config, grams, paymentMethod)   (line 1550-1694)
  setState(_isProcessing = true)   → screen renders full-screen "Processing Payment..." overlay (line 285-380)
  rate = locked rate for current commodity (from the `market` param, itself the locked rate from Flow 1)
  customerId/mobile = userProvider (core/providers/user_provider.dart)
  metalId = selectedMetalIdProvider (dynamic id_metal from commoditiesProvider, fallback '1'/'3')
  if customerId empty or rate==0 → abort with toast "Market rates not ready." (no API call made)
  ▼
  POST savings/check-eligibility   (saving_service.dart:16-35)
    payload: { id_customer, id_metal, mobile, amount_inr: totalPayable, rate_per_gram: rate,
               device_id: 'device-id-placeholder', coupon_code, request_from: 'instant' }
    ENCRYPTED FIELDS (via api_interceptor.dart + encryption_service.dart, RSA-OAEP-SHA256):
       'mobile', 'amount_inr'  — both are in AppConfig.sensitiveFields (app_config.dart:74-99)
    NOT encrypted: id_customer, id_metal, rate_per_gram, device_id, coupon_code, request_from
       (rate_per_gram is NOT in sensitiveFields — only 'buy_rate' is, and that key is used by withdrawal,
       not this endpoint)
  ◀ response: { next_step: 'KYC_REQUIRED' | 'PAYMENT' | 'UPI_LIST' | other }
  setState(_isProcessing = false)
  ▼
  branch on eligibility.nextStep:
  ┌─ 'KYC_REQUIRED' ─────────────────────────────────────────────────────────────────────────────┐
  │  kycDone = await KycVerificationFlow.start(context, ref, requestFrom:'instant',                │
  │      extraData: { amount: totalPayable, metal_id, rate, buy_type: isAmountMode?1:2, weight })  │
  │    → Navigator.pushNamed(AppRouter.kyc, arguments) → KycScreen (kyc module — unified PAN+       │
  │      Aadhaar hub). Pops `true` only when BOTH approved.                                         │
  │  if kycDone == true → PaymentHandler(ref,context).startPayment(amount: totalPayable,             │
  │      metalId, rate, buyType, weight: grams, paymentMethod, onLoadingStart/End)                   │
  │    ⚠ amount/rate here are the values captured BEFORE the KYC detour — see RULE-INSTANTSAVING-006 │
  └───────────────────────────────────────────────────────────────────────────────────────────────┘
  ┌─ 'PAYMENT' ───────────────────────────────────────────────────────────────────────────────────┐
  │  PaymentHandler(ref,context).startPayment(...) directly, same params.                            │
  └───────────────────────────────────────────────────────────────────────────────────────────────┘
  ┌─ 'UPI_LIST' ──────────────────────────────────────────────────────────────────────────────────┐
  │  Navigator.pushNamed(AppRouter.upiSelection, arguments: {amount, metal_id, rate, buy_type,       │
  │      weight})  — a SEPARATE flow (screen physically lives in withdrawal/screens/, per Withdrawal │
  │      module brain it's registered in app_router.dart:96,284; not further traced in this brain).  │
  └───────────────────────────────────────────────────────────────────────────────────────────────┘
  ┌─ else (unknown value) ────────────────────────────────────────────────────────────────────────┐
  │  Fallback → PaymentHandler.startPayment(...), same as 'PAYMENT'.                                  │
  └───────────────────────────────────────────────────────────────────────────────────────────────┘
  catch (e): setState(_isProcessing=false), toast with e.message (if Failure) or generic message
```

## Flow 4: PaymentHandler.startPayment → savings/initiate → gateway selection → SDK launch

```
PaymentHandler.startPayment({amount, metalId, rate, buyType, weight, couponCode, paymentMethod,
                              onLoadingStart, onLoadingEnd})              (payment_handler.dart:81-126)
  _cfPaymentGatewayService.setCallback(_onCashfreeSuccess, _onCashfreeError)   // registered BEFORE initiate
  onLoadingStart?.call()
  AppLifecycleObserver.suppressAppLock = true      (app_lifecycle_observer.dart:39; set here so leaving the
                                                     app for a UPI-app intent doesn't trigger MPIN re-lock)
  ▼
  _initiatePurchase(...)                            (payment_handler.dart:132-216)
    timerState = ref.read(sellRateTimerProvider)
    activeRate = timerState.isActive ? timerState.lockedRates[gold?goldSell:silverSell] : rate (passed-in)
       ⚠ this can differ from the `rate` used to compute `amount`/`totalPayable` in Flow 3 if the rate-lock
         timer expired and re-locked during a KYC detour — see RULE-INSTANTSAVING-006.
    weightForApi:
       buyType==2 (GRAMS): double.parse(weight.toStringAsFixed(4))                 // 4dp, ROUNDED not truncated
       buyType==1 (AMOUNT): gstRate=(config?.gst ?? 3.0)/100
                             raw = (amount / (1+gstRate)) / activeRate
                             weightForApi = double.parse(raw.toStringAsFixed(4))   // 4dp, ROUNDED, recomputed
                                                                                    // independently of the 6dp
                                                                                    // TRUNCATED value shown to
                                                                                    // the user in Flow 2b
    ▼
    POST savings/initiate   (saving_service.dart:37-64)
      payload: { id_customer, id_metal, mobile, buy_type (1|2), amount_inr: amount.toStringAsFixed(2),
                 rate_per_gram: activeRate, weight: weightForApi, device_id, coupon_code, request_from:'instant',
                 payment_method? }
      ENCRYPTED FIELDS: 'mobile', 'amount_inr', 'weight' (all three in AppConfig.sensitiveFields)
      NOT encrypted: id_customer, id_metal, buy_type, rate_per_gram, device_id, coupon_code, request_from,
                     payment_method
    ◀ response → PurchaseInitiateResponse (saving_models.dart:107-167):
        orderId, sessionId, environment, amountInr, weight, ratePerGram,
        paymentGateway ("cashfree"|"hdfc"|"razorpay", default "cashfree" if absent),
        sdkPayload/merchantId/clientId/hdfcEnvironment (HDFC only),
        rzOrderId/keyId (Razorpay only)
    confirmedAmount = double.tryParse(purchase.amountInr) ?? amount    // SERVER-CONFIRMED amount is authoritative
    ▼
    gateway = purchase.paymentGateway
    if gateway empty/unrecognized → fall back to config.paymentMethods[paymentMethod] map (from savings/config)
    ┌─ gateway=="hdfc" ────────────┬─ gateway=="razorpay" ─────────┬─ else ("cashfree") ─────────────┐
    │ _launchHdfc(purchase,        │ _launchRazorpay(purchase,     │ _launchCashfree(purchase)         │
    │   confirmedAmount,method)    │   confirmedAmount, method)    │   — builds CFSession(orderId,      │
    │ → HdfcPaymentHandler         │ → RazorpayPaymentHandler      │   sessionId, env) → doPayment()    │
    │   .launchPayment(...)        │   .launchPayment(...)         │                                    │
    └───────────────────────────────┴────────────────────────────────┴────────────────────────────────┘
```

### 4a. HDFC (Juspay HyperSDK) path — `hdfc_payment_handler.dart`

```
launchPayment: suppressAppLock=true (redundant re-set, already true from PaymentHandler)
  validate sdkPayload/merchantId/clientId present, else toast + suppressAppLock=false + abort
  if !_isInitiated: HyperSDK().initiate({merchantId, clientId, environment: hdfcEnvironment ?? 'production'})
  _openPaymentPage:
    deep-copy sdkPayload; payload.returnUrl = 'about:blank'  (WebView return URL neutralized — the app
      handles the real confirmation via the SDK's native `process_result` callback with the auth token,
      NOT via the returnUrl hitting the backend unauthenticated)
    if paymentMethod given: map to Juspay paymentMethodType (UPI/CARD/NB), apply payment_filter restricting
      the SDK's own UI to that instrument
    HyperSDK().openPaymentPage(sdkPayload, _hyperSDKCallbackHandler)
  ▼ SDK callback 'process_result':
    suppressAppLock=false
    status/orderId parsed from methodCall.arguments (JSON string or map)
    if status in {'backpressed','user_aborted'} AND orderId empty → straight to failure PurchaseSuccessScreen
      (no confirm-payment call — nothing to confirm, order was never created server-side at this state)
    else (any other status, including success) → _confirmAndNavigate(orderId, sdkStatus: status)
  ▼
  _confirmAndNavigate: POST savings/confirm-payment → PurchaseSuccessScreen (success/failure per response['success'])
```

### 4b. Razorpay path — `razorpay_payment_handler.dart`

```
launchPayment: suppressAppLock=true
  keyId = purchase.keyId; rzOrderId = purchase.rzOrderId ?? purchase.sessionId
  options = { key: keyId, amount: (confirmedAmountInr*100).toInt() [paise], name:'startGOLD',
              order_id: rzOrderId, prefill:{contact,email}, config: singleMethodConfig(paymentMethod) }
  Razorpay().open(options)
  ▼ SDK events:
    EVENT_PAYMENT_SUCCESS  → _confirmAndNavigate(orderId, rzPaymentId, rzSignature, rzOrderId)
    EVENT_PAYMENT_ERROR    → _confirmAndNavigate(orderId, fallbackErrorMsg: response.message)
    EVENT_EXTERNAL_WALLET  → just ends loading + clears SDK, NO confirm-payment call (wallet flow pending —
                              a wallet-paid order may never reach confirm-payment from the client; server-side
                              webhook is presumably the source of truth for that case, unconfirmed)
  ▼
  _confirmAndNavigate: POST savings/confirm-payment { order_id, razorpay_payment_id?, razorpay_signature?,
      razorpay_order_id? } → PurchaseSuccessScreen
```
`savings/confirm-payment` is encrypted by the interceptor's **substring** match on the endpoint list entry
`'payment'` (`app_config.dart:61`) — `path.contains(e)` in `api_interceptor.dart:134` means any path
containing the literal substring `"payment"` gets its sensitive fields encrypted, so `savings/confirm-payment`,
`payments/methods`, `payments/create-order`, `payments/status` are all covered by this one generic entry
even though none of them appear by exact name in `AppConfig.encryptedEndpoints`.

### 4c. Cashfree path — `payment_handler.dart:256-320`

```
_launchCashfree: CFSessionBuilder(environment, orderId, sessionId).build() → CFWebCheckoutPaymentBuilder().build()
  → _cfPaymentGatewayService.doPayment(...)   (loading indicator stays active — cleared in the callback)
  ▼ SDK callback (registered in startPayment, BEFORE initiate):
    _onCashfreeSuccess(orderId): suppressAppLock=false → _confirmAndNavigate(orderId)
    _onCashfreeError(errorResponse, orderId): suppressAppLock=false →
      _confirmAndNavigate(orderId, wasError:true, fallbackErrorMsg:'Payment failed for order $orderId...')
  ▼
  _confirmAndNavigate: POST savings/confirm-payment → isSuccess = !wasError && response['success']==true
    → PurchaseSuccessScreen
```

## Flow 5: confirm-payment → PurchaseSuccessScreen → post-purchase state refresh

```
All 3 handlers converge on the same shape:
  response = await SavingService.confirmPayment(orderId, [gateway-specific fields])
  onLoadingEnd?.call()
  isSuccess = response?['success'] == true   (Cashfree also ANDs with !wasError)
  Navigator.pushReplacement(MaterialPageRoute(builder: (_) => PurchaseSuccessScreen(data: {...})))
    success data: { isSuccess:true, orderId, weight: grams_credited|credited_weight|weight,
                     message, commodity_name, total_amount, rate, payment_mode }
    failure data: { isSuccess:false, orderId, message }
  ⚠ Note: PurchaseSuccessScreen is reached via an ANONYMOUS MaterialPageRoute (no `settings.name`) — any
    code elsewhere relying on `ModalRoute.of(context)?.settings.name` to detect "we're on the success screen"
    (e.g. `popUntil` by route name) will not match it. purchase_success_screen.dart's own back-navigation
    logic works around this with `pushNamedAndRemoveUntil(AppRouter.main, (route)=>false)` instead of `popUntil`.
  ▼
  User taps "Back to Home" (success) or "Try Again" (failure)   (purchase_success_screen.dart:481-527)
    Navigator.pushNamedAndRemoveUntil(AppRouter.main, (route)=>false)   [clears entire nav stack]
    +350ms: selectedTabProvider.state = 0 (Home) or 1 (Invest)
    +650ms (SUCCESS ONLY): portfolioProvider.fetchPortfolio(), invalidate(homeDashboardProvider),
                            invalidate(profileProvider)
    → this is the ONLY point in the entire purchase flow where cached portfolio/dashboard state is
      refreshed; nothing on confirm-payment success itself triggers a refresh. See MODULE_BRAIN risk #6.
```

## Encrypted-field summary (all three `savings/*` calls this module makes)

| Endpoint | Encrypted fields | Not encrypted |
|---|---|---|
| `savings/check-eligibility` | `mobile`, `amount_inr` | `id_customer`, `id_metal`, `rate_per_gram`, `device_id`, `coupon_code`, `request_from` |
| `savings/initiate` | `mobile`, `amount_inr`, `weight` | `id_customer`, `id_metal`, `buy_type`, `rate_per_gram`, `device_id`, `coupon_code`, `request_from`, `payment_method` |
| `savings/confirm-payment` | none of its fields are in `AppConfig.sensitiveFields` by name, but the endpoint matches the generic `'payment'` substring entry so the interceptor still runs `encryptJson` over the payload — with no matching field names, `encryptJson` is a no-op pass-through (`encryption_service.dart:109-126`) | `order_id`, `razorpay_payment_id`, `razorpay_signature`, `razorpay_order_id` (effectively sent plaintext) |

Source: `app_config.dart:47-99` (`encryptedEndpoints`, `sensitiveFields`), `api_interceptor.dart:132-138,165-182`,
`encryption_service.dart:109-126`.
