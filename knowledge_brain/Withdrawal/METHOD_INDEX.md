---
module: Withdrawal
last_updated: 2026-08-19
---

# Method Index — Withdrawal

Alphabetical within each file. `file:line` refers to `lib/features/withdrawal/<file>` unless noted otherwise.

## models/withdrawal_balance.dart

| Method | Line | Callers |
|---|---|---|
| `WithdrawalBalance.fromJson(json)` | 25 | `WithdrawalService.fetchWithdrawalEligibility` (`services/withdrawal_service.dart:152`) |
| `WithdrawalBalance.empty` (static const) | 39 | `withdrawalBalanceProvider` fallback (`services/withdrawal_service.dart:222`) |

## models/withdrawal_method.dart

| Method | Line | Callers |
|---|---|---|
| `WithdrawalMethod.fromJson(json)` | 18 | `WithdrawalService.fetchAccountDetails` (`services/withdrawal_service.dart:28`) |

## models/withdrawal_policy.dart

| Method | Line | Callers |
|---|---|---|
| `WithdrawalPolicy.fromJson(json)` | 13 | `WithdrawalService.fetchWithdrawalPolicy` (`services/withdrawal_service.dart:172`) |
| `WithdrawalLimits.fromJson(json)` | 40 | `WithdrawalPolicy.fromJson` |
| `WithdrawalValidation.fromJson(json)` | 66 | `WithdrawalPolicy.fromJson` |
| `UserEligibility.fromJson(json)` | 84 | `WithdrawalPolicy.fromJson` |

## providers/withdrawal_provider.dart

| Method | Line | Callers |
|---|---|---|
| `WithdrawalState.copyWith(...)` | 22 | Every `WithdrawalNotifier` mutator |
| `WithdrawalNotifier.updateAmount(value)` | 44 | `withdrawal_screen.dart` amount `TextField.onChanged` (:707), `initState` reset (:54), commodity-switch reset (:118, :473, :485) |
| `WithdrawalNotifier.selectMethod(method)` | 48 | `withdrawal_screen.dart:_selectBankAndProceed` (:1164), `upi_selection_screen.dart:_autoSelect`/account tap (:50, :143), `upi_selection_screen.dart` list-sync `ref.listen` (:66,68,70) |
| `WithdrawalNotifier.setProcessing(value)` | 52 | `withdrawal_screen.dart:_handleWithdraw` (:1077, :1092, :1117, :1139) |
| `WithdrawalNotifier.validate(availableBalanceGrams, buyPrice)` | 56 | **No callers found in the 9 module files or elsewhere in `lib/`** — dead code. Client-side balance/min/max checks the UI actually uses are inlined in `withdrawal_screen.dart:_buildFooter` (:752-770) instead. |

## services/withdrawal_service.dart

