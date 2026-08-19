---
module: InstantSaving
last_updated: 2026-08-19
---

# InstantSaving — Forensic Template

Symptom → check first → likely suspects, for the most consequential bug classes in this module. All file:line
references point to the code paths traced in `DATA_FLOW.md` / `BUSINESS_RULES.md`.

## 1. "GST looks calculated wrong" / "total payable doesn't match metal value + GST"

**Check first**: which entry mode was the user in (₹ vs grams) when the discrepancy occurred — the two modes
use different formula directions (RULE-INSTANTSAVING-001 vs -002), and a bug in one does not imply a bug in
the other.

**Likely suspects**:
- Confirm the `gst` value actually in play — was `savingConfigProvider` resolved yet, or was the `3.0`
  UI fallback (`instant_saving_screen.dart:769,1033`) still active because config hadn't loaded? A GST
  mismatch that "fixes itself" after a moment strongly suggests this race.
- Confirm which of the **two independent conversion sites** produced the number being complained about: the
  live input hint (`_buildAmountInputCard`, lines 761-774, informal, grams-mode doesn't add GST to its ₹
  hint) vs the authoritative breakdown (`_computeBreakdown`, lines 1304-1334, used by Pay Now/sheet). A
  complaint about the small grey hint text next to the input field is not the same bug surface as a
  complaint about the breakdown sheet or final charged amount.
- Truncation vs rounding: `_trunc2`/`_trunc6` floor. If someone "fixed" one of these to round instead
  (matches a natural instinct), amounts will drift by up to 1 paise / 1e-6 gram from what the backend expects
  — check for an unintended `round()`/`toStringAsFixed` swap in a recent diff.
- Confirm `SavingConfig.type` isn't being newly read somewhere (RULE-INSTANTSAVING-003) — if a change started
  branching on it without also updating both `_computeBreakdown` and the inline hint, the two would diverge.

## 2. "Rate expired mid-payment" / "amount charged doesn't match the rate shown to the user"

**Check first**: did the user go through the KYC flow (`next_step=='KYC_REQUIRED'`) before reaching the
gateway? This is the primary known mechanism (RULE-INSTANTSAVING-006).

**Likely suspects**:
- `PaymentHandler._initiatePurchase` (`payment_handler.dart:144-151`) resolves `activeRate` from
  `sellRateTimerProvider` **at initiate time**, not from the rate captured when the user tapped Pay Now. If
  the timer auto-re-locked (`RateTimerNotifier._refreshAndRestart`, `timer_provider.dart:80-105`, fires every
  `sellRateLockSeconds`) during a slow KYC flow or slow network, `activeRate` differs from what was shown pre-KYC.
- Check whether `amount_inr` (fixed, pre-KYC) and `weight` (recomputed with `activeRate`, post-KYC) in the
  `savings/initiate` payload are mutually consistent with either the old or the new rate — they may match
  neither cleanly if the rate moved between eligibility-check and initiate.
- Confirm market wasn't marked closed between the two points (`marketStatusProvider` transition) — a
  closed→open transition also force-restarts the timer with a fresh rate (`instant_saving_screen.dart:179-189`),
  which is a second, independent trigger for the same class of mismatch.
- There is **no re-confirmation screen** shown to the user after KYC and before gateway launch — if the
  product requirement is "user must see and accept the final rate/amount before paying," this is currently
  not implemented for the KYC-detour path. Confirm this is/isn't the actual root cause before assuming a code
  defect — it may be an accepted product gap.

## 3. "Payment succeeded but purchase not recorded" / "money debited, no gold credited"

**Check first**: which gateway was used (Cashfree/HDFC/Razorpay) — each has a distinct confirm-payment call
site and a distinct set of terminal SDK callback states; narrow to the right handler file first.

**Likely suspects**:
- `_confirmAndNavigate` in all three handlers calls `POST savings/confirm-payment` and treats **any thrown
  exception from that call as non-fatal to navigation** — the `catch` block just logs and continues to
  `PurchaseSuccessScreen` with `response == null`, meaning `isSuccess` evaluates `false` (`response?['success']
  == true` is `false` for a null response) — the user is shown a **failure** screen even though the payment
  gateway itself reported success, if `confirm-payment` merely failed to respond (network blip, 5xx, timeout).
  This is the single most likely client-side cause of "gateway says success, app says failure" — no retry is
  attempted.
- Razorpay's `EVENT_EXTERNAL_WALLET` handler (`razorpay_payment_handler.dart:202-206`) never calls
  `confirm-payment` at all — if a wallet payment actually completes, the client has no code path that learns
  about it; investigate whether this event fires for completed-vs-still-pending wallet flows before assuming
  a bug (may be intentional if wallet completion is server-webhook-driven only).
