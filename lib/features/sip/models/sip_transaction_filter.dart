import 'package:intl/intl.dart';

/// Immutable filter state for one SIP Transactions tab (Daily/Weekly/
/// Monthly/Custom).
///
/// Frequency itself is the tab selection, not part of this filter — each
/// tab already scopes its requests to one frequency (see
/// SipHistoryNotifier). Commodity is handled by the existing inline chip
/// row per tab, which also feeds into this filter's [commodity] field.
///
/// Filtering is server-side (`POST sip/transactions` accepts `commodity`/
/// `status`/`date_from`/`date_to` alongside the required `frequency` — see
/// SipHistoryNotifier.applyFilter) so results reflect the customer's full
/// history for that frequency, not just whatever page happens to already be
/// loaded locally.
class SipTransactionFilter {
  /// null = no date restriction
  final DateTime? fromDate;
  final DateTime? toDate;

  /// null / empty = "All"
  final String? commodity;
  final String? status;

  const SipTransactionFilter({
    this.fromDate,
    this.toDate,
    this.commodity,
    this.status,
  });

  static const SipTransactionFilter empty = SipTransactionFilter();

  bool get isEmpty =>
      fromDate == null &&
      toDate == null &&
      (commodity == null || commodity!.isEmpty) &&
      (status == null || status!.isEmpty);

  /// Count of active filters (for badge display) — commodity is excluded
  /// since it's always visible as a chip, not a hidden filter-sheet choice.
  int get activeCount {
    int count = 0;
    if (fromDate != null || toDate != null) count++;
    if (status != null && status!.isNotEmpty) count++;
    return count;
  }

  SipTransactionFilter copyWith({
    DateTime? fromDate,
    DateTime? toDate,
    bool clearDates = false,
    String? commodity,
    bool clearCommodity = false,
    String? status,
    bool clearStatus = false,
  }) {
    return SipTransactionFilter(
      fromDate: clearDates ? null : (fromDate ?? this.fromDate),
      toDate: clearDates ? null : (toDate ?? this.toDate),
      commodity: clearCommodity ? null : (commodity ?? this.commodity),
      status: clearStatus ? null : (status ?? this.status),
    );
  }

  /// Backend date format is `DD-MM-YYYY` (matches the general Transaction
  /// History filter convention — see TransactionFilter.dateFromParam).
  String? get dateFromParam =>
      fromDate != null ? DateFormat('dd-MM-yyyy').format(fromDate!) : null;

  String? get dateToParam =>
      toDate != null ? DateFormat('dd-MM-yyyy').format(toDate!) : null;
}
