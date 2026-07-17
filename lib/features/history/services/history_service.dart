import '../../../core/network/api_client.dart';
import '../models/history_models.dart';
import '../models/history_filter_options_model.dart';

class HistoryService {
  final ApiClient _apiClient = ApiClient();

  /// Fetches the dynamic filter option set (commodities, transaction types,
  /// statuses) for the Transaction History filter sheet. Backend-driven so
  /// new values appear without a mobile app release.
  Future<HistoryFilterOptions> getFilterOptions({
    required String customerId,
  }) async {
    final response =
        await _apiClient.post('transactions/filter-options', data: {
      'id_customer': customerId,
    });

    if (response.data != null) {
      if (response.data['success'] == false) {
        final errorMsg = response.data['error']?['message'] ??
            response.data['error']?['internal_message'] ??
            'Failed to load filter options';
        throw Exception(errorMsg);
      }
      if (response.data['data'] != null) {
        return HistoryFilterOptions.fromJson(response.data['data']);
      }
    }
    throw Exception('Failed to load filter options');
  }

  Future<HistoryResponse> getTransactionHistory({
    required String customerId,
    String? metalType,
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _apiClient.post('transactions/history', data: {
      'id_customer': customerId,
      if (metalType != null) 'metal_type': metalType,
      'page': page,
      'limit': limit,
    });

    if (response.data != null) {
      if (response.data['success'] == false) {
        final errorMsg = response.data['error']?['message'] ?? response.data['error']?['internal_message'] ?? 'Failed to load transaction history';
        throw Exception(errorMsg);
      }
      if (response.data['data'] != null) {
        return HistoryResponse.fromJson(response.data['data']);
      }
    }
    throw Exception('Failed to load transaction history');
  }

  Future<TransactionDetailResponse> getTransactionDetails({
    required String customerId,
    required String transactionId,
  }) async {
    final response = await _apiClient.post('transactions/details', data: {
      'id_customer': customerId,
      'transaction_id': transactionId,
    });

    if (response.data != null) {
      if (response.data['success'] == false) {
        final errorMsg = response.data['error']?['message'] ?? response.data['error']?['internal_message'] ?? 'Failed to load transaction details';
        throw Exception(errorMsg);
      }
      if (response.data['data'] != null) {
        return TransactionDetailResponse.fromJson(response.data['data']);
      }
    }
    throw Exception('Failed to load transaction details');
  }
}
