# History — Forensic Template

Symptom → check first → likely suspects. Use alongside `_SYSTEM/DIAGNOSTIC_PLAYBOOK.md` once
that's built at the system level.

---

### Symptom: "A transaction I just completed doesn't show up in History"
**Check first**: was the History tab already visited this session (i.e. is
`_visitedTabs.contains(2)` already true in `MainScreen`)? Did the user manually refresh (pull-to-
refresh or the header refresh icon) since completing the transaction?
**Likely suspects**:
1. **This is expected behavior, not a bug** (RULE-HISTORY-007): the History tab does not
   auto-refetch on every tab switch by design — only on first-ever visit (constructor fetch) or
   an explicit `refresh()` call (tab re-entry, pull-to-refresh, header button). If none of those
   happened since the transaction completed, the list is legitimately stale.
2. Backend indexing/propagation delay — confirm the transaction actually exists server-side via
   the detail endpoint (`POST transactions/details`) before assuming a client bug.
3. The currently-applied `TransactionFilter` excludes the new transaction (e.g. a status filter
   set to "Success" while the new transaction is still "Pending") — check `_filter.activeCount`
   in the UI (the "N Filters" chip row) before assuming it's missing entirely.

---

### Symptom: "Scrolling to the bottom doesn't load more transactions"
**Check first**: `historyState.hasMore` — is the backend actually reporting more pages
(`pagination.has_next`)? Is `isLoadingMore` stuck `true`?
**Likely suspects**:
1. Backend genuinely has no more pages — not a bug, verify via `hasMore` in a debug watch.
2. `loadMore()`'s guard (`isLoading || isLoadingMore || !hasMore`) is stuck true because a
   prior fetch's `finally`/catch path didn't reset `isLoadingMore` — check
   `history_controller.dart:159-163`'s catch block did run (an *uncaught* exception type would
   skip the `state.copyWith(isLoadingMore: false)` reset entirely and wedge lazy-load forever).
3. `ScrollController` not attached / `_scrollController.hasClients` false at the moment of
   scroll (e.g. screen rebuilt with a new controller instance) — check
   `transaction_history_screen.dart:54-60`.

---

### Symptom: "Applying a filter shows stale or wrong results"
**Check first**: confirm the request actually sent to `POST transactions/history` includes the
expected filter params — this is 100% server-side (RULE-HISTORY-001); a wrong result is very
likely a backend filter-matching issue, not client logic re-filtering incorrectly (there is no
client-side filter step to get wrong).
**Likely suspects**:
1. `TransactionFilter.dateFromParam`/`dateToParam` format mismatch — client sends `DD-MM-YYYY`;
   confirm the backend expects exactly that format and not `YYYY-MM-DD` (a silent format
   mismatch would likely return an empty/wrong result set with no client-visible error).
2. `_filter.metalName`/`type`/`status` values must match the backend's `value` field from
   `historyFilterOptionsProvider`, not the display `label` — check `_TransactionFilterSheet`
   is sending `opt.value` (it is, per `transaction_filter_sheet.dart:575`) rather than the label.
3. A stale `filterOptionsAsync` (backend option list) diverged from what the history endpoint
   currently accepts — e.g. a status value renamed server-side; the filter sheet would show the
   old spelling until `historyFilterOptionsProvider` (autoDispose) is refetched on next mount.

---

### Symptom: "Transaction detail screen shows a loading spinner forever, or an error for a transaction that exists"
**Check first**: is `transactionDetailsProvider(id)` actually being invalidated with the correct
`id`? Log `widget.transactionData['id']` at `initState`.
**Likely suspects**:
1. Wrong/missing `id` in the route arguments — `TransactionDetailsScreen` trusts whatever
   `Map<String,dynamic>` it's given; if the caller passed the wrong key name (should be `'id'`,
   `transaction_history_screen.dart:598`) or a null value, `POST transactions/details` will be
   called with an empty/invalid `transaction_id`.
2. Backend `success: false` with no `error.message`/`error.internal_message` — falls through to
   the generic `'Failed to load transaction details'` string
   (`history_service.dart:84-86`) — check server logs for the real cause since the client error
   message is a fallback, not the actual reason.
3. `ref.invalidate` firing every `initState` (RULE-HISTORY-009) means a rapid back-then-forward
   navigation re-triggers a full fetch each time — if the screen appears to "never finish
   loading," check for a navigation loop causing repeated invalidate/re-mount cycles rather than
   a single stuck request.

---

### Symptom: "SIP transactions don't appear in general History (or vice versa)"
**Check first**: which screen/endpoint is actually being viewed — `/transaction-history` (general,
`POST transactions/history`) vs. `/sip-transactions` (SIP-specific, `POST sip/transactions`)?
**Likely suspects**:
1. **This may be expected** — confirm whether the backend's `transactions/history` endpoint is
   supposed to include SIP-originated transactions (the general history screen's UI does render a
   `'sip'` type case, `transaction_history_screen.dart:554,562-563`, implying SIP transactions
   *can* appear there) or whether SIP transactions are meant to be exclusively in the dedicated
   SIP history screen. This module brain did not trace the backend's inclusion logic —
   **unconfirmed**, verify against the `sip` module brain and/or backend behavior before treating
   this as a client bug.
2. If a SIP transaction is missing from the *dedicated* SIP screen specifically, that's a `sip`
   module issue (`SipHistoryNotifier`/`sip/transactions` endpoint) — out of this brain's scope,
   see the `sip` module brain.

---

### Symptom: "Filter sheet shows 'Unable to load options' or an empty chip section"
**Check first**: `historyFilterOptionsProvider`'s `AsyncValue` state — is it `error` or `data`
with an empty list for that section?
**Likely suspects**:
1. `POST transactions/filter-options` failed or returned a shape `HistoryFilterOptions.fromJson`
   couldn't parse (e.g. `commodities`/`transaction_types`/`statuses` keys renamed server-side —
   `parseList` silently returns `[]` for any key that isn't a `List` at all,
   `history_filter_options_model.dart:54-61`, so a renamed key produces an empty section with no
   explicit error, not a parse exception).
2. Since `historyFilterOptionsProvider` is `autoDispose`, if the filter sheet is opened
   immediately after the screen mounts (before the provider has resolved), the sheet's own
   `.when(loading: ...)` branch should show — if it instead shows an empty chip list with no
   spinner, check that `_buildDynamicChipGroup` is receiving the live `AsyncValue` and not a
   stale snapshot passed in at sheet-open time (it's passed as a constructor parameter, not
   re-watched inside the sheet — `transaction_filter_sheet.dart:57`, so a filter-options fetch
   that resolves *while the sheet is already open* will not update the sheet's chips until the
   sheet is reopened).
