---
module: Withdrawal
folder: lib/features/withdrawal/
last_updated: 2026-08-19
round: 1 (build)
files_read: 9/9 module files + app_router.dart + ~14 core/cross-module files
---

# Withdrawal — Module Brain

Sell gold/silver holdings and cash out to a payout method. **Live code confirms bank-account payout only —
UPI payout is implemented but currently disabled in the UI** (see §Drift). This directly contradicts
`STARTGOLD_DOCUMENTATION.md` §3.16–3.19, which describes UPI as an active payout option.

## Folder Inventory (9 files)

```
lib/features/withdrawal/
├── models/
│   ├── withdrawal_balance.dart     WithdrawalBalance — per-commodity holdings breakdown
│   ├── withdrawal_method.dart      WithdrawalMethod — unified UPI/bank payout target
│   └── withdrawal_policy.dart      WithdrawalPolicy, WithdrawalLimits, WithdrawalValidation, UserEligibility
├── providers/
│   └── withdrawal_provider.dart    WithdrawalState/WithdrawalNotifier (screen-local form state)
├── screens/
│   ├── withdrawal_screen.dart              route /withdrawal — amount entry + rate lock
│   ├── upi_selection_screen.dart           route /upi-selection — NOT part of live withdrawal flow (see Drift)
│   ├── withdrawal_confirmation_screen.dart route /withdrawal-confirmation — review + MPIN + submit
│   └── withdrawal_success_screen.dart      route /withdrawal-success — receipt
└── services/
    └── withdrawal_service.dart     WithdrawalService — all withdrawal-related API calls + Riverpod providers
```

## Route Table (from `lib/routes/app_router.dart`)

| Constant | Path | Screen | Registered |
|---|---|---|---|
| `AppRouter.withdrawal` | `/withdrawal` | `WithdrawalScreen` | app_router.dart:84,207 |
| `AppRouter.withdrawalConfirmation` | `/withdrawal-confirmation` | `WithdrawalConfirmationScreen` | app_router.dart:85,208 |
| `AppRouter.upiSelection` | `/upi-selection` | `UpiSelectionScreen` | app_router.dart:96,284 |
| `AppRouter.withdrawalSuccess` | `/withdrawal-success` | `WithdrawalSuccessScreen` | app_router.dart:97,285 |

Entry point: `home_screen.dart:1417` (`Navigator.pushNamed(context, AppRouter.withdrawal)`), also referenced as
a dashboard action at `home_screen.dart:848`.

## Architecture / Flow (as actually wired)

```
WithdrawalScreen (/withdrawal)
  amount entry, live rate + buyRateTimerProvider lock, market-closed guard
      │ tap "Withdrawal" → fetchWithdrawalPolicy → checkEligibility
      │   if KYC_REQUIRED → KycVerificationFlow.start() (kyc module) → resume
      ▼
BankAccountPickerScreen (sip module, reused — NOT UpiSelectionScreen)
  select verified bank account from profile's bankAccountsProvider
      │ pop(BankAccount) → withdrawalProvider.selectMethod(...)
      ▼
WithdrawalConfirmationScreen (/withdrawal-confirmation)
  re-locks rate on entry, shows amount/weight/rate/destination
      │ tap "Confirm Sale & Transfer" → MPIN screen (type: withdrawal_pin)
      │   MPIN verified via POST mpin/validate (mpin module)
      ▼ (only if pin returned non-empty)
  submitWithdrawal() → POST withdrawal/withdraw
      ▼
WithdrawalSuccessScreen (/withdrawal-success)
  receipt: amount, txnId, target account, status
```

`UpiSelectionScreen` physically lives in this module's `screens/` folder but is **navigated to only from
`instant_saving_screen.dart:1654`** (a purchase-payment UPI selection step), not from any withdrawal
screen — see `CROSS_MODULE_MAP.md` and `FORENSIC_TEMPLATE.md` for the bug this implies.

## State Management

- `withdrawalProvider` (`providers/withdrawal_provider.dart:78`) — `StateNotifierProvider<WithdrawalNotifier,
  WithdrawalState>`. Screen-local form state: amount, isGrams, selectedMethod, savedMethods, isProcessing,
  error. Reset to `amount: 0` on every `WithdrawalScreen.initState` (provider.dart is NOT autoDispose, so
  stale `selectedMethod` from a prior aborted attempt is not cleared by navigation alone — only by explicit
  `updateAmount(0)`/`selectMethod(null)` calls).
