// Dynamic filter option models for the SIP Transactions filter sheet.
//
// Backed by `POST sip/transaction-filter-options`, mirroring
// HistoryFilterOptions (history_filter_options_model.dart) — the backend
// owns the list of frequencies, commodities, and statuses so new values
// show up without a mobile app release.

import '../../history/models/history_filter_options_model.dart' show FilterOption;

/// Full dynamic option set for the SIP Transactions filter sheet.
class SipTransactionFilterOptions {
  final List<FilterOption> frequencies;
  final List<FilterOption> commodities;
  final List<FilterOption> statuses;

  const SipTransactionFilterOptions({
    required this.frequencies,
    required this.commodities,
    required this.statuses,
  });

  static const empty = SipTransactionFilterOptions(
    frequencies: [],
    commodities: [],
    statuses: [],
  );

  factory SipTransactionFilterOptions.fromJson(Map<String, dynamic> json) {
    List<FilterOption> parseList(String key) {
      final raw = json[key];
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => FilterOption.fromJson(e))
          .toList();
    }

    return SipTransactionFilterOptions(
      frequencies: parseList('frequencies'),
      commodities: parseList('commodities'),
      statuses: parseList('statuses'),
    );
  }
}
