---
module: sip
last_updated: 2026-08-19
---

# SIP — Business Rules

## RULE-SIP-001 — 24-hour cancellation lock
A SIP (regular or Custom) cannot be cancelled within 24 hours of creation. The server computes
`cancel_eligible_at` (implied: `created_at + 24h`) and an authoritative `can_cancel_now` boolean,
returned by `sip/manage-details` / `sip/custom/{id}/status` (`models/sip_models.dart:258-265,
382-383`). The client only displays/re-derives the gate from these values
(`screens/sip_cancel_screen.dart:55-58`) — it never computes the window itself. Enforcement is
server-side; the client check is a UX backstop (exact server contract `unconfirmed`, but strongly
implied by the doc comments' "computed server-side ... so the client never has to re-derive the
rule" language, `sip_models.dart:258-260`).
⚠️ **Drift vs `STARTGOLD_DOCUMENTATION.md`** §3.21-3.26 — the hand-written doc says nothing about
a lock-in window at all. Trust this rule (code-grounded).

## RULE-SIP-002 — One active/paused regular-SIP plan per (frequency, commodity)
`SipState.hasActivePlanForFrequency()`/`getActivePlanForFrequency()` (`controller/sip_controller.dart:125-144`)
block creating a second Daily+Gold (etc.) plan while one is ACTIVE or PAUSED.
`SipPlanDetail.isOccupying` (`models/sip_models.dart:244`) = `isActive || isPaused` —
`PENDING_AUTH`/`BANK_APPROVAL_PENDING` plans do **not** block, so a stuck/incomplete mandate can be
retried on the same frequency+commodity slot.

## RULE-SIP-003 — Custom SIP uniqueness is per day-of-month, not per frequency
A day-of-month (1-28) already owned by an ACTIVE or PAUSED Custom SIP scheme cannot be selected
for a new scheme — `CustomSipScheme.isOccupying` (`sip_models.dart:353`). Tapping a committed date
in the picker routes to managing that scheme instead of selecting it
(`screens/auto_savings_screen.dart:1901-1911`). `PENDING_AUTH` schemes don't block either
(`:1797-1808`), same convention as RULE-SIP-002.

## RULE-SIP-004 — Amount range validation
Amount must satisfy `config.minAmount <= amount <= config.maxAmount`
(`auto_savings_screen.dart:717-725`, CTA-enable check `:1224`). No multiple-of/step constraint
found in client code beyond the range check.

## RULE-SIP-005 — Frequency-specific required fields
Weekly requires `day` (day-of-week string, e.g. `"Monday"`); Monthly requires `date` (int, 1-28).
Daily requires neither. Payload only includes the field when the matching frequency is selected
(`services/sip_service.dart:98-103`).

## RULE-SIP-006 — Custom SIP runs on every selected date, every month
Not a single date like Monthly — 1 to 28 day-of-month values, the saving executes on **all** of
them each month (`services/custom_sip_service.dart:19-21`).

## RULE-SIP-007 — Market-closed guard is soft, and only on the creation screen
`isCurrentMarketClosed` (from `marketStatusProvider` socket data) disables the "Setup Auto
Savings" CTA and the "Manage Savings" footer button on `AutoSavingsScreen`
(`auto_savings_screen.dart:95,1230,1343`) but is **not** checked anywhere in
`ManageSavingsScreen`, `ManageCustomSavingsScreen`, or `SipCancelScreen` — pause/resume/cancel are
never blocked by market status client-side.

## RULE-SIP-008 — KYC gate on creation (both products)
SIP creation requires `profileProvider.user.kycStatus == 1`. Checked proactively client-side
before the bank-picker step (`auto_savings_screen.dart:1392-1400`, forces a fresh profile fetch
first to avoid a false "needs KYC" from a stale cache) and backstopped server-side two ways: a
200-OK response with `errorCode == 'KYC_REQUIRED'` (`:2254-2276` regular, `:2081-2096` custom) and
a thrown `KycRequiredFailure` (`:2287-2309` regular, `:2108-2124` custom). Both paths route through
`KycVerificationFlow.start(requestFrom:'sip')` and auto-retry the same creation call once verified.

## RULE-SIP-009 — Payment methods are server-driven, Card is Razorpay-only
`SipConfig.supportedPaymentMethods` (default `['upi','netbanking']` if the backend omits it,
`models/sip_models.dart:53,60,72-74`) drives which options `PaymentMethodSheet` offers. Per a
backend-mirroring code comment, Card is only included when Razorpay is the active gateway
(`sip_models.dart:49-52`). The UI's `'netbanking'` id is always relabeled "eMandate" for SIP
(`isRecurring: true`) and translated to the backend value `'emandate'` immediately before the
create call (`auto_savings_screen.dart:1993-1996, 2187-2192`).

## RULE-SIP-010 — eMandate requires bank details up front
Selecting eMandate requires bank details before mandate creation: primarily via a previously
registered/verified bank account (`BankAccountPickerScreen` — only `isVerified` accounts
selectable, `screens/bank_account_picker_screen.dart:100`), or via the legacy ad-hoc typed form
(`widgets/bank_details_sheet.dart`) with a regex-validated IFSC (`^[A-Z]{4}0[A-Z0-9]{6}$`, `:59`)
and account-number confirmation match.

## RULE-SIP-011 — Custom SIP bypasses field-level encryption (security gap, code-grounded)
`core/config/app_config.dart`'s `encryptedEndpoints` list (`:47-71`) includes only `sip/create`,
`sip/cancel`, `sip/pause` for this module. **`sip/resume` and every `sip/custom/*` endpoint
(create/list/pause/resume/cancel/status) are absent.** Confirmed via the interceptor's match logic
— `path.contains(e)` (`core/security/api_interceptor.dart:134,194`) — the string
`'sip/custom/create'` does not contain the substring `'sip/create'` (interrupted by `custom/`), so
it never matches. Consequence: Custom SIP creation's `amount` and (eMandate) `bank_account_number`/
`bank_ifsc`/`bank_beneficiary_name` fields — all listed in `AppConfig.sensitiveFields`
(`app_config.dart:74-99`) — are sent without the RSA-OAEP-SHA256 field-level encryption regular
SIP creation gets (still TLS-protected in transit, but missing the extra layer `AGENTS.md` §3
mandates for these exact field names). **Flagged as a `_SYSTEM/DANGER_ZONES.md` candidate** —
`unconfirmed` whether this is an intentional backend design choice or an oversight; verify with
backend before "fixing" (adding the path to `encryptedEndpoints` is a one-line client change but
must match what the backend actually expects to decrypt).

## RULE-SIP-012 — Cancel reasons are a fixed client-side enum
`sipCancelReasons` (`models/sip_models.dart:310-315`): `'No money'`, `'Change frequency'`,
`'Other saving method'`, `'Goal achieved'` — hardcoded, not backend-driven (unlike the SIP
Transactions filter's status/commodity options, which come from `sip/transaction-filter-options`).
A reason is mandatory before the Cancel button is enabled
(`screens/sip_cancel_screen.dart:200-202`).

## RULE-SIP-013 — Screen-entry data is always force-refreshed, never trusted from cache
`AutoSavingsScreen`, `SipOverviewScreen`, `SipTransactionHistoryScreen`, and
`SipTransactionDetailsScreen` all call `ref.invalidate(...)` in `initState` for their respective
non-autoDispose providers (`auto_savings_screen.dart:68`; `sip_overview_screen.dart:40-43`;
`sip_transaction_history_screen.dart:60-64`; `sip_transaction_details_screen.dart:43-46`) —
deliberate, per code comments, to avoid showing stale mandate/plan state after an out-of-band
change (e.g. the customer cancelling a mandate directly inside their UPI app).
