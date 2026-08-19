---
module: sip
last_updated: 2026-08-19
---

# SIP — State Analysis

## 1. Riverpod providers (`controller/sip_controller.dart`)

| Provider | Type | Auto-dispose? | Invalidated by |
|---|---|---|---|
| `sipServiceProvider` | `Provider<SipService>` | n/a | — |
| `customSipServiceProvider` | `Provider<CustomSipService>` | n/a | — |
| `sipConfigProvider` | `FutureProvider<SipConfig>` | yes | screen dispose |
| `sipGoldDenominationsProvider(int?)` | `FutureProvider.family` | yes | frequency change (new family key) |
| `sipSilverDenominationsProvider(int?)` | `FutureProvider.family` | yes | frequency change (new family key) |
| `sipDetailsProvider` | `FutureProvider<List<SipPlanDetail>>` | **no** | explicit `ref.invalidate` on every relevant screen entry/mutation (create, pause, resume, cancel, payment confirm) |
| `customSipSchemesProvider` | `FutureProvider<List<CustomSipScheme>>` | **no** | explicit invalidate after create/pause/resume/cancel |
| `customSipSchemeDetailsProvider` | `FutureProvider<List<CustomSipSchemeDetail>>` | **no** (composed from `listSchemes()` + per-scheme `getSchemeStatus()`, per-scheme failures swallowed) | explicit invalidate on `SipOverviewScreen` entry |
| `sipControllerProvider` | `StateNotifierProvider<SipNotifier, SipState>` | n/a (app-lifetime) | `SipNotifier.reset()`/individual setters |
| `sipHistoryProvider(String frequency)` | `StateNotifierProvider.family<SipHistoryNotifier, SipHistoryPageState, String>` | **no** | explicit invalidate (all 4 frequencies) on `SipTransactionHistoryScreen` entry; internal `refresh()`/`applyFilter()` |
| `sipHistoryFilterOptionsProvider` | `FutureProvider<SipTransactionFilterOptions>` | yes | screen dispose |
| `sipTransactionDetailsProvider(String transactionId)` | `FutureProvider.family` | no explicit `.autoDispose` modifier, but keyed per transaction id so old entries just accumulate until app restart — explicit `ref.invalidate` on `SipTransactionDetailsScreen` entry for the current id | — |

## 2. `SipState` shape (creation-form state, `sip_controller.dart:77-145`)

```dart
class SipState {
  int? selectedFrequencyId;      // 1=Daily, 2=Weekly, 3=Monthly (null before config loads)
  int? selectedCommodityId;
  double amount;                 // defaults 0
  String? selectedDay;           // Weekly only
  int? selectedDate;             // Monthly only
  List<SipPlanDetail> activePlans; // synced from sipDetailsProvider, not fetched by the notifier itself
  bool isCreating;
  String? errorMessage;
}
```
Note: `SipState` has no field for the "Custom" tab or `_selectedCustomDates` — those live purely
in `_AutoSavingsScreenState`'s local `bool _isCustomFrequency` / `Set<int> _selectedCustomDates`
(`screens/auto_savings_screen.dart:50,54`), not in Riverpod state at all. This means navigating
away and back to `AutoSavingsScreen` loses in-progress Custom-date selection (screen-local state,
not provider state) — expected Flutter behavior, noting it for forensic use.

## 3. `SipHistoryPageState` shape (`sip_controller.dart:210-251`)
Page-accumulating pagination state, one instance per frequency tab (family-keyed):
`transactions: List<TransactionItem>`, `groupedData: Map<String, List<TransactionItem>>`,
`isLoading`/`isLoadingMore`/`hasMore`/`page`/`error`. Mirrors the general Transaction History
module's pattern exactly (per code comment).

## 4. Model shapes (`models/sip_models.dart`, `models/sip_transaction_filter.dart`,
`models/sip_transaction_filter_options_model.dart`)

| Model | Key fields | Notes |
|---|---|---|
| `SipFrequency` | `id, name, isDefault` | |
| `SipCommodity` | `id, name` | |
| `SipConfig` | `minAmount, maxAmount, frequencies, commodities, supportedPaymentMethods` | Defaults `supportedPaymentMethods` to `['upi','netbanking']` if backend omits it |
| `SipDenomination` | `value, isPopular` | |
| `SipCreateResponse` | `success, message, errorCode?, subscriptionId?, status?, orderId?, sessionId?, environment?, authorizationLink?, paymentGateway (default 'cashfree'), keyId?, mode (default 'subscriptions'), customerId?, paymentMethod (default 'upi')` | Shared shape for both regular and Custom SIP create responses |
| `SipPlanDetail` | `subscriptionId, startDate, frequency, frequencyId, amount, status, commodityName, commodityId, day?, date?` | `isActive/isPaused/isPendingAuth/isOccupying` getters |
| `SipManageDetails` | `subscriptionId, startDate, amount, status, frequency, commodityName, day?, date?, cancelEligibleAt?, canCancelNow (default true)` | `canCancelNow` defaults `true` = "fails open" on an old app build missing the field (server-side cancel still enforces the real rule regardless) |
| `CancelReason` | `label, value` | `sipCancelReasons` const list of 4 |
| `CustomSipScheme` | `schemeId, label, amount, customDates: List<int>, commodityId?, status` | Lightweight — used for the date-picker ownership map |
| `CustomSipSchemeDetail` | `schemeId, label, subscriptionId, startDate?, amount, customDates, commodityName, status, cancelEligibleAt?, canCancelNow` | Full detail for the manage screen |
| `SipTransactionFilter` | `fromDate?, toDate?, commodity?, status?` | `dateFromParam`/`dateToParam` format `dd-MM-yyyy` |
| `SipTransactionFilterOptions` | `frequencies, commodities, statuses: List<FilterOption>` (from `history` module) | Backend-driven |

## 5. Secure storage / persistence

The `sip` module itself owns **no** secure-storage keys directly. It relies entirely on the
`core/security` layer's shared token/RSA-public-key storage — no SIP-specific
`flutter_secure_storage` writes were found anywhere in `lib/features/sip/`. Nothing SIP-specific
is cached to `shared_preferences` either. All "persistence" is provider-cache lifetime only (see
§1's autodispose column), explicitly invalidated per RULE-SIP-013.

## 6. Comparison to `daily_savings`

`daily_savings_screen.dart` has a single local `String _selectedAmount = '20'` — `setState` only,
zero Riverpod usage, zero providers. See `knowledge_brain/DailySavings/STATE_ANALYSIS.md` for
detail; not duplicated here since the modules don't interoperate (see CROSS_MODULE_MAP.md §0).
