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
