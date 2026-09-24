# History — Data Flow

## Flow 1: First load of the Transaction History tab

```
1. MainScreen renders TransactionHistoryScreen for the first time when the user taps the
   "History" bottom-nav item (index 2) — main_screen.dart:167-169, _visitedTabs.add(2)

2. TransactionHistoryScreen.build() → ref.watch(historyProvider)                  line 117
   → historyProvider (StateNotifierProvider, not autoDispose) is created for the first time
     → ref.read(userProvider) resolves the logged-in customer id                  history_controller.dart:174
     → HistoryNotifier(service, customerId) constructed
       → constructor immediately calls _fetchFirstPage()                          line 72-75

3. _fetchFirstPage()                                                              line 90
   → guards: if customerId == null → state = error('User not logged in'), return
   → state = state.copyWith(isLoading: true, clearError: true)   (list, if any, stays visible)
   → HistoryService.getTransactionHistory(customerId, page:1, limit:10,
       commodity: _filter.metalName, transactionType: _filter.type, status: _filter.status,
       dateFrom/dateTo: _filter.date*Param)                                       line 101-110
     → POST transactions/history via ApiClient (Dio)                              history_service.dart:48
   → HistoryResponse.fromJson(response.data['data'])                              history_models.dart:15-41
     → parses grouped_transactions (Map<dateKey, List<TransactionItem>>) into both
       a flat list and the grouped map; pagination.has_next → hasMore
   → state = HistoryPageState(transactions, groupedData, hasMore, page:1)         line 111-116

4. Screen rebuilds with hasData=true (or shows the empty/error state) →
   _buildBody renders historyState.groupedData directly — no local re-filtering
   (server already applied the filter, which is empty on first load)              transaction_history_screen.dart:237-262

5. In parallel, ref.watch(historyFilterOptionsProvider)                            transaction_history_screen.dart:118
   → POST transactions/filter-options                                             history_service.dart:11-31
   → HistoryFilterOptions.fromJson — commodities/transactionTypes/statuses lists,
     each optionally carrying a backend hex color                                 history_filter_options_model.dart:53-68
   → used for: filter sheet chip choices, and _statusColor() fallback resolution on cards
```

## Flow 2: Scroll-triggered lazy load

```
1. User scrolls the ListView; ScrollController fires _onScroll()                  transaction_history_screen.dart:54
2. position.pixels >= maxScrollExtent - 300 → ref.read(historyProvider.notifier).loadMore()
3. loadMore()                                                                     history_controller.dart:126
   → early-return if isLoading || isLoadingMore || !hasMore  (dedupes repeated scroll events)
   → state = state.copyWith(isLoadingMore: true)   → bottom spinner appears (_buildBottomLoader)
   → HistoryService.getTransactionHistory(page: state.page + 1, ...same filter params...)
   → response merged: for each dateKey in the new response's groupedData, append to the
     existing list at that key (or create it) — a date group can legitimately span a page
     boundary, so this is an append, never an overwrite                           line 144-150
   → state = state.copyWith(transactions: [...old, ...new], groupedData: merged,
       hasMore: response.hasMore, page: nextPage, isLoadingMore: false)
4. On error: state = state.copyWith(isLoadingMore: false) only — already-loaded data and
   hasMore are left untouched, so the next scroll-near-bottom event retries automatically
   (line 159-163).
```

## Flow 3: Applying a filter

```
1. User taps the header Filter button → _openFilterSheet(filterOptionsAsync)      line 72
2. showTransactionFilterSheet(context, current: _filter, filterOptions: ...)      transaction_filter_sheet.dart:39
   → modal bottom sheet renders Date Range (always usable) + 3 backend-driven chip groups
     (Commodity/Type/Status), each independently showing its own loading/error/data state
     based on the SAME AsyncValue<HistoryFilterOptions> passed in (not re-fetched)
3. User picks values, taps "Apply (N)" or "Show All" → _apply()                   line 112
   → Navigator.pop(context, TransactionFilter(fromDate, toDate, metalName, type, status))
4. Back in the screen: _openFilterSheet's awaited result is non-null → _applyFilter(result)
5. _applyFilter(filter)                                                           line 87
   → setState(_filter = filter)   (updates the active-chips row + badge count locally)
   → ref.read(historyProvider.notifier).applyFilter(filter)
6. HistoryNotifier.applyFilter(filter)                                            history_controller.dart:85
   → _filter = filter; return _fetchFirstPage()
   → this is a FULL page-1 re-fetch from the backend with the new criteria — replaces
     HistoryPageState entirely (all previously-loaded pages are discarded), NOT a local
     filter over already-cached rows
7. Subsequent loadMore() calls now carry the new _filter automatically (it's notifier-level
   state, read fresh on every fetch) — filtering and lazy-loading compose correctly.
```

## Flow 4: Opening transaction detail

```
1. User taps a transaction card → Navigator.pushNamed(AppRouter.transactionDetails,
     arguments: {'id': tx.transactionId, 'type': tx.type})                        transaction_history_screen.dart:596-601
2. app_router.dart:171-174 extracts the arguments map, passes to
   TransactionDetailsScreen(transactionData: {...})
3. initState(): Future.microtask(() =>
     ref.invalidate(transactionDetailsProvider(transactionData['id'])))            transaction_details_screen.dart:38-40
   → guarantees a fresh fetch even if this same transaction id was viewed before in this
     session (transactionDetailsProvider is a FutureProvider.family — normally cached per
     argument; the invalidate forces a bypass every time the screen opens)
4. build() → ref.watch(transactionDetailsProvider(id))                             line 46
   → POST transactions/details {id_customer, transaction_id}                       history_service.dart:77-92
   → TransactionDetailResponse.fromJson — timeline, priceBreakdown, technicalDetails,
     optional schemeInfo (SIP only)                                                history_models.dart:128-156
5. .when(data/loading/error) renders the appropriate card stack (§5 in MODULE_BRAIN.md).
6. Invoice download (if details.invoiceUrl non-empty): tap → loading dialog →
   InvoiceService.downloadInvoice(url) → on success, pushes AppRouter.invoiceViewer with the
   local file path; on InvoiceException or any other error, shows an AppToast and dismisses
   the loading dialog (transaction_details_screen.dart:355-394).
```

## Flow 5: Tab re-entry (History tab tapped again after first visit)

```
1. MainScreen._onTabTapped or equivalent bottom-nav handler sets selectedTabProvider to 2
2. Because _visitedTabs already contains 2 (from Flow 1), MainScreen does NOT recreate
   TransactionHistoryScreen — the same historyProvider instance (with its already-loaded
   pages and the ListView's scroll position) is reused, UNLIKE a fresh push
3. MainScreen explicitly calls ref.read(historyProvider.notifier).refresh()          main_screen.dart:107
   → this is the ONLY automatic refetch on tab re-entry — it replaces page 1 (keeping the
     currently-applied filter, if any) while the existing list stays visible during the fetch
4. If the user instead pulls-to-refresh or taps the header refresh icon, the same refresh()
   path runs — there is no separate "silent background refresh" implementation.
```
