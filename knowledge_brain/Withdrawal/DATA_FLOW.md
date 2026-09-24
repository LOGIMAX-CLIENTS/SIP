---
module: Withdrawal
last_updated: 2026-08-19
---

# Data Flow — Withdrawal

All `file:line` refer to `lib/features/withdrawal/` unless a full path is given.

## Flow 1 — Screen load → withdrawable balance + live rate

1. `WithdrawalScreen.initState()` (`screens/withdrawal_screen.dart:49`) fires a `Future.microtask`:
   resets `withdrawalProvider` amount to 0 (`:54`), reads `commodityProvider` for the entry commodity, reads
   `marketStatusProvider` for that commodity — if not explicitly closed, clears then starts
   `buyRateTimerProvider` using `savingConfigProvider.buyRateLockSeconds`
   (`core/instant_saving/models/saving_models.dart:7`, sourced from `savings/config`,
   `instant_saving/controller/saving_controller.dart:8`).
2. `build()` watches `withdrawalBalanceProvider` (`services/withdrawal_service.dart:216`), which chains:
   `GET withdrawal/eligibility` → `withdrawalEligibilityProvider` (list of `WithdrawalBalance` per commodity,
   `:208`) → `.firstWhere` on the currently `selectedMetalIdProvider` (`core/providers/commodity_provider.dart:26`),
   falling back to `WithdrawalBalance.empty` (`models/withdrawal_balance.dart:39`).
3. `build()` also watches `marketRatesStreamProvider` (socket-fed) and `buyRateTimerProvider`. Display
   priority (`:189-203`): locked rate while timer active → last locked rate right after expiry → live socket
   rate → loading. This avoids the "zig-zag" flicker documented inline (`:189-195`).
4. Withdrawable balance in INR = `balance.withdrawable * displayRate` (`:616-620`), rendered alongside grams.

## Flow 2 — Amount entry → rate lock → validation

1. User types in the amount `TextField` (`:691-719`); `FilteringTextInputFormatter.digitsOnly` +
   `NoLeadingZerosFormatter(allowDecimal: false)` — **amount input is INR-integer only, no decimals, no
   direct gram entry** despite `WithdrawalState.isGrams` existing as a field (it is never set to `true`
   anywhere in this module — `isGrams` is always `false` in the live flow; the model's gram-mode branches in
   `withdrawal_confirmation_screen.dart:242-248` are dead in practice).
2. On each keystroke: `withdrawalProvider.notifier.updateAmount(doubleValue)` (`providers/withdrawal_provider.dart:44`);
   any prior `_policyError` is cleared so the submit button can re-enable.
3. Live gram equivalent shown inline: `grams = state.amount / price` where `price` is the current displayed
   rate (`:722-733`) — pure client-side estimate, not authoritative.
4. Submit-button enablement (`_buildFooter`, `:747-770`): `amount > 0 && !isProcessing && !isCurrentMarketClosed
   && !exceedsBalance && _policyError == null`, where `exceedsBalance = amount > withdrawable * liveRate`.
   This is a **client-side pre-check only** — see Flow 3 for the authoritative server check.
5. Commodity switch (Gold↔Silver tab, `:470-491`) clears amount, clears the rate timer, and restarts it from
   the current `savingConfigProvider` value — a brand-new rate lock window per commodity, not shared.
6. Market status transition closed→open (`ref.listen<marketStatusProvider>`, `:140-157`) and the
   first-valid-rate race-condition guard (`:159-187`, guards against the socket's status frame `5|...|1`
   arriving before the first rate frame `3|...`) both restart the timer defensively.

## Flow 3 — Submit tap → policy check → eligibility check → KYC gate → bank selection

`_handleWithdraw()` (`:1071-1145`):

1. `notifier.setProcessing(true)`.
2. `POST withdrawal/policy` with `{id_metal, amount}` (`services/withdrawal_service.dart:162-176`,
   RSA-encrypted `amount` field — see `BUSINESS_RULES.md` RULE-WITHDRAWAL-006). Response →
   `WithdrawalPolicy.validation.isValid`. If `false`: `setProcessing(false)`, `_policyError` set to the
   server message, toast shown, **flow stops here** — this is the authoritative min/max/eligibility gate,
   not the client-side arithmetic in Flow 2.
3. If valid: `POST savings/check-eligibility` with `{id_customer, mobile, id_metal, amount_inr,
   request_from: 'withdraw'}` (`:59-82`, encrypted `mobile`+`amount_inr`). Response → `next_step`.
