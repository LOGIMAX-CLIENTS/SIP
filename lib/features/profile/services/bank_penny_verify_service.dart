import '../../../core/network/api_client.dart';
import '../../../core/security/secure_logger.dart';

/// ₹1 payment-deduction verification layer — runs after Cashfree BAV
/// (Add Bank Account) to prove the account is live and controlled by the
/// customer right now. No refund — a plain payment, not a penny-drop/
/// reverse-penny-drop (see backend domains/transactions/services/
/// bank_penny_verify.py).
class BankPennyVerifyService {
  final ApiClient _apiClient = ApiClient();

  /// POST account/verify-bank/penny/initiate — creates a real ₹1 order via
  /// the active PAYMENT gateway for [paymentMethod] ('upi' | 'card' |
  /// 'netbanking'). Returns the raw data map — shape depends on which
  /// gateway is active (Cashfree: session_id + sdk_payload{session_id,
  /// order_id}; Razorpay: session_id + sdk_payload{key, order_id, amount,
  /// currency, name, prefill}) — the caller dispatches on `payment_gateway`.
  Future<Map<String, dynamic>> initiate({
    required String cbankId,
    required String paymentMethod,
  }) async {
    SecureLogger.d(
        'BankPennyVerify: initiating ₹1 verify for cbank=$cbankId via $paymentMethod');
    final response = await _apiClient.post(
      'account/verify-bank/penny/initiate',
      data: {'cbank_id': cbankId, 'payment_method': paymentMethod},
    );
    if (response.data == null || response.data['success'] != true) {
      throw Exception(_extractErrorMessage(
          response.data, 'Could not start account verification.'));
    }
    return Map<String, dynamic>.from(response.data['data'] ?? {});
  }

  /// POST account/verify-bank/penny/confirm — server-authoritative check;
  /// never trusts the SDK callback alone. Returns {verified: bool, status}.
  Future<Map<String, dynamic>> confirm({required String internalOrderId}) async {
    SecureLogger.d('BankPennyVerify: confirming order=$internalOrderId');
    final response = await _apiClient.post(
      'account/verify-bank/penny/confirm',
      data: {'internal_order_id': internalOrderId},
    );
    if (response.data == null || response.data['success'] != true) {
      throw Exception(
          _extractErrorMessage(response.data, 'Could not confirm payment.'));
    }
    return Map<String, dynamic>.from(response.data['data'] ?? {});
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
