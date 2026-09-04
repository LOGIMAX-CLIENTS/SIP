import '../../../core/network/api_client.dart';
import '../../../core/security/secure_logger.dart';
import '../models/sip_models.dart';
import '../models/sip_transaction_filter_options_model.dart';
import '../../history/models/history_models.dart';

/// SIP API service.
///
/// All endpoints are POST as specified in the requirements.
/// Encryption of sensitive fields (`amount`, `transaction_pin`, etc.) is
/// handled automatically by [ApiSecurityInterceptor].
class SipService {
  final ApiClient _apiClient = ApiClient();

  // ─── Config ─────────────────────────────────────────────────────────────
  /// Fetches SIP configuration (frequencies, commodities, min/max amounts).
  Future<SipConfig> getConfig() async {
    SecureLogger.d('SIP: Fetching SIP config');
    final response = await _apiClient.post('sip/config');
    if (response.data != null && response.data['data'] != null) {
      return SipConfig.fromJson(response.data['data']);
    }
    throw Exception('Failed to load SIP configuration');
  }

  // ─── Denominations ──────────────────────────────────────────────────────
  /// Gold denominations for SIP, optionally filtered by frequency.
  Future<List<SipDenomination>> getGoldDenominations({int? frequencyId}) async {
    SecureLogger.d('SIP: Fetching gold denominations (freq=$frequencyId)');
    final Map<String, dynamic> payload = {};
    if (frequencyId != null) payload['frequency'] = frequencyId;
    final response =
        await _apiClient.post('sip/gold-denominations', data: payload);
    if (response.data != null && response.data['data'] != null) {
      final List list = response.data['data'];
      return list.map((e) => SipDenomination.fromJson(e)).toList();
    }
    return [];
  }

  /// Silver denominations for SIP, optionally filtered by frequency.
  Future<List<SipDenomination>> getSilverDenominations(
      {int? frequencyId}) async {
    SecureLogger.d('SIP: Fetching silver denominations (freq=$frequencyId)');
    final Map<String, dynamic> payload = {};
    if (frequencyId != null) payload['frequency'] = frequencyId;
    final response =
        await _apiClient.post('sip/silver-denominations', data: payload);
    if (response.data != null && response.data['data'] != null) {
      final List list = response.data['data'];
      return list.map((e) => SipDenomination.fromJson(e)).toList();
    }
    return [];
  }

  // ─── Create SIP Plan ────────────────────────────────────────────────────
  /// Creates a new SIP plan.
  ///
  /// [frequencyId]:  1 = Daily, 2 = Weekly, 3 = Monthly.
  /// [day]:          Required for Weekly (e.g., "Monday").
  /// [date]:         Required for Monthly (1–28).
  Future<SipCreateResponse> createSip({
    required int frequencyId,
    required int commodityId,
    required int amount,
    String? day,
    int? date,
    /// 'upi' | 'card' | 'emandate'. Omitted/null keeps the backend's own
    /// default ('upi') — matches pre-existing behaviour for callers that
    /// don't yet offer method selection. 'emandate' is the canonical value
    /// for bank-account mandate registration (previously sent as
    /// 'netbanking' — the backend still accepts that as a legacy alias for
    /// older app builds, but this client now sends 'emandate' directly; see
    /// SIPCreateSerializer.validate() in the backend repo).
    String? paymentMethod,
    /// Registered bank account (from the Bank Listing picker) — recorded on
    /// the scheme for every method; for 'emandate' it also supplies the
    /// mandate's bank_details, taking priority over the raw bank_* fields
    /// below (see SIPCreateSerializer.validate()).
    int? bankAccountId,
    /// eMandate only — legacy ad-hoc entry, required by the backend when
    /// paymentMethod == 'emandate' AND bankAccountId is absent (see
    /// SIPCreateSerializer.validate()).
    String? bankAccountNumber,
    String? bankIfsc,
    String? bankBeneficiaryName,
    String? bankAccountType,
  }) async {
    SecureLogger.d(
        'SIP: Creating SIP – frequency=$frequencyId, commodity=$commodityId, method=${paymentMethod ?? 'upi'}');

    final Map<String, dynamic> payload = {
      'frequency': frequencyId,
      'commodity_id': commodityId,
      'amount': amount,
    };

    if (frequencyId == 2 && day != null) {
      payload['day'] = day;
    }
    if (frequencyId == 3 && date != null) {
      payload['date'] = date;
    }
    if (paymentMethod != null) {
      payload['payment_method'] = paymentMethod;
    }
    if (bankAccountId != null) {
      payload['bank_account_id'] = bankAccountId;
    }
    if (paymentMethod == 'emandate') {
      payload['bank_account_number'] = bankAccountNumber;
      payload['bank_ifsc'] = bankIfsc;
      payload['bank_beneficiary_name'] = bankBeneficiaryName;
      payload['bank_account_type'] = bankAccountType ?? 'savings';
    }

    final response = await _apiClient.post('sip/create', data: payload);
    return SipCreateResponse.fromJson(response.data);
  }

  // ─── SIP Details (active plans list) ────────────────────────────────────
  /// Retrieves current SIP plan details.
  Future<List<SipPlanDetail>> getSipDetails() async {
    SecureLogger.d('SIP: Fetching SIP details');
    final response = await _apiClient.post('sip/details');
    if (response.data != null && response.data['data'] != null) {
      final data = response.data['data'];
      if (data is List) {
        return data.map((e) => SipPlanDetail.fromJson(e)).toList();
      } else if (data is Map<String, dynamic>) {
        return [SipPlanDetail.fromJson(data)];
      }
    }
    return [];
  }

