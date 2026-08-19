---
module: Withdrawal
last_updated: 2026-08-19
---

# Business Rules — Withdrawal

## RULE-WITHDRAWAL-001 — Rate lock on entry and re-lock on confirmation

The buy rate shown to the user (labelled "Live Withdrawal Price") is locked client-side for
`SavingConfig.buyRateLockSeconds` (server-driven, `savings/config`, `saving_models.dart:7,34`) the moment
`WithdrawalScreen` opens (`screens/withdrawal_screen.dart:56-71`) and is **re-locked again** when
`WithdrawalConfirmationScreen` opens (`screens/withdrawal_confirmation_screen.dart:38-49`) — the lock is not
simply carried over from the entry screen. `TimerState.isActive` requires `remainingSeconds > 0 &&
lockedRates != null && !isMarketClosed` (`core/providers/timer_provider.dart:18-19`). The final submitted
`buy_rate` is whatever `timerState.lockedRates` holds at the moment "Confirm Sale & Transfer" is tapped
(`withdrawal_confirmation_screen.dart:453-455`), not a value re-fetched live at that instant.

## RULE-WITHDRAWAL-002 — "Buy rate" terminology = the platform buys, the user sells

The UI reads `MarketRates.goldBuy`/`silverBuy` (the platform's buy-side quote) for withdrawal pricing
(`withdrawal_screen.dart:297-298,617-619`, `withdrawal_confirmation_screen.dart:239-241`) — confirming the
hand-written doc's claim that "buy rate for the platform = sell rate for the user" in this codebase's
naming convention. No separate `sellRateTimerProvider` value is used here even though one exists
(`core/providers/timer_provider.dart:121-124`) — Withdrawal and InstantSaving both key off `buyRateTimerProvider`.

## RULE-WITHDRAWAL-003 — Market-closed guard

`isCurrentMarketClosed` is derived per-commodity from `marketStatusProvider` (socket status frames,
`core/providers/market_provider.dart:58-61`), keyed by commodity ID string (`'1'` gold, `'3'` silver);
absence from the map is treated as open (`withdrawal_screen.dart:134-137`). When closed:
- Amber banner shown, submit CTA disabled (`withdrawal_screen.dart:766-770`).
- Confirmation screen: banner shown, "Confirm Sale & Transfer" disabled
  (`withdrawal_confirmation_screen.dart:207-233,387`).
- Weight/rate become `—`/"Market Closed" placeholders to avoid `Infinity` from a zero-price division
  (`withdrawal_confirmation_screen.dart:290-299`).

## RULE-WITHDRAWAL-004 — Amount/weight conversion math

`amountInGrams = isGrams ? amount : (price > 0 ? amount / price : 0.0)` and
`amountInINR = isGrams ? amount * price : amount` (`withdrawal_confirmation_screen.dart:242-248,456-462`).
In the live flow `isGrams` is always `false` (see `DATA_FLOW.md` Flow 2 note) — the app only supports
INR-denominated withdrawal amount entry, not gram-denominated, despite the model supporting both. Submitted
`weight` is rounded to 4 decimal places via `double.parse(x.toStringAsFixed(4))` (`:458-462`); the
withdrawable balance itself is displayed to 6 decimal places (`withdrawal_screen.dart:623,957` etc.) — a
precision mismatch between display (6dp) and submission (4dp) worth flagging if it ever causes an
off-by-a-fraction-of-a-milligram mismatch against server-side ledger rounding. All arithmetic is raw `double`
— no dedicated decimal/money type (see `MODULE_BRAIN.md` Top Risk #4).

## RULE-WITHDRAWAL-005 — Min/max withdrawal (client-side constants; server is authoritative)

`AppConstants.minWithdrawalGrams = 0.001`, `maxWithdrawalGrams = 100.0`
(`core/constants/app_constants.dart:64-65`) back the (now-dead — see RULE-WITHDRAWAL-009) `WithdrawalNotifier.validate()`
method. The **live, authoritative** limits are `WithdrawalLimits.minWithdrawal`/`maxWithdrawal`/
`minPurchaseRequired`/`dailyLimit`/`sameDayLock`, returned per-request by `POST withdrawal/policy`
(`models/withdrawal_policy.dart:25-53`) and enforced via `WithdrawalValidation.isValid`/`message`
(`:55-73`), consumed in `_handleWithdraw()` (`withdrawal_screen.dart:1091-1099`).

## RULE-WITHDRAWAL-006 — Field-level RSA encryption (verified against `AppConfig`, NOT the hand-written doc)

`ApiSecurityInterceptor` treats a path as sensitive if it `.contains()` ANY entry in
`AppConfig.encryptedEndpoints` (`core/security/api_interceptor.dart:132-138`); entries are substring matches,
e.g. the single entry `'withdraw'` matches `withdrawal/withdraw`, `withdrawal/policy`, and
`withdrawal/eligibility` alike (all contain the substring "withdraw"). When a path is sensitive, every key in
`options.data` that also appears in `AppConfig.sensitiveFields` (`app_constants... actually app_config.dart:74-99`)
is RSA-OAEP-SHA256 encrypted in place (`encryption_service.dart:109-127`).

Verified per-endpoint, by cross-referencing the actual payload keys sent (`withdrawal_service.dart`) against
`AppConfig.sensitiveFields`:

| Endpoint | Payload keys sent | Keys actually encrypted |
|---|---|---|
| `POST withdrawal/withdraw` | `id_metal, amount, weight, buy_rate, withdrawal_method_id, withdrawal_method` | `amount`, `weight`, `buy_rate` |
| `POST withdrawal/policy` | `id_metal, amount` | `amount` |
| `POST savings/check-eligibility` | `id_customer, mobile, id_metal, amount_inr, request_from` | `mobile`, `amount_inr` |
| `POST account/verify-upi` | `mobile, upi_id` | `mobile`, `upi_id` |
| `POST account/verify-bank` | `mobile, account_holder, bank_name, account_no, ifsc_code` | `mobile`, `account_no`, `ifsc_code` |
| `GET withdrawal/eligibility` | (no body) | n/a — response decryption also attempted but `EncryptionService.decrypt()` is a documented no-op (`encryption_service.dart:99-104`) |
| `POST referrals/reward-balance` | `id_metal` | none — path matches no `encryptedEndpoints` entry |
| `POST profile/accountdetails` | `id_customer, mobile` | none — path matches no `encryptedEndpoints` entry (⚠ `mobile` travels in cleartext on this call despite being a `sensitiveFields` entry, purely because the endpoint path isn't on the encrypted-endpoints allowlist) |

**Confirms/corrects the hand-written doc**: the doc claimed `withdrawal_amount`, `upi_id`, `bank_details`,
`buy_rate` are encrypted on `withdraw/initiate`. Reality — no `withdraw/initiate` endpoint exists; the real
submit endpoint (`withdrawal/withdraw`) encrypts `amount` (not `withdrawal_amount`), `weight`, and `buy_rate`;
`upi_id` is encrypted only on the separate `account/verify-upi` call; there is no single `bank_details` field
anywhere — bank data travels as discrete `account_no`/`ifsc_code` (encrypted) plus `account_holder`/`bank_name`
(NOT encrypted) on `account/verify-bank`.

## RULE-WITHDRAWAL-007 — MPIN (transaction PIN) re-verification gate

Every withdrawal submission requires a fresh MPIN verification immediately before submit:
`Navigator.pushNamed(context, AppRouter.mpin, arguments: {'type': 'withdrawal_pin'})`
(`withdrawal_confirmation_screen.dart:464-468`) → server-side `POST mpin/validate`
(`mpin/mpin_screen.dart:713-722`). If verification fails, the MPIN screen shuffles its keypad and does not
pop — `_completeWithdrawal` never proceeds past `if (pin != null && pin is String && pin.isNotEmpty)`
(`:470`). See `MODULE_BRAIN.md` Security section for the caveat that the resulting PIN string is not itself
forwarded in the `withdrawal/withdraw` payload.

## RULE-WITHDRAWAL-008 — KYC eligibility gate

`POST savings/check-eligibility` with `request_from: 'withdraw'` can return `next_step: 'KYC_REQUIRED'`,
which routes through the shared `KycVerificationFlow.start(requestFrom: 'withdraw')`
(`kyc/kyc_flow.dart:20-33`) requiring both PAN and Aadhaar to reach APPROVED before the withdrawal can
resume (`withdrawal_screen.dart:1119-1133`).

## RULE-WITHDRAWAL-009 — Duplicate-withdrawal prevention is server-enforced, client shows an informational banner only

The client displays "Only one withdrawal request per metal is allowed per calendar day for security
purposes." (`withdrawal_screen.dart:803`) but performs no client-side same-day lockout check itself — no
local timestamp/date comparison exists in this module. The actual mechanism is
`WithdrawalLimits.dailyLimit`/`sameDayLock` (`models/withdrawal_policy.dart:29,37`), returned by
`withdrawal/policy` and enforced via that endpoint's `is_valid`/`message` response, which the submit flow
checks before proceeding (`withdrawal_screen.dart:1091-1099`, see RULE-WITHDRAWAL-005). Separately, the
submit button itself is disabled while `isProcessing` (`withdrawal_screen.dart:766`,
`withdrawal_confirmation_screen.dart:387`) — a UI-level double-tap guard, not an idempotency key. **No
client-generated idempotency key/nonce was found anywhere in the submit payload** — a network retry after a
timeout (where the server processed the first request but the response was lost) could plausibly produce a
duplicate submission; this is a server-side responsibility this brain cannot verify without backend access.
Marked **unconfirmed** whether the backend itself deduplicates on retry.

## RULE-WITHDRAWAL-010 — Only verified payout accounts are selectable

`BankAccountPickerScreen._buildAccountTile` only allows tapping (`selectable = account.isVerified`,
`bank_account_picker_screen.dart:100-102`) — pending/unverified accounts are shown greyed-out with a
"pending" badge but cannot be chosen as a payout destination.

## RULE-WITHDRAWAL-011 — UPI payout is implemented but currently disabled

`UpiSelectionScreen._showAddOptions` has the "UPI Handle" option tile commented out entirely
(`upi_selection_screen.dart:471-484`); only "Bank Account" is offered. `_bankOnly()` (`:42-43`) filters any
previously-saved UPI methods out of the visible list even if the backend still has them on file. The
underlying `verifyAndAddUpi` service call and `WithdrawalMethod.isUpi` model support remain intact — this
appears to be a feature flag/rollback at the UI layer, not a removed capability. See `MODULE_BRAIN.md` Top
Risk #1 for the associated routing concern.