| Method | Line | Endpoint | Callers |
|---|---|---|---|
| `WithdrawalService.fetchAccountDetails({customerId, mobile})` | 13 | `POST profile/accountdetails` | `accountDetailsProvider` (:186) |
| `WithdrawalService.submitWithdrawal({metalId, amount, weight, buyRate, withdrawalMethodId, withdrawalMethod})` | 36 | `POST withdrawal/withdraw` | `withdrawal_confirmation_screen.dart:_completeWithdrawal` (:475) |
| `WithdrawalService.checkEligibility({customerId, mobile, amount, metalId})` | 59 | `POST savings/check-eligibility` (`request_from: 'withdraw'`) | `withdrawal_screen.dart:_handleWithdraw` (:1109) |
| `WithdrawalService.verifyAndAddUpi({customerId, mobile, upiId})` | 85 | `POST account/verify-upi` | `upi_selection_screen.dart:_processAddUpi` (:738) — only reachable via the commented-out UPI option |
| `WithdrawalService.verifyAndAddBank({customerId, mobile, holderName, bankName, accNo, ifsc})` | 98 | `POST account/verify-bank` | `shared/widgets/add_bank_account_sheet.dart` (shared sheet, used by both Withdrawal's bank picker and Profile → Bank Details) |
| `WithdrawalService.fetchRewardBalance({metalId})` | 121 | `POST referrals/reward-balance` | `rewardBalanceProvider` (:197) — **provider itself has no callers found in withdrawal screens**; appears superseded by `withdrawalEligibilityProvider`/`withdrawalBalanceProvider` per the comment at :207 ("replaces as the withdrawal screen's balance source") |
| `WithdrawalService.fetchWithdrawalEligibility()` | 147 | `GET withdrawal/eligibility` | `withdrawalEligibilityProvider` (:211) |
| `WithdrawalService.fetchWithdrawalPolicy({metalId, amount})` | 162 | `POST withdrawal/policy` | `withdrawal_screen.dart:_handleWithdraw` (:1085, direct service call) AND `WithdrawalPolicyNotifier.fetch` (:238, itself uncalled) |
| `withdrawalServiceProvider` | 179 | — | Every screen in this module |
| `accountDetailsProvider` | 182 | `profile/accountdetails` | `upi_selection_screen.dart` only |
| `rewardBalanceProvider` | 194 | `referrals/reward-balance` | No confirmed callers in withdrawal screens — likely legacy |
| `withdrawalEligibilityProvider` | 208 | `withdrawal/eligibility` | `withdrawalBalanceProvider` (:219) |
| `withdrawalBalanceProvider` | 216 | derived | `withdrawal_screen.dart` balance display + `_buildFooter` validation (:87, :756) |
| `WithdrawalPolicyNotifier.build()` | 232 | — | Riverpod lifecycle (idle state) |
| `WithdrawalPolicyNotifier.fetch({metalId, amount})` | 235 | `withdrawal/policy` | **No callers found** — dead relative to `withdrawal_screen.dart`'s direct service call |
| `withdrawalPolicyProvider` | 245 | — | No confirmed callers |

## screens/withdrawal_screen.dart (`_WithdrawalScreenState`, all private)

| Method | Line | Purpose |
|---|---|---|
| `initState()` | 49 | Reset amount to 0; lock buy rate if market open for entry commodity |
| `build()` | 82 | Wires `commodityProvider`, `portfolioProvider`, `withdrawalProvider`, `buyRateTimerProvider`, `withdrawalBalanceProvider`, `savingConfigProvider`, `marketStatusProvider`, `marketRatesStreamProvider` |
| `_buildLiveRateSection()` | 291 | Live buy rate + countdown/market-closed badge |
| `_buildCommodityTabs()` / `_buildTabItem()` | 457 / 498 | Gold/Silver toggle, resets amount + clears/restarts rate timer |
| `_buildMainInputCard()` | 560 | Withdrawable balance display, amount `TextField`, live gram conversion |
| `_buildFooter()` | 747 | Client-side balance check, duplicate-withdrawal info banner, submit CTA gating |
| `_showHoldingInfoSheet()` / `_holdingRow()` | 850 / 1026 | Withdrawable/Requested/On Hold/Total Holding breakdown bottom sheet |
| `_handleWithdraw(market, type)` | 1071 | policy check → eligibility check → KYC gate if needed → `_selectBankAndProceed` |
| `_selectBankAndProceed()` | 1153 | Pushes `BankAccountPickerScreen` (from `sip` module), on result `selectMethod` + navigate to confirmation |

## screens/upi_selection_screen.dart (`_UpiSelectionScreenState`, all private) — reachable only from InstantSaving

| Method | Line | Purpose |
|---|---|---|
| `_bankOnly(list)` | 42 | Filters out any UPI methods — UPI display/selection is disabled here |
| `initState()` / `_autoSelect()` | 33 / 45 | Auto-selects first bank account on load |
| `build()` | 56 | Watches `accountDetailsProvider`; syncs `withdrawalProvider.selectedMethod` on data change |
| `_buildBody()` / `_buildAccountCard()` | 100 / 137 | Account list rendering |
| `_buildAddRow()` / `_buildEmptyState()` / `_buildErrorState()` | 255 / 299 / 349 | Empty/error/add-account states |
| `_buildFooter()` | 375 | Submit → `Navigator.pushNamed(context, '/withdrawal-confirmation')` regardless of caller's original intent (purchase vs withdrawal) |
| `_showAddOptions()` / `_buildOptionTile()` | 422 / 510 | Add-account sheet; UPI option commented out (:471-484), only Bank Account routes to `showAddBankAccountSheet` |
| `_showUpiForm()` / `_buildField()` / `_processAddUpi()` | 566 / 673 / 723 | Dead-reachable UPI-add flow (UI entry point disabled); calls `WithdrawalService.verifyAndAddUpi` |

## screens/withdrawal_confirmation_screen.dart (`_WithdrawalConfirmationScreenState`, all private)

| Method | Line | Purpose |
|---|---|---|
| `initState()` | 36 | Immediately re-locks rate if market open |
| `_handleRateExpiry()` / `_onRateUpdated()` | 56 / 67 | Rate-lock refresh cycle on timer expiry |
| `build()` | 89 | Market status/rate wiring, race-condition guards (see inline comments :124-152) |
| `_buildSummaryCard()` / `_buildSummaryRow()` | 287 / 341 | Amount/weight/rate/commodity summary |
| `_buildDestinationCard()` | 353 | Shows `selectedMethod.identifier` |
| `_buildFinalAction()` | 386 | Confirm CTA, disabled while refreshing/submitting/market-closed |
| `_completeWithdrawal(context)` | 439 | MPIN gate (`AppRouter.mpin`, `type: withdrawal_pin`) → `submitWithdrawal()` → navigate to success or show error |

## screens/withdrawal_success_screen.dart (`WithdrawalSuccessScreen`, `ConsumerWidget`)

| Method | Line | Purpose |
|---|---|---|
| `build()` | 22 | Renders receipt from `data` map passed via route arguments |
| `_getCommodityLabel()` | 245 | Maps `data['commodity']` to display label |
| `_truncateId()` | 253 | Truncates transaction ID for display |
| `_detailRow()` | 258 | Row renderer, includes copy-to-clipboard with 60s auto-clear (:304-307) |
| `_rowDivider()` | 323 | Divider styling |
| `_navigateHome(context, ref)` | 331 | Refreshes `portfolioProvider`, invalidates `homeDashboardProvider`/`profileProvider`, navigates to `AppRouter.home` |

## Coverage note

All public/instance methods across the 9 files are catalogued above (screens' private `_build*` widget
builders included for completeness since this is a small module). `WithdrawalNotifier.validate` and
`WithdrawalPolicyNotifier.fetch`/`withdrawalPolicyProvider` are confirmed **dead code** relative to the live
navigation graph (no call sites found via grep across `lib/`) — flagged rather than silently omitted.