- HDFC's `_handleProcessResult` (`hdfc_payment_handler.dart:284-309`) treats `backpressed`/`user_aborted`
  **with a non-empty orderId** as "confirm anyway" (falls through to `_confirmAndNavigate`), but with an
  **empty orderId** as "never confirm, show generic failure" — if the SDK ever returns `user_aborted` with an
  orderId that the backend nonetheless materialized as a real order, that order is orphaned client-side (no
  confirm call, no way for the user to retry-verify it from this screen). `SavingService.cancelOrder()` exists
  for exactly this kind of cleanup but is **never called anywhere in this module**.
- Confirm the order really was created server-side: `savings/initiate`'s `orderId` in the response is the
  ground truth — if `_launchCashfree` bailed early because `orderId`/`sessionId` were null
  (`payment_handler.dart:257-265`), no gateway ever launched and no confirm call could logically follow; this
  presents to the user as an immediate toast, not a stuck/ambiguous state, so it's a different symptom than
  "payment succeeded but not recorded."

## 4. "Duplicate transaction created" / "charged twice for one purchase"

**Check first**: did the user tap Pay Now multiple times, or retry after a network error, or background/
foreground the app during processing?

**Likely suspects**:
- `_isProcessing` (screen-local `bool`) is the only guard against a double-tap on Pay Now
  (`instant_saving_screen.dart:1463-1466`, `1387-1397`) — confirm it was actually `true` for the full duration
  of the eligibility-check + initiate + gateway-launch sequence, including the `await` on `KycVerificationFlow
  .start()`. Note `_handleConfirmOrder` sets `_isProcessing = false` right after `checkEligibility` returns
  (`instant_saving_screen.dart:1594`), **before** the KYC/payment branch runs — so the Pay Now button is
  re-enabled (and the processing overlay disappears) during the KYC hub navigation. If the user backs out of
  KYC and the surrounding code doesn't fully unwind, or if they tap Pay Now again quickly in that window, a
  second `checkEligibility`+`initiate` sequence could plausibly start. This is the most concrete client-side
  double-submission risk found in this module.
- `AppLifecycleObserver.suppressAppLock` gates the MPIN app-lock overlay, not double-submission — do not
  confuse the two mechanisms when investigating.
- Confirm whether `savings/initiate` was called more than once with the same computed amount/weight (check
  `SecureLogger` output around `[PaymentHandler] savings/initiate →` and `[INITIATE] buy_type →` log lines,
  `payment_handler.dart:166-167`, `saving_service.dart:48-49`) — if two orders were created server-side, this
  is a client-triggered double-initiate, not a gateway-side duplicate charge.
- No idempotency key/order-dedup mechanism is visible client-side in `savings/initiate`'s payload — if the
  backend doesn't dedupe on its own criteria (e.g. a very-recent identical order for the same customer), a
  double-tap that both slip through `_isProcessing` will create two real orders.

## 5. "Min/max amount error shows/doesn't show incorrectly"

**Check first**: entry mode (₹ vs grams) and whether the complaint is about the inline red error text or the
Pay Now button's enabled/disabled state — RULE-INSTANTSAVING-004 documents these as two separate,
not-fully-unified checks.

**Likely suspects**:
- Grams-mode inline validation (`instant_saving_screen.dart:782-787`) compares `inputVal * rate` (no GST)
  against min/max, while the authoritative Pay Now gate uses the full GST-inclusive `totalPayable`
  (`_computeBreakdown`). A value that inline-validates as OK could still be blocked at Pay Now, or vice versa,
  for inputs near a boundary — reproduce with the same commodity/rate/config to confirm before assuming a
  regression.
- Confirm `config.minAmount`/`maxAmount` actually loaded (`configAsync.hasValue`) — both inline and gate
  checks silently skip validation (`if (inputVal>0 && config!=null)`, `if (config==null...) return
  SizedBox.shrink()`) when config is still loading, so a very fast Pay Now tap right after screen entry could
  theoretically bypass the min/max gate if `_buildBottomAction` returns `SizedBox.shrink()` for a null config
  — verify this doesn't actually leave a way to trigger `_handleConfirmOrder` without a rendered/enabled
  button in that state.

## 6. "Portfolio/holdings balance doesn't reflect a just-completed purchase"

**Check first**: did the user tap "Back to Home" on the success screen, or did they background/kill the app,
or navigate away some other way (e.g. OS back gesture, if not blocked)?

**Likely suspects**:
- `PurchaseSuccessScreen` uses `PopScope(canPop: false, ...)` (`purchase_success_screen.dart:76-77`) to block
  the OS back gesture, but the **only** code path that refreshes `portfolioProvider`/`homeDashboardProvider`/
  `profileProvider` is the "Back to Home" button's `onPressed`, 650ms after navigation
  (`purchase_success_screen.dart:500-507`). If the app was killed/backgrounded from this screen before the
  tap, or if a future change adds another way to leave the screen, no refresh happens — the next natural
  screen load elsewhere in the app is what eventually shows the correct balance, not anything triggered by
  this purchase completing.
