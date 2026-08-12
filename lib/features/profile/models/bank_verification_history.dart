/// One BANK_ACCOUNT (BAV) verification attempt — GET account/verify-bank/bav-history.
class BavHistoryItem {
  final int kycId;
  final String status; // "Approved" | "Rejected" | "Pending" | ...
  final String? accountLast4;
  final bool? nameMatched;
  final double? nameMatchScore;
  final DateTime? attemptedOn;
  final String? provider;

  BavHistoryItem({
    required this.kycId,
    required this.status,
    this.accountLast4,
    this.nameMatched,
    this.nameMatchScore,
    this.attemptedOn,
    this.provider,
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
      provider: json['provider']?.toString(),
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
  final String? gatewayProvider; // "Razorpay" | "Cashfree"

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
    this.gatewayProvider,
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
      gatewayProvider: json['gateway_provider']?.toString(),
    );
  }
}

enum BankTimelineKind { bav, pennyPayment, pennyRefund }

/// One row in the merged Bank Account Verification timeline — combines BAV
/// attempts and Rs.1 payment/refund attempts into a single chronological
/// feed (Profile > Bank Account Verification).
class BankTimelineEntry {
  final BankTimelineKind kind;
  final String title;
  final String status;
  final String? provider;
  final String? subtitle;
  final DateTime? dateTime;

  BankTimelineEntry({
    required this.kind,
    required this.title,
    required this.status,
    required this.dateTime,
    this.provider,
    this.subtitle,
  });

  /// User-facing status label — same underlying value, worded per the
  /// action each timeline row represents (e.g. a paid Rs.1 row reads
  /// "Debited", a successful refund reads "Refunded").
  String get displayStatus {
    final s = status.toLowerCase();
    switch (kind) {
      case BankTimelineKind.bav:
        if (s == 'approved') return 'Verified';
        return status;
      case BankTimelineKind.pennyPayment:
        if (s == 'paid') return 'Debited';
        return status;
      case BankTimelineKind.pennyRefund:
        if (s == 'success') return 'Refunded';
        return status;
    }
  }
}

/// One verification ATTEMPT for one bank account — a single card holding
/// up to 3 lines (BAV / Rs.1 Payment / Rs.1 Refund) for that attempt.
/// BAV rows and Rs.1 rows come from two independent tables with no shared
/// attempt id, so a Rs.1 row is paired with the BAV row for the same
/// account (accountLast4) whose attempt happened just before it — real
/// flow always runs BAV to APPROVED before a Rs.1 payment is even allowed
/// (see BankPennyVerifyService.initiate()'s cbank_is_verify gate), so
/// "closest preceding BAV row" is the correct match, not a guess.
class BankVerificationCard {
  final String bankLabel;
  final BankTimelineEntry? bav;
  final BankTimelineEntry? payment;
  final BankTimelineEntry? refund;
  final DateTime? sortDate;

  BankVerificationCard({
    required this.bankLabel,
    required this.sortDate,
    this.bav,
    this.payment,
    this.refund,
  });

  /// Groups BAV + Rs.1 payment/refund rows into per-attempt cards, newest
  /// first. Every Rs.1 row becomes its own card (paired with the nearest
  /// preceding BAV row for the same account, if any); any BAV row never
  /// consumed by a Rs.1 pairing becomes its own standalone card.
  static List<BankVerificationCard> build(
    List<BavHistoryItem> bav,
    List<PennyVerifyHistoryItem> penny,
  ) {
    final sortedBav = [...bav]..sort((a, b) {
        if (a.attemptedOn == null) return 1;
        if (b.attemptedOn == null) return -1;
        return a.attemptedOn!.compareTo(b.attemptedOn!); // oldest first
      });
    final usedBav = <int>{}; // kycId of BAV rows already paired

    BankTimelineEntry bavEntry(BavHistoryItem item) => BankTimelineEntry(
          kind: BankTimelineKind.bav,
          title: 'Bank Account Verification',
          status: item.status,
          provider: item.provider,
          dateTime: item.attemptedOn,
        );

    final cards = <BankVerificationCard>[];

    for (final item in penny) {
      // Nearest BAV attempt (same account) at or before this Rs.1 attempt.
      BavHistoryItem? matched;
      for (final b in sortedBav) {
        if (usedBav.contains(b.kycId)) continue;
        if (b.accountLast4 == null || b.accountLast4 != item.accountLast4) continue;
        if (item.createdOn != null && b.attemptedOn != null &&
            b.attemptedOn!.isAfter(item.createdOn!)) {
          break; // sortedBav is oldest-first — later rows are only later
        }
        matched = b;
      }
      if (matched != null) usedBav.add(matched.kycId);

      final bankLabel =
          '${item.bankName ?? 'Bank Account'}${item.accountLast4 != null ? ' •• ${item.accountLast4}' : ''}';

      cards.add(BankVerificationCard(
        bankLabel: bankLabel,
        sortDate: item.createdOn,
        bav: matched != null ? bavEntry(matched) : null,
        payment: BankTimelineEntry(
          kind: BankTimelineKind.pennyPayment,
          title: 'Rs.1 Verification Payment',
          status: item.status,
          provider: item.gatewayProvider,
          dateTime: item.createdOn,
        ),
        refund: BankTimelineEntry(
          kind: BankTimelineKind.pennyRefund,
          title: 'Rs.1 Verification Refund',
          status: item.refundStatus,
          provider: item.gatewayProvider,
          dateTime: item.refundedOn ?? item.createdOn,
        ),
      ));
    }

    // BAV attempts never paired with a Rs.1 row — standalone cards.
    for (final item in bav) {
      if (usedBav.contains(item.kycId)) continue;
      cards.add(BankVerificationCard(
        bankLabel: item.accountLast4 != null
            ? 'Bank Account •• ${item.accountLast4}'
            : 'Bank Account',
        sortDate: item.attemptedOn,
        bav: bavEntry(item),
      ));
    }

    cards.sort((a, b) {
      if (a.sortDate == null && b.sortDate == null) return 0;
      if (a.sortDate == null) return 1;
      if (b.sortDate == null) return -1;
      return b.sortDate!.compareTo(a.sortDate!); // newest first
    });
    return cards;
  }
}