4. If `next_step == 'KYC_REQUIRED'`: `KycVerificationFlow.start(context, ref, requestFrom: 'withdraw')`
   (`kyc/kyc_flow.dart:20`) pushes `AppRouter.kyc` and awaits `true` only once both PAN and Aadhaar are
   APPROVED. On success, resumes at `_selectBankAndProceed()`. On cancel/failure, the withdrawal flow simply
   stops (no explicit error surfaced beyond whatever the KYC hub itself shows).
5. Otherwise (or after KYC completes): `_selectBankAndProceed()` (`:1153-1175`) pushes
   `BankAccountPickerScreen` (`features/sip/screens/bank_account_picker_screen.dart`, a **cross-feature
   widget from the `sip` module**, reused here — see `CROSS_MODULE_MAP.md`). It reads `bankAccountsProvider`
   (`features/profile/services/bank_details_service.dart:59`, `POST profile/bank-accounts`) — a **different
   endpoint and provider** than this module's own `accountDetailsProvider`
   (`profile/accountdetails`, used only by the orphaned `UpiSelectionScreen`).
6. Only `isVerified` accounts are tappable in the picker (`bank_account_picker_screen.dart:100`). On tap,
   `Navigator.pop(context, account)` returns a `BankAccount`.
7. Back in `_selectBankAndProceed`: wraps the `BankAccount` into a `WithdrawalMethod(isUpi: false, ...)`
   (`:1164-1173`), calls `withdrawalProvider.notifier.selectMethod(...)`, then
   `Navigator.pushNamed(context, AppRouter.withdrawalConfirmation)`.

## Flow 4 — Confirmation → rate re-lock → MPIN → submit → success

`WithdrawalConfirmationScreen`:

1. `initState()` (`:36-50`) immediately re-locks the freshest rate if market is open — the rate the user
   locked on the entry screen is **not** carried forward as-is; confirmation always re-fetches/re-locks.
2. `build()` computes `amountInINR`/`amountInGrams` from `withdrawal.amount` and the current locked/live rate
   (`:239-248`), with a zero-price guard to avoid `Infinity` when market is closed.
3. Tap "Confirm Sale & Transfer" → `_completeWithdrawal()` (`:439-525`):
   a. Guards: `user != null`, `selectedMethod != null`, `timerState.isActive` — else a warning toast, no
      submit.
   b. Computes final `price` from `timerState.lockedRates` (the re-locked rate from step 1, NOT a fresh read
      at tap time) — `amountInINR`, `amountInGrams` (rounded to 4 decimals via
      `double.parse(x.toStringAsFixed(4))`, `:458-462`).
   c. **MPIN gate**: `Navigator.pushNamed(context, AppRouter.mpin, arguments: {'type': 'withdrawal_pin'})`
      (`:464-468`). `mpin_screen.dart` VERIFY MODE calls `POST mpin/validate` server-side
      (`mpin_screen.dart:715`); on success for `type == 'withdrawal_pin'` it pops the plaintext PIN string
      back (`mpin_screen.dart:720-722`).
   d. If a non-empty PIN string was returned: `setState(_isSubmitting = true)`, then
      `WithdrawalService.submitWithdrawal({metalId, amount: amountInINR, weight: amountInGrams,
      buyRate: price, withdrawalMethodId, withdrawalMethod: isUpi ? 'UPI' : 'BANK'})` →
      `POST withdrawal/withdraw` (RSA-encrypted `amount`, `weight`, `buy_rate` — see RULE-WITHDRAWAL-006).
      **Note: the PIN itself is not sent in this payload** — see `MODULE_BRAIN.md` Security section.
   e. On `response['success'] == true`: navigate with `pushNamedAndRemoveUntil` to
      `AppRouter.withdrawalSuccess`, passing `amount`, `txnId` (`transfer_id` ?? `withdrawal_id`), `account`
      (local `selectedMethod.identifier`, not server-echoed), `status` (default `COMPLETED`), `commodity`.
   f. On failure: error message extracted from `response['error']['message']` → `response['data']['message']`
      → `response['message']` → generic fallback; toast shown, `_isSubmitting` reset, **user stays on the
      confirmation screen** (no automatic retry, no lockout — see `FORENSIC_TEMPLATE.md` "duplicate
      withdrawal submitted").

## Flow 5 — Success screen → home

`WithdrawalSuccessScreen.build()` renders the passed `data` map directly (no re-fetch, no server round-trip
to confirm status). `PopScope(canPop: false)` blocks back-navigation (`:27`). "BACK TO HOME"
(`_navigateHome`, `:331-342`) refreshes `portfolioProvider`, invalidates `homeDashboardProvider` and
`profileProvider`, then `pushNamedAndRemoveUntil` to `AppRouter.home` — this is the only point where
portfolio/holdings state is refreshed after a withdrawal; if the user kills the app instead of tapping this
button, stale portfolio data may persist until the next natural refresh elsewhere.
