// lib/features/instant_saving/razorpay_payment_handler.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// RazorpayPaymentHandler — Razorpay Payment Gateway Orchestrator
//
// Mirrors HdfcPaymentHandler but uses razorpay_flutter SDK for checkout.
// Only used for Instant Savings (one-time gold/silver purchases).
//
// Flow:
//   1. Caller provides the PurchaseInitiateResponse (already obtained via
//      savings/initiate API which returned payment_gateway == "razorpay")
//   2. Register success, error, and external wallet callbacks
//   3. Launch payment page with key_id, rz_order_id, amount, and contact prefill
//   4. Handle Razorpay SDK callbacks
//   5. On completion → call savings/confirm-payment → navigate to result screen
//
// Usage (from PaymentHandler._launchRazorpay()):
//
//   final razorpay = RazorpayPaymentHandler(ref: ref, context: context);
//   await razorpay.launchPayment(
//     purchase: purchaseResponse,
//     confirmedAmountInr: confirmedAmount,
//     onLoadingStart: () => ...,
//     onLoadingEnd: () => ...,
//   );
//
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../core/error/failures.dart';
import '../../core/providers/user_provider.dart';
import '../../core/security/app_lifecycle_observer.dart';
import '../../core/security/secure_logger.dart';
import '../../shared/widgets/app_toast.dart';
import 'controller/saving_controller.dart';
import 'models/saving_models.dart';
import 'screens/purchase_success_screen.dart';

class RazorpayPaymentHandler {
  final WidgetRef ref;
  final BuildContext context;

  /// Razorpay SDK instance.
  final Razorpay _razorpay = Razorpay();

  /// Server-confirmed amount (used in success/failure screen).
  double _confirmedAmountInr = 0;

  /// Callbacks to toggle loading state on the caller widget.
  VoidCallback? _onLoadingStart;
  VoidCallback? _onLoadingEnd;

  /// Internal order ID from the initiate response.
  String? _internalOrderId;

