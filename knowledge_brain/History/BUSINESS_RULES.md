# History — Business Rules

Format: `RULE-HISTORY-NNN`: plain-English rule → code that implements it.

---

### RULE-HISTORY-001 — Filtering is always server-side, never re-applied locally
Every fetch (initial, load-more, or a fresh `applyFilter`) sends the currently-active
`TransactionFilter` fields as request params. The list screen renders `groupedData` as-is; there
is no client-side filter/search over the already-loaded rows anywhere in this module.
- Code: `history_controller.dart:101-110, 133-142`, `transaction_history_screen.dart:239-246`.

### RULE-HISTORY-002 — Applying a filter discards all previously-loaded pages
`applyFilter` calls `_fetchFirstPage()`, which fully replaces `HistoryPageState` (not merges) —
switching filters always starts from a fresh page 1 under the new criteria.
- Code: `history_controller.dart:85-88, 111-116`.

### RULE-HISTORY-003 — Filter option choices come entirely from the backend
Commodity/transaction-type/status chip choices (and their display colors) are sourced from
`POST transactions/filter-options`, never hardcoded or derived from the locally-loaded
transaction list. A new status value added server-side (e.g. "Processing") appears in the filter
sheet without an app release.
- Code: `history_filter_options_model.dart` (whole file, especially the doc comment at the top),
  `transaction_filter_sheet.dart:520-548`.
- Fallbacks (`defaultTypeLabel`, `defaultStatusColorHex`,
  `history_filter_options_model.dart:75-111`) apply only when the backend list is
  loading/errored/missing a value for something already known client-side — they never invent
  new values.

### RULE-HISTORY-004 — Page size is 10, lazy-loaded 300px before the physical bottom
- Code: `history_controller.dart:59` (`pageSize = 10`), `transaction_history_screen.dart:54-60`
  (300px threshold).
- Note: the code comment on `pageSize` ("first 5, then +5 per scroll") describes a different,
  presumably earlier, spec — the live constant is 10 for every page including the first. Treat
  the comment as stale, the constant as authoritative.

### RULE-HISTORY-005 — `loadMore()` is idempotent under rapid scroll events
No-ops if a fetch (`isLoading` or `isLoadingMore`) is already in flight, or if the backend has
already reported no more pages (`!hasMore`) — prevents duplicate page requests from repeated
near-bottom scroll callbacks.
- Code: `history_controller.dart:128`.

### RULE-HISTORY-006 — Date groups can span page boundaries; merging is additive
When a `loadMore()` page arrives, its `groupedData` is merged into the existing map by
`dateKey`, appending to an existing list rather than overwriting it — a date that already has
rows from a prior page (e.g. "16 Aug 2026" spanning pages 2 and 3) accumulates correctly instead
of losing page-2's rows.
- Code: `history_controller.dart:144-150`.

### RULE-HISTORY-007 — No automatic refetch on tab switch; manual refresh only
Re-selecting the History tab after its first visit does **not** re-fetch by default — the
already-loaded pages and scroll position are preserved. `MainScreen` explicitly calls
`refresh()` (not `invalidate`) on every re-entry, which is the *sole* automatic refresh trigger
beyond pull-to-refresh and the header refresh button.
- Code: `main_screen.dart:96-108`, comment explains the "why" explicitly.
- Consequence: a transaction completed on another screen while History was last open will not
  appear until one of these three refresh paths fires.

### RULE-HISTORY-008 — Errors are surfaced as plain `Exception(message)`, not a `Failure` type
`HistoryService`'s three methods throw `Exception(errorMsg)` extracted from
`response.data['error']['message']` (or `internal_message`, or a generic fallback) — there is no
mapping to a dedicated `Failure` type as AGENTS.md §5 generally prescribes for the service layer.
`TransactionDetailsScreen` strips the `"Exception: "` prefix before display
(`transaction_details_screen.dart:60-61`); `HistoryNotifier` stores `e.toString()` directly in
`HistoryPageState.error` with no stripping (`history_controller.dart:118`) — a minor UI
inconsistency between the list and detail error surfaces, not a functional bug.

### RULE-HISTORY-009 — Detail view always fetches fresh; no cross-visit caching
`TransactionDetailsScreen` explicitly invalidates its `FutureProvider.family` entry on every
`initState`, bypassing Riverpod's normal per-argument caching — re-opening the same transaction
id later in the same session always re-fetches rather than showing a stale cached detail.
- Code: `transaction_details_screen.dart:38-40`.

### RULE-HISTORY-010 — Detail rows hide themselves when the value is empty/placeholder
`_buildDetailRow` returns `SizedBox.shrink()` for `value.isEmpty`, `'N/A'`, or `'null'` — a
missing field from the backend collapses the row entirely rather than showing a blank or literal
"null" to the user.
- Code: `transaction_details_screen.dart:796-799`.

### RULE-HISTORY-011 — Copied IDs auto-clear from the clipboard after 60 seconds
Tapping the copy icon next to Order ID / Transaction ID copies the value, then schedules a clear
of the clipboard 60 seconds later.
- Code: `transaction_details_screen.dart:836-841`.
- Consistent with AGENTS.md §3's general anti-clipboard-sniffing posture, applied here even
  though order/transaction IDs aren't classified as strictly sensitive fields.

### RULE-HISTORY-012 — SIP transactions get an extra Scheme Info card; other types don't
The `SchemeInfo` card only renders when `type == 'sip'` **and** `details.schemeInfo != null` —
absence of either condition (e.g. a SIP-typed transaction whose backend response omitted
`scheme_info`) silently skips the card with no placeholder/error shown.
- Code: `transaction_details_screen.dart:121-125`.

### RULE-HISTORY-013 — The `so_type` field is parsed but not consumed anywhere in the UI
`TransactionItem.soType` is populated from `json['so_type']` but no screen, filter, or business
logic in this module reads it. **Unconfirmed** whether it's reserved for a future feature (e.g.
distinguishing buy vs. sell direction within a type) or truly dead.
- Code: `history_models.dart:51, 64, 80`.
