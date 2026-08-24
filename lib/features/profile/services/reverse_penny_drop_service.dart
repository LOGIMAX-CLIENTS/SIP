import '../../../core/network/api_client.dart';
import '../../../core/security/secure_logger.dart';

/// SurePass Reverse Penny Drop — an OPTIONAL extra live-control proof layered
/// on top of an already Pennyless-verified bank account (see backend
/// domains/transactions/services/bank_verification_surepass.py module
/// docstring for why RPD alone can't target a specific account). The user
/// pays ₹1 from whichever UPI app they choose; the resolved payer account is
/// cross-checked server-side against the SAME cbank row this was initiated
/// for — a mismatch fails the attempt without touching the Pennyless result.
class ReversePennyDropService {
  final ApiClient _apiClient = ApiClient();

  /// POST account/verify-bank/rpd/initiate — returns {client_id,
  /// payment_link, ios_links: {paytm, phonepe, gpay, bhim, whatsapp}, amount}.
  /// [cbankId] must already be Pennyless/BAV-verified (cbank_is_verify=1).
  Future<Map<String, dynamic>> initiate({required String cbankId}) async {
    SecureLogger.d('ReversePennyDrop: initiating for cbank=$cbankId');
    final response = await _apiClient.post(
      'account/verify-bank/rpd/initiate',
      data: {'cbank_id': cbankId},
    );
    if (response.data == null || response.data['success'] != true) {
      throw Exception(_extractErrorMessage(
          response.data, 'Could not start Reverse Penny Drop verification.'));
    }
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  /// POST account/verify-bank/rpd/status — server-authoritative; re-checks
  /// SurePass directly rather than trusting any client-side assumption.
  /// Returns {verified: bool, status: 'PENDING'|'SUCCESS'|'FAILED'|'ACCOUNT_MISMATCH'}.
  Future<Map<String, dynamic>> status({required String clientId}) async {
    SecureLogger.d('ReversePennyDrop: checking status client_id=$clientId');
    final response = await _apiClient.post(
      'account/verify-bank/rpd/status',
      data: {'client_id': clientId},
    );
    if (response.data == null || response.data['success'] != true) {
      throw Exception(_extractErrorMessage(
          response.data, 'Could not check verification status.'));
    }
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  /// GET-equivalent (POST) account/verify-bank/rpd/history — past attempts.
  Future<List<Map<String, dynamic>>> history() async {
    final response = await _apiClient.get('account/verify-bank/rpd/history');
    if (response.data == null || response.data['success'] != true) return [];
    final List data = response.data['data'] ?? [];
    return data.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// Backend error shape nests the message under `error.message`
  /// (shared/utils/response.py `error_response()`), never top-level —
  /// check both so a real backend message is never masked by [fallback].
  String _extractErrorMessage(dynamic data, String fallback) {
    if (data is! Map) return fallback;
    final direct = data['message']?.toString();
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = (data['error'] is Map)
        ? (data['error'] as Map)['message']?.toString()
        : null;
    if (nested != null && nested.isNotEmpty) return nested;
    return fallback;
  }
}
