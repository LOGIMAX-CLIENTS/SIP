---
module: sip
last_updated: 2026-08-19
---

# SIP — Method Index

Alphabetical by class. `file:line` → primary caller(s). Screens/widgets that are pure UI builders
(`_buildXxx()`) are omitted except where they carry logic (validation, navigation).

## AutoSavingsScreen (`screens/auto_savings_screen.dart`)

| Method | Location | Purpose | Called by |
|---|---|---|---|
| `_createCustomSipPlan()` | `:2027` | POSTs `sip/custom/create`, routes to payment/success, retries after KYC | `_showCustomDatesPicker()` confirm button |
| `_createSipPlan()` | `:2198` | POSTs `sip/create`, routes to payment/success, retries after KYC | `_selectPaymentMethodAndCreate()` |
| `_listenDenominations()` | `:215` | Seeds amount field from the popular denomination | `build()` |
| `_onSetupTapped()` | `:1378` | KYC gate → frequency dispatch (Daily direct / Weekly / Monthly / Custom picker) | "Setup Auto Savings" CTA |
| `_selectPaymentMethodAndCreate()` | `:2165` | Bank picker → PaymentMethodSheet → `_createSipPlan` | `_onSetupTapped` (Daily), day/date pickers' Confirm |
| `_showCustomDatesPicker()` | `:1790` | Multi-select date grid; committed dates route to manage instead of selecting | `_onSetupTapped` (Custom tab) |
| `_showMonthlyDatePicker()` | `:1617` | Single-date grid (1-28) | `_onSetupTapped` (Monthly) |
| `_showWeeklyDayPicker()` | `:1483` | Day-of-week list | `_onSetupTapped` (Weekly) |

## BankAccountPickerScreen (`screens/bank_account_picker_screen.dart`)

| Method | Location | Purpose |
|---|---|---|
| `build()` | `:28` | Lists `bankAccountsProvider` accounts; only `isVerified` ones tappable/selectable; "Add Bank Account" opens `showAddBankAccountSheet` |

## BankDetailsSheet (`widgets/bank_details_sheet.dart`)

