class HistoryResponse {
  final List<TransactionItem> transactions;
  final Map<String, List<TransactionItem>> groupedData;
  /// From the backend `pagination.has_next` flag — true while more pages
  /// remain to be lazy-loaded. Defaults to false for any response that
  /// omits `pagination` (keeps older/other callers safe).
  final bool hasMore;

  HistoryResponse({
    required this.transactions,
    required this.groupedData,
    this.hasMore = false,
  });

  factory HistoryResponse.fromJson(Map<String, dynamic> json) {
    // Support both full response and 'data' map
    final data = json.containsKey('data')
        ? (json['data'] as Map<String, dynamic>? ?? {})
        : json;
    final groupedJson =
        data['grouped_transactions'] as Map<String, dynamic>? ?? {};
    final pagination = data['pagination'] as Map<String, dynamic>?;

    final List<TransactionItem> flatList = [];
    final Map<String, List<TransactionItem>> groupedMap = {};

    groupedJson.forEach((dateKey, items) {
      if (items is List) {
        final List<TransactionItem> txList =
            items.map((i) => TransactionItem.fromJson(i, dateKey)).toList();
        groupedMap[dateKey] = txList;
        flatList.addAll(txList);
      }
    });

    return HistoryResponse(
      transactions: flatList,
      groupedData: groupedMap,
      hasMore: pagination?['has_next'] == true,
    );
  }

  Map<String, List<TransactionItem>> get groupedTransactions => groupedData;
}

class TransactionItem {
  final String transactionId;
  final String title;
  final String subtitle;
  final String type;
  final int soType;
  final double amount;
  final double weightGrams;
  final String displayDate;
  final String status;
  final String metalName;
  final String date; // Keep date key for grouping if needed

  TransactionItem({
    required this.transactionId,
    required this.title,
    this.subtitle = '',
    required this.type,
    this.soType = 0,
    required this.amount,
    required this.weightGrams,
    required this.displayDate,
    required this.status,
    required this.metalName,
    required this.date,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json,
      [String dateKey = '']) {
    return TransactionItem(
      transactionId: json['transaction_id']?.toString() ?? '',
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      type: json['type'] ?? '',
      soType: json['so_type'] ?? 0,
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0.0,
      weightGrams: double.tryParse(json['weight_grams']?.toString() ?? '0') ?? 0.0,
      displayDate: json['display_date'] ?? '',
      status: json['status'] ?? '',
      metalName: json['metal_name'] ?? 'Gold 24K',
      date: dateKey,
    );
  }
}

class TransactionDetailResponse {
  final String transactionId;
  final String orderId;
  final String title;
  final String subtitle;
  final String amount;
  final double weightGrams;
  final String metalName;
  final String scheduledDate;
  final String paymentMethod;
  final List<TimelineStep> timeline;
  final String footerMessage;
  final String invoiceNumber;
  final String invoiceUrl;
  final PriceBreakdown priceBreakdown;
  final TechnicalDetails technicalDetails;
  final SchemeInfo? schemeInfo;

  TransactionDetailResponse({
    required this.transactionId,
    required this.orderId,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.weightGrams,
    required this.metalName,
    this.scheduledDate = '',
    this.paymentMethod = '',
    required this.timeline,
    required this.footerMessage,
    required this.invoiceNumber,
    required this.invoiceUrl,
    required this.priceBreakdown,
    required this.technicalDetails,
    this.schemeInfo,
  });

