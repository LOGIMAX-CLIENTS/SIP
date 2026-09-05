import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../models/bank_verification_history.dart';

class BankVerificationHistoryService {
  final ApiClient _apiClient = ApiClient();

  /// GET account/verify-bank/bav-history
  Future<List<BavHistoryItem>> fetchBavHistory() async {
    final response = await _apiClient.get('account/verify-bank/bav-history');
    if (response.data != null && response.data['success'] == true) {
      final List data = response.data['data'] ?? [];
      return data.map((e) => BavHistoryItem.fromJson(e)).toList();
    }
    return [];
  }

  /// GET account/verify-bank/penny/history — backs both the payment and
  /// refund history screens (same rows, different fields rendered).
  Future<List<PennyVerifyHistoryItem>> fetchPennyVerifyHistory() async {
    final response = await _apiClient.get('account/verify-bank/penny/history');
    if (response.data != null && response.data['success'] == true) {
      final List data = response.data['data'] ?? [];
      return data.map((e) => PennyVerifyHistoryItem.fromJson(e)).toList();
    }
    return [];
  }

  /// GET account/verify-bank/rpd/history — the RPD line on the Bank Account
  /// Verification hub. Same endpoint ReversePennyDropService.history() also
  /// calls, but typed here alongside the other two history fetches so the
  /// hub's data layer (bavHistoryProvider/pennyVerifyHistoryProvider) stays
  /// self-contained rather than reaching into a screen-local service.
  Future<List<RpdHistoryItem>> fetchRpdHistory() async {
    final response = await _apiClient.get('account/verify-bank/rpd/history');
    if (response.data != null && response.data['success'] == true) {
      final List data = response.data['data'] ?? [];
      return data.map((e) => RpdHistoryItem.fromJson(e)).toList();
    }
    return [];
  }

  /// POST account/verify-bank/pan-link — check (or retry) whether the
  /// customer's own already-verified PAN is linked to [cbankId], an
  /// already-BAV-verified bank account. Uses the PAN on file server-side;
  /// the client never sends a PAN value (see PanBankLinkView's docstring).
  /// Returns `data` — `{linked, full_name, account_type, account_nature,
  /// account_holder}` — on success; throws with the server's specific
  /// reason on failure (e.g. "not currently required", "must pass BAV
  /// verification first", "Complete your PAN verification...").
  Future<Map<String, dynamic>> checkPanBankLink({required String cbankId}) async {
    final response = await _apiClient.post('account/verify-bank/pan-link', data: {
      'cbank_id': cbankId,
    });

    final data = response.data['data'];
    if (response.data['success'] == true) {
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    final errorObj = response.data['error'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (data is Map ? data['message'] : null) ??
        response.data['message'] ??
        'Could not check PAN-Bank account linkage.';
    throw Exception(serverMessage);
  }
}

final bankVerificationHistoryServiceProvider =
    Provider((ref) => BankVerificationHistoryService());

final bavHistoryProvider =
    FutureProvider.autoDispose<List<BavHistoryItem>>((ref) {
  return ref.read(bankVerificationHistoryServiceProvider).fetchBavHistory();
});

final pennyVerifyHistoryProvider =
    FutureProvider.autoDispose<List<PennyVerifyHistoryItem>>((ref) {
  return ref
      .read(bankVerificationHistoryServiceProvider)
      .fetchPennyVerifyHistory();
});

final rpdHistoryProvider =
    FutureProvider.autoDispose<List<RpdHistoryItem>>((ref) {
  return ref.read(bankVerificationHistoryServiceProvider).fetchRpdHistory();
});
