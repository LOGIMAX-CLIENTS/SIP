---
module: InstantSaving
last_updated: 2026-08-19
---

# InstantSaving — Business Rules

Each rule: plain-English statement + the exact code that implements it. Where a value is server-driven and
not visible client-side, this is stated explicitly rather than guessed.

## RULE-INSTANTSAVING-001 — Amount-mode conversion (₹ entered → grams)

When the user types a rupee amount ("Buy in Rupees"), that typed value is treated as the **GST-inclusive
total payable**. GST is backed out to get the metal value, which is then divided by the locked rate to get
grams.

```
totalPayable = trunc2(inputVal)
metalValue   = trunc2( totalPayable / (1 + gstRate/100) )
gstAmount    = trunc2( totalPayable - metalValue )
grams        = trunc6( metalValue / rate )
```
`instant_saving_screen.dart:1316-1320` (authoritative, drives Pay Now) and a lighter-weight duplicate for the
live input hint at `instant_saving_screen.dart:768-771`. `trunc2`/`trunc6` are **floor**, not round
(`instant_saving_screen.dart:1698-1699`).

## RULE-INSTANTSAVING-002 — Grams-mode conversion (grams entered → ₹)

When the user types a weight ("Buy in Grams"), GST is added on top of the metal value.

```
grams        = trunc6(inputVal)
metalValue   = trunc2( grams * rate )
gstAmount    = trunc2( metalValue * gstRate/100 )
totalPayable = trunc2( metalValue + gstAmount )
```
`instant_saving_screen.dart:1321-1325`.

## RULE-INSTANTSAVING-003 — GST rate is server-driven; `SavingConfig.type` field is unused

`gst` comes from `POST savings/config` (`saving_service.dart:8-14`), parsed as
`double.tryParse(json['gst']?.toString() ?? '0') ?? 0.0` (`saving_models.dart:31`). **The exact percentage is
not hardcoded anywhere in the client and its live value was not observed in this review — do not state "GST
is 3%" as fact.** The literal `3.0` that appears at `instant_saving_screen.dart:769,1033`,
`payment_handler.dart:161`, and legacy `payment_methods_screen.dart:231` is a **UI-only fallback** used
before `savingConfigProvider` resolves; it is never sent to the server and never used once config has loaded.

`SavingConfig.type` (`"inclusive"`/`"exclusive"`, `saving_models.dart:5,32`) is parsed from the API response
but **not read anywhere** in the conversion logic — RULE-INSTANTSAVING-001/002's inclusive-vs-exclusive
behavior is hardcoded to which entry mode (`_isAmountMode`) the user is in, not driven by this field. If the
backend ever intends `type` to switch behavior independent of entry mode, the client does not honor it.

## RULE-INSTANTSAVING-004 — Min/max validation is entirely server-config-driven

`config.minAmount` / `config.maxAmount` (from `savings/config`, `min_amount`/`max_amount` fields,
`saving_models.dart:29-30`) gate:
- Inline error text while typing (`instant_saving_screen.dart:788-793`) — compares `inputVal` directly in
  amount mode, or `inputVal * rate` (no GST) in grams mode.
- The footer Pay Now button and breakdown sheet's disabled state — compares the **GST-inclusive**
  `totalPayable` from `_computeBreakdown` against `minAmount`/`maxAmount`
  (`instant_saving_screen.dart:1395-1397`, 1352-1355). These two comparisons use different bases (grams-mode
  inline check excludes GST; the authoritative gate includes it) and are not unified into one function —
  flagged as a maintainability risk, not a confirmed bug.

No client-side min/max constant exists anywhere in this module; both bounds must come from a live
`savings/config` response.

## RULE-INSTANTSAVING-005 — Weight sent to the server is recomputed independently of the weight shown to the user, at lower precision

The value the user sees in the breakdown sheet (`grams`, from RULE-001/002, 6-decimal **floor-truncated**) is
**not** the value transmitted in `savings/initiate`. `PaymentHandler._initiatePurchase`
(`payment_handler.dart:153-164`) recomputes weight from scratch:

```
buyType==2 (GRAMS mode): weightForApi = double.parse(weight.toStringAsFixed(4))      // 4dp, ROUNDED
buyType==1 (AMOUNT mode): raw = (amount / (1 + gstRate/100)) / activeRate
                          weightForApi = double.parse(raw.toStringAsFixed(4))         // 4dp, ROUNDED
```
Two precision mismatches versus the UI: (a) 4 decimal places vs 6 shown to the user, and (b)
`toStringAsFixed` **rounds**, while the UI's `_trunc6`/`_trunc2` **floor**. The same independent
recomputation exists in the legacy `payment_methods_screen.dart:226-234` (`_createPaymentOrder`). If the
backend's own rounding/truncation convention differs from either, the grams actually credited
(`response['data']['grams_credited']`) can differ from what the breakdown sheet displayed pre-payment.

## RULE-INSTANTSAVING-006 — Rate used for weight calculation can be re-locked mid-flow, after the user has already seen and accepted an amount based on the earlier rate