  RazorpayPaymentHandler({required this.ref, required this.context}) {
    // Register event listeners
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _handlePaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _handlePaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _handleExternalWallet);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Launch Razorpay payment using data from savings/initiate response.
  ///
  /// [paymentMethod] — "upi" | "card" | "netbanking", the instrument the user
  /// picked on the app's own PaymentMethodSheet. When set, Checkout's `method`
  /// restriction is applied so it skips the method-picker tab bar and opens
  /// that instrument's screen directly (Razorpay Standard Checkout behavior:
  /// https://razorpay.com/docs/payment-gateway/integrations-guide/checkout/standard/#checkout-form).
  Future<void> launchPayment({
    required PurchaseInitiateResponse purchase,
    required double confirmedAmountInr,
    String? paymentMethod,
    VoidCallback? onLoadingStart,
    VoidCallback? onLoadingEnd,
  }) async {
    _onLoadingStart = onLoadingStart;
    _onLoadingEnd = onLoadingEnd;
    _confirmedAmountInr = confirmedAmountInr;
    _internalOrderId = purchase.orderId;

    _onLoadingStart?.call();

    // Suppress app lock during payment — the user may leave the app
    // (e.g. to open UPI app like Google Pay, PhonePe) and we must NOT trigger
    // MPIN/session-check on resume.
    AppLifecycleObserver.suppressAppLock = true;

    try {
      final keyId = purchase.keyId;
      final rzOrderId = purchase.rzOrderId ?? purchase.sessionId;

      if (keyId == null || keyId.isEmpty) {
        throw Exception('Razorpay Key ID is missing from server response.');
      }
      if (rzOrderId == null || rzOrderId.isEmpty) {
        throw Exception('Razorpay Order ID is missing from server response.');
      }

      final user = ref.read(userProvider);
      final checkoutConfig = _singleMethodConfig(paymentMethod);

      final options = {
        'key': keyId,
        'amount': (confirmedAmountInr * 100).toInt(), // Razorpay expects amount in paise
        'name': 'startGOLD',
        'description': 'Purchase of Gold/Silver',
        'order_id': rzOrderId,
        'prefill': {
          'contact': user?.mobile ?? '',
          'email': user?.email ?? '',
        },
        if (checkoutConfig != null) 'config': checkoutConfig,
      };

      SecureLogger.d(
          '[RazorpayPaymentHandler] Opening Razorpay checkout... method=$paymentMethod');
      _razorpay.open(options);
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      _onLoadingEnd?.call();
      _razorpay.clear();
      if (context.mounted) {
        final message = (e is Failure)
            ? e.message
            : 'Razorpay payment initiation failed. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  /// Builds a Razorpay Checkout `config.display` block that shows ONLY the
  /// given instrument and fully suppresses the method-picker / "All Payment
  /// Options" screen. This is Razorpay's current documented mechanism for
  /// single-method checkout (the older flat `method: {card:'1', upi:'0'}`
  /// restriction is not part of current docs and was found empirically to
  /// only partially work — it left "More Options" reachable on UPI and did
  /// not restrict Card at all):
  /// https://razorpay.com/docs/payments/payment-gateway/web-integration/standard/configure-payment-methods/sample-code/
  ///
  /// `preferences.show_default_blocks: false` is the key that removes every
  /// other instrument/category from the screen — without it Checkout shows
  /// the configured block ALONGSIDE the full default list.
  static Map<String, dynamic>? _singleMethodConfig(String? method) {
    const labels = {
      'upi': 'Pay via UPI',
      'card': 'Pay via Card',
      'netbanking': 'Pay via Netbanking',
    };
    final label = labels[method];
    if (label == null) return null;
    return {
      'display': {
        'blocks': {
          'selected': {
            'name': label,
            'instruments': [
              {'method': method}
            ],
          },
        },
        'sequence': ['block.selected'],
        'preferences': {'show_default_blocks': false},
      },
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // EVENT HANDLERS
  // ─────────────────────────────────────────────────────────────────────────

  void _handlePaymentSuccess(PaymentSuccessResponse response) {
    SecureLogger.d('[RazorpayPaymentHandler] Payment Success: paymentId=${response.paymentId}');
    _confirmAndNavigate(
      _internalOrderId ?? '',
      rzPaymentId: response.paymentId,
      rzSignature: response.signature,
      rzOrderId: response.orderId,
    );
    _razorpay.clear();
  }

  void _handlePaymentError(PaymentFailureResponse response) {
    SecureLogger.e(
        '[RazorpayPaymentHandler] Payment Error: code=${response.code} | message=${response.message}');
    
    // Always notify the server or navigate to failure screen
    _confirmAndNavigate(
      _internalOrderId ?? '',
      fallbackErrorMsg: response.message ?? 'Payment failed.',
    );
    _razorpay.clear();
  }

  void _handleExternalWallet(ExternalWalletResponse response) {
    SecureLogger.d('[RazorpayPaymentHandler] External Wallet: ${response.walletName}');
    _onLoadingEnd?.call();
    _razorpay.clear();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 — savings/confirm-payment → navigate to result screen
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmAndNavigate(
    String orderId, {
    String? rzPaymentId,
    String? rzSignature,
    String? rzOrderId,
    String? fallbackErrorMsg,
  }) async {
    Map<String, dynamic>? response;

    // Re-enable app lock now that the payment SDK flow is complete.
    AppLifecycleObserver.suppressAppLock = false;

    try {
      response = await ref.read(savingServiceProvider).confirmPayment(
            orderId,
            razorpayPaymentId: rzPaymentId,
            razorpaySignature: rzSignature,
            razorpayOrderId: rzOrderId,
          );
      SecureLogger.d('[RazorpayPaymentHandler] confirm-payment response received');
    } catch (e) {
      SecureLogger.e('[RazorpayPaymentHandler] confirm-payment threw: $e');
    }

    _onLoadingEnd?.call();

    if (!context.mounted) return;

    final bool isSuccess = response?['success'] == true;

    if (isSuccess) {
      // ── SUCCESS ─────────────────────────────────────────────────────────
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseSuccessScreen(
            data: {
              'isSuccess': true,
              'orderId': response?['data']?['order_id'] ?? orderId,
              'weight': response?['data']?['grams_credited'] ??
                  response?['data']?['credited_weight'] ??
                  response?['data']?['weight'],
              'message': response?['message'] ??
                  'Gold has been successfully added to your locker.',
              'commodity_name': response?['data']?['commodity_name'],
              'total_amount': response?['data']?['total_amount'] ??
                  (_confirmedAmountInr > 0 ? _confirmedAmountInr : 0),
              'rate': response?['data']?['rate'],
              'payment_mode': response?['data']?['payment_mode'],
            },
          ),
        ),
      );
    } else {
      // ── FAILURE ─────────────────────────────────────────────────────────
      final errorMsg = response?['message'] ??
          response?['error']?['message'] ??
          fallbackErrorMsg ??
          'Your order could not be processed. Please try again.';

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseSuccessScreen(
            data: {
              'isSuccess': false,
              'orderId': orderId,
              'message': errorMsg,
            },
          ),
        ),
      );
    }
  }
}