- `buyRateTimerProvider` (`core/providers/timer_provider.dart:126`) — shared with `instant_saving`; the
  "sell rate for the user = buy rate for the platform" per in-app copy ("Live Withdrawal Price" label reads
  the `goldBuy`/`silverBuy` fields of `MarketRates`, not `goldSell`/`silverSell`) — confirms the hand-written
  doc's buy/sell terminology.
- `withdrawalEligibilityProvider` / `withdrawalBalanceProvider` (`withdrawal_service.dart:208,216`) — the
  Total Holding/Requested/On Hold/Withdrawable breakdown, `GET withdrawal/eligibility`.
- `withdrawalPolicyProvider` (`withdrawal_service.dart:245`) — `AsyncNotifierProvider`, fetched on submit via
  `WithdrawalPolicyNotifier.fetch()`, NOT auto-fetched on screen load (build() returns null until first
  `fetch()` call) — see `withdrawal_screen.dart:1085` which calls `fetchWithdrawalPolicy` directly through the
  service, bypassing the notifier's `fetch()` method entirely (two independent code paths reach the same
  endpoint — the `withdrawalPolicyProvider` notifier appears unused by the live screen).
- `accountDetailsProvider` (`withdrawal_service.dart:182`) — `profile/accountdetails`, used only by
  `UpiSelectionScreen` (the orphaned screen). The live flow uses `bankAccountsProvider` (profile module,
  `profile/bank-accounts`) via `BankAccountPickerScreen` instead.

## Security-Relevant Behavior

- **MPIN re-verification** before every submit: `withdrawal_confirmation_screen.dart:464-468` pushes
  `AppRouter.mpin` with `arguments: {'type': 'withdrawal_pin'}`. `mpin_screen.dart:713-722` handles this as
  VERIFY MODE → `POST mpin/validate` (server-side, not local match) → pops the plaintext MPIN string back.
  **The returned PIN string is never included in the `submitWithdrawal()` payload**
  (`withdrawal_confirmation_screen.dart:474-483`) — it is used only as a truthy gate
  (`if (pin != null && pin is String && pin.isNotEmpty)`). The actual authorization is whatever server-side
  session state `mpin/validate` establishes; the withdrawal submission itself carries no PIN field. Flag this
  for a security-adjacent code review — the client never proves *which* MPIN attempt authorized *this*
  specific submission beyond timing.
