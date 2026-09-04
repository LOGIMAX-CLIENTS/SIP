/// SIP (Auto Savings) data models.
///
/// All models follow the same serialisation pattern used across the codebase:
///   • Named constructors via `fromJson`
///   • Defensive null-coalescing (`??`)
///   • No code-generation dependencies

// ─── SIP Configuration ──────────────────────────────────────────────────────

class SipFrequency {
  final int id;
  final String name;
  final bool isDefault;

  SipFrequency({
    required this.id,
    required this.name,
    this.isDefault = false,
  });

  factory SipFrequency.fromJson(Map<String, dynamic> json) {
    return SipFrequency(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
      isDefault: (json['is_default'] ?? 0) == 1,
    );
  }
}

class SipCommodity {
  final int id;
  final String name;

  SipCommodity({required this.id, required this.name});

  factory SipCommodity.fromJson(Map<String, dynamic> json) {
    return SipCommodity(
      id: int.tryParse(json['id']?.toString() ?? '0') ?? 0,
      name: json['name']?.toString() ?? '',
    );
  }
}

class SipConfig {
  final double minAmount;
  final double maxAmount;
  final List<SipFrequency> frequencies;
  final List<SipCommodity> commodities;
  /// Payment method ids the active SIP Autopay gateway supports for mandate
  /// registration. Card is only included when Razorpay is the active
  /// gateway (its TPV supports Debit Cards); Cashfree omits it (its TPV
  /// docs never mention card support) — see backend SIPSchemeService.get_config().
  final List<String> supportedPaymentMethods;

  SipConfig({
    required this.minAmount,
    required this.maxAmount,
    required this.frequencies,
    required this.commodities,
    this.supportedPaymentMethods = const ['upi', 'netbanking'],
  });

  factory SipConfig.fromJson(Map<String, dynamic> json) {
    final List freqList = json['frequencies'] ?? [];
    final List commodityList = json['commodities'] ?? [];
    final List? methodList = json['supported_payment_methods'];
    return SipConfig(
      minAmount: (json['min_amount'] ?? 0).toDouble(),
      maxAmount: (json['max_amount'] ?? 0).toDouble(),
      frequencies: freqList.map((e) => SipFrequency.fromJson(e)).toList(),
      commodities: commodityList.map((e) => SipCommodity.fromJson(e)).toList(),
      supportedPaymentMethods: methodList != null
          ? methodList.map((e) => e.toString()).toList()
          : const ['upi', 'netbanking'],
    );
  }
}

// ─── SIP Denomination ───────────────────────────────────────────────────────

class SipDenomination {
  final double value;
  final bool isPopular;

  SipDenomination({required this.value, this.isPopular = false});

  factory SipDenomination.fromJson(Map<String, dynamic> json) {
    return SipDenomination(
      value: (json['value'] ?? 0).toDouble(),
      isPopular: (json['is_popular'] ?? 0) == 1,
    );
  }
}

// ─── SIP Create Response ────────────────────────────────────────────────────

class SipCreateResponse {
  final bool success;
  final String message;
  final String? errorCode;
  final String? subscriptionId;
  final String? status;
  final String? orderId;
  final String? sessionId;
  final String? environment;
  /// Full Cashfree subscription checkout URL.
  /// Backend obtains this from Cashfree's mandate creation response.
  final String? authorizationLink;
  /// Which gateway/SDK the client should launch: 'cashfree' or 'razorpay'.
  /// Defaults to 'cashfree' for backward compatibility with older backend
  /// responses that predate this field.
  final String paymentGateway;
  /// Razorpay Checkout publishable key (rzp_test_xxx / rzp_live_xxx).
  /// Empty when paymentGateway == 'cashfree' — the Cashfree subscription
  /// SDK does not need a client-side key.
  final String? keyId;
  /// Only meaningful when paymentGateway == 'razorpay': 'subscriptions'
  /// (orderId is a real sub_xxx id; Checkout takes subscription_id) or
  /// 'recurring' (orderId is a real order_xxx id; Checkout takes order_id +
  /// recurring: '1' instead — see sip_payment_screen.dart). Defaults to
  /// 'subscriptions' to match the backend's own default when this field is
  /// absent (see shared/services/sip.py create_scheme).
  final String mode;
  /// Razorpay Recurring Payments mode only: the Razorpay Customer id
  /// (cust_xxx) the order/token was registered against. Must be passed to
  /// Checkout alongside order_id + recurring:'1' — Razorpay support
  /// identified omitting this as a likely cause of "Token absent for
  /// recurring payment". Empty for Subscriptions mode and Cashfree.
  final String? customerId;
  /// The instrument actually registered: 'upi' | 'card' | 'emandate'
  /// (older mandates may still echo the legacy 'netbanking' value — treat
  /// both as the same thing for display purposes).
  /// Echoed back by the backend (see shared/services/sip.py create_scheme's
  /// return dict) for display/logging only — it does NOT change how
  /// Checkout is launched (see sip_payment_screen.dart's
  /// _launchRazorpayAutoPay: the order's own 'method' field already
  /// determines what Checkout presents). Defaults to 'upi' to match the
  /// backend's own default for pre-existing/older responses.
  final String paymentMethod;

