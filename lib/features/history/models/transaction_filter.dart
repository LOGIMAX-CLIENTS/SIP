import 'package:intl/intl.dart';
import '../models/history_models.dart';

/// Immutable filter state for the Transaction History screen.
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

  /// Apply this filter to a flat list and regroup by date.
  Map<String, List<TransactionItem>> applyTo(HistoryResponse history) {
    // Try to parse the API date key format: "21 April 2026"
    // Falls back to DateTime.parse for ISO strings.
    DateTime? _parseGroupKey(String key) {
      try {
        return DateFormat('d MMMM yyyy').parse(key);
      } catch (_) {}
      try {
        return DateTime.parse(key);
      } catch (_) {}
      return null;
    }

    // Iterate over the original grouped data to preserve date-group order
    // and use the group key as the date source (correct and reliable).
    final Map<String, List<TransactionItem>> grouped = {};

    for (final entry in history.groupedData.entries) {
      final dateKey = entry.key;
      final txDate = _parseGroupKey(dateKey);

      // ── Date range filter ──────────────────────────────────────────
      if (fromDate != null || toDate != null) {
        if (txDate == null) continue; // can't parse → skip group
        final day = DateTime(txDate.year, txDate.month, txDate.day);
        if (fromDate != null) {
          final from =
              DateTime(fromDate!.year, fromDate!.month, fromDate!.day);
          if (day.isBefore(from)) continue;
        }
        if (toDate != null) {
          final to = DateTime(toDate!.year, toDate!.month, toDate!.day);
          if (day.isAfter(to)) continue;
        }
      }

      // Filter individual transactions within the date group
      final List<TransactionItem> items = entry.value.where((tx) {
        // ── Metal / commodity ────────────────────────────────────────
        if (metalName != null && metalName!.isNotEmpty) {
          if (!tx.metalName
              .toLowerCase()
              .contains(metalName!.toLowerCase())) {
            return false;
          }
        }

        // ── Type (purchase / withdrawal / referral) ──────────────────
        if (type != null && type!.isNotEmpty) {
          if (tx.type.toLowerCase() != type!.toLowerCase()) return false;
        }

        // ── Status (Success / Pending / Cancelled) ───────────────────
        if (status != null && status!.isNotEmpty) {
          if (tx.status.toLowerCase() != status!.toLowerCase()) return false;
        }

        return true;
      }).toList();

      if (items.isNotEmpty) {
        grouped[dateKey] = items;
      }
    }
    return grouped;
  }

}
