# History — Method Index

Alphabetical by class. All line numbers verified against the current source (2026-08-19).

## `HistoryNotifier` — `lib/features/history/controller/history_controller.dart`

| Method | Line | Signature / purpose | Callers |
|---|---|---|---|
| `HistoryNotifier(service, customerId)` (constructor) | 72 | Calls `_fetchFirstPage()` immediately on creation | `historyProvider` factory (line 175) |
| `loadInitial()` | 77 | Public wrapper for `_fetchFirstPage()` | Not directly called by any screen found — screens rely on the constructor's auto-fetch or `refresh()`; **unconfirmed external caller** |
| `applyFilter(filter)` | 85 | Stores the filter, then re-fetches page 1 (replaces all loaded pages) | `TransactionHistoryScreen._applyFilter` (`transaction_history_screen.dart:89`) |
| `_fetchFirstPage()` | 90 | `POST transactions/history` page 1, replaces state entirely; guards `_customerId == null` | `applyFilter`, `refresh`, constructor |
| `loadMore()` | 126 | Fetches `page + 1`, merges into existing `groupedData`/`transactions`; no-ops if already loading or `!hasMore` | `TransactionHistoryScreen._onScroll` (`transaction_history_screen.dart:58`) |
| `refresh()` | 166 | Alias for `_fetchFirstPage()` | Header refresh button (`transaction_history_screen.dart:178`), `RefreshIndicator.onRefresh` (`transaction_history_screen.dart:459`), `MainScreen` tab re-entry (`main_screen.dart:107`) |

## Top-level providers — `history_controller.dart`

| Provider | Line | Purpose | Watched/read by |
|---|---|---|---|
| `historyServiceProvider` | 8 | `Provider<HistoryService>` | `historyProvider`, `historyFilterOptionsProvider`, `transactionDetailsProvider` |
| `historyProvider` | 172-176 | `StateNotifierProvider<HistoryNotifier, HistoryPageState>` — **not** autoDispose, so loaded pages + scroll position survive navigating away and back within the session | `TransactionHistoryScreen`, `MainScreen` |
| `historyFilterOptionsProvider` | 181-189 | `FutureProvider.autoDispose<HistoryFilterOptions>` — `POST transactions/filter-options` | `TransactionHistoryScreen`, `TransactionFilterSheet` |
| `transactionDetailsProvider` | 191-199 | `FutureProvider.family<TransactionDetailResponse, String>` keyed by transaction ID — `POST transactions/details` | `TransactionDetailsScreen` |

## `HistoryService` — `lib/features/history/services/history_service.dart`

| Method | Line | Endpoint | Purpose | Callers |
|---|---|---|---|---|
| `getFilterOptions({customerId})` | 11-31 | `POST transactions/filter-options` | Fetches dynamic commodity/type/status filter choices | `historyFilterOptionsProvider` |
| `getTransactionHistory({customerId, page, limit, commodity, transactionType, status, dateFrom, dateTo})` | 37-71 | `POST transactions/history` | Fetches one page of the (optionally filtered) transaction list, grouped by date | `HistoryNotifier._fetchFirstPage`, `HistoryNotifier.loadMore` |
| `getTransactionDetails({customerId, transactionId})` | 73-92 | `POST transactions/details` | Fetches the full receipt/timeline for one transaction | `transactionDetailsProvider` |

All three methods throw a plain `Exception(message)` on `success == false` or a missing `data`
key — no dedicated `Failure` type mapping (see `BUSINESS_RULES.md` RULE-HISTORY-008 for the
AGENTS.md §5 implication).

## `TransactionHistoryScreen` — `lib/features/history/screens/transaction_history_screen.dart`

| Method | Line | Purpose |
|---|---|---|
| `_onScroll()` | 54-60 | Lazy-load trigger — fires `loadMore()` within 300px of scroll bottom |
| `_openFilterSheet(filterOptionsAsync)` | 72-83 | Opens `showTransactionFilterSheet`, applies result if non-null |
| `_applyFilter(filter)` | 87-90 | Updates local `_filter` state + calls `historyProvider.notifier.applyFilter` |
| `_removeChip(chipType)` | 93-112 | Clears one filter dimension (date/metal/type/status) and re-applies |
| `_buildRefreshButton` / `_buildFilterButton` | 174-234 | Header action widgets |
| `_buildBody` / `_buildActiveChipsRow` / `_buildList` / `_buildDateGroup` / `_buildTransactionCard` / `_buildEmptyState` | 237-772 | Presentational — render `historyState.groupedData` as-is (no client re-filtering) |
| `_statusColor(raw, statusOptions)` | 781-791 | Resolves a status's display color from backend `statusOptions`, falling back to `defaultStatusColorHex` |
| `_getTransactionIcon(type, metalName)` | 793-813 | Maps `(type, metal)` → an SVG asset path |

## `TransactionDetailsScreen` — `lib/features/history/screens/transaction_details_screen.dart`

| Method | Line | Purpose |
|---|---|---|
| `initState()` | 34-41 | `Future.microtask` invalidates `transactionDetailsProvider(id)` — forces a fresh fetch on every entry |
| `_buildContent` | 97-133 | Composes top/status/scheme-info/order-details cards based on transaction `type` |
| `_buildTopCard` | 135-270 | Icon, metal name, type label, amount, weight |
| `_buildStatusCard` | 272-450 | Timeline steps + tone-colored footer message + invoice download + "Save Again" CTA |
| `_statusTone(status, isDark)` | 455-499 | Maps a raw status string to `(color, badgeBgColor, badgeTextColor, icon)` — shared by timeline steps and the footer badge |
| `_buildTimelineStep` | 501-590 | Renders one timeline entry with connecting line, icon, badge, optional failure `reason` text |
| `_buildSchemeInfoCard` | 592-659 | SIP-only card (plan/frequency/amount/total saved/cycles) |
| `_buildOrderDetails` | 661-791 | Collapsible rate/quantity/value/GST/total + IDs (copy-to-clipboard) |
| `_buildDetailRow` | 793-854 | Hides itself when `value` is empty/`'N/A'`/`'null'`; copy button auto-clears clipboard after 60s |
| `_getTransactionIcon` | 856-876 | Duplicate of the list screen's icon-mapping logic (not shared/extracted) |

## `showTransactionFilterSheet` / `_TransactionFilterSheetState` — `transaction_filter_sheet.dart`

| Function/Method | Line | Purpose |
|---|---|---|
| `resolveHexColor(hex, fallback)` | 12-18 | Top-level helper — parses a `"#RRGGBB"` string to `Color`, `FF`-prefixing for alpha | Reused by `transaction_history_screen.dart` for status chip colors |
| `showTransactionFilterSheet({context, current, filterOptions})` | 39-53 | Opens the modal bottom sheet, returns the applied `TransactionFilter?` (`null` if dismissed) | `TransactionHistoryScreen._openFilterSheet` |
| `_pickDate({isFrom})` | 124-157 | Native date picker with from/to bounds enforcement | `_buildDateRange` |
| `_apply()` | 112-121 | Pops the sheet with the currently-selected `TransactionFilter` | Apply button |
| `_reset()` | 104-110 | Clears all local filter state (does not close the sheet) | Reset button, header "Reset All" |
| `_buildDynamicChipGroup` | 524-548 | Renders commodity/type/status chips strictly from `widget.filterOptions` (backend), with its own loading/error sub-states | `_buildSection` calls for Commodity/Type/Status |
