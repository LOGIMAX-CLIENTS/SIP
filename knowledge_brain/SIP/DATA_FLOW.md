---
module: sip
last_updated: 2026-08-19
---

# SIP — Data Flows

## Flow A — Regular SIP creation (Daily / Weekly / Monthly)

1. `AutoSavingsScreen` (`screens/auto_savings_screen.dart:33`) mounts. `sipConfigProvider`
   (`controller/sip_controller.dart:17`) → `SipService.getConfig()` (`services/sip_service.dart:17`)
   → `POST sip/config` → `SipConfig{minAmount, maxAmount, frequencies, commodities,
   supportedPaymentMethods}` (`models/sip_models.dart:44`).
2. `sipDetailsProvider` (`sip_controller.dart:38`) → `SipService.getSipDetails()`
   (`sip_service.dart:123`) → `POST sip/details` → `List<SipPlanDetail>`. Forced fresh on every
   entry via `ref.invalidate` in `initState` (`auto_savings_screen.dart:68`). Synced into
   `SipState.activePlans` via `ref.listen` (`:124-129`) so the duplicate-plan guard
   (`SipState.hasActivePlanForFrequency`, `sip_controller.dart:125`) has current data.
3. User picks frequency + commodity (radio) + amount (denomination chip or manual entry, validated
   client-side against `config.minAmount`/`maxAmount`, `auto_savings_screen.dart:717-725`).
4. Tap "Setup Auto Savings" → `_onSetupTapped()` (`:1378`):
   a. **Proactive KYC gate** — force-refetches `pc.profileProvider`, checks `kycStatus == 1`
      (`:1392-1400`); if not verified, `KycVerificationFlow.start(requestFrom:'sip')`
      (`features/kyc/kyc_flow.dart:20`) runs inline before proceeding.
   b. Frequency dispatch: **Daily** → `_selectPaymentMethodAndCreate()` directly. **Weekly** →
      `_showWeeklyDayPicker()` (`:1483`, day required). **Monthly** → `_showMonthlyDatePicker()`
      (`:1617`, date 1-28 required). Both pickers call `_selectPaymentMethodAndCreate()` on Confirm.
5. `_selectPaymentMethodAndCreate()` (`:2165`): `Navigator.pushNamed(bankAccountPicker)` →
   `BankAccountPickerScreen` returns a `BankAccount` (only `isVerified` accounts selectable,
   `bank_account_picker_screen.dart:100`) → `PaymentMethodSheet(isRecurring: true,
   allowedMethodIds: config.supportedPaymentMethods)` — the UI id `'netbanking'` is translated to
   the backend value `'emandate'` right here (`:2187-2192`).
6. `_createSipPlan()` (`:2198`) → `SipService.createSip()` (`sip_service.dart:62`) → `POST
   sip/create` with `{frequency, commodity_id, amount, day?, date?, payment_method?,
   bank_account_id?, [emandate-only] bank_account_number/bank_ifsc/bank_beneficiary_name/
   bank_account_type}`. `sip/create` is in `AppConfig.encryptedEndpoints`
   (`core/config/app_config.dart:67`) so `amount`/`bank_account_number`/etc. are RSA-OAEP
   field-encrypted by the interceptor before send.
7. Response → `SipCreateResponse` (`sip_models.dart:97`):
   - `success && sessionId != null && orderId != null` → push `sipPayment` with the full gateway
     payload (`:2225-2241`).
   - `success` with no session/order → push `sipSuccess` directly (immediate-activation path).
   - `errorCode == 'KYC_REQUIRED'` (200-OK-wrapped backend rejection) → re-run
     `KycVerificationFlow.start` and retry `_createSipPlan()` once verified (`:2254-2276`).
   - `KycRequiredFailure` thrown (alternate HTTP-error path) → same retry logic (`:2287-2309`).
8. `SipPaymentScreen` (`sip_payment_screen.dart:45`) launches Cashfree Subscription Checkout
   (`:132-204`) or Razorpay AutoPay Checkout (`:257-331`) per `paymentData['payment_gateway']`.
9. SDK success callback → `_verifyMandateStatus()` (`:403`) → `SipService.confirmSip()`
   (`sip_service.dart:193`) → `POST sip/confirm{order_id, subscription_id?}` → backend re-checks
   mandate status with the gateway. `status ACTIVE | BANK_APPROVAL_PENDING` → `sipSuccess`; else
   → `sipFailure`. `sipDetailsProvider` invalidated either way (`:427`).
10. SDK failure callback → directly to `sipFailure` (no confirm call).

## Flow A′ — Custom SIP creation (parallel path)

Same screen, `_isCustomFrequency = true` (client-side toggle only, no backend frequency id).
1. `_onSetupTapped()` → `_showCustomDatesPicker()` (`:1790`). `customSipSchemesProvider`
   (`sip_controller.dart:48`) → `CustomSipService.listSchemes()`
   (`services/custom_sip_service.dart:55`) → `POST sip/custom/list` → non-terminal schemes.
   Dates already owned by an ACTIVE/PAUSED scheme render as committed (green/amber, tap → manage
   that scheme); free dates are multi-selectable (`:1802-1959`).
2. Confirm → same bank-account-picker + `PaymentMethodSheet` sequence as Flow A (`:1976-2003`).
3. `_createCustomSipPlan()` (`:2027`) → `CustomSipService.createCustomSip()`
   (`custom_sip_service.dart:23`) → `POST sip/custom/create{commodity_id, amount, custom_dates:
   List<int>, label?, bank_account_id?, payment_method?}`. **`sip/custom/create` is NOT in
   `encryptedEndpoints`** — see BUSINESS_RULES.md RULE-SIP-011 — `amount`/bank fields sent
   without field-level encryption.
