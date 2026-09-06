import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/network/api_client.dart';
import '../models/bank_account.dart';

class BankDetailsService {
  final ApiClient _apiClient = ApiClient();

  /// POST profile/bank-accounts — list all active bank accounts.
  Future<List<BankAccount>> fetchBankAccounts() async {
    final response = await _apiClient.post('profile/bank-accounts', data: {});
    if (response.data != null && response.data['success'] == true) {
      final List data = response.data['data']?['accounts'] ?? [];
      return data.map((e) => BankAccount.fromJson(e)).toList();
    }
    return [];
  }

  /// POST profile/bank-accounts/set-primary — mark one account as Primary.
  Future<void> setPrimary(String idBank) async {
    final response = await _apiClient.post(
      'profile/bank-accounts/set-primary',
      data: {'id_bank': idBank},
    );
    if (response.data == null || response.data['success'] != true) {
      throw Exception(response.data?['message'] ??
          'Could not set this account as Primary. Please try again.');
    }
  }

  /// POST profile/bank-accounts/remove — soft-remove (backend keeps history).
  Future<void> removeBank(String idBank) async {
    final response = await _apiClient.post(
      'profile/bank-accounts/remove',
      data: {'id_bank': idBank},
    );
    if (response.data == null || response.data['success'] != true) {
      throw Exception(
          response.data?['message'] ?? 'Could not remove this bank account.');
    }
  }

  /// POST account/check-beneficiary-name — live name-match check against the
  /// customer's verified PAN/Aadhaar, called on Beneficiary Name field-blur.
  Future<Map<String, dynamic>> checkBeneficiaryName(String name) async {
    final response = await _apiClient
        .post('account/check-beneficiary-name', data: {'name': name});
    final data = response.data?['data'] as Map<String, dynamic>? ?? {};
    return {
      'matched': data['matched'] == true,
      'message': data['message']?.toString() ?? '',
      // Distinguishes "no verified PAN/Aadhaar at all" (customer needs to
      // complete KYC) from "typed name doesn't match" (customer needs to
      // fix the name) — both report matched=false, but call for different
      // follow-up UI. Defaults true so older/unexpected response shapes
      // don't wrongly show a "Complete KYC" prompt to an already-KYC'd
      // customer who hit a genuine name mismatch.
      'has_kyc': data['has_kyc'] != false,
    };
  }

  /// POST account/verify-bank/contact-admin — "Contact Admin" after a BAV
  /// failure. Records what the customer typed as a case awaiting an admin;
  /// verifies nothing on its own (see backend BankAccountService.
  /// request_manual_review's docstring — no CustomerBank row is created and
  /// no verification status changes). [passbookPhoto] (passbook or
  /// cancelled-cheque photo) is required — same evidence expectation as
  /// PAN/Aadhaar's own manual upload (KycRepository.submitManualKyc) — sent
  /// as multipart/form-data under key "passbook", same reasoning as that
  /// method's doc comment (ApiClient.post() auto-detects FormData; the
  /// encryption interceptor only touches Map payloads). Same raw-map return
  /// shape as the other bank-account calls above — caller reads
  /// result['success'].
  ///
  /// Lives here, not in withdrawal_service.dart — this is a bank-account
  /// verification concern (same family as checkBeneficiaryName above), and
  /// its only caller, add_bank_account_sheet.dart, is a shared widget used
  /// by both Withdrawal and Profile → Bank Details, not withdrawal-specific.
  Future<Map<String, dynamic>> requestManualBavReview({
    required String accNo,
    required String ifsc,
    required String holderName,
    required XFile passbookPhoto,
  }) async {
    final formData = FormData.fromMap({
      'account_no': accNo,
      'ifsc_code': ifsc,
      'account_holder': holderName,
      'passbook': await MultipartFile.fromFile(
        passbookPhoto.path,
        filename: passbookPhoto.name,
      ),
    });
    final response = await _apiClient.post('account/verify-bank/contact-admin', data: formData);
    return response.data ?? {};
  }
}

final bankDetailsServiceProvider = Provider((ref) => BankDetailsService());

/// Fetches the customer's bank accounts for the Bank Details screen.
/// Invalidate after add/remove/set-primary to refresh the list.
final bankAccountsProvider =
    FutureProvider.autoDispose<List<BankAccount>>((ref) {
  return ref.read(bankDetailsServiceProvider).fetchBankAccounts();
});
