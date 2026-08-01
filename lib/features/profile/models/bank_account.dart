class BankAccount {
  final String idBank;
  final String bankName;
  final String accountNumberMasked;
  final String ifscCode;
  final String holderName;
  final String verificationStatus; // "VERIFIED" | "PENDING"
  final bool isPrimary;

  BankAccount({
    required this.idBank,
    required this.bankName,
    required this.accountNumberMasked,
    required this.ifscCode,
    required this.holderName,
    required this.verificationStatus,
    required this.isPrimary,
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
    );
  }
}
