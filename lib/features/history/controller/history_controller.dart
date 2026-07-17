import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/history_models.dart';
import '../models/history_filter_options_model.dart';
import '../models/transaction_filter.dart';
import '../services/history_service.dart';
import '../../../core/providers/user_provider.dart';

final historyServiceProvider = Provider<HistoryService>((ref) => HistoryService());

/// Lazy-loaded, page-accumulating Transaction History state.
///
/// [transactions]/[groupedData] hold every page fetched so far (merged, not
/// replaced), so scrolling back up never re-fetches already-loaded rows.
class HistoryPageState {
  final List<TransactionItem> transactions;
  final Map<String, List<TransactionItem>> groupedData;
  final bool isLoading; // first page in flight
  final bool isLoadingMore; // a subsequent page in flight
  final bool hasMore;
  final int page; // last successfully loaded page number (0 = none yet)
  final String? error;

  const HistoryPageState({
    this.transactions = const [],
    this.groupedData = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 0,
    this.error,
  });

  bool get isEmpty => transactions.isEmpty;

  HistoryPageState copyWith({
    List<TransactionItem>? transactions,
    Map<String, List<TransactionItem>>? groupedData,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
  }) {
    return HistoryPageState(
      transactions: transactions ?? this.transactions,
      groupedData: groupedData ?? this.groupedData,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class HistoryNotifier extends StateNotifier<HistoryPageState> {
  /// "first 5, then +5 per scroll" per the Transaction History lazy-load spec.
  static const int pageSize = 10;

  final HistoryService _service;
  final String? _customerId;

  /// Currently-applied filter (commodity/type/status/date range). Every
  /// page fetch — initial, "load more", or a fresh filter application —
  /// sends this to the backend, so lazy-loading and filtering compose
  /// correctly (scrolling while filtered keeps fetching more *filtered*
  /// pages, not the unfiltered stream).
  TransactionFilter _filter = TransactionFilter.empty;
  TransactionFilter get currentFilter => _filter;

  HistoryNotifier(this._service, this._customerId)
      : super(const HistoryPageState()) {
    _fetchFirstPage();
  }

  Future<void> loadInitial() => _fetchFirstPage();

  /// Applies [filter] server-side: fetches page 1 with the new filter
  /// criteria from the backend (replacing all currently-loaded pages), then
  /// continues lazy-loading with the same criteria as the user scrolls.
  /// Passing [TransactionFilter.empty] is the "Show All" case — a fresh
  /// unfiltered fetch from the backend, not just clearing a local filter
  /// over whatever happens to already be cached.
  Future<void> applyFilter(TransactionFilter filter) {
    _filter = filter;
    return _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    if (_customerId == null) {
      state = const HistoryPageState(error: 'User not logged in');
      return;
    }
    state = const HistoryPageState(isLoading: true);
    try {
      final response = await _service.getTransactionHistory(
        customerId: _customerId,
        page: 1,
        limit: pageSize,
        commodity: _filter.metalName,
        transactionType: _filter.type,
        status: _filter.status,
        dateFrom: _filter.dateFromParam,
        dateTo: _filter.dateToParam,
      );
      state = HistoryPageState(
        transactions: response.transactions,
        groupedData: response.groupedData,
        hasMore: response.hasMore,
        page: 1,
      );
    } catch (e) {
      state = HistoryPageState(error: e.toString());
    }
  }

  /// Fetches and appends the next page (using the currently-applied
  /// filter, if any). No-ops while a fetch is already in flight or once the
  /// backend reports no more pages — this is what prevents duplicate
  /// requests from repeated scroll-near-bottom events.
  Future<void> loadMore() async {
    if (_customerId == null) return;
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.page + 1;
      final response = await _service.getTransactionHistory(
        customerId: _customerId,
        page: nextPage,
        limit: pageSize,
        commodity: _filter.metalName,
        transactionType: _filter.type,
        status: _filter.status,
        dateFrom: _filter.dateFromParam,
        dateTo: _filter.dateToParam,
      );

      // Merge by date key — a date group can legitimately span a page
      // boundary, so append rather than overwrite.
      final merged = Map<String, List<TransactionItem>>.from(state.groupedData);
      response.groupedData.forEach((dateKey, items) {
        merged.update(dateKey, (existing) => [...existing, ...items],
            ifAbsent: () => items);
      });

      state = state.copyWith(
        transactions: [...state.transactions, ...response.transactions],
        groupedData: merged,
        hasMore: response.hasMore,
        page: nextPage,
        isLoadingMore: false,
      );
    } catch (_) {
      // Keep already-loaded data; drop the spinner so the user can retry by
      // scrolling again (hasMore is left untouched).
      state = state.copyWith(isLoadingMore: false);
    }
  }

  Future<void> refresh() => _fetchFirstPage();
}

/// Not autoDispose — state (and therefore loaded pages + effective scroll
/// position) survives navigating away from and back to the history screen
/// within the same app session.
final historyProvider =
    StateNotifierProvider<HistoryNotifier, HistoryPageState>((ref) {
  final user = ref.read(userProvider);
  return HistoryNotifier(ref.read(historyServiceProvider), user?.id);
});

/// Dynamic filter option set (commodities, transaction types, statuses)
/// for the Transaction History filter sheet. Mirrors [sipConfigProvider]'s
/// "fetch config on screen load" pattern.
final historyFilterOptionsProvider =
    FutureProvider.autoDispose<HistoryFilterOptions>((ref) async {
  final user = ref.read(userProvider);
  if (user == null) throw Exception('User not logged in');

  return ref.read(historyServiceProvider).getFilterOptions(
        customerId: user.id,
      );
});

final transactionDetailsProvider = FutureProvider.family<TransactionDetailResponse, String>((ref, transactionId) async {
  final user = ref.read(userProvider);
  if (user == null) throw Exception('User not logged in');

  return ref.read(historyServiceProvider).getTransactionDetails(
    customerId: user.id,
    transactionId: transactionId,
  );
});
