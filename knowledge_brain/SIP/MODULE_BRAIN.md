---
module: sip
brain_status: 🟢 (Round 1, ~92% — see COVERAGE_TRACKER.md)
last_updated: 2026-08-19
round: 1
---

# SIP — Module Brain

## 0. TL;DR

`sip` implements **Systematic Investment Plans** ("Auto Savings" in the UI) — recurring gold/
silver purchases funded by a payment-gateway mandate (Cashfree Subscriptions or Razorpay AutoPay,
selected by the backend per request). It is one of the largest modules: 18 `.dart` files, 11
routes. Two distinct backend products live under one UI:

- **Regular SIP** (`SIPScheme` backend model) — Daily / Weekly / Monthly cadence, one active plan
  per (frequency, commodity) pair. `SipService` (`services/sip_service.dart`).
- **Custom SIP** (`CustomSIPScheme` backend model) — an arbitrary set of day-of-month dates
  (1–28), the saving runs on **every** selected date each month. No frequency id, own uniqueness
  rule (per date, not per frequency). `CustomSipService` (`services/custom_sip_service.dart`).

Both share the same create-response shape (`SipCreateResponse`), the same payment-gateway launch
screen (`SipPaymentScreen`), and the same success/failure screens — but are otherwise separate
API surfaces, separate manage screens, and (critically, see §7) separate encryption coverage.

The module has **no client-side per-installment trigger** — once a mandate is `ACTIVE`, the
periodic debit happens gateway-side/server-side on schedule. The app's role is: registration
(mandate setup), monitoring (plan status, transaction history), and lifecycle control
(pause/resume/cancel).

The sibling `daily_savings` module (see `knowledge_brain/DailySavings/`) is a **dead, disconnected
UI prototype** for the same "Daily" concept — not a real dependency of `sip`, do not treat it as
one. SIP's own "Daily" frequency (`frequencyId: 1`) is the real, live implementation.

## 1. Inventory

```
lib/features/sip/
├── controller/sip_controller.dart          (382 lines — all Riverpod providers/notifiers)
├── models/sip_models.dart                  (420 lines — 10 model classes)
├── models/sip_transaction_filter.dart      (73 lines)
├── models/sip_transaction_filter_options_model.dart (44 lines)
├── screens/auto_savings_screen.dart        (2367 lines — SIP + Custom SIP creation UI)
├── screens/bank_account_picker_screen.dart (243 lines)
├── screens/manage_custom_savings_screen.dart (568 lines)
├── screens/manage_savings_screen.dart      (611 lines)
├── screens/sip_cancel_screen.dart          (414 lines)
├── screens/sip_failure_screen.dart         (123 lines)
├── screens/sip_overview_screen.dart        (811 lines)
├── screens/sip_payment_screen.dart         (664 lines — Cashfree + Razorpay launch)
├── screens/sip_success_screen.dart         (151 lines)
├── screens/sip_transaction_details_screen.dart (682 lines)
├── screens/sip_transaction_filter_sheet.dart   (623 lines)
├── screens/sip_transaction_history_screen.dart (917 lines)
├── services/custom_sip_service.dart        (102 lines — 6 methods)
├── services/sip_service.dart               (293 lines — 13 methods)
└── widgets/bank_details_sheet.dart          (248 lines — eMandate ad-hoc bank form)
```
All 18 files were read. Route entries live externally in `lib/routes/app_router.dart` per the
codebase convention (`AGENTS.md` §1).

## 2. Architecture

Standard `Screen → Controller (Riverpod) → Service → ApiClient` layering, followed correctly.
`SipService`/`CustomSipService` both wrap the shared `core/network/api_client.dart` `ApiClient`
directly (no raw `Dio`). All endpoints are POST. State is Riverpod (`StateNotifier` for creation
form state and paginated history; `FutureProvider`/`FutureProvider.family` for everything
read-only) — no `setState`-only screens except pure local UI toggles (e.g. expand/collapse in
`sip_transaction_details_screen.dart`).

## 3. Route Table (11 entries, `app_router.dart`)

| Route constant | Path | Screen | Args |
|---|---|---|---|
| `autoSavings` | `/auto-savings` | `AutoSavingsScreen` | none |
| `sipManage` | `/sip-manage` | `ManageSavingsScreen` | `subscription_id` |
| `customSipManage` | `/custom-sip-manage` | `ManageCustomSavingsScreen` | `scheme_id` |
| `bankAccountPicker` | `/bank-account-picker` | `BankAccountPickerScreen` | none (also reused by Withdrawal) |
| `sipCancel` | `/sip-cancel` | `SipCancelScreen` | `subscription_id`, `cancel_eligible_at`, `can_cancel_now`, `is_custom`, `scheme_id` |
| `sipPayment` | `/sip-payment` | `SipPaymentScreen` | full gateway payload map |
| `sipSuccess` | `/sip-success` | `SipSuccessScreen` | `subscription_id`, `message` |
| `sipFailure` | `/sip-failure` | `SipFailureScreen` | `message`, `order_id` |
| `sipTransactions` | `/sip-transactions` | `SipTransactionHistoryScreen` | none |
| `sipTransactionDetails` | `/sip-transaction-details` | `SipTransactionDetailsScreen` | transaction map (needs `id`) |
| `sipOverview` | `/sip-overview` | `SipOverviewScreen` | none |

