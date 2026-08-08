/// One BANK_ACCOUNT (BAV) verification attempt — GET account/verify-bank/bav-history.
class BavHistoryItem {
  final int kycId;
  final String status; // "Approved" | "Rejected" | "Pending" | ...
  final String? accountLast4;
  final bool? nameMatched;
  final double? nameMatchScore;
  final DateTime? attemptedOn;

  BavHistoryItem({
    required this.kycId,
    required this.status,
    this.accountLast4,
    this.nameMatched,
    this.nameMatchScore,
    this.attemptedOn,
  });

  bool get isApproved => status.toLowerCase() == 'approved';

  factory BavHistoryItem.fromJson(Map<String, dynamic> json) {
    return BavHistoryItem(
      kycId: (json['kyc_id'] as num?)?.toInt() ?? 0,
      status: json['status']?.toString() ?? 'Pending',
      accountLast4: json['account_last4']?.toString(),
      nameMatched: json['name_matched'] as bool?,
      nameMatchScore: (json['name_match_score'] as num?)?.toDouble(),
      attemptedOn: json['attempted_on'] != null
          ? DateTime.tryParse(json['attempted_on'].toString())
          : null,
    );
  }
}

/// One Rs.1 verification attempt (payment + refund) — GET
/// account/verify-bank/penny/history. Same row backs both the "Rs.1 Payment
/// Verification History" and "Refund Verification History" screens.
class PennyVerifyHistoryItem {
  final int cbpvId;
  final String internalOrderId;
  final String amount;
  final String? paymentMethod;
  final String status; // "Initiated" | "Paid" | "Failed"
  final String? bankName;
  final String? accountLast4;
  final DateTime? createdOn;
  final String? refundId;
  final String refundStatus; // "Not Initiated" | "Pending" | "Success" | "Failed"
  final DateTime? refundedOn;

  PennyVerifyHistoryItem({
    required this.cbpvId,
    required this.internalOrderId,
    required this.amount,
    this.paymentMethod,
    required this.status,
    this.bankName,
    this.accountLast4,
    this.createdOn,
    this.refundId,
    required this.refundStatus,
    this.refundedOn,
  });

  bool get isPaid => status.toLowerCase() == 'paid';
  bool get isRefunded => refundStatus.toLowerCase() == 'success';

  factory PennyVerifyHistoryItem.fromJson(Map<String, dynamic> json) {
    return PennyVerifyHistoryItem(
      cbpvId: (json['cbpv_id'] as num?)?.toInt() ?? 0,
      internalOrderId: json['internal_order_id']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '1.00',
      paymentMethod: json['payment_method']?.toString(),
      status: json['status']?.toString() ?? 'Initiated',
      bankName: json['bank_name']?.toString(),
      accountLast4: json['account_last4']?.toString(),
      createdOn: json['created_on'] != null
          ? DateTime.tryParse(json['created_on'].toString())
          : null,
      refundId: json['refund_id']?.toString(),
      refundStatus: json['refund_status']?.toString() ?? 'Not Initiated',
      refundedOn: json['refunded_on'] != null
          ? DateTime.tryParse(json['refunded_on'].toString())
          : null,
    );
  }
}
