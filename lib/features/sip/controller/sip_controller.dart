import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sip_models.dart';
import '../models/sip_transaction_filter.dart';
import '../models/sip_transaction_filter_options_model.dart';
import '../services/sip_service.dart';
import '../services/custom_sip_service.dart';
import '../../history/models/history_models.dart' show TransactionItem;

// ─── Service Provider ───────────────────────────────────────────────────────
final sipServiceProvider = Provider((ref) => SipService());

/// Custom SIP (multi-date AutoPay) — separate service, separate backend
/// product (see custom_sip_service.dart), same provider pattern.
final customSipServiceProvider = Provider((ref) => CustomSipService());

// ─── Config Provider ────────────────────────────────────────────────────────
final sipConfigProvider = FutureProvider.autoDispose<SipConfig>((ref) async {
  final service = ref.watch(sipServiceProvider);
  return service.getConfig();
});

// ─── Denominations (frequency-aware) ────────────────────────────────────────
/// Gold denominations keyed by frequencyId — re-fetches when frequency changes.
final sipGoldDenominationsProvider =
    FutureProvider.autoDispose.family<List<SipDenomination>, int?>((ref, frequencyId) async {
  final service = ref.watch(sipServiceProvider);
  return service.getGoldDenominations(frequencyId: frequencyId);
});

/// Silver denominations keyed by frequencyId — re-fetches when frequency changes.
final sipSilverDenominationsProvider =
    FutureProvider.autoDispose.family<List<SipDenomination>, int?>((ref, frequencyId) async {
  final service = ref.watch(sipServiceProvider);
  return service.getSilverDenominations(frequencyId: frequencyId);
});

// ─── Active Plans ───────────────────────────────────────────────────────────
final sipDetailsProvider =
    FutureProvider<List<SipPlanDetail>>((ref) async {
  final service = ref.watch(sipServiceProvider);
  return service.getSipDetails();
});

/// Non-terminal Custom SIP schemes for this customer — used to mark
/// already-committed dates on the Custom tab's date picker grid.
/// Not autoDispose: invalidated explicitly after create/pause/resume/cancel
/// so the grid reflects the latest state next time the picker opens.
final customSipSchemesProvider =
    FutureProvider<List<CustomSipScheme>>((ref) async {
  final service = ref.watch(customSipServiceProvider);
  return service.listSchemes();
});

/// Full detail (commodity name, start date, dates) for every non-terminal
/// Custom SIP scheme this customer owns — used by SipOverviewScreen's
/// "Custom" tab, which needs fields listSchemes()'s summary doesn't carry.
/// Per-scheme failures are skipped rather than failing the whole list, since
/// one bad scheme shouldn't blank the tab for the customer's other schemes.
final customSipSchemeDetailsProvider =
    FutureProvider<List<CustomSipSchemeDetail>>((ref) async {
  final service = ref.watch(customSipServiceProvider);
  final schemes = await service.listSchemes();
  final details = await Future.wait(
    schemes.map((s) async {
      try {
        return await service.getSchemeStatus(schemeId: s.schemeId);
      } catch (_) {
        return null;
      }
    }),
  );
  return details.whereType<CustomSipSchemeDetail>().toList();
});

// ─── SIP State ──────────────────────────────────────────────────────────────

class SipState {
  final int? selectedFrequencyId;
  final int? selectedCommodityId;
  final double amount;
  final String? selectedDay; // for Weekly
  final int? selectedDate; // for Monthly
  final List<SipPlanDetail> activePlans;
  final bool isCreating;
  final String? errorMessage;

  SipState({
    this.selectedFrequencyId,
    this.selectedCommodityId,
    this.amount = 0,
    this.selectedDay,
    this.selectedDate,
    this.activePlans = const [],
    this.isCreating = false,
    this.errorMessage,
  });