| Method | Location | Purpose |
|---|---|---|
| `_submit()` | `:70` | Validates form (name ≥4 chars, account# ≥6 digits + confirm match, IFSC regex), calls `widget.onSubmit(BankDetails)` |

## CustomSipService (`services/custom_sip_service.dart`)

| Method | Location | Endpoint | Called by |
|---|---|---|---|
| `cancelScheme()` | `:80` | `POST sip/custom/{id}/cancel` | `SipCancelScreen._executeCancel()` (`sip_cancel_screen.dart:361`) |
| `createCustomSip()` | `:23` | `POST sip/custom/create` | `AutoSavingsScreen._createCustomSipPlan()` (`:2037`) |
| `getSchemeStatus()` | `:94` | `POST sip/custom/{id}/status` | `ManageCustomSavingsScreen._loadDetails()` (`:51`); `customSipSchemeDetailsProvider` (`sip_controller.dart:66`) |
| `listSchemes()` | `:55` | `POST sip/custom/list` | `customSipSchemesProvider` (`sip_controller.dart:51`); `AutoSavingsScreen._showCustomDatesPicker()` (`:1793`) |
| `pauseScheme()` | `:66` | `POST sip/custom/{id}/pause` | `ManageCustomSavingsScreen._executePause()` (`:461`) |
| `resumeScheme()` | `:73` | `POST sip/custom/{id}/resume` | `ManageCustomSavingsScreen._executeResume()` (`:521`) |

## ManageCustomSavingsScreen (`screens/manage_custom_savings_screen.dart`)

| Method | Location | Purpose |
|---|---|---|
| `_executePause()` | `:457` | Pauses scheme, invalidates `customSipSchemesProvider`, reloads |
| `_executeResume()` | `:517` | Resumes scheme, invalidates `customSipSchemesProvider`, reloads |
| `_loadDetails()` | `:44` | Fetches `CustomSipSchemeDetail` via `getSchemeStatus()` |
| Cancel action `onTap` | `:200-213` | Navigates to `sipCancel` with `is_custom: true`, `scheme_id` |

## ManageSavingsScreen (`screens/manage_savings_screen.dart`)

| Method | Location | Purpose |
|---|---|---|
| `_executePause()` | `:477` | `SipService.pauseSip()`, invalidates `sipDetailsProvider` |
| `_executeResume()` | `:557` | `SipService.resumeSip()`, invalidates `sipDetailsProvider` |
| `_loadDetails()` | `:39` | Fetches `SipManageDetails` via `getManageDetails()` |
| Cancel action `onTap` | `:209-220` | Navigates to `sipCancel` (no `is_custom`/`scheme_id` — regular SIP only) |

## SipCancelScreen (`screens/sip_cancel_screen.dart`)

| Method | Location | Purpose |
|---|---|---|
| `_blockedMessage` (getter) | `:60` | Formats the "cannot cancel before {date}" message |
| `_executeCancel()` | `:355` | Routes to `CustomSipService.cancelScheme()` or `SipService.cancelSip()` depending on `widget.isCustom` |
| `_executeCancelConfirmation()` | `:310` | Confirm dialog before `_executeCancel()` |
| `_isBlocked` (getter) | `:55` | `!canCancelNow \|\| now.isBefore(cancelEligibleAt)` — re-evaluated every build |

## SipController providers (`controller/sip_controller.dart`)

| Provider | Location | Type | Notes |
|---|---|---|---|
| `customSipSchemeDetailsProvider` | `:59` | `FutureProvider<List<CustomSipSchemeDetail>>` | Per-scheme failures skipped, not fatal |
| `customSipSchemesProvider` | `:48` | `FutureProvider<List<CustomSipScheme>>` | Not autoDispose — explicit invalidation after mutations |
| `customSipServiceProvider` | `:14` | `Provider<CustomSipService>` | |
| `sipConfigProvider` | `:17` | `FutureProvider.autoDispose<SipConfig>` | |
| `sipControllerProvider` | `:199` | `StateNotifierProvider<SipNotifier, SipState>` | Creation-form state |
| `sipDetailsProvider` | `:38` | `FutureProvider<List<SipPlanDetail>>` | Not autoDispose — explicit invalidation |
| `sipGoldDenominationsProvider` | `:24` | `FutureProvider.autoDispose.family<..., int?>` | Keyed by frequencyId |
| `sipHistoryFilterOptionsProvider` | `:367` | `FutureProvider.autoDispose<SipTransactionFilterOptions>` | |
| `sipHistoryProvider` | `:360` | `StateNotifierProvider.family<SipHistoryNotifier, SipHistoryPageState, String>` | Keyed by frequency name |
| `sipServiceProvider` | `:10` | `Provider<SipService>` | |
| `sipSilverDenominationsProvider` | `:31` | `FutureProvider.autoDispose.family<..., int?>` | Keyed by frequencyId |
| `sipTransactionDetailsProvider` | `:376` | `FutureProvider.family<Map, String>` | Keyed by transaction id |

## SipHistoryNotifier (`controller/sip_controller.dart:253-353`)

| Method | Location | Purpose |
|---|---|---|
| `_fetchFirstPage()` | `:283` | Page-1 fetch, replaces state, keeps old data visible while loading |
| `applyFilter()` | `:278` | Sets filter, re-fetches page 1 |
| `loadInitial()` | `:272` | Alias for `_fetchFirstPage()` |
| `loadMore()` | `:314` | Appends next page; no-op while loading or `!hasMore` |
| `refresh()` | `:352` | Alias for `_fetchFirstPage()` |

## SipNotifier (`controller/sip_controller.dart:147-197`)

| Method | Location | Purpose |
|---|---|---|
| `reset()` | `:190` | Clears form fields, keeps frequency/commodity/activePlans |
| `setActivePlans()` | `:174` | Syncs `sipDetailsProvider` result for duplicate-plan checks |
| `setAmount()` | `:162` | |
| `setCommodity()` | `:158` | |
| `setCreating()` | `:178` | |
| `setDate()` | `:170` | Monthly |
| `setDay()` | `:166` | Weekly |
| `setError()` | `:182` | |
| `setFrequency()` | `:150` | Also clears `selectedDay`/`selectedDate` |

## SipPaymentScreen (`screens/sip_payment_screen.dart`)

| Method | Location | Purpose |
|---|---|---|
| `_friendlyRazorpayErrorMessage()` | `:351` | Maps Razorpay error codes/messages to user text (handles literal `"undefined"` string) |
| `_launchRazorpayAutoPay()` | `:257` | Builds Razorpay Checkout options (`subscriptions` vs `recurring` mode) |
| `_launchSubscriptionCheckout()` | `:132` | Builds/launches Cashfree `CFSubscriptionPaymentBuilder` |
| `_onRazorpayError()` | `:372` | → `sipFailure` route |
| `_onRazorpaySuccess()` | `:337` | → `_verifyMandateStatus()` |
| `_onSubscriptionFailure()` | `:220` | → `sipFailure` route |
| `_onSubscriptionVerify()` | `:212` | → `_verifyMandateStatus()` |
| `_verifyMandateStatus()` | `:403` | `POST sip/confirm`; routes to `sipSuccess`/`sipFailure` by response status |
| `didChangeAppLifecycleState()` | `:106` | 2s-delayed fallback verify if SDK callback never fires on resume |

## SipService (`services/sip_service.dart`)

| Method | Location | Endpoint | Called by |
|---|---|---|---|
| `cancelSip()` | `:175` | `POST sip/cancel` | `SipCancelScreen._executeCancel()` |
| `confirmSip()` | `:193` | `POST sip/confirm` | `SipPaymentScreen._verifyMandateStatus()` (`:419`) |
| `createSip()` | `:62` | `POST sip/create` | `AutoSavingsScreen._createSipPlan()` (`:2208`) |
| `getConfig()` | `:17` | `POST sip/config` | `sipConfigProvider` |
| `getGoldDenominations()` | `:28` | `POST sip/gold-denominations` | `sipGoldDenominationsProvider` |
| `getManageDetails()` | `:139` | `POST sip/manage-details` | `ManageSavingsScreen._loadDetails()` |
| `getSilverDenominations()` | `:42` | `POST sip/silver-denominations` | `sipSilverDenominationsProvider` |
| `getSipDetails()` | `:123` | `POST sip/details` | `sipDetailsProvider` |
| `getSipTransactionDetails()` | `:275` | `POST sip/transaction-details` | `sipTransactionDetailsProvider` |
| `getSipTransactionFilterOptions()` | `:256` | `POST sip/transaction-filter-options` | `sipHistoryFilterOptionsProvider` |
| `getSipTransactions()` | `:219` | `POST sip/transactions` | `SipHistoryNotifier._fetchFirstPage()`/`loadMore()` |
| `pauseSip()` | `:153` | `POST sip/pause` | `ManageSavingsScreen._executePause()` |
| `resumeSip()` | `:164` | `POST sip/resume` | `ManageSavingsScreen._executeResume()` |

## SipState (`controller/sip_controller.dart:77-145`)

| Method | Location | Purpose |
|---|---|---|
| `copyWith()` | `:98` | Nullable-field clearing via `clearDay`/`clearDate`/`clearError` flags |
| `getActivePlanForFrequency()` | `:135` | First matching ACTIVE/PAUSED plan |
| `hasActivePlanForFrequency()` | `:125` | Duplicate-plan guard predicate |

## Model helper getters (`models/sip_models.dart`)

| Getter | Class | Location |
|---|---|---|
| `isActive`/`isPaused`/`isPendingAuth`/`isOccupying` | `SipPlanDetail` | `:232-244` |
| `isActive`/`isPaused`/`isOccupying` | `CustomSipScheme` | `:344-353` |
| `isActive`/`isPaused` | `CustomSipSchemeDetail` | `:398-399` |