4. Same `SipCreateResponse`-shaped result → same `sipPayment`/`sipSuccess` routing and same
   `KYC_REQUIRED` retry logic as Flow A (`:2047-2135`).
5. On success, `customSipSchemesProvider` invalidated (`:2050`) so the date grid reflects newly
   committed dates next time it opens.

## Flow B — Installment / recurring debit "processing"

**There is no client-triggered per-installment flow in this module.** Once a mandate reaches
`ACTIVE` (via Flow A/A′ step 9's `sip/confirm`), the periodic debit is executed by the payment
gateway (Cashfree/Razorpay) against the registered instrument on its own schedule — entirely
server/gateway-side, outside any app runtime code. `unconfirmed`: no manual "pay now" / retry
button exists anywhere in this module for a missed/failed cycle.

The app's role after activation is purely observational:
1. `SipTransactionHistoryScreen` (`/sip-transactions`) — 4 tabs (Daily/Weekly/Monthly/Custom), each
   backed by `sipHistoryProvider(frequency)` (`sip_controller.dart:360`,
   `SipHistoryNotifier`, `:253-353`). `_fetchFirstPage()`/`loadMore()` call
   `SipService.getSipTransactions()` (`sip_service.dart:219`) → `POST sip/transactions
   {frequency, page, limit, commodity?, status?, date_from?, date_to?}` → reuses the `history`
   module's `HistoryResponse` (grouped-by-date transaction list + pagination).
2. Filter sheet (`sip_transaction_filter_sheet.dart`) options come from
   `sipHistoryFilterOptionsProvider` → `getSipTransactionFilterOptions()`
   (`sip_service.dart:256`) → `POST sip/transaction-filter-options` (backend-driven).
3. Tapping a row → `SipTransactionDetailsScreen` (`/sip-transaction-details`) →
   `sipTransactionDetailsProvider(transactionId)` → `getSipTransactionDetails()`
   (`sip_service.dart:275`) → `POST sip/transaction-details` → reuses `history` module's
   `TransactionDetailResponse`/`TimelineStep` for the status timeline; optional invoice download
   via `InvoiceService.downloadInvoice()` → `AppRouter.invoiceViewer`
   (`sip_transaction_details_screen.dart:290-302`).
4. `SipOverviewScreen` (`/sip-overview`) shows the aggregate current-plan view (both products) —
   `sipDetailsProvider` + `customSipSchemeDetailsProvider`, both force-invalidated on entry
   (`sip_overview_screen.dart:40-43`).

## Flow C — Cancellation-eligibility check

1. Manage screen loads plan detail:
   - Regular: `ManageSavingsScreen._loadDetails()` (`manage_savings_screen.dart:39`) →
     `SipService.getManageDetails()` (`sip_service.dart:139`) → `POST sip/manage-details
     {subscription_id}` → `SipManageDetails` (`sip_models.dart:249`), which carries server-computed
     `cancelEligibleAt: DateTime?` and `canCancelNow: bool` (`:261,265` — parsed with `.toLocal()`,
     `:290-295`).
   - Custom: `ManageCustomSavingsScreen._loadDetails()` (`manage_custom_savings_screen.dart:44`) →
     `CustomSipService.getSchemeStatus()` (`custom_sip_service.dart:94`) → `POST
     sip/custom/{id}/status` → `CustomSipSchemeDetail` (`sip_models.dart:373`), same
     `cancelEligibleAt`/`canCancelNow` fields (`:382-383`).
   - The client **never independently computes** the 24h window — it only displays/re-checks the
     server-supplied values.
2. "Cancel Savings" action navigates to `sipCancel` with:
   - Regular: `{subscription_id, cancel_eligible_at, can_cancel_now}`
     (`manage_savings_screen.dart:213-218`) — `is_custom` omitted, defaults `false`
     (`app_router.dart:339`).
   - Custom: `{subscription_id, is_custom: true, scheme_id, cancel_eligible_at, can_cancel_now}`
     (`manage_custom_savings_screen.dart:204-211`).
3. `SipCancelScreen` (`sip_cancel_screen.dart:28`) computes `_isBlocked` (`:55-58`) on every
   `build()`:
   ```dart
   !widget.canCancelNow ||
     (widget.cancelEligibleAt != null && DateTime.now().isBefore(widget.cancelEligibleAt!))
   ```
   Not cached — if the customer sits on the screen across the eligibility boundary, the next
   rebuild (e.g. any parent state change) reflects the new state without a fresh API call.
4. **Blocked** → `_buildBlockedState()` (`:216-308`): red banner with `_blockedMessage`
   (`:60-68`, formats `cancelEligibleAt` as `d MMM yyyy, h:mm a`), only a "Back" button — no
   reason picker rendered at all, since attempting cancel would only fail server-side.
5. **Not blocked** → reason picker (`sipCancelReasons`, `sip_models.dart:310-315`, a fixed 4-item
   client-side enum) → confirm dialog (`_executeCancelConfirmation`, `:310-353`) →
   `_executeCancel()` (`:355-413`):
   - `isCustom == true` → `CustomSipService.cancelScheme()` (`custom_sip_service.dart:80`) →
     `POST sip/custom/{id}/cancel{reason}` — **not** in `encryptedEndpoints`.
   - else → `SipService.cancelSip()` (`sip_service.dart:175`) → `POST sip/cancel
     {subscription_id, reason}` — **is** in `encryptedEndpoints` (though `reason`/`subscription_id`
     aren't in `sensitiveFields`, so no field is actually encrypted here in practice).
6. On success: relevant provider invalidated (`sipDetailsProvider` or `customSipSchemesProvider`),
   toast shown, `Navigator.pop(context)` back to the manage screen (which itself reloads via the
   `.then((_) => _loadDetails())` chained on the original push, `manage_savings_screen.dart:219`).
