# History — Coverage Tracker

## Round 1 — 2026-08-19 — Build

| Dimension | Weight | Actual count | Documented | Coverage |
|---|---|---|---|---|
| Screens | 25% | 3 (`TransactionHistoryScreen`, `TransactionDetailsScreen`, `_TransactionFilterSheet`/`showTransactionFilterSheet`) | 3/3, full method breakdown in `METHOD_INDEX.md`, full flows in `DATA_FLOW.md` | 100% |
| Controller/service public methods | 25% | 9 (`HistoryNotifier`: `loadInitial`, `applyFilter`, `_fetchFirstPage`, `loadMore`, `refresh` = 5; `HistoryService`: `getFilterOptions`, `getTransactionHistory`, `getTransactionDetails` = 3; `showTransactionFilterSheet` = 1) | 9/9 in `METHOD_INDEX.md` | 100% |
| Models | 15% | 9 classes (`HistoryPageState`, `HistoryResponse`, `TransactionItem`, `TransactionDetailResponse`, `TimelineStep`, `PriceBreakdown`, `TechnicalDetails`, `SchemeInfo`, `TransactionFilter`) + 2 (`FilterOption`, `HistoryFilterOptions`) = 11 total | 11/11 field-by-field in `STATE_ANALYSIS.md` | 100% |
| API/protocol surface | 15% | 3 REST endpoints (`transactions/filter-options`, `transactions/history`, `transactions/details`) | 3/3 documented with request params and response shape | 100% |
| Business rules | 10% | 13 rules extracted | 13 in `BUSINESS_RULES.md` (RULE-HISTORY-001 through 013) | 100% |
| Cross-module deps | 10% | 1 major cross-module relationship (SIP model reuse) + 2 core deps (`api_client.dart`, `user_provider.dart`) + 1 minor (`invoice_service.dart`) | All mapped with Mermaid graph in `CROSS_MODULE_MAP.md` | 100% |

**Weighted total: 100%**
**Badge: 🔵 100% + verified**

### Manual spot-check (required for 🔵)
Every `.dart` file under `lib/features/history/` was read in full during this build (8 files,
not summarized from a prior pass): `history_controller.dart` (200 lines),
`history_filter_options_model.dart` (112 lines), `history_models.dart` (274 lines),
`transaction_filter.dart` (76 lines), `history_service.dart` (94 lines),
`transaction_history_screen.dart` (815 lines), `transaction_details_screen.dart` (878 lines),
`transaction_filter_sheet.dart` (722 lines). Cross-checked against the SIP module's reuse via
targeted reads of `sip_transaction_history_screen.dart` imports, `sip_controller.dart`'s
`SipHistoryNotifier`, and `sip_service.dart`'s `getSipTransactions`/endpoint.
Also confirmed route registration in `app_router.dart` and tab-shell integration in
`main_screen.dart`.

### Drift found vs `STARTGOLD_DOCUMENTATION.md` §3.27-3.28
No factual drift — the hand-written doc's claims ("Filterable list, date range, transaction type
filter, detailed receipt view") are all confirmed true, just far less detailed than the actual
implementation (no mention of server-side pagination, lazy-load-on-scroll, the backend-driven
filter-option system, the manual-refresh-only tab behavior, or the SIP/general split). Logged as
an **under-documentation** note (not a correctness discrepancy) to
`_OVERVIEW/BUILD_SUMMARY.md` per AGENTS.md §10.

### Known gaps (not blocking 🔵, but flagged for future rounds)
- `TransactionItem.soType`'s purpose is unconfirmed — parsed but unused anywhere found in this
  module (RULE-HISTORY-013). Revisit once the backend contract or a future UI use is known.
- Whether SIP-originated transactions are included in the *general* `transactions/history`
  response (in addition to the dedicated `sip/transactions` endpoint) was not confirmed against
  backend behavior — flagged in `FORENSIC_TEMPLATE.md`. The general list screen's UI clearly
  anticipates a `'sip'` type appearing there, but this brain only verified client-side handling,
  not the backend's actual inclusion rule.
- `historyProvider.loadInitial()` has no confirmed caller — likely a public convenience method
  never actually invoked outside the constructor's own auto-fetch; not removed/flagged as dead
  code definitively since it's plausible a future screen could use it.