`app_router.dart:108-126` (constants), `:305-367` (builders). `SipCancelScreen` is shared between
regular and Custom SIP via the `is_custom`/`scheme_id` args — see DATA_FLOW.md Flow C.

## 4. Regular vs Custom SIP — key differences

| Aspect | Regular SIP | Custom SIP |
|---|---|---|
| Backend product | `SIPScheme` | `CustomSIPScheme` |
| Cadence | Daily / Weekly / Monthly (`frequencyId` 1/2/3) | Day-of-month set (1–28 entries), runs on ALL of them monthly |
| Uniqueness guard | One ACTIVE/PAUSED plan per (frequency, commodity) — `SipState.hasActivePlanForFrequency` (`sip_controller.dart:125`) | One ACTIVE/PAUSED scheme per day-of-month — `dateOwners` map (`auto_savings_screen.dart:1802`) |
| Create endpoint | `sip/create` | `sip/custom/create` |
| Manage endpoint | `sip/manage-details`, `sip/pause`, `sip/resume`, `sip/cancel` | `sip/custom/{id}/status`, `.../pause`, `.../resume`, `.../cancel` |
| Manage screen | `ManageSavingsScreen` | `ManageCustomSavingsScreen` |
| Field-level encryption | `sip/create`/`sip/cancel`/`sip/pause` ARE encrypted endpoints | **None of `sip/custom/*` are in `encryptedEndpoints`** — see §7, RULE-SIP-011 |
| Payment methods | UPI / Card (Razorpay only) / eMandate, per `SipConfig.supportedPaymentMethods` | Same sheet reused (`isRecurring:true`); comment history shows it used to be UPI-only, now supports the same set |
| Extra day/date field | `day` (Weekly) or `date` (Monthly) | `custom_dates: List<int>` |
| Create response shape | `SipCreateResponse` | Same `SipCreateResponse` shape (backend contract deliberately mirrored) |

## 5. Screens (see DATA_FLOW.md / METHOD_INDEX.md for depth)

- **AutoSavingsScreen** (`/auto-savings`) — creation UI for both products via a "Custom" tab
  toggle (`_isCustomFrequency`, client-side only, no backend frequency id). KYC-gated
  (`_onSetupTapped`, `:1378`). Duplicate-plan card shown instead of the setup form when one
  exists. Market-closed banner (soft, non-blocking on Manage) from `marketStatusProvider`.
- **BankAccountPickerScreen** (`/bank-account-picker`) — full-page select-and-return picker
  (`Navigator.push<BankAccount>`), only `isVerified` accounts tappable, reused by Withdrawal too.
- **ManageSavingsScreen** (`/sip-manage`) — regular SIP detail + Pause/Resume/Cancel/Support.
- **ManageCustomSavingsScreen** (`/custom-sip-manage`) — same for a Custom SIP scheme; shows a
  "Runs on" dates row instead of Frequency/Day/Date.
- **SipCancelScreen** (`/sip-cancel`) — reason picker + 24h cancellation-lock gate, shared by
  both products via `isCustom`/`schemeId`. See DATA_FLOW.md Flow C, RULE-SIP-001.
  ⚠️ **Drift vs `STARTGOLD_DOCUMENTATION.md`**: the hand-written doc doesn't mention the 24h
  lock-in at all (§3.21-3.26 just says "Cancel active subscription"). Code-verified rule; trust
  this brain.
- **SipPaymentScreen** (`/sip-payment`) — gateway-agnostic checkout launcher: Cashfree Subscription
  SDK or Razorpay Standard Checkout (AutoPay), chosen by `paymentData['payment_gateway']`. Converges
  on `sip/confirm` for both. Suppresses app-lock during Razorpay's UPI-app handoff.
- **SipSuccessScreen** / **SipFailureScreen** (`/sip-success`, `/sip-failure`) — terminal states;
  Failure's Retry pops with `'retry'` rather than navigating (caller must handle it — verify
  callers actually do, `SipPaymentScreen` itself never pushes `SipFailureScreen` expecting a pop
  result, so this may be dead code / unconfirmed intent).
- **SipOverviewScreen** (`/sip-overview`) — Profile-level summary across all 4 tabs (Daily/Weekly/
  Monthly/Custom), reuses the same plan-card pattern as AutoSavingsScreen's existing-plan card.
- **SipTransactionHistoryScreen** (`/sip-transactions`) — 4 independent lazy-paginated tabs
  (`sipHistoryProvider.family`), server-side filter (commodity chip + status/date-range sheet).
