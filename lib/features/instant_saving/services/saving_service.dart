import '../../../core/network/api_client.dart';
import '../models/saving_models.dart';
import '../../../core/security/secure_logger.dart';

class SavingService {
  final ApiClient _apiClient = ApiClient();

  Future<SavingConfig> getSavingConfig() async {
    final response = await _apiClient.post('savings/config');
    if (response.data != null && response.data['data'] != null) {
      return SavingConfig.fromJson(response.data['data']);
    }
    throw Exception('Failed to load saving configuration');
  }

  Future<EligibilityResponse> checkEligibility({
    required String customerId,
    required String metalId,
    required String mobile,
    required double amount,
    required double rate,
    String? couponCode,
  }) async {
    final response = await _apiClient.post('savings/check-eligibility', data: {
      'id_customer': customerId,
      'id_metal': metalId,
      'mobile': mobile,
      'amount_inr': amount,
      'rate_per_gram': rate,
      'device_id': 'device-id-placeholder',
      'coupon_code': couponCode,
      'request_from': 'instant',
    });
    return EligibilityResponse.fromJson(response.data['data']);
  }

  Future<PurchaseInitiateResponse> initiatePurchase({
    required String customerId,
    required String metalId,
    required String mobile,
    required int buyType, // 1 = AMOUNT, 2 = GRAMS
    required double amount,
    required double rate,
    required double weight,
    String? couponCode,
    String? paymentMethod, // "upi", "card", "netbanking" — gateway routing hint
  }) async {
    SecureLogger.d(
        '[INITIATE] buy_type → $buyType (${buyType == 1 ? 'AMOUNT' : 'GRAMS'})');
    final response = await _apiClient.post('savings/initiate', data: {
      'id_customer': customerId,
      'id_metal': metalId,
      'mobile': mobile,
      'buy_type': buyType, // sends 1 or 2 to server
      'amount_inr': amount.toStringAsFixed(2),
      'rate_per_gram': rate,
      'weight': weight,
      'device_id': 'device-id-placeholder',
      'coupon_code': couponCode,
      'request_from': 'instant',
      if (paymentMethod != null) 'payment_method': paymentMethod,
    });
    return PurchaseInitiateResponse.fromJson(response.data['data']);
  }

  Future<Map<String, dynamic>> confirmPayment(
    String orderId, {
    String? razorpayPaymentId,
    String? razorpaySignature,
    String? razorpayOrderId,
  }) async {
    final response = await _apiClient.post('savings/confirm-payment', data: {
      'order_id': orderId,
      if (razorpayPaymentId != null) 'razorpay_payment_id': razorpayPaymentId,
      if (razorpaySignature != null) 'razorpay_signature': razorpaySignature,
      if (razorpayOrderId != null) 'razorpay_order_id': razorpayOrderId,
    });
    return response.data;
  }

  Future<Map<String, dynamic>> cancelOrder(String orderId) async {
    final response = await _apiClient.post('savings/cancel_order', data: {
      'order_id': orderId,
    });
    return response.data;
  }
}

class PaymentService {
  final ApiClient _apiClient = ApiClient();

  Future<List<PaymentMethod>> getPaymentMethods() async {
    SecureLogger.d('DEBUG: Calling getPaymentMethods API...');
    final response = await _apiClient.post('payments/methods');
    if (response.data != null && response.data['data'] != null) {
      final List list = response.data['data']['payment_methods'] ?? [];
      return list.map((item) => PaymentMethod.fromJson(item)).toList();
    }
    return [];
  }

  Future<PaymentOrder> createOrder({
    required double amount,
    required String methodId,
    required String transactionId,
  }) async {
    final response = await _apiClient.post('payments/create-order', data: {
      'amount': amount,
      'method_id': methodId,
      'transaction_id': transactionId,
    });
    return PaymentOrder.fromJson(response.data['data']);
  }

  Future<String> verifyPaymentStatus(String orderId) async {
    final response = await _apiClient.post('payments/status', data: {
      'order_id': orderId,
    });
    return response.data['data']['status'];
  }
}
