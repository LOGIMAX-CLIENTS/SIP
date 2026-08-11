import '../../../core/network/api_client.dart';
import '../../../core/security/secure_logger.dart';
import '../models/sip_models.dart';

/// Custom SIP (multi-date AutoPay) API service.
///
/// Separate product from regular Daily/Weekly/Monthly SIP on the backend
/// (CustomSIPScheme, not SIPScheme — see domains/transactions/views/
/// custom_sip.py) but its create-response is shaped to match
/// SipCreateResponse exactly (see shared/services/custom_sip.py
/// create_scheme()'s return dict), so the mobile app reuses the same model
/// and the same Cashfree-checkout launch (sip_payment_screen.dart) as
/// regular SIP — nothing gateway-specific needed here.
class CustomSipService {
  final ApiClient _apiClient = ApiClient();

  /// Creates a new Custom SIP plan.
  ///
  /// [customDates]: day-of-month values (1-31), 1 to 28 entries — the auto
  /// saving runs on ALL of these dates every month. Always UPI Autopay on
  /// the backend (CSIPCreateSerializer has no payment_method field) — no
  /// payment method selection needed for this flow.
  Future<SipCreateResponse> createCustomSip({
    required int commodityId,
    required int amount,
    required List<int> customDates,
    String? label,
    /// Registered bank account (from the Bank Listing picker) — recorded on
    /// the scheme for reconciliation. Required (source of bank_details) when
    /// paymentMethod == 'emandate'; optional (TPV only) otherwise — see
    /// CSIPCreateSerializer.
    int? bankAccountId,
    /// 'upi' (default) | 'card' | 'emandate' — see CSIPCreateSerializer.
    String? paymentMethod,
  }) async {
    SecureLogger.d(
        'CustomSIP: Creating plan – commodity=$commodityId, dates=$customDates, paymentMethod=$paymentMethod');

    final Map<String, dynamic> payload = {
      'commodity_id': commodityId,
      'amount': amount,
      'custom_dates': customDates,
      if (label != null && label.isNotEmpty) 'label': label,
      if (bankAccountId != null) 'bank_account_id': bankAccountId,
      if (paymentMethod != null) 'payment_method': paymentMethod,
    };

    final response = await _apiClient.post('sip/custom/create', data: payload);
    return SipCreateResponse.fromJson(response.data);
  }

  /// Fetches every non-terminal Custom SIP scheme this customer owns —
  /// used to mark already-committed dates on the picker grid before the
  /// customer selects new ones.
  Future<List<CustomSipScheme>> listSchemes() async {
    SecureLogger.d('CustomSIP: Fetching scheme list');
    final response = await _apiClient.post('sip/custom/list');
    if (response.data != null && response.data['data'] != null) {
      final List list = response.data['data'];
      return list.map((e) => CustomSipScheme.fromJson(e)).toList();
    }
    return [];
  }

  /// Pauses an active Custom SIP scheme.
  Future<Map<String, dynamic>> pauseScheme({required int schemeId}) async {
    SecureLogger.d('CustomSIP: Pausing scheme $schemeId');
    final response = await _apiClient.post('sip/custom/$schemeId/pause');
    return response.data;
  }

  /// Resumes a paused Custom SIP scheme.
  Future<Map<String, dynamic>> resumeScheme({required int schemeId}) async {
    SecureLogger.d('CustomSIP: Resuming scheme $schemeId');
    final response = await _apiClient.post('sip/custom/$schemeId/resume');
    return response.data;
  }

  /// Cancels a Custom SIP scheme — frees its dates for a new scheme.
  Future<Map<String, dynamic>> cancelScheme({
    required int schemeId,
    required String reason,
  }) async {
    SecureLogger.d('CustomSIP: Cancelling scheme $schemeId');
    final response = await _apiClient.post(
      'sip/custom/$schemeId/cancel',
      data: {'reason': reason},
    );
    return response.data;
  }

  /// Full detail for the manage screen (subscription ID, start date,
  /// commodity name, amount, dates, status).
  Future<CustomSipSchemeDetail> getSchemeStatus({required int schemeId}) async {
    SecureLogger.d('CustomSIP: Fetching status for scheme $schemeId');
    final response = await _apiClient.post('sip/custom/$schemeId/status');
    if (response.data != null && response.data['data'] != null) {
      return CustomSipSchemeDetail.fromJson(response.data['data']);
    }
    throw Exception('Failed to load Custom SIP details');
  }
}