  SipState copyWith({
    int? selectedFrequencyId,
    int? selectedCommodityId,
    double? amount,
    String? selectedDay,
    int? selectedDate,
    List<SipPlanDetail>? activePlans,
    bool? isCreating,
    String? errorMessage,
    // Allow clearing nullable fields
    bool clearDay = false,
    bool clearDate = false,
    bool clearError = false,
  }) {
    return SipState(
      selectedFrequencyId: selectedFrequencyId ?? this.selectedFrequencyId,
      selectedCommodityId: selectedCommodityId ?? this.selectedCommodityId,
      amount: amount ?? this.amount,
      selectedDay: clearDay ? null : (selectedDay ?? this.selectedDay),
      selectedDate: clearDate ? null : (selectedDate ?? this.selectedDate),
      activePlans: activePlans ?? this.activePlans,
      isCreating: isCreating ?? this.isCreating,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// Whether the current frequency+commodity already has an active/paused plan.
  bool hasActivePlanForFrequency(int frequencyId, {int? commodityId}) {
    return activePlans.any(
      (p) =>
          p.frequencyId == frequencyId &&
          p.isOccupying &&
          (commodityId == null || p.commodityId == commodityId),
    );
  }

  /// Get the existing plan for a frequency+commodity (if any).
  SipPlanDetail? getActivePlanForFrequency(int frequencyId,
      {int? commodityId}) {
    final matching = activePlans.where(
      (p) =>
          p.frequencyId == frequencyId &&
          p.isOccupying &&
          (commodityId == null || p.commodityId == commodityId),
    );
    return matching.isNotEmpty ? matching.first : null;
  }
}

class SipNotifier extends StateNotifier<SipState> {
  SipNotifier() : super(SipState());

  void setFrequency(int id) {
    state = state.copyWith(
      selectedFrequencyId: id,
      clearDay: true,
      clearDate: true,
    );
  }

  void setCommodity(int id) {
    state = state.copyWith(selectedCommodityId: id);
  }

  void setAmount(double amount) {
    state = state.copyWith(amount: amount, clearError: true);
  }

  void setDay(String day) {
    state = state.copyWith(selectedDay: day);
  }

  void setDate(int date) {
    state = state.copyWith(selectedDate: date);
  }

  void setActivePlans(List<SipPlanDetail> plans) {
    state = state.copyWith(activePlans: plans);
  }

  void setCreating(bool creating) {
    state = state.copyWith(isCreating: creating);
  }

  void setError(String? error) {
    if (error == null) {
      state = state.copyWith(clearError: true);
    } else {
      state = state.copyWith(errorMessage: error);
    }
  }

  void reset() {
    state = SipState(
      selectedFrequencyId: state.selectedFrequencyId,
      selectedCommodityId: state.selectedCommodityId,
      activePlans: state.activePlans,
    );
  }
}

final sipControllerProvider =
    StateNotifierProvider<SipNotifier, SipState>((ref) {
  return SipNotifier();
});

// ─── SIP Transaction History (lazy-loaded, per-frequency-tab) ──────────────
/// Lazy-loaded, page-accumulating SIP Transaction History state for ONE
/// frequency tab (Daily/Weekly/Monthly/Custom). Mirrors HistoryPageState
/// (history_controller.dart) — [transactions]/[groupedData] hold every page
/// fetched so far for this tab (merged, not replaced), so scrolling back up
/// never re-fetches already-loaded rows.
class SipHistoryPageState {
  final List<TransactionItem> transactions;
  final Map<String, List<TransactionItem>> groupedData;
  final bool isLoading; // first page in flight
  final bool isLoadingMore; // a subsequent page in flight
  final bool hasMore;
  final int page; // last successfully loaded page number (0 = none yet)
  final String? error;

  const SipHistoryPageState({
    this.transactions = const [],
    this.groupedData = const {},
    this.isLoading = false,
    this.isLoadingMore = false,
    this.hasMore = true,
    this.page = 0,
    this.error,
  });

  bool get isEmpty => transactions.isEmpty;

  SipHistoryPageState copyWith({
    List<TransactionItem>? transactions,
    Map<String, List<TransactionItem>>? groupedData,
    bool? isLoading,
    bool? isLoadingMore,
    bool? hasMore,
    int? page,
    String? error,
    bool clearError = false,
  }) {
    return SipHistoryPageState(
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

class SipHistoryNotifier extends StateNotifier<SipHistoryPageState> {
  static const int pageSize = 20;

  final SipService _service;
  final String _frequency;

  /// Currently-applied filter (commodity/status/date range) for this tab.
  /// Every page fetch — initial, "load more", or a fresh filter application
  /// — sends this to the backend, so lazy-loading and filtering compose
  /// correctly (scrolling while filtered keeps fetching more *filtered*
  /// pages, not the unfiltered stream).
  SipTransactionFilter _filter = SipTransactionFilter.empty;
  SipTransactionFilter get currentFilter => _filter;

  SipHistoryNotifier(this._service, this._frequency)
      : super(const SipHistoryPageState()) {
    _fetchFirstPage();
  }

  Future<void> loadInitial() => _fetchFirstPage();

  /// Applies [filter] server-side: fetches page 1 with the new filter
  /// criteria from the backend (replacing all currently-loaded pages for
  /// this tab), then continues lazy-loading with the same criteria as the
  /// user scrolls.
  Future<void> applyFilter(SipTransactionFilter filter) {
    _filter = filter;
    return _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    // Keep whatever is already loaded on screen while the new page-1 fetch
    // is in flight (initial load, manual refresh, or a changed filter) —
    // only the header spinner should indicate activity; the list itself
    // must not blank out and reappear.
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _service.getSipTransactions(
        frequency: _frequency,
        page: 1,
        limit: pageSize,
        commodity: _filter.commodity,
        status: _filter.status,
        dateFrom: _filter.dateFromParam,
        dateTo: _filter.dateToParam,
      );
      state = SipHistoryPageState(
        transactions: response.transactions,
        groupedData: response.groupedData,
        hasMore: response.hasMore,
        page: 1,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Fetches and appends the next page (using the currently-applied filter,
  /// if any). No-ops while a fetch is already in flight or once the backend
  /// reports no more pages — this is what prevents duplicate requests from
  /// repeated scroll-near-bottom events.
  Future<void> loadMore() async {
    if (state.isLoading || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    try {
      final nextPage = state.page + 1;
      final response = await _service.getSipTransactions(
        frequency: _frequency,
        page: nextPage,
        limit: pageSize,
        commodity: _filter.commodity,
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

/// Keyed by frequency ("Daily" | "Weekly" | "Monthly" | "Custom") so each
/// SIP Transactions tab lazy-loads and filters independently. Not
/// autoDispose — SipTransactionHistoryScreen explicitly invalidates all four
/// on screen entry (matches this screen's "always fetch fresh" requirement)
/// rather than relying on dispose/recreate timing.
final sipHistoryProvider = StateNotifierProvider.family<SipHistoryNotifier,
    SipHistoryPageState, String>((ref, frequency) {
  return SipHistoryNotifier(ref.read(sipServiceProvider), frequency);
});

/// Dynamic filter option set (frequencies, commodities, statuses) for the
/// SIP Transactions filter sheet. Mirrors historyFilterOptionsProvider.
final sipHistoryFilterOptionsProvider =
    FutureProvider.autoDispose<SipTransactionFilterOptions>((ref) async {
  final service = ref.watch(sipServiceProvider);
  return service.getSipTransactionFilterOptions();
});

// ─── SIP Transaction Details ────────────────────────────────────────────────
/// SIP transaction detail — keyed by transaction ID.
/// Invalidated on every screen entry to always get fresh data.
final sipTransactionDetailsProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
        (ref, transactionId) async {
  final service = ref.watch(sipServiceProvider);
  return service.getSipTransactionDetails(transactionId: transactionId);
});
