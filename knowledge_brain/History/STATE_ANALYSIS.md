# History — State Analysis

## Riverpod state graph

| Provider | Kind | Autodispose? | Notes |
|---|---|---|---|
| `historyServiceProvider` | `Provider<HistoryService>` | No | Plain stateless service wrapper around `ApiClient` |
| `historyProvider` | `StateNotifierProvider<HistoryNotifier, HistoryPageState>` | **No** | Deliberately kept alive so pages + scroll position survive tab switches within a session (see `MODULE_BRAIN.md` §4) |
| `historyFilterOptionsProvider` | `FutureProvider.autoDispose<HistoryFilterOptions>` | Yes | Re-fetched each time the screen/sheet mounts fresh |
| `transactionDetailsProvider` | `FutureProvider.family<TransactionDetailResponse, String>` | Not marked `.autoDispose` explicitly, but effectively bypassed via `ref.invalidate` on every screen entry (see RULE-HISTORY-009) | Family-keyed by transaction ID string |

## `HistoryPageState` (`history_controller.dart:14-55`)

```dart
class HistoryPageState {
  final List<TransactionItem> transactions;             // flat, accumulated across pages
  final Map<String, List<TransactionItem>> groupedData; // keyed by backend-supplied date string
  final bool isLoading;       // true only during the first-page fetch
  final bool isLoadingMore;   // true only during a loadMore() fetch
  final bool hasMore;         // from response pagination.has_next
  final int page;             // last successfully loaded page (0 = none yet)
  final String? error;
  bool get isEmpty => transactions.isEmpty;
}
```
Note: `isLoading` and `isLoadingMore` are mutually exclusive in practice — `_fetchFirstPage` sets
`isLoading`, `loadMore` sets `isLoadingMore`; nothing sets both simultaneously.

## `HistoryResponse` (`history_models.dart:1-44`)

```dart
class HistoryResponse {
  final List<TransactionItem> transactions;              // flattened from groupedData
  final Map<String, List<TransactionItem>> groupedData;   // from json['data']['grouped_transactions']
  final bool hasMore;                                     // from json['data']['pagination']['has_next']
}
```
`fromJson` tolerates two response shapes: a wrapper with a top-level `'data'` key, or the data
fields directly at the root (`history_models.dart:17-19`) — defensive parsing for API response
inconsistency.

## `TransactionItem` (`history_models.dart:46-89`)

```dart
class TransactionItem {
  final String transactionId;
  final String title;
  final String subtitle;       // default ''
  final String type;           // 'purchase' | 'sip' | 'referral' | 'offer' | (else → 'withdrawal' UI branch)
  final int soType;            // parsed, unconsumed — see RULE-HISTORY-013
  final double amount;
  final double weightGrams;
  final String displayDate;    // backend-formatted, used as-is (no client reformatting)
  final String status;         // free-text, matched case-insensitively against filter statuses
  final String metalName;      // default 'Gold 24K'
  final String date;           // the grouping date-key this item was found under
}
```
All numeric fields use `double.tryParse(...toString() ?? '0') ?? 0.0` — tolerant of the backend
sending numbers as either JSON numbers or strings. No rounding/precision handling beyond that;
display formatting (`toStringAsFixed`) happens purely at the UI layer.

## `TransactionDetailResponse` and nested models (`history_models.dart:91-273`)

```
TransactionDetailResponse
├── transactionId, orderId, title, subtitle
├── amount (String, not double — kept as raw display string), weightGrams (double)
├── metalName, scheduledDate, paymentMethod
├── timeline: List<TimelineStep>
├── footerMessage, invoiceNumber, invoiceUrl
├── priceBreakdown: PriceBreakdown
├── technicalDetails: TechnicalDetails
└── schemeInfo: SchemeInfo?          // present only for SIP-originated transactions
```
- `TimelineStep { stepName, status, time, reason }` — `reason` populated only on a "Failed" step.
- `PriceBreakdown { quantity, rate, value, gst, totalAmount }` — **all pre-formatted strings**
  (`'₹$rate'`, `'0.000123 gm'`) built inside `fromJson`, not raw numerics — the model itself owns
  currency/unit formatting rather than leaving it to the widget layer, unlike `TransactionItem`.
  Accepts either `quantity`/`gold_quantity`, `rate`/`gold_rate`, `value`/`gold_value` backend key
  variants (`history_models.dart:200-206`).
- `TechnicalDetails { transactionIdDisplay, goldTransactionId?, orderId, placedOn, paidVia }`.
- `SchemeInfo { schemeId, label, frequency, amount, totalSaved, cyclesDone, status }` — all
  amount fields kept as display strings, `schemeId`/`cyclesDone` as `int`.

## `TransactionFilter` (`transaction_filter.dart:11-75`)

```dart
class TransactionFilter {
  final DateTime? fromDate;   // null = no restriction
  final DateTime? toDate;
  final String? metalName;    // null/empty = "All"
  final String? type;
  final String? status;
  static const empty = TransactionFilter();
  bool get isEmpty => ...;          // true iff every field is null/empty
  int get activeCount => ...;       // 0-4, drives the badge count in the UI
  String? get dateFromParam => DateFormat('dd-MM-yyyy').format(fromDate!);  // backend format
  String? get dateToParam => ...;   // same format
}
```
Backend date format is `DD-MM-YYYY` — explicitly documented in the class doc comment as matching
the sibling `sip` module's filter convention.

## `HistoryFilterOptions` / `FilterOption` (`history_filter_options_model.dart`)

```dart
class FilterOption { final String value; final String label; final String? colorHex; }
class HistoryFilterOptions {
  final List<FilterOption> commodities;
  final List<FilterOption> transactionTypes;
  final List<FilterOption> statuses;
  static const empty = HistoryFilterOptions(commodities: [], transactionTypes: [], statuses: []);
}
```
`FilterOption.fromJson` tolerates `value`/`id`/`name` and `label`/`name` key variants
(`history_filter_options_model.dart:24-32`) — defensive against backend field-naming drift.

## Secure storage / persistence

None. No history data, filter state, or scroll position is written to
`flutter_secure_storage`/`shared_preferences` — everything is in-memory Riverpod state for the
duration of the app session (persisted across tab switches only because `historyProvider` is not
`autoDispose`, not because of any disk persistence). A fresh app cold-start always re-fetches
page 1 with an empty filter.
