class SavingConfig {
  final double minAmount;
  final double maxAmount;
  final double gst;
  final String type; // inclusive / exclusive
  final int sellRateLockSeconds;
  final int buyRateLockSeconds;

  SavingConfig({
    required this.minAmount,
    required this.maxAmount,
    required this.gst,
    required this.type,
    required this.sellRateLockSeconds,
    required this.buyRateLockSeconds,
  });

  factory SavingConfig.fromJson(Map<String, dynamic> json) {
    return SavingConfig(
      minAmount: (json['min_amount'] ?? 0).toDouble(),
      maxAmount: (json['max_amount'] ?? 0).toDouble(),
      gst: double.tryParse(json['gst']?.toString() ?? '0') ?? 0.0,
      type: json['type'] ?? '',
      sellRateLockSeconds: json['sell_rate_lock_seconds'] ?? 0,
      buyRateLockSeconds: json['buy_rate_lock_seconds'] ?? 0,
    );
  }
}

class PaymentMethod {
  final String id;
  final String name;
  final String icon;          // legacy: filename or icon key
  final String description;   // legacy: same as subtitle

  // ── New fields (API v2 — payment method icons) ───────────────────────
  final String iconUrl;              // absolute URL to category icon
  final String subtitle;             // e.g. "GPay, PhonePe, Paytm & more"
  final List<String> badgeIcons;     // absolute URLs for sub-brand logos

  PaymentMethod({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    this.iconUrl = '',
    this.subtitle = '',
    this.badgeIcons = const [],
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      icon: json['icon'] ?? '',
      description: json['description'] ?? '',
      iconUrl: json['icon_url'] ?? '',
      subtitle: json['subtitle'] ?? json['description'] ?? '',
      badgeIcons: (json['badge_icons'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}


class PaymentOrder {
  final String paymentUrl;
  final String orderId;

  PaymentOrder({
    required this.paymentUrl,
    required this.orderId,
  });

  factory PaymentOrder.fromJson(Map<String, dynamic> json) {
    return PaymentOrder(
      paymentUrl: json['payment_url'] ?? '',
      orderId: json['order_id'] ?? '',
    );
  }
}

class EligibilityResponse {
  final String nextStep; // KYC_REQUIRED or PAYMENT

  EligibilityResponse({required this.nextStep});

  factory EligibilityResponse.fromJson(Map<String, dynamic> json) {
    return EligibilityResponse(
      nextStep: json['next_step'] ?? 'PAYMENT',
    );
  }
}

class PurchaseInitiateResponse {
  final String? orderId;
  final String? sessionId;
  final String? environment;
  final String? message;
  final String? amountInr;
  final String? weight;
  final String? ratePerGram;
  // ── Gateway routing ──────────────────────────────────────────────────────
  /// Which payment gateway the backend selected: "cashfree" or "hdfc".
  /// Defaults to "cashfree" for backward compatibility.
  final String paymentGateway;
  // ── HDFC / Juspay HyperSDK fields ────────────────────────────────────────
  /// Full Juspay sdkPayload JSON returned by backend after calling
  /// Juspay's order.create API. Passed directly to hyperSDK.openPaymentPage().
  final Map<String, dynamic>? sdkPayload;
  final String? merchantId;
  final String? clientId;
  final String? hdfcEnvironment;

  PurchaseInitiateResponse({
    this.orderId,
    this.sessionId,
    this.environment,
    this.message,
    this.amountInr,
    this.weight,
    this.ratePerGram,
    this.paymentGateway = 'cashfree',
    this.sdkPayload,
    this.merchantId,
    this.clientId,
    this.hdfcEnvironment,
  });

  factory PurchaseInitiateResponse.fromJson(Map<String, dynamic> json) {
    return PurchaseInitiateResponse(
      orderId: json['order_id'],
      sessionId: json['session_id'],
      environment: json['environment'],
      message: json['message'],
      amountInr: json['amount_inr']?.toString(),
      weight: json['weight']?.toString(),
      ratePerGram: json['rate_per_gram']?.toString(),
      paymentGateway: json['payment_gateway']?.toString() ?? 'cashfree',
      sdkPayload: json['sdk_payload'] is Map<String, dynamic>
          ? json['sdk_payload']
          : null,
      merchantId: json['merchant_id']?.toString(),
      clientId: json['client_id']?.toString(),
      hdfcEnvironment: json['hdfc_environment']?.toString(),
    );
  }
}

