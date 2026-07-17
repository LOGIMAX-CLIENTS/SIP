// Dynamic filter option models for the Transaction History filter sheet.
//
// Backed by `POST transactions/filter-options`, following the same
// `*/config`-style pattern used by SipConfig (see sip_models.dart): the
// backend owns the list of commodities, transaction types, and statuses so
// new values (e.g. a new "Processing" status) show up without a mobile app
// release.

/// A single dynamic filter choice.
///
/// `colorHex` is only meaningful for statuses (e.g. `"#10B981"`) and is
/// optional — when absent the UI falls back to [defaultStatusColorHex].
class FilterOption {
  final String value;
  final String label;
  final String? colorHex;

  const FilterOption({
    required this.value,
    required this.label,
    this.colorHex,
  });

  factory FilterOption.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] ?? json['id'] ?? json['name'] ?? '').toString();
    final label = (json['label'] ?? json['name'] ?? value).toString();
    return FilterOption(
      value: value,
      label: label,
      colorHex: json['color']?.toString(),
    );
  }
}

/// Full dynamic option set for the Transaction History filter sheet.
class HistoryFilterOptions {
  final List<FilterOption> commodities;
  final List<FilterOption> transactionTypes;
  final List<FilterOption> statuses;

  const HistoryFilterOptions({
    required this.commodities,
    required this.transactionTypes,
    required this.statuses,
  });

  static const empty = HistoryFilterOptions(
    commodities: [],
    transactionTypes: [],
    statuses: [],
  );

  factory HistoryFilterOptions.fromJson(Map<String, dynamic> json) {
    List<FilterOption> parseList(String key) {
      final raw = json[key];
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => FilterOption.fromJson(e))
          .toList();
    }

    return HistoryFilterOptions(
      commodities: parseList('commodities'),
      transactionTypes: parseList('transaction_types'),
      statuses: parseList('statuses'),
    );
  }
}

String capitalise(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Fallback label for a known transaction type — used only when neither the
/// backend nor the loaded transaction list has already supplied a label.
String defaultTypeLabel(String raw) {
  switch (raw.toLowerCase()) {
    case 'purchase':
      return 'Instant Saving';
    case 'withdrawal':
      return 'Withdrawal';
    case 'referral':
      return 'Referral Reward';
    case 'sip':
      return 'SIP Autopay';
    case 'offer':
      return 'Offer Reward';
    default:
      return capitalise(raw);
  }
}

/// Fallback status color (hex) — used only when the backend doesn't supply
/// one for a given status.
String defaultStatusColorHex(String raw) {
  switch (raw.toLowerCase()) {
    case 'success':
      return '#10B981';
    case 'pending':
      return '#F59E0B';
    case 'processing':
      return '#3B82F6';
    case 'on hold':
      return '#D97706';
    case 'cancelled':
    case 'failed':
      return '#DC2626';
    default:
      return '#1B882C';
  }
}
