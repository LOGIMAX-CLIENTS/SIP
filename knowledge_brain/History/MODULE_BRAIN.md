# History — Module Brain

```
status: 🔵 100% (Round 1)
last_updated: 2026-08-19
owns: lib/features/history/  (controller/, models/, screens/, services/)
```

## 1. What this module is

The general Transaction History tab (bottom-nav index 2) — a server-paginated, server-filtered
list of every non-SIP transaction (Instant Saving purchases, Withdrawals, Referral rewards, Offer
rewards) plus a detail/receipt view. SIP has its own **separate** transaction-history screen and
controller in `features/sip/` that reuses this module's models but not its controller or
endpoints — see §6 and `CROSS_MODULE_MAP.md`.

`STARTGOLD_DOCUMENTATION.md` §3.27-3.28 covers this module in 4 lines ("Filterable list, date
range, transaction type filter, detailed receipt view") — directionally correct but far short of
the real surface: server-side pagination with lazy-load-on-scroll, a fully backend-driven filter
option set (not a hardcoded enum), and a 3-tier response shape (list + detail + scheme-info for
SIP-originated transactions). No material drift found, just under-documentation.

## 2. File inventory

| File | Role |
|---|---|
| `controller/history_controller.dart` | `HistoryNotifier` (page-accumulating list state), `historyProvider`, `historyFilterOptionsProvider`, `transactionDetailsProvider` |
| `models/history_models.dart` | `HistoryResponse`, `TransactionItem`, `TransactionDetailResponse`, `TimelineStep`, `PriceBreakdown`, `TechnicalDetails`, `SchemeInfo` — **also imported by the `sip` module** |
| `models/history_filter_options_model.dart` | `FilterOption`, `HistoryFilterOptions`, `defaultTypeLabel`, `defaultStatusColorHex` — **`FilterOption` also imported by `sip`** |
| `models/transaction_filter.dart` | `TransactionFilter` — local UI filter-sheet state, general-history-only (SIP has its own `SipTransactionFilter`) |
| `services/history_service.dart` | `HistoryService` — 3 Dio calls: filter options, history list, transaction details |
| `screens/transaction_history_screen.dart` | Route `/transaction-history` — the list screen, lazy-load, pull-to-refresh, filter chips |
| `screens/transaction_details_screen.dart` | Route `/transaction-details` — receipt/timeline/invoice view |
| `screens/transaction_filter_sheet.dart` | `showTransactionFilterSheet()` — modal bottom sheet, not a route |

## 3. Routes

| Route constant | Path | Screen | Registered |
|---|---|---|---|
| `AppRouter.transactionHistory` | `/transaction-history` | `TransactionHistoryScreen` | `app_router.dart:101,170` |
| `AppRouter.transactionDetails` | `/transaction-details` | `TransactionDetailsScreen(transactionData: {id, type})` | `app_router.dart:102,171-174` |

`TransactionHistoryScreen` is also rendered directly (not via named route) as bottom-nav tab index
2 inside `MainScreen` — `main_screen.dart:167-169`. Its back button checks
`ModalRoute.of(context)?.settings.name` to decide whether it was pushed as a route (pop) or is
the tab-shell instance (switch `selectedTabProvider` back to tab 0) —
`transaction_history_screen.dart:141-147`.

## 4. List screen: server pagination + server filtering (not client-side)

`HistoryNotifier` (`history_controller.dart:57-167`) holds `HistoryPageState` — **all pages
fetched so far, merged, never replaced** (except on a fresh filter/refresh). Key behaviors:

- **Page size**: `pageSize = 10` (`history_controller.dart:59`) — note the doc's "first 5, then
  +5" comment on that same line describes an *older* spec; the actual constant is 10 per page.
- **Lazy load trigger**: `transaction_history_screen.dart:54-60` fires
  `historyProvider.notifier.loadMore()` when the scroll position is within 300px of the bottom.
  `loadMore()` itself no-ops if a fetch is already in flight or `hasMore` is false
  (`history_controller.dart:128`), so repeated near-bottom scroll events are safe.
- **Filtering is 100% server-side**: `TransactionFilter` (commodity/type/status/date range) is
  sent as request params on *every* page fetch — initial, load-more, and re-filter
  (`history_controller.dart:101-110, 133-142`). There is no client-side re-filtering of an
  already-loaded list anywhere in this module.
- **Filter options are backend-driven, not hardcoded**: `historyFilterOptionsProvider`
  (`FutureProvider.autoDispose`) calls `POST transactions/filter-options`
  (`history_service.dart:11-31`) to get the actual commodities/types/statuses list (including
  optional per-status hex colors) — the filter sheet never invents its own enum of choices.
  `defaultTypeLabel`/`defaultStatusColorHex` (`history_filter_options_model.dart:75-111`) are
  fallbacks used only when the backend doesn't supply a label/color for a known raw value.
- **Manual refresh only, no tab-switch auto-refetch**: `MainScreen` calls
  `historyProvider.notifier.refresh()` (not `ref.invalidate`) when the History tab is
  re-selected *after* its first visit — deliberately preserves scroll position and loaded pages;
  a transaction made elsewhere won't appear until the user manually pulls-to-refresh or taps the
  header refresh icon, or backs fully out and re-enters (`main_screen.dart:96-108`,
  `transaction_history_screen.dart:174-199`).
- **Error/empty/loading semantics**: full-page spinner/error only shown on the true first load
  (`hasData == false`); once any data has loaded, a failed refresh/filter re-fetch keeps the
  existing list on screen (`history_controller.dart:117-119`, `transaction_history_screen.dart:
  121-133`).

## 5. Detail screen

`TransactionDetailsScreen` takes `{id, type}` via route arguments, always invalidates
`transactionDetailsProvider(id)` in `initState` (`transaction_details_screen.dart:38-40`) so
navigating in always fetches fresh data — no stale-detail caching across visits. Renders:
top card (icon/type/amount/weight), status card (timeline steps + tone-colored footer message +
optional invoice download button + "Save Again" CTA for non-SIP purchases), a collapsible Order
Details card (rate/quantity/value/GST/total + IDs with copy-to-clipboard), and — only when
`type == 'sip'` and `schemeInfo != null` — a SIP Plan Details card. Clipboard copy auto-clears
after 60 seconds (`transaction_details_screen.dart:838-841`) — a deliberate anti-clipboard-sniffing
measure, consistent with AGENTS.md §3's security posture even though transaction/order IDs aren't
classified as "sensitive fields" in the strict PII/financial-secret sense.

## 6. The SIP split (cross-module)

`features/sip/screens/sip_transaction_history_screen.dart` is a **separate screen with its own
controller** (`SipHistoryNotifier` in `sip_controller.dart`) and **separate endpoint**
(`POST sip/transactions`, frequency-tabbed — `sip_service.dart:219-250`), but it:
- imports and reuses `TransactionItem`, `HistoryResponse` from
  `features/history/models/history_models.dart` (`sip_transaction_history_screen.dart:15`,
  `sip_controller.dart:7`, `sip_service.dart` doc comment: "Reuses the same `HistoryResponse`
  model from the history module since the response structure ... is identical")
- imports `FilterOption` from `features/history/models/history_filter_options_model.dart`
  (`sip_transaction_history_screen.dart:16`)
- has its **own** `SipTransactionFilter` model (not `TransactionFilter`) and its own filter sheet
  (`sip_transaction_filter_sheet.dart`), because SIP's filter set includes a frequency tab
  (daily/weekly/monthly) that general history has no concept of.

This module (`history`) has **no** import of anything from `features/sip/` — the dependency is
one-directional (SIP → History models only). See `CROSS_MODULE_MAP.md` for the full picture and
why this is a reasonable split rather than a violation of AGENTS.md's feature-isolation rule
(model reuse through explicit imports, not reaching into another feature's controller/service).

## 7. Top risks

1. **Manual-refresh-only** (§4) means a transaction completed on another screen (e.g. just
   finished an Instant Saving purchase) will not appear in History until the user explicitly
   refreshes — worth confirming this is the intended UX, not a missed invalidation.
2. **`pageSize` doc-comment drift**: the code comment says "first 5, then +5" but the actual
   constant is 10 (`history_controller.dart:58-59`) — a stale comment, not a functional bug, but
   flag if touching this file.
3. **`so_type` field is parsed but never consumed** (`TransactionItem.soType`,
   `history_models.dart:51,64,80`) — unconfirmed purpose; likely a buy/sell direction flag not
   yet wired into the UI.
4. **Two independent filter-sheet implementations** (general history vs. SIP) with near-identical
   chip/date-range UI — duplication, not a bug, but a refactor candidate.

## 8. See also

- `METHOD_INDEX.md` — every public method, file:line, callers.
- `DATA_FLOW.md` — list load → lazy-load → filter → detail, end to end.
- `BUSINESS_RULES.md` — RULE-HISTORY-NNN.
- `CROSS_MODULE_MAP.md` — relationship to the `sip` module's separate history screens.
- `STATE_ANALYSIS.md` — exact model shapes.
- `FORENSIC_TEMPLATE.md` — symptom → suspect for history/detail bugs.
