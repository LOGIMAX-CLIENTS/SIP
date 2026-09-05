// lib/features/instant_saving/payment_handler.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PaymentHandler — Centralized Payment Orchestrator (Cashfree + HDFC)
//
// This class is the SINGLE source of truth for all payment logic.
// It supports two gateways:
//   • Cashfree — via flutter_cashfree_pg_sdk (Web Checkout)
//   • HDFC SmartGateway — via Juspay HyperSDK (delegated to HdfcPaymentHandler)
//
// The backend decides which gateway to use and returns `payment_gateway`
// in the savings/initiate response ("cashfree" or "hdfc").
//
// Responsibilities:
//   1. Call savings/initiate API to create a server-side order
//   2. Route to Cashfree or HDFC based on payment_gateway field
//   3. Handle callbacks → call savings/confirm-payment
//   4. Navigate to PurchaseSuccessScreen with the correct result data
//
// Usage (from InvestScreen OR after KYC completes):
//
//   final handler = PaymentHandler(ref: ref, context: context);
//   await handler.startPayment(
//     amount:   totalPayable,
//     metalId:  metalId,
//     rate:     rate,
//     buyType:  1,       // 1 = AMOUNT, 2 = GRAMS
//     weight:   grams,
//   );
//
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/error/failures.dart';
import '../../core/providers/timer_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/security/app_lifecycle_observer.dart';
import '../../core/security/secure_logger.dart';
import '../../shared/widgets/app_toast.dart';
import 'controller/saving_controller.dart';
import 'hdfc_payment_handler.dart';
import 'razorpay_payment_handler.dart';
import 'models/saving_models.dart';
import 'screens/purchase_success_screen.dart';

class PaymentHandler {
  final WidgetRef ref;
  final BuildContext context;

  // Cashfree SDK gateway service — single instance per handler.
  final CFPaymentGatewayService _cfPaymentGatewayService =
      CFPaymentGatewayService();

  // Stores the server-confirmed amount_inr after savings/initiate succeeds.
  // Used in the success/failure screen when savings/confirm-payment
  // doesn't return the amount.
  double _confirmedAmountInr = 0;

  // Callbacks passed by the caller to toggle loading state on the parent widget.
  VoidCallback? _onLoadingStart;
  VoidCallback? _onLoadingEnd;

