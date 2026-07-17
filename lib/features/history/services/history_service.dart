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

  /// [commodity]/[transactionType]/[status]/[dateFrom]/[dateTo] are the
  /// Transaction History filter sheet's server-side filter params — applied
  /// across the customer's full history before pagination, so filtered
  /// results aren't limited to whatever page is already cached locally.
  Future<HistoryResponse> getTransactionHistory({
    required String customerId,
    String? metalType,
    int page = 1,
    int limit = 20,
    String? commodity,
    String? transactionType,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await _apiClient.post('transactions/history', data: {
      'id_customer': customerId,
      if (metalType != null) 'metal_type': metalType,
      'page': page,
      'limit': limit,
      if (commodity != null && commodity.isNotEmpty) 'commodity': commodity,
      if (transactionType != null && transactionType.isNotEmpty)
        'transaction_type': transactionType,
      if (status != null && status.isNotEmpty) 'status': status,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
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