Sequence: `_handleConfirmOrder` captures `rate` (the currently locked rate) once, before calling
`check-eligibility`. If the response is `KYC_REQUIRED`, execution suspends on `KycVerificationFlow.start()` —
an `await` on the full PAN+Aadhaar KYC hub, which can take minutes. **No re-confirmation of amount/rate is
shown after KYC completes.** `PaymentHandler.startPayment` is then called with the **original** `amount` and
`rate` values.

Inside `_initiatePurchase` (`payment_handler.dart:144-151`):
```
activeRate = timerState.isActive
    ? (metalId=='1' ? timerState.lockedRates!.goldSell : timerState.lockedRates!.silverSell)
    : rate;   // the pre-KYC rate, only used if the timer is no longer active
```
If the rate-lock timer expired and auto-re-locked during the KYC detour (`RateTimerNotifier
._refreshAndRestart`, `timer_provider.dart:80-105`, fires automatically every `sellRateLockSeconds`),
`activeRate` becomes a **freshly-locked, potentially different** rate. `amount_inr` sent to `savings/initiate`
is still the original pre-KYC rupee figure (`amount.toStringAsFixed(2)`), but for AMOUNT-mode purchases the
`weight` field is recomputed using this possibly-new `activeRate` — so the rupee amount and the gram weight
in the same request can be internally inconsistent with each other relative to any single rate. This is the
concrete client-side mechanism behind the "rate expires mid-payment" fintech risk noted in
`STARTGOLD_DOCUMENTATION.md` §3.11; the doc does not describe this specific KYC-interaction case. See
`FORENSIC_TEMPLATE.md`.

## RULE-INSTANTSAVING-007 — Rate lock is shared infrastructure, not screen-specific

The rate lock timer (`sellRateTimerProvider`) is an instance of the generic `RateTimerNotifier`
(`core/providers/timer_provider.dart:22-119`), the same class type `withdrawal` uses for its
`buyRateTimerProvider`. Duration is always `config.sellRateLockSeconds` for this module (never
`buyRateLockSeconds`, which exists in `SavingConfig` but is not read anywhere in `instant_saving/`). Lock
value: the live `MarketRates` snapshot from `marketRatesStreamProvider` at the moment `startOrRefresh` is
called (`timer_provider.dart:46-54`) — not a value returned by any REST endpoint; it comes from the socket
stream.

## RULE-INSTANTSAVING-008 — Market-closed gate blocks purchase per-commodity, independent of the rate-lock timer

`marketStatusProvider` (socket-driven, `'1'`=gold/`'3'`=silver → `bool` open/closed) independently gates the
UI: an amber banner renders and the timer is prevented from actively locking a rate while
`marketStatusMap[commodityId] == false` (`instant_saving_screen.dart:169,268,399-430`). `TimerState.isActive`
itself also requires `!isMarketClosed` (`timer_provider.dart:18-19`) though `isMarketClosed` is never set to
`true` by any code path found in `RateTimerNotifier` — the closed-market UI gating is driven entirely by
`marketStatusProvider`, not by `TimerState.isMarketClosed`. No explicit "reject purchase because market
closed" check was found at the `_handleConfirmOrder`/`PaymentHandler` layer beyond the UI disabling Pay Now
via `isInvalid`/rate being stale — market-closed enforcement appears to be UI-only on the client, with the
server presumably re-validating on `check-eligibility`/`initiate` (not traced — backend not in scope).

## RULE-INSTANTSAVING-009 — Best-Offer silver reward calculation (Gold purchases only)

Shown only when `countdownOfferProvider` reports `enabled==true`, commodity is Gold, and silver market is
open (`instant_saving_screen.dart:448,987-995`). Per the in-code comment mirroring the backend formula
(`instant_saving_screen.dart:1018-1028`):
```
so_qty (goldQty)  = trunc6( amount-mode: trunc2(inputVal/(1+gstRate)) / goldRate  |  grams-mode: inputVal )
target_wt         = trunc6( goldQty * rewardPercentage / 100 )
reward_amt        = trunc2( target_wt * silverRate )
reward_net        = trunc2( reward_amt / (1 + gstRate/100) )
reward_qty(silverGrams) = trunc6( reward_net / silverRate )
```
`rewardPercentage` source: `offer.existingOffer.currentRewardPercentage` (EXISTING customers) or
`offer.newOffer.rewardPercentage`, upgraded to `benchmarkPercentage` if `inputVal >= newOffer.benchmarkAmount`
and `newOffer.benchmarkEnabled` (NEW customers) — all server-driven via `countdownOfferProvider` →
`HomeService.getCountdownOffer()`, not traced further in this brain (Home module's concern).

## RULE-INSTANTSAVING-010 — Which payment gateway launches is a backend decision per order, not a client setting

`PurchaseInitiateResponse.paymentGateway` (`saving_models.dart:118,156`) — defaults to `"cashfree"` string
literal client-side if the field is absent, but is otherwise whatever `savings/initiate` returns. The
client's own instrument choice (`upi`/`card`/`netbanking`, picked in `PaymentMethodSheet`) is sent as a
*hint* (`payment_method` field) — it does not determine the gateway; `PaymentHandler._initiatePurchase` only
falls back to resolving gateway from `config.paymentMethods[paymentMethod]` (a map also from
`savings/config`) if the initiate response's `payment_gateway` is empty or not one of the three recognized
strings (`payment_handler.dart:199-206`).