  PaymentHandler({required this.ref, required this.context});

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Entry point. Call this from InvestScreen (direct PAYMENT path) or
  /// from InvestScreen after KYC returns `true`.
  ///
  /// [onLoadingStart] / [onLoadingEnd] — optional callbacks so the caller can
  /// show/hide its own loading indicator while payment is in-flight.
  Future<void> startPayment({
    required double amount,
    required String metalId,
    required double rate,
    required int buyType, // 1 = AMOUNT, 2 = GRAMS
    required double weight,
    String? couponCode,
    String? paymentMethod, // "upi" → HDFC, "card"/"netbanking" → Cashfree
    VoidCallback? onLoadingStart,
    VoidCallback? onLoadingEnd,
  }) async {
    _onLoadingStart = onLoadingStart;
    _onLoadingEnd = onLoadingEnd;

    // Register Cashfree callbacks BEFORE initiating the order so the SDK is
    // ready to receive callbacks as soon as doPayment() is called.
    _cfPaymentGatewayService.setCallback(_onCashfreeSuccess, _onCashfreeError);

    _onLoadingStart?.call();

    // Suppress app lock during payment — user may leave the app
    // (e.g. UPI Intent opens GPay/PhonePe) and we must NOT trigger
    // MPIN/session-check on resume before confirm-payment runs.
    AppLifecycleObserver.suppressAppLock = true;

    try {
      await _initiatePurchase(
        amount: amount,
        metalId: metalId,
        rate: rate,
        buyType: buyType,
        weight: weight,
        couponCode: couponCode,
        paymentMethod: paymentMethod,
      );
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      _onLoadingEnd?.call();
      if (context.mounted) {
        final message = (e is Failure)
            ? e.message
            : 'Payment initiation failed. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 — savings/initiate
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initiatePurchase({
    required double amount,
    required String metalId,
    required double rate,
    required int buyType,
    required double weight,
    String? couponCode,
    String? paymentMethod,
  }) async {
    final user = ref.read(userProvider);
    if (user == null) throw Exception('User not logged in');

    // Use the timer-locked rate if available; otherwise fall back to the
    // rate that was passed in (already validated before calling startPayment).
    final timerState = ref.read(sellRateTimerProvider);
    final activeRate = timerState.isActive
        ? (metalId == '1'
            ? timerState.lockedRates!.goldSell
            : timerState.lockedRates!.silverSell)
        : rate;

    // ── Weight calculation ─────────────────────────────────────────────────
    // buyType 1 (AMOUNT): weight is derived from amount / rate (net of GST).
    // buyType 2 (GRAMS) : weight is exactly what the customer requested.
    final double weightForApi;
    if (buyType == 2) {
      weightForApi = double.parse(weight.toStringAsFixed(4));
    } else {
      final config = ref.read(savingConfigProvider).valueOrNull;
      final gstRate = (config?.gst ?? 3.0) / 100;
      final raw = (amount / (1 + gstRate)) / activeRate;
      weightForApi = double.parse(raw.toStringAsFixed(4));
    }

    SecureLogger.d(
        '[PaymentHandler] savings/initiate → buyType=$buyType | weight=$weightForApi | paymentMethod=$paymentMethod');

    final PurchaseInitiateResponse purchase =
        await ref.read(savingServiceProvider).initiatePurchase(
              customerId: user.id,
              metalId: metalId,
              mobile: user.mobile,
              buyType: buyType,
              amount: amount,
              rate: activeRate,
              weight: weightForApi,
              couponCode: couponCode,
              paymentMethod: paymentMethod,
            );

    // Use the server-confirmed amount_inr (authoritative for the gateway).
    // For GRAMS mode this may differ from [amount] when the rate has moved.
    final confirmedAmount =
        (purchase.amountInr != null && purchase.amountInr!.isNotEmpty)
            ? double.tryParse(purchase.amountInr!) ?? amount
            : amount;

    _confirmedAmountInr = confirmedAmount;

    SecureLogger.d(
        '[PaymentHandler] initiate OK → orderId=${purchase.orderId}, gateway=${purchase.paymentGateway}');

    // ── STEP 2: Route to the correct payment gateway ────────────────────────
    if (context.mounted) {
      // Trust the gateway returned by the backend initiate API first because it matches
      // the order's specific payment provider and payload (e.g. sdkPayload or sessionId).
      // Fall back to config-resolved gateway only if the API returned gateway is empty or unrecognized.
      String gateway = purchase.paymentGateway;
      if (gateway.isEmpty || (gateway != 'hdfc' && gateway != 'cashfree' && gateway != 'razorpay')) {
        final config = ref.read(savingConfigProvider).valueOrNull;
        if (paymentMethod != null && config != null && config.paymentMethods.containsKey(paymentMethod)) {
          gateway = config.paymentMethods[paymentMethod]!;
          SecureLogger.d('[PaymentHandler] Gateway resolved from config fallback: $paymentMethod -> $gateway');
        }
      }

      if (gateway == 'hdfc') {
        _launchHdfc(purchase, confirmedAmount, paymentMethod);
      } else if (gateway == 'razorpay') {
        _launchRazorpay(purchase, confirmedAmount, paymentMethod);
      } else {
        _launchCashfree(purchase);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2a — Launch HDFC SmartGateway (Juspay HyperSDK)
  // ─────────────────────────────────────────────────────────────────────────

  void _launchHdfc(PurchaseInitiateResponse purchase, double confirmedAmount, String? paymentMethod) {
    SecureLogger.d('[PaymentHandler] Routing to HDFC gateway...');

    final hdfc = HdfcPaymentHandler(ref: ref, context: context);
    hdfc.launchPayment(
      purchase: purchase,
      confirmedAmountInr: confirmedAmount,
      paymentMethod: paymentMethod,
      onLoadingStart: _onLoadingStart,
      onLoadingEnd: _onLoadingEnd,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2b — Launch Razorpay Checkout
  // ─────────────────────────────────────────────────────────────────────────

  void _launchRazorpay(PurchaseInitiateResponse purchase, double confirmedAmount, String? paymentMethod) {
    SecureLogger.d('[PaymentHandler] Routing to Razorpay gateway...');

    final razorpay = RazorpayPaymentHandler(ref: ref, context: context);
    razorpay.launchPayment(
      purchase: purchase,
      confirmedAmountInr: confirmedAmount,
      paymentMethod: paymentMethod,
      onLoadingStart: _onLoadingStart,
      onLoadingEnd: _onLoadingEnd,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2b — Launch Cashfree Web Checkout
  // ─────────────────────────────────────────────────────────────────────────

  void _launchCashfree(PurchaseInitiateResponse purchase) {
    if (purchase.orderId == null || purchase.sessionId == null) {
      _onLoadingEnd?.call();
      if (context.mounted) {
        AppToast.show(
            context, 'Failed to initiate payment session. Please try again.',
            type: ToastType.error);
      }
      return;
    }

    try {
      final env = purchase.environment?.toUpperCase() == 'PRODUCTION'
          ? CFEnvironment.PRODUCTION
          : CFEnvironment.SANDBOX;

      final session = CFSessionBuilder()
          .setEnvironment(env)
          .setOrderId(purchase.orderId!)
          .setPaymentSessionId(purchase.sessionId!)
          .build();

      final cfWebCheckoutPayment =
          CFWebCheckoutPaymentBuilder().setSession(session).build();

      SecureLogger.d('[PaymentHandler] Launching Cashfree SDK...');
      _cfPaymentGatewayService.doPayment(cfWebCheckoutPayment);

      // Loading stays active — it is cleared inside the Cashfree callbacks.
    } catch (e) {
      _onLoadingEnd?.call();
      if (context.mounted) {
        final message = (e is Failure)
            ? e.message
            : 'Payment gateway error. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3a — Cashfree SUCCESS callback
  // ─────────────────────────────────────────────────────────────────────────

  void _onCashfreeSuccess(String orderId) async {
    SecureLogger.d('[PaymentHandler] Cashfree SUCCESS → orderId=$orderId');
    AppLifecycleObserver.suppressAppLock = false;
    await _confirmAndNavigate(orderId);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3b — Cashfree FAILURE callback
  // ─────────────────────────────────────────────────────────────────────────

  void _onCashfreeError(CFErrorResponse errorResponse, String orderId) async {
    SecureLogger.e(
        '[PaymentHandler] Cashfree ERROR → orderId=$orderId | ${errorResponse.getMessage()}');
    AppLifecycleObserver.suppressAppLock = false;

    // Always notify the server even on failure so it can update order status.
    final fallbackMsg =
        'Payment failed for order $orderId.\n${errorResponse.getMessage()}';
    await _confirmAndNavigate(orderId,
        wasError: true, fallbackErrorMsg: fallbackMsg);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 — savings/confirm-payment → navigate to result screen
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmAndNavigate(
    String orderId, {
    bool wasError = false,
    String? fallbackErrorMsg,
  }) async {
    Map<String, dynamic>? response;

    try {
      response =
          await ref.read(savingServiceProvider).confirmPayment(orderId);
      SecureLogger.d('[PaymentHandler] confirm-payment response received');
    } catch (e) {
      // Server error during confirm — still navigate to result screen.
      SecureLogger.e('[PaymentHandler] confirm-payment threw: $e');
    }

    _onLoadingEnd?.call();

    // The authoritative result just arrived. If the app was backgrounded
    // during checkout (Cashfree's webview, a UPI app switch, etc.) and this
    // confirm-payment round trip took longer than InstantSavingScreen's
    // 2-second "resumed but still waiting" fallback, that fallback may have
    // already fired a "could not confirm your payment status" toast — a
    // guess made before this real answer was known. That toast lives on
    // the root overlay (see AppToast.show), so it survives the navigation
    // below for the rest of its own lifetime unless explicitly cleared
    // here, producing a contradictory success-screen-with-failure-warning.
    // Now that we know the real outcome, drop the stale guess before
    // showing it. Mirrors razorpay_payment_handler's/hdfc_payment_handler's
    // identical fix.
    AppToast.dismiss();

    if (!context.mounted) return;

    final bool isSuccess =
        !wasError && (response?['success'] == true);

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
      // Prefer server message; fall back to Cashfree error message.
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