  factory TransactionDetailResponse.fromJson(Map<String, dynamic> json) {
    // Details might also be inside a "data" field?
    // Usually detail APIs return data directly or inside "data".
    // I will check for "data" field just in case.
    final root = json.containsKey('data') ? json['data'] : json;

    var timelineList = root['timeline'] as List? ?? [];
    return TransactionDetailResponse(
      transactionId: root['transaction_id']?.toString() ?? '',
      orderId: root['order_id']?.toString() ?? '',
      title: root['title'] ?? '',
      subtitle: root['subtitle'] ?? '',
      amount: root['amount']?.toString() ?? '0',
      weightGrams: double.tryParse(root['weight_grams']?.toString() ?? '0') ?? 0.0,
      metalName: root['metal_name'] ?? 'Gold 24K',
      scheduledDate: root['scheduled_date'] ?? '',
      paymentMethod: root['payment_method'] ?? '',
      timeline: timelineList.map((i) => TimelineStep.fromJson(i)).toList(),
      footerMessage: root['footer_message'] ?? '',
      invoiceNumber: root['invoice_number'] ?? '',
      invoiceUrl: root['invoice_url'] ?? '',
      priceBreakdown: PriceBreakdown.fromJson(root['price_breakdown'] ?? {}),
      technicalDetails:
          TechnicalDetails.fromJson(root['technical_details'] ?? {}),
      schemeInfo: root['scheme_info'] != null
          ? SchemeInfo.fromJson(root['scheme_info'])
          : null,
    );
  }
}

class TimelineStep {
  final String stepName;
  final String status;
  final String time;

  TimelineStep({
    required this.stepName,
    required this.status,
    required this.time,
  });

  factory TimelineStep.fromJson(Map<String, dynamic> json) {
    return TimelineStep(
      stepName: json['step_name'] ?? '',
      status: json['status'] ?? '',
      time: json['time'] ?? '',
    );
  }
}

class PriceBreakdown {
  final String quantity;
  final String rate;
  final String value;
  final String gst;
  final String totalAmount;

  PriceBreakdown({
    required this.quantity,
    required this.rate,
    required this.value,
    required this.gst,
    required this.totalAmount,
  });

  factory PriceBreakdown.fromJson(Map<String, dynamic> json) {
    final qtyRaw = json['quantity']?.toString() ?? json['gold_quantity']?.toString() ?? '0';
    // Strip any existing unit suffix (e.g. "0.0005 g") to parse pure number
    final qtyNum = double.tryParse(qtyRaw.replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0;
    final rate = json['rate']?.toString() ?? json['gold_rate']?.toString() ?? '0';
    final val = json['value']?.toString() ?? json['gold_value']?.toString() ?? '0';
    final gst = json['gst']?.toString() ?? '0.00';
    final total = json['total_amount']?.toString() ?? '0';
    return PriceBreakdown(
      quantity: '${qtyNum.toStringAsFixed(6)} gm',
      rate: '₹$rate',
      value: '₹$val',
      gst: '₹$gst',
      totalAmount: '₹$total',
    );
  }
}

class TechnicalDetails {
  final String transactionIdDisplay;
  final String? goldTransactionId;
  final String orderId;
  final String placedOn;
  final String paidVia;

  TechnicalDetails({
    required this.transactionIdDisplay,
    this.goldTransactionId,
    required this.orderId,
    required this.placedOn,
    required this.paidVia,
  });

  factory TechnicalDetails.fromJson(Map<String, dynamic> json) {
    return TechnicalDetails(
      transactionIdDisplay: json['transaction_id_display'] ?? '',
      goldTransactionId: json['gold_transaction_id'],
      orderId: json['order_id']?.toString() ?? '',
      placedOn: json['placed_on'] ?? '',
      paidVia: json['paid_via'] ?? '',
    );
  }
}

class SchemeInfo {
  final int schemeId;
  final String label;
  final String frequency;
  final String amount;
  final String totalSaved;
  final int cyclesDone;
  final String status;

  SchemeInfo({
    required this.schemeId,
    required this.label,
    required this.frequency,
    required this.amount,
    required this.totalSaved,
    required this.cyclesDone,
    required this.status,
  });

  factory SchemeInfo.fromJson(Map<String, dynamic> json) {
    return SchemeInfo(
      schemeId: json['scheme_id'] ?? 0,
      label: json['label'] ?? '',
      frequency: json['frequency'] ?? '',
      amount: json['amount']?.toString() ?? '0',
      totalSaved: json['total_saved']?.toString() ?? '0',
      cyclesDone: json['cycles_done'] ?? 0,
      status: json['status'] ?? '',
    );
  }
}
