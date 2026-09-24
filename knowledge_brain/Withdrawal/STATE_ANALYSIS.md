---
module: Withdrawal
last_updated: 2026-08-19
---

# State Analysis — Withdrawal

## Riverpod Providers Owned by This Module

| Provider | Type | File:line | Disposal | Notes |
|---|---|---|---|---|
| `withdrawalProvider` | `StateNotifierProvider<WithdrawalNotifier, WithdrawalState>` | `providers/withdrawal_provider.dart:78` | **Not autoDispose** — global lifetime | Screen-local form state; only explicitly reset fields are cleared on re-entry (see `MODULE_BRAIN.md` Top Risk #2b) |
| `withdrawalServiceProvider` | `Provider<WithdrawalService>` | `services/withdrawal_service.dart:179` | Global | Plain service instance, holds its own `ApiClient()` |
| `accountDetailsProvider` | `FutureProvider.autoDispose<List<WithdrawalMethod>>` | `services/withdrawal_service.dart:182` | autoDispose | `profile/accountdetails`; consumed only by `UpiSelectionScreen` |
| `rewardBalanceProvider` | `FutureProvider.autoDispose<Map<String, dynamic>>` | `services/withdrawal_service.dart:194` | autoDispose | `referrals/reward-balance`; no confirmed live caller — legacy |
| `withdrawalEligibilityProvider` | `FutureProvider.autoDispose<List<WithdrawalBalance>>` | `services/withdrawal_service.dart:208` | autoDispose, rebuilds on `selectedMetalIdProvider` change | `GET withdrawal/eligibility` |
| `withdrawalBalanceProvider` | `FutureProvider.autoDispose<WithdrawalBalance>` | `services/withdrawal_service.dart:216` | autoDispose | Derives the single row for the currently selected commodity |
| `withdrawalPolicyProvider` | `AsyncNotifierProvider.autoDispose<WithdrawalPolicyNotifier, WithdrawalPolicy?>` | `services/withdrawal_service.dart:245` | autoDispose | No confirmed live caller — `withdrawal_screen.dart` calls the service method directly instead |

## `WithdrawalState` Shape (`providers/withdrawal_provider.dart:5-20`)

| Field | Type | Default | Set by |
|---|---|---|---|
| `amount` | `double` | `0` | `updateAmount()` — from the INR text field |
| `isGrams` | `bool` | `false` | **Never set to `true` anywhere in the live module** — dead flag in practice |
| `selectedMethod` | `WithdrawalMethod?` | `null` | `selectMethod()` — from `BankAccountPickerScreen` result (live path) or `UpiSelectionScreen` tap (orphaned path) |
| `savedMethods` | `List<WithdrawalMethod>` | `[]` | **Never populated in the live module** — `copyWith` param exists but no call site sets it |
| `isProcessing` | `bool` | `false` | `setProcessing()` — gates the withdrawal-screen submit button during policy/eligibility checks |
| `error` | `String?` | `null` | Cleared on `updateAmount()`; never explicitly set to a non-null value anywhere in the module (errors are surfaced via `AppToast`/`_policyError` local `State`, not through this field) |

## Model Shapes

### `WithdrawalBalance` (`models/withdrawal_balance.dart`)
`commodityId: int?`, `commodity: String`, `totalHolding/requested/onHold/withdrawable: double`. Parsed via a
lenient `double.tryParse(v?.toString() ?? '0') ?? 0.0` helper — tolerant of the API sending numbers as
strings. `commodityId` similarly tolerant of int-or-string. Source: `GET withdrawal/eligibility` →
`data.holdings[]`.

### `WithdrawalMethod` (`models/withdrawal_method.dart`)
Unified UPI/bank shape: `id, identifier, title, subtitle?, isUpi, isVerified`. `fromJson` infers `isUpi` from
presence of `upi_id`/`upi_handle` keys, and falls back through `id_payout` → `id_upi` → `id` for `id`. Used
both for API-sourced accounts (`accountDetailsProvider`) and the locally-constructed value built from a
`BankAccount` in `_selectBankAndProceed()` (`withdrawal_screen.dart:1164-1173`) — two different construction
paths feed the same model shape.

### `WithdrawalPolicy` / `WithdrawalLimits` / `WithdrawalValidation` / `UserEligibility` (`models/withdrawal_policy.dart`)
All fields defensively defaulted (`?? {}`, `?? 0`, `== true`) — a missing/malformed `withdrawal/policy`
response degrades to permissive defaults (`isValid: true` default on `WithdrawalValidation`, `isEligible:
true` default on `UserEligibility`) rather than failing closed. Worth flagging: if the server ever returns a
response missing the `validation` object entirely (network hiccup mid-response, malformed JSON recovered
partially), the client would treat it as **valid by default** rather than blocking the withdrawal. Not
observed in code as an actual bug path (fromJson always receives a full parsed Map or the caller's `throw
Exception` fires first) but the default values themselves are permissive, not restrictive.

## Secure Storage Keys Touched

None directly by this module. MPIN state (`SecureStorageService.setMpinEnabled`) is touched by the `mpin`
module during the `withdrawal_pin` verification flow, not by withdrawal code itself. No tokens, no
withdrawal-specific secure-storage keys were found in `lib/features/withdrawal/`.

## Local (non-Riverpod) `State` Used

| Screen | Field | Purpose |
|---|---|---|
| `WithdrawalScreen` | `_amountController` (TextEditingController) | Bound to the amount field; cleared on commodity switch |
| `WithdrawalScreen` | `_portfolioLoaded` | Prevents full-screen loader flashing on Gold↔Silver switch after first successful load |
| `WithdrawalScreen` | `_hasUserTyped` | Suppresses validation error display until the user starts typing |
| `WithdrawalScreen` | `_policyError` | Non-null blocks the submit button until amount changes; set from `withdrawal/policy`'s validation message |
| `WithdrawalConfirmationScreen` | `_isRefreshing` | True while re-fetching `savingConfigProvider` after rate-lock expiry |
| `WithdrawalConfirmationScreen` | `_showUpdateSuccess` | Shows "Rate updated..." message for 3s after a refresh completes |
| `WithdrawalConfirmationScreen` | `_isSubmitting` | Disables the final CTA during the MPIN+submit round trip |
| `UpiSelectionScreen` (`_showUpiForm` local closure state) | `isVerifying` | Disables the UPI-add sheet's fields/button during `verifyAndAddUpi` — reachable only via dead-disabled UI path |

## Financial-Value Representation (per `AGENTS.md` §2 open question)

Confirmed for this module: **raw `double`, no dedicated decimal/money type**. Rounding discipline is ad hoc
and inconsistent between call sites — `toStringAsFixed(2)` for INR display, `toStringAsFixed(6)` for
withdrawable-balance display, `toStringAsFixed(4)` for the submitted `weight` value (see
`BUSINESS_RULES.md` RULE-WITHDRAWAL-004). This module does not introduce a new pattern; it inherits
InstantSaving's approach (shared `SavingConfig`/rate-timer infrastructure).