  SipCreateResponse({
    required this.success,
    required this.message,
    this.errorCode,
    this.subscriptionId,
    this.status,
    this.orderId,
    this.sessionId,
    this.environment,
    this.authorizationLink,
    this.paymentGateway = 'cashfree',
    this.keyId,
    this.mode = 'subscriptions',
    this.customerId,
    this.paymentMethod = 'upi',
  });

  factory SipCreateResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final error = json['error'] as Map<String, dynamic>? ?? {};

    // Message can be at top-level, inside 'error', or inside 'data'
    final message = json['message']?.toString() ??
        error['message']?.toString() ??
        data['message']?.toString() ??
        '';

    return SipCreateResponse(
      success: json['success'] == true,
      message: message,
      errorCode: error['code']?.toString() ?? data['code']?.toString(),
      subscriptionId: data['subscription_id']?.toString(),
      status: data['status']?.toString(),
      orderId: data['order_id']?.toString(),
      sessionId: data['session_id']?.toString(),
      environment: data['environment']?.toString(),
      authorizationLink: data['authorization_link']?.toString(),
      paymentGateway:
          data['payment_gateway']?.toString().toLowerCase() ?? 'cashfree',
      keyId: data['key_id']?.toString(),
      mode: data['mode']?.toString().toLowerCase() ?? 'subscriptions',
      customerId: data['customer_id']?.toString(),
      paymentMethod: data['payment_method']?.toString().toLowerCase() ?? 'upi',
    );
  }
}

// ─── SIP Plan Detail ────────────────────────────────────────────────────────

class SipPlanDetail {
  final String subscriptionId;
  final String startDate;
  final String frequency;
  final int frequencyId;
  final double amount;
  final String status;
  final String commodityName;
  final int commodityId;
  final String? day;
  final int? date;

  SipPlanDetail({
    required this.subscriptionId,
    required this.startDate,
    required this.frequency,
    required this.frequencyId,
    required this.amount,
    required this.status,
    required this.commodityName,
    required this.commodityId,
    this.day,
    this.date,
  });

  factory SipPlanDetail.fromJson(Map<String, dynamic> json) {
    return SipPlanDetail(
      subscriptionId: json['subscription_id']?.toString() ?? '',
      startDate: json['start_date']?.toString() ?? '',
      frequency: json['frequency']?.toString() ?? '',
      frequencyId:
          int.tryParse(json['frequency_id']?.toString() ?? '0') ?? 0,
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status']?.toString() ?? '',
      commodityName: json['commodity_name']?.toString() ?? '',
      commodityId:
          int.tryParse(json['commodity_id']?.toString() ?? '0') ?? 0,
      day: json['day']?.toString(),
      date: int.tryParse(json['date']?.toString() ?? ''),
    );
  }

  bool get isActive =>
      status.toUpperCase() == 'ACTIVE';

  bool get isPaused =>
      status.toUpperCase() == 'PAUSED';

  bool get isPendingAuth =>
      status.toUpperCase() == 'PENDING_AUTH' ||
      status.toUpperCase() == 'BANK_APPROVAL_PENDING';

  /// Whether this plan is occupying a frequency slot (blocks new creation).
  /// Only ACTIVE and PAUSED plans block — PENDING_AUTH means incomplete mandate.
  bool get isOccupying => isActive || isPaused;
}

// ─── SIP Manage Details Response ────────────────────────────────────────────

class SipManageDetails {
  final String subscriptionId;
  final String startDate;
  final double amount;
  final String status;
  final String frequency;
  final String commodityName;
  final String? day;
  final int? date;
  /// When this SIP becomes eligible for cancellation (creation + 24h),
  /// computed server-side so the client never has to re-derive the rule.
  /// Null if the creation timestamp wasn't available.
  final DateTime? cancelEligibleAt;
  /// Server's authoritative answer to "can this be cancelled right now".
  /// Defaults to true when unknown, so an outdated app build fails open
  /// (server-side cancel still enforces the real rule either way).
  final bool canCancelNow;

  SipManageDetails({
    required this.subscriptionId,
    required this.startDate,
    required this.amount,
    required this.status,
    required this.frequency,
    required this.commodityName,
    this.day,
    this.date,
    this.cancelEligibleAt,
    this.canCancelNow = true,
  });

  factory SipManageDetails.fromJson(Map<String, dynamic> json) {
    return SipManageDetails(
      subscriptionId: json['subscription_id']?.toString() ?? '',
      startDate: json['start_date']?.toString() ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      status: json['status']?.toString() ?? '',
      frequency: json['frequency']?.toString() ?? '',
      commodityName: json['commodity_name']?.toString() ?? '',
      day: json['day']?.toString(),
      date: int.tryParse(json['date']?.toString() ?? ''),
      cancelEligibleAt: DateTime.tryParse(
              json['cancel_eligible_at']?.toString() ?? '')
          ?.toLocal(),
      canCancelNow: json['can_cancel_now'] == null
          ? true
          : json['can_cancel_now'] == true,
    );
  }
}

