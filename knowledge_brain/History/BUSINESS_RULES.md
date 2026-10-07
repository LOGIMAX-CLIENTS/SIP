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

### RULE-HISTORY-007 — Page 1 is re-fetched on every entry into History
*(Corrected 2026-10-07 — this rule previously said "manual refresh only"; the code has since
changed.)* Switching **to** the History tab from another tab calls
`historyProvider.notifier.refresh()` (not `invalidate`, so an applied filter survives) on every
visit after the first; a pushed `/transaction-history` route also refreshes in `initState`.
Pull-to-refresh and the header refresh icon are the other two triggers.
- Code: `main_screen.dart:100-102, 121-137`; `transaction_history_screen.dart:62-67`.
- Gaps: tapping History while already on it is a no-op (`main_screen.dart:102`), and popping back
  to the History tab from a pushed route (e.g. "Save Again" → Instant Saving → back) does not
  re-fetch — a transaction made that way needs a pull-to-refresh.
- Date groups come only from the backend's `grouped_transactions` keys
  (`history_models.dart:20-34`): a day with no transactions returned has no header at all — the
  app never inserts empty days.

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
- Same idea for metal (2026-10-07): when `price_breakdown` has no `quantity`/`gold_quantity`
  (`PriceBreakdown.hasMetal == false`), the Rate / Quantity / Value / CGST / SGST rows are not
  built at all — `fromJson` would otherwise fill them with ₹0 placeholders. Amount and the ID rows
  still show. Likewise the grams line under the amount (list row and top card) is hidden when
  `weight_grams` is 0. Code: `history_models.dart:250, 284`, `transaction_details_screen.dart:263,
  876`, `transaction_history_screen.dart:773`.

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

### RULE-HISTORY-014 — Refund progress is shown only from the backend's `refund` object
When `transactions/details` returns a `data.refund` object, the detail screen adds a "Refund
Status" card directly under Transaction Status: an overall status badge, the backend's refund
steps (same `step_name`/`status`/`time`/`reason` shape as the main timeline), then Refund
Amount / Refund To / Expected By / Refund ID (copy) / Bank Reference No. (copy) rows and an
optional tinted note. The app never derives refund stages, turnaround times, or the "expected by"
date itself — no `refund` object, no card.
- Step status vocabulary the UI colors: `Success`/`Refunded` → green check, `Pending`/`Processing`
  → amber clock, `Failed` → red, `Upcoming`/`Not Initiated` → grey outline circle (a step not yet
  reached). Overall badge uses the same mapping, so in-flight refunds should be `Processing`, not
  `Initiated` (which falls through to green).
- Contract status (2026-10-07): **backend merged to `phase1`, not in production.** Backend repo
  `fintect_application` PR #1441 (branch `feature/pg-refund-tracking`, merge `f3964a24`) records refunds
  the gateway reports (HDFC `AUTO_REFUNDED`, portal refunds) in a new `pg_refund` table and returns
  `refund` on `transactions/details` for a **cancelled** spot purchase only (`null` otherwise).
  What it sends: `status` `Processing`/`Refunded`/`Failed`; `refund_to` "Your UPI account" / "Your
  card" / "Your bank account" / "Original payment method" (never a VPA or digits); `expected_by`
  always `""` (no gateway gives one, so the row hides); two steps "Refund initiated" (Success) and
  "Refund processed" (Pending with empty time → Success/Failed). It never sends `Upcoming`. The
  Payment step reads `Success` when a refund exists, and the footer is refund-aware. Backend rule:
  that repo's `knowledge_brain/Transactions/BUSINESS_RULES.md` TXN-025. `apis.md` here is not updated.
- Code: `history_models.dart:162-209`, `transaction_details_screen.dart:121-125, 465-558,
  572-575, 601-608`. Test: `test/transaction_refund_status_test.dart`.

### RULE-HISTORY-015 — A refunded AutoPay setup charge is a History row
Setting up AutoPay (UPI/card) charges ₹10, which normally buys gold and shows as an ordinary
"AutoGold Autopay" purchase. When the backend's payer-account check rejects the mandate after
that debit, the plan is cancelled and the ₹10 refunded, and the backend lists it as its own row:
`transaction_id` `SIPAUTH{apm_id}`, `type: sip`, subtitle "AutoPay setup charge", `weight_grams`
0, status **Refund Processing** / **Refunded** / **Refund Failed**. Tapping it opens the normal
detail screen with the RULE-HISTORY-014 refund card and an amount-only breakdown
(RULE-HISTORY-010). The app adds nothing of its own: label, icon and colour come from
`type: sip` and the filter-options status colours. Fallback colours for the three statuses
(blue / green / red) are in `defaultStatusColorHex` (`history_filter_options_model.dart:97-109`).
- Backend (2026-10-07): `fintect_application` branch `feature/sip-auth-refund-history`, **not
  merged yet** — that repo's `knowledge_brain/Transactions/BUSINESS_RULES.md` TXN-026 and
  `knowledge_brain/SIP/BUSINESS_RULES.md` RULE-SIP-041.
- Not covered: a ₹10 the backend never recorded (the mandate failed before the payment webhook
  arrived), and the Auto Savings screen's own history (`sip/transactions`).
- Test: `test/transaction_refund_status_test.dart`.
