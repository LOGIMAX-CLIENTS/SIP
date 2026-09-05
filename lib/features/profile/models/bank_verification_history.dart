/// One BANK_ACCOUNT (BAV) verification attempt — GET account/verify-bank/bav-history.
class BavHistoryItem {
  final int kycId;
  final String status; // "Approved" | "Rejected" | "Pending" | ...
  final String? accountLast4;
  final bool? nameMatched;
  final double? nameMatchScore;
  final DateTime? attemptedOn;
  final String? provider;
  // Live CustomerBank.cbank_id for this row, resolved server-side only when
  // status is Approved and a currently-verified account matches the same
  // last-4 digits — null otherwise. Used to offer the optional Reverse
  // Penny Drop extra check (see reverse_penny_drop_screen.dart).
  final String? cbankId;
  // Whether THIS attempt is both historically approved AND still backed by
  // a live, still-BAV-verified CustomerBank row (server cross-check against
  // cbank_by_last4) — distinct from `status`, which is a pure historical
  // label that stays "Approved" even after the account is later removed/
  // reset. Use `isApproved` (this field), never `status`, to decide whether
  // bank verification is CURRENTLY satisfied (e.g. the KYC checklist step);
  // use `status` only for a past-tense record of what happened.
  final bool isApproved;

  BavHistoryItem({
    required this.kycId,
    required this.status,
    this.accountLast4,
    this.nameMatched,
    this.nameMatchScore,
    this.attemptedOn,
    this.provider,
    this.cbankId,
    required this.isApproved,
  });

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
      cbankId: json['cbank_id']?.toString(),
      isApproved: json['is_approved'] as bool? ?? false,
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

/// One Reverse Penny Drop attempt — GET account/verify-bank/rpd/history.
/// The SurePass/Meon-provider-based live-control second step, alternative
/// to the Rs.1 Payment/Refund pair above (Cashfree/Razorpay in-app SDK) —
/// see reverse_penny_drop_screen.dart. No refund step by product design.
class RpdHistoryItem {
  final int crpdId;
  final String clientId;
  final String status; // "Pending" | "Success" | "Failed"
  final String? bankName;
  final String? accountLast4;
  final String? holderName;
  final bool nameMatched;
  final DateTime? createdOn;
  // Live CustomerBank.cbank_id for this row — direct FK on the backend
  // (crpd_cbank_id), unlike BavHistoryItem/PennyVerifyHistoryItem's last-4
  // heuristic, so pairing to a card by id here is exact, not a guess.
  final String? cbankId;
  // Human-readable reason, populated only when status == "Failed" —
  // disambiguates an account mismatch from a plain payment failure (both
  // persist as the same crpd_status; see backend history()'s comment).
  final String? failureReason;

  RpdHistoryItem({
    required this.crpdId,
    required this.clientId,
    required this.status,
    this.bankName,
    this.accountLast4,
    this.holderName,
    required this.nameMatched,
    this.createdOn,
    this.cbankId,
    this.failureReason,
  });

  factory RpdHistoryItem.fromJson(Map<String, dynamic> json) {
    return RpdHistoryItem(
      crpdId: (json['crpd_id'] as num?)?.toInt() ?? 0,
      clientId: json['client_id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Pending',
      bankName: json['bank_name']?.toString(),
      accountLast4: json['account_last4']?.toString(),
      holderName: json['holder_name']?.toString(),
      nameMatched: json['name_matched'] as bool? ?? false,
      createdOn: json['created_on'] != null
          ? DateTime.tryParse(json['created_on'].toString())
          : null,
      cbankId: json['cbank_id']?.toString(),
      failureReason: json['failure_reason']?.toString(),
    );
  }
}

enum BankTimelineKind { bav, pennyPayment, pennyRefund, reversePennyDrop }

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
  final String? cbankId;

  BankTimelineEntry({
    required this.kind,
    required this.title,
    required this.status,
    required this.dateTime,
    this.provider,
    this.subtitle,
    this.cbankId,
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
      case BankTimelineKind.reversePennyDrop:
        if (s == 'success') return 'Verified';
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
  final BankTimelineEntry? rpd;
  final DateTime? sortDate;

  BankVerificationCard({
    required this.bankLabel,
    required this.sortDate,
    this.bav,
    this.payment,
    this.refund,
    this.rpd,
  });

  /// Groups BAV + Rs.1 payment/refund rows into per-attempt cards, newest
  /// first. Every Rs.1 row becomes its own card (paired with the nearest
  /// preceding BAV row for the same account, if any); any BAV row never
  /// consumed by a Rs.1 pairing becomes its own standalone card. RPD attempts
  /// (a third, independent table) are attached AFTER cards are built, paired
  /// by cbankId — exact, since crpd_cbank_id is a direct FK unlike the
  /// last-4+timing heuristic the BAV<->penny pairing above needs.
  static List<BankVerificationCard> build(
    List<BavHistoryItem> bav,
    List<PennyVerifyHistoryItem> penny, [
    List<RpdHistoryItem> rpd = const [],
  ]) {
    final sortedBav = [...bav]..sort((a, b) {
        if (a.attemptedOn == null) return 1;
        if (b.attemptedOn == null) return -1;
        return a.attemptedOn!.compareTo(b.attemptedOn!); // oldest first
      });
    final usedBav = <int>{}; // kycId of BAV rows already paired

    // Latest RPD attempt per cbankId — rpd arrives newest-first from the
    // backend (order_by('-crpd_id')), so first-seen-per-key wins.
    final rpdByCbankId = <String, RpdHistoryItem>{};
    for (final r in rpd) {
      if (r.cbankId != null && !rpdByCbankId.containsKey(r.cbankId)) {
        rpdByCbankId[r.cbankId!] = r;
      }
    }
    BankTimelineEntry? rpdEntry(String? cbankId) {
      final item = cbankId != null ? rpdByCbankId[cbankId] : null;
      if (item == null) return null;
      return BankTimelineEntry(
        kind: BankTimelineKind.reversePennyDrop,
        title: 'Reverse Penny Drop Verification',
        status: item.status,
        dateTime: item.createdOn,
        cbankId: item.cbankId,
        subtitle: item.failureReason,
      );
    }

    BankTimelineEntry bavEntry(BavHistoryItem item) => BankTimelineEntry(
          kind: BankTimelineKind.bav,
          title: 'Bank Account Verification',
          status: item.status,
          provider: item.provider,
          dateTime: item.attemptedOn,
          cbankId: item.cbankId,
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
        rpd: rpdEntry(matched?.cbankId),
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
        rpd: rpdEntry(item.cbankId),
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