// ─── Cancel Reason ──────────────────────────────────────────────────────────

class CancelReason {
  final String label;
  final String value;

  const CancelReason({required this.label, required this.value});
}

/// Pre-defined cancel reasons as specified.
const List<CancelReason> sipCancelReasons = [
  CancelReason(label: 'No money', value: 'No money'),
  CancelReason(label: 'Change frequency', value: 'Change frequency'),
  CancelReason(label: 'Other saving method', value: 'Other saving method'),
  CancelReason(label: 'Goal achieved', value: 'Goal achieved'),
];

// ─── Custom SIP Scheme Summary ──────────────────────────────────────────────

/// Lightweight summary of one non-terminal Custom SIP scheme — enough for
/// the date picker to mark which day-of-month values are already committed
/// to a scheme (tap -> manage) vs free to select for a new one (tap ->
/// multi-select -> create). Mirrors CustomSIPService.list_schemes()'s
/// return shape (shared/services/custom_sip.py).
class CustomSipScheme {
  final int schemeId;
  final String label;
  final double amount;
  final List<int> customDates;
  final int? commodityId;
  /// 'ACTIVE' | 'PAUSED' | 'PENDING_AUTH' | 'MANDATE_EXPIRED_PAUSED'
  /// (terminal statuses are excluded server-side — see
  /// CustomSIPSchemeRepository.get_non_terminal_schemes_for_customer).
  final String status;

  CustomSipScheme({
    required this.schemeId,
    required this.label,
    required this.amount,
    required this.customDates,
    this.commodityId,
    required this.status,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isPaused => status == 'PAUSED';

  /// Whether this scheme is occupying its custom_dates (blocks new
  /// creation on those dates). Only ACTIVE and PAUSED block — PENDING_AUTH
  /// means an incomplete mandate, same convention as regular SIP's
  /// SipPlanDetail.isOccupying (sip_models.dart) — a customer with a
  /// stuck/incomplete mandate can retry on the same dates instead of
  /// being locked out with no visible way to reclaim them.
  bool get isOccupying => isActive || isPaused;

  factory CustomSipScheme.fromJson(Map<String, dynamic> json) {
    final List rawDates = json['custom_dates'] ?? [];
    return CustomSipScheme(
      schemeId: int.tryParse(json['scheme_id']?.toString() ?? '0') ?? 0,
      label: json['label']?.toString() ?? 'Custom AutoGold',
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
      customDates: rawDates.map((d) => int.tryParse(d.toString()) ?? 0).toList(),
      commodityId: int.tryParse(json['commodity_id']?.toString() ?? ''),
      status: json['status']?.toString().toUpperCase() ?? 'ACTIVE',
    );
  }
}

// ─── Custom SIP Scheme Detail (full manage screen) ──────────────────────────

/// Full detail for one Custom SIP scheme's manage screen — mirrors
/// CustomSIPService.get_scheme_status()'s return dict (shared/services/
/// custom_sip.py), same fields SipManageDetails carries for regular SIP.
class CustomSipSchemeDetail {
  final int schemeId;
  final String label;
  final String subscriptionId;
  final String? startDate;
  final double amount;
  final List<int> customDates;
  final String commodityName;
  final String status;
  final DateTime? cancelEligibleAt;
  final bool canCancelNow;

  CustomSipSchemeDetail({
    required this.schemeId,
    required this.label,
    required this.subscriptionId,
    this.startDate,
    required this.amount,
    required this.customDates,
    required this.commodityName,
    required this.status,
    this.cancelEligibleAt,
    this.canCancelNow = true,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isPaused => status == 'PAUSED';

  factory CustomSipSchemeDetail.fromJson(Map<String, dynamic> json) {
    final List rawDates = json['custom_dates'] ?? [];
    return CustomSipSchemeDetail(
      schemeId: int.tryParse(json['scheme_id']?.toString() ?? '0') ?? 0,
      label: json['label']?.toString() ?? 'Custom AutoGold',
      subscriptionId: json['subscription_id']?.toString() ?? '',
      startDate: json['start_date']?.toString(),
      amount: double.tryParse(json['amount']?.toString() ?? '0') ?? 0,
      customDates: rawDates.map((d) => int.tryParse(d.toString()) ?? 0).toList(),
      commodityName: json['commodity_name']?.toString() ?? '',
      status: json['status']?.toString().toUpperCase() ?? 'ACTIVE',
      cancelEligibleAt: DateTime.tryParse(
              json['cancel_eligible_at']?.toString() ?? '')
          ?.toLocal(),
      canCancelNow: json['can_cancel_now'] == null
          ? true
          : json['can_cancel_now'] == true,
    );
  }
}
