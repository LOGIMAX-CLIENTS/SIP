class LinkedUpi {
  final String id;
  final String upiId;
  final bool isVerified;

  LinkedUpi({required this.id, required this.upiId, required this.isVerified});

  factory LinkedUpi.fromJson(Map<String, dynamic> json) {
    return LinkedUpi(
      id: json['id']?.toString() ?? '',
      upiId: json['upi_id']?.toString() ?? '',
      isVerified: json['is_verified'] == true,
    );
  }
}

class BankAccount {
  final String idBank;
  final String bankName;
  final String accountNumberMasked;
  final String ifscCode;
  final String holderName;
  final String verificationStatus; // "VERIFIED" | "PENDING"
  final bool isPrimary;
  final List<LinkedUpi> linkedUpis;

  BankAccount({
    required this.idBank,
    required this.bankName,
    required this.accountNumberMasked,
    required this.ifscCode,
    required this.holderName,
    required this.verificationStatus,
    required this.isPrimary,
    this.linkedUpis = const [],
  });

  bool get isVerified => verificationStatus == 'VERIFIED';

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      idBank: json['id_bank']?.toString() ?? '',
      bankName: json['bank_name']?.toString() ?? 'Bank',
      accountNumberMasked: json['account_number_masked']?.toString() ?? '',
      ifscCode: json['ifsc_code']?.toString() ?? '',
      holderName: json['holder_name']?.toString() ?? '',
      verificationStatus: json['verification_status']?.toString() ?? 'PENDING',
      isPrimary: json['is_primary'] == true,
      linkedUpis: (json['linked_upis'] as List<dynamic>? ?? [])
          .map((e) => LinkedUpi.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