  // ─── Manage Details ─────────────────────────────────────────────────────
  /// Fetches detailed info for the manage savings screen.
  Future<SipManageDetails> getManageDetails({
    required String subscriptionId,
  }) async {
    SecureLogger.d('SIP: Fetching manage details for $subscriptionId');
    final response = await _apiClient.post('sip/manage-details', data: {
      'subscription_id': subscriptionId,
    });
    if (response.data != null && response.data['data'] != null) {
      return SipManageDetails.fromJson(response.data['data']);
    }
    throw Exception('Failed to load manage details');
  }

  // ─── Pause ──────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> pauseSip({
    required String subscriptionId,
  }) async {
    SecureLogger.d('SIP: Pausing subscription $subscriptionId');
    final response = await _apiClient.post('sip/pause', data: {
      'subscription_id': subscriptionId,
    });
    return response.data;
  }

  // ─── Resume ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> resumeSip({
    required String subscriptionId,
  }) async {
    SecureLogger.d('SIP: Resuming subscription $subscriptionId');
    final response = await _apiClient.post('sip/resume', data: {
      'subscription_id': subscriptionId,
    });
    return response.data;
  }

  // ─── Cancel ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> cancelSip({
    required String subscriptionId,
    required String reason,
  }) async {
    SecureLogger.d('SIP: Cancelling subscription $subscriptionId');
    final response = await _apiClient.post('sip/cancel', data: {
      'subscription_id': subscriptionId,
      'reason': reason,
    });
    return response.data;
  }

  // ─── Confirm (After Cashfree mandate auth callback) ────────────────────
  /// Verifies mandate authorization status with the backend.
  ///
  /// Called after Cashfree SDK returns a success/failure callback.
  /// Backend checks the mandate status with Cashfree and returns
  /// the verified result.
  Future<Map<String, dynamic>> confirmSip({
    required String orderId,
    String? subscriptionId,
  }) async {
    SecureLogger.d('SIP: Confirming mandate auth for order $orderId');
    final Map<String, dynamic> payload = {
      'order_id': orderId,
    };
    if (subscriptionId != null && subscriptionId.isNotEmpty) {
      payload['subscription_id'] = subscriptionId;
    }
    SecureLogger.d('SIP: Confirming with payload keys: ${payload.keys}');
    final response = await _apiClient.post('sip/confirm', data: payload);
    return response.data;
  }

  // ─── SIP Transaction History ─────────────────────────────────────────
  /// Fetches one page of SIP transaction history for [frequency]
  /// (Daily/Weekly/Monthly/Custom — required, since each tab lazy-loads
  /// independently). [commodity]/[status]/[dateFrom]/[dateTo] are the SIP
  /// Transactions filter sheet's server-side filter params — applied across
  /// the customer's full history for that frequency before pagination, same
  /// principle as HistoryService.getTransactionHistory.
  ///
  /// Reuses the same [HistoryResponse] model from the history module since
  /// the response structure (grouped_transactions + pagination) is identical.
  Future<HistoryResponse> getSipTransactions({
    required String frequency,
    int page = 1,
    int limit = 20,
    String? commodity,
    String? status,
    String? dateFrom,
    String? dateTo,
  }) async {
    SecureLogger.d('SIP: Fetching SIP transaction history (freq=$frequency, page=$page)');
    final response = await _apiClient.post('sip/transactions', data: {
      'frequency': frequency,
      'page': page,
      'limit': limit,
      if (commodity != null && commodity.isNotEmpty) 'commodity': commodity,
      if (status != null && status.isNotEmpty) 'status': status,
      if (dateFrom != null) 'date_from': dateFrom,
      if (dateTo != null) 'date_to': dateTo,
    });
    if (response.data != null) {
      if (response.data['success'] == false) {
        final errorMsg = response.data['error']?['message'] ??
            response.data['error']?['internal_message'] ??
            'Failed to load AutoGold transactions';
        throw Exception(errorMsg);
      }
      if (response.data['data'] != null) {
        return HistoryResponse.fromJson(response.data['data']);
      }
    }
    throw Exception('Failed to load AutoGold transactions');
  }

  // ─── SIP Transaction Filter Options ───────────────────────────────────
  /// Fetches the dynamic filter option set (frequencies, commodities,
  /// statuses) for the SIP Transactions filter sheet. Backend-driven so new
  /// values appear without a mobile app release.
  Future<SipTransactionFilterOptions> getSipTransactionFilterOptions() async {
    SecureLogger.d('SIP: Fetching SIP transaction filter options');
    final response = await _apiClient.post('sip/transaction-filter-options');
    if (response.data != null) {
      if (response.data['success'] == false) {
        final errorMsg = response.data['error']?['message'] ??
            response.data['error']?['internal_message'] ??
            'Failed to load filter options';
        throw Exception(errorMsg);
      }
      if (response.data['data'] != null) {
        return SipTransactionFilterOptions.fromJson(response.data['data']);
      }
    }
    throw Exception('Failed to load filter options');
  }

  // ─── SIP Transaction Details ─────────────────────────────────────────
  /// Fetches details for a single SIP transaction.
  Future<Map<String, dynamic>> getSipTransactionDetails({
    required String transactionId,
  }) async {
    SecureLogger.d('SIP: Fetching SIP transaction details for $transactionId');
    final response = await _apiClient.post('sip/transaction-details', data: {
      'transaction_id': transactionId,
    });
    if (response.data != null) {
      if (response.data['success'] == false) {
        final errorMsg = response.data['error']?['message'] ??
            response.data['error']?['internal_message'] ??
            'Failed to load AutoGold transaction details';
        throw Exception(errorMsg);
      }
      return response.data;
    }
    throw Exception('Failed to load AutoGold transaction details');
  }
}
