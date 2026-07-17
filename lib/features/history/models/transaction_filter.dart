import 'package:intl/intl.dart';

/// Immutable filter state for the Transaction History screen.
///
/// Filtering itself is server-side (`POST transactions/history` accepts
/// `commodity`/`transaction_type`/`status`/`date_from`/`date_to` — see
/// [HistoryNotifier.applyFilter]) so results reflect the customer's full
/// history, not just whatever page happens to already be loaded locally.
/// This class only carries the currently-selected criteria for the filter
/// sheet UI (active chips, badge count) and for building that request.
class TransactionFilter {
  /// null = no date restriction
  final DateTime? fromDate;
  final DateTime? toDate;

  /// null / empty = "All"
  final String? metalName;
  final String? type;
  final String? status;

  const TransactionFilter({
    this.fromDate,
    this.toDate,
    this.metalName,
    this.type,
    this.status,
  });

  static const TransactionFilter empty = TransactionFilter();

  bool get isEmpty =>
      fromDate == null &&
      toDate == null &&
      (metalName == null || metalName!.isEmpty) &&
      (type == null || type!.isEmpty) &&
      (status == null || status!.isEmpty);

  /// Count of active filters (for badge display).
  int get activeCount {
    int count = 0;
    if (fromDate != null || toDate != null) count++;
    if (metalName != null && metalName!.isNotEmpty) count++;
    if (type != null && type!.isNotEmpty) count++;
    if (status != null && status!.isNotEmpty) count++;
    return count;
  }

  TransactionFilter copyWith({
    DateTime? fromDate,
    DateTime? toDate,
    bool clearDates = false,
    String? metalName,
    bool clearMetal = false,
    String? type,
    bool clearType = false,
    String? status,
    bool clearStatus = false,
  }) {
    return TransactionFilter(
      fromDate: clearDates ? null : (fromDate ?? this.fromDate),
      toDate: clearDates ? null : (toDate ?? this.toDate),
      metalName: clearMetal ? null : (metalName ?? this.metalName),
      type: clearType ? null : (type ?? this.type),
      status: clearStatus ? null : (status ?? this.status),
    );
  }

  /// Backend date format is `DD-MM-YYYY` (matches the sibling
  /// `transactions/history/filter` endpoint's convention).
  String? get dateFromParam =>
      fromDate != null ? DateFormat('dd-MM-yyyy').format(fromDate!) : null;

  String? get dateToParam =>
      toDate != null ? DateFormat('dd-MM-yyyy').format(toDate!) : null;
}
