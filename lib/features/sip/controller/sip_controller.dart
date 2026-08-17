import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/sip_models.dart';
import '../services/sip_service.dart';
import '../services/custom_sip_service.dart';

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

// ─── SIP Transaction History ────────────────────────────────────────────────
/// Raw SIP transaction data — returns the full API response map.
/// Invalidated on every screen entry to always get fresh data.
final sipTransactionsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final service = ref.watch(sipServiceProvider);
  return service.getSipTransactions();
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