- **SipTransactionDetailsScreen** (`/sip-transaction-details`) — timeline + invoice download,
  reuses `history` module's `TransactionDetailResponse`/`TimelineStep` models wholesale.
- **BankDetailsSheet** (widget, not routed) — legacy ad-hoc eMandate bank-details form, shown when
  no bank account is already selected (superseded in the main flow by `BankAccountPickerScreen`,
  kept for the sheet's own internal reuse — unconfirmed if still reachable from the primary flow).

## 6. State / Providers (see STATE_ANALYSIS.md for full list)

`sip_controller.dart` owns everything: `sipServiceProvider`/`customSipServiceProvider`,
`sipConfigProvider`, `sipGoldDenominationsProvider`/`sipSilverDenominationsProvider` (family by
frequencyId), `sipDetailsProvider`, `customSipSchemesProvider`/`customSipSchemeDetailsProvider`,
`sipControllerProvider` (`SipNotifier`/`SipState` — the creation-form state), `sipHistoryProvider`
(family by frequency string — `SipHistoryNotifier`, page-accumulating), `sipHistoryFilterOptionsProvider`,
`sipTransactionDetailsProvider` (family by transaction id).

## 7. Security notes

- **`sip/create`, `sip/cancel`, `sip/pause`** are in `core/config/app_config.dart`'s
  `encryptedEndpoints` (`:67-69`) → their `amount`/`bank_account_number`/etc. fields get
  RSA-OAEP-SHA256 field-level encryption via `EncryptionService.encryptJson` before hitting the
  wire (`core/security/api_interceptor.dart:165-182`).
- **`sip/resume` and every `sip/custom/*` endpoint are NOT in that list** — confirmed by the
  interceptor's substring match (`path.contains(e)`, `api_interceptor.dart:134,194`): e.g.
  `'sip/custom/create'` does not contain the substring `'sip/create'`. Custom SIP's `amount` and
  (for eMandate) bank fields — all named in `AppConfig.sensitiveFields` — travel to the backend
  over TLS only, without the extra field-level encryption layer regular SIP creation gets. See
  **RULE-SIP-011** in BUSINESS_RULES.md — flagged as a `_SYSTEM/DANGER_ZONES.md` candidate.
- App-lock is suppressed during Razorpay's UPI-app handoff (`AppLifecycleObserver.suppressAppLock`,
  `sip_payment_screen.dart:298,320,339,374`) — matches `AGENTS.md` §3's documented intentional
  pattern, not a bug.
- Cashfree/Razorpay SDKs own all card/UPI credential entry — no custom card form exists here (PCI
  DSS compliant per `AGENTS.md` §3).

## 8. Payment gateways

Both **Cashfree** (`flutter_cashfree_pg_sdk`, Subscription Checkout flow — `CFSubscriptionSessionBuilder`
→ `CFSubscriptionPaymentBuilder` → `CFPaymentGatewayService.doPayment`) and **Razorpay**
(`razorpay_flutter`, Standard Checkout adapted for AutoPay — two sub-modes, `subscriptions` and
`recurring`, chosen by `paymentData['mode']`) are wired. The gateway is a **runtime backend
decision** (`SipCreateResponse.paymentGateway`), not a fixed app choice — do not assume Cashfree
when reading only part of `sip_payment_screen.dart`.

## 9. Top Risks

1. **RULE-SIP-011** — Custom SIP create/pause/resume/cancel bypass field-level encryption (see §7).
2. **Manual reconciliation surface only** — no client code verifies gateway-side debit success
   beyond `sip/confirm`'s one-time mandate-authorization check; ongoing installment health is
   entirely opaque to the app until it shows up in `sip/transactions`/`sip/details`. If a customer
   reports "shows active but no debit," there is no client-side signal to inspect (see
   FORENSIC_TEMPLATE.md #1).
3. **Client-computed cancel-eligibility relies on device clock** — `_isBlocked` compares
   `DateTime.now()` to a `.toLocal()`-converted server timestamp (`sip_cancel_screen.dart:55-58`,
   `sip_models.dart:290-292`); a skewed device clock or timezone bug could show the wrong gate
   state, though the actual cancel call is still server-enforced.
4. **Two competing bank-detail entry paths** — `BankAccountPickerScreen` (primary, used throughout
   `auto_savings_screen.dart`) vs `BankDetailsSheet` (ad-hoc typed form) — unclear if the latter is
   still reachable; verify before removing either.
5. **`daily_savings` confusion risk** (inherited, not sip's own bug) — see §0.

## 10. See Also

`METHOD_INDEX.md` · `DATA_FLOW.md` · `BUSINESS_RULES.md` · `CROSS_MODULE_MAP.md` ·
`STATE_ANALYSIS.md` · `FORENSIC_TEMPLATE.md` · `COVERAGE_TRACKER.md`