- **Field-level encryption**: see `BUSINESS_RULES.md` RULE-WITHDRAWAL-006 — actual encrypted fields differ
  from the hand-written doc's claim. Real fields on `withdrawal/withdraw`: `amount`, `weight`, `buy_rate`.
  `withdrawal_method_id`/`withdrawal_method` are NOT encrypted. No `upi_id`/`bank_details` keys are ever sent
  in the submit payload (those field names in `AppConfig.sensitiveFields` are legacy/aspirational relative to
  this module's actual payload shape).
- Screenshot/recording protection is **not** explicitly invoked per-screen in this module (no
  `ScreenshotSecurityService.secureScreen()`/`releaseScreen()` calls found in any withdrawal screen) — relies
  entirely on the global `AppConfig.enableScreenshotProtection` toggle applied once at app launch
  (`screenshot_security_service.dart:14-38`). If that global flag is off, withdrawal screens (which display
  bank account numbers, IFSC, transaction IDs) have no screen-level protection.
- Clipboard: `WithdrawalSuccessScreen._detailRow` auto-clears the copied transaction ID from clipboard after
  60s (`withdrawal_success_screen.dart:304-307`).

## Top Risks / Anti-Patterns Found

1. **`UpiSelectionScreen` misrouting risk** — reachable only from Instant Saving's `UPI_LIST` purchase path
   (`instant_saving_screen.dart:1654`), but the screen's own "Withdrawal" submit button unconditionally
   navigates to `/withdrawal-confirmation` (`upi_selection_screen.dart:392`) and never reads the
   amount/metal_id/rate/buy_type/weight arguments passed by the caller. A user who reaches the UPI purchase
   path would land on a bank-account picker mislabeled for withdrawal, not a purchase-UPI flow. Likely
   dead/broken code kept around from a prior architecture — verify against a real device before assuming it's
   reachable at all (UPI purchase method may already be gated off elsewhere). **Unconfirmed without a live
   trace of what gates `nextStep == 'UPI_LIST'`.**
2. **Two independent code paths call `withdrawal/policy`** — `WithdrawalPolicyNotifier.fetch()`
   (`withdrawal_service.dart:235`) is defined but not invoked by `withdrawal_screen.dart`, which instead calls
   `ref.read(withdrawalServiceProvider).fetchWithdrawalPolicy(...)` directly
   (`withdrawal_screen.dart:1085`). Dead provider code — low risk but a maintenance trap.
2b. **`withdrawalProvider` is not `autoDispose`** — global `StateNotifierProvider`, so `selectedMethod`
   persists across navigation away and back unless explicitly cleared. `withdrawal_screen.dart` clears
   `amount` on entry (`:54`) but never clears `selectedMethod`.
3. **MPIN result not bound into the submit payload** — see Security section above.
4. **Raw `double` arithmetic throughout** (`amount / price`, `withdrawable * rate`) with `toStringAsFixed`
   applied only at render/submit time, no dedicated decimal type — consistent with `AGENTS.md` §2's flagged
   concern; the module does not resolve that open question, it inherits the same pattern as InstantSaving.
5. **Duplicate-withdrawal prevention is UI-copy only on the client** — the "one withdrawal per metal per
   calendar day" rule (`withdrawal_screen.dart:803`) has no client-side lockout beyond the info banner text;
   enforcement is server-side via `WithdrawalLimits.dailyLimit`/`sameDayLock`
   (`models/withdrawal_policy.dart:29,37`) surfaced through the `withdrawal/policy` validation response. See
   `BUSINESS_RULES.md` RULE-WITHDRAWAL-009.

## Drift vs `STARTGOLD_DOCUMENTATION.md` §3.16–3.19

| Hand-written doc claim | Live code |
|---|---|
| `POST withdraw/initiate` | No such endpoint. Actual: `POST withdrawal/withdraw` (`withdrawal_service.dart:45`) |
| `POST withdraw/verify-upi` | Actual: `POST account/verify-upi` (`withdrawal_service.dart:90`) |
| Encrypted fields: `withdrawal_amount`, `upi_id`, `bank_details`, `buy_rate` | Actual encrypted fields on the submit payload: `amount`, `weight`, `buy_rate` only (see RULE-WITHDRAWAL-006). Field literally named `withdrawal_amount` does not exist anywhere in this module. `bank_details` as a single field does not exist — bank data is sent as separate `account_no`/`ifsc_code` fields, only on the separate `account/verify-bank` call, not on submit. |
| UPI/Bank selection presented as a live dual-option choice | UPI add is commented out/disabled in the UI (`upi_selection_screen.dart:471-484`); only bank-account payout is currently reachable from the withdrawal flow. |
| "UPI Selection" screen (§3.17) is a withdrawal step | `UpiSelectionScreen` is not reachable from the withdrawal flow at all in current routing — see Top Risk #1. |
| Transaction PIN verification (fintech risk bullet) | Confirmed — MPIN re-verify via `mpin/validate`, see Security section. |
| Market closed → withdrawal blocked | Confirmed — `isCurrentMarketClosed` disables the submit button (`withdrawal_screen.dart:766-770`) and the confirmation screen (`withdrawal_confirmation_screen.dart:387`). |
| Rate lock prevents sell-price manipulation | Confirmed — `buyRateTimerProvider`, shared with InstantSaving. |

See `_OVERVIEW/BUILD_SUMMARY.md` for the running cross-module drift log — this table should be mirrored there.

## See Also

- `METHOD_INDEX.md` — every public method, file:line, callers.
- `DATA_FLOW.md` — full amount→rate-lock→selection→confirmation→submit→success trace.
- `BUSINESS_RULES.md` — RULE-WITHDRAWAL-NNN catalogue.
- `CROSS_MODULE_MAP.md` — dependency graph on core/, kyc, profile, sip, instant_saving, mpin.
- `STATE_ANALYSIS.md` — provider/model/secure-storage inventory.
- `FORENSIC_TEMPLATE.md` — symptom → suspect entries for support/debugging.
- `COVERAGE_TRACKER.md` — this build's coverage score.
