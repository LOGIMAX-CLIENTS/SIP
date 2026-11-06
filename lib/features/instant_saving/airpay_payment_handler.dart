// lib/features/instant_saving/airpay_payment_handler.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// AirpayPaymentHandler — Airpay (hosted payment page) Orchestrator
//
// Airpay has no Flutter SDK here: the backend returns `checkout_url`, a page
// on the secure server that POSTs the signed order to Airpay. This handler
// shows it in AirpayCheckoutWebView and, once the WebView closes (Airpay's
// return, or the customer backing out), asks savings/confirm-payment — the
// backend checks with Airpay itself, as for every other gateway.
//
// Flow:
//   1. Caller provides the PurchaseInitiateResponse (savings/initiate
//      returned payment_gateway == "airpay" with checkout_url + return_url)
//   2. Push AirpayCheckoutWebView(checkoutUrl, returnUrl)
//   3. WebView pops → savings/confirm-payment → result screen
//
// Airpay also notifies the backend directly (IPN), which can complete the
// order before the app asks. confirm-payment then answers "already
// confirmed" with no receipt, so the success screen falls back to the
// amounts from savings/initiate.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/security/app_lifecycle_observer.dart';
import '../../core/security/secure_logger.dart';
import '../../shared/widgets/app_toast.dart';
import 'controller/saving_controller.dart';
import 'models/saving_models.dart';
import 'screens/airpay_checkout_webview.dart';
import 'screens/purchase_success_screen.dart';

class AirpayPaymentHandler {
  final WidgetRef ref;
  final BuildContext context;

  AirpayPaymentHandler({required this.ref, required this.context});

  /// True when savings/initiate chose Airpay.
  static bool handles(PurchaseInitiateResponse purchase) =>
      purchase.paymentGateway.contains('airpay') ||
      (purchase.checkoutUrl != null && purchase.checkoutUrl!.isNotEmpty);

  Future<void> launchPayment({
    required PurchaseInitiateResponse purchase,
    required double confirmedAmountInr,
    String? paymentMethod,
    VoidCallback? onLoadingStart,
    VoidCallback? onLoadingEnd,
  }) async {
    final orderId = purchase.orderId ?? '';
    final checkoutUrl = purchase.checkoutUrl ?? '';
    final returnUrl = purchase.returnUrl ?? '';

    if (orderId.isEmpty || checkoutUrl.isEmpty || returnUrl.isEmpty) {
      SecureLogger.e('[AirpayPaymentHandler] initiate response is missing order_id/checkout_url/return_url');
      onLoadingEnd?.call();
      if (context.mounted) {
        AppToast.show(context, 'Failed to initiate payment session. Please try again.',
            type: ToastType.error);
      }
      return;
    }

    onLoadingStart?.call();
    // The customer may switch to a UPI app mid-payment; don't lock the app
    // on resume, or confirm-payment would run without a session.
    AppLifecycleObserver.suppressAppLock = true;

    SecureLogger.d('[AirpayPaymentHandler] Opening Airpay checkout for $orderId (method=$paymentMethod)');
    final reachedReturn = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AirpayCheckoutWebView(checkoutUrl: checkoutUrl, returnUrl: returnUrl),
      ),
    );
    SecureLogger.d('[AirpayPaymentHandler] WebView closed (reachedReturn=$reachedReturn)');

    await _confirmAndNavigate(purchase, confirmedAmountInr, onLoadingEnd);
  }

  Future<void> _confirmAndNavigate(
    PurchaseInitiateResponse purchase,
    double confirmedAmountInr,
    VoidCallback? onLoadingEnd,
  ) async {
    final orderId = purchase.orderId ?? '';
    Map<String, dynamic>? response;

    AppLifecycleObserver.suppressAppLock = false;
    try {
      response = await ref.read(savingServiceProvider).confirmPayment(orderId);
      SecureLogger.d('[AirpayPaymentHandler] confirm-payment response received');
    } catch (e) {
      SecureLogger.e('[AirpayPaymentHandler] confirm-payment threw: $e');
    }

    onLoadingEnd?.call();
    // Drop any "could not confirm" toast a resume-timeout guessed earlier
    // (see RazorpayPaymentHandler for the race).
    AppToast.dismiss();
    if (!context.mounted) return;

    if (response?['success'] == true) {
      final data = response?['data'] is Map ? response!['data'] as Map : const {};
      // An IPN-completed order comes back with no receipt — use what
      // savings/initiate already told us about this purchase.
      final hasReceipt = data.isNotEmpty;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseSuccessScreen(
            data: {
              'isSuccess': true,
              'orderId': data['order_id'] ?? orderId,
              'weight': data['grams_credited'] ??
                  data['credited_weight'] ??
                  data['weight'] ??
                  purchase.weight,
              'message': hasReceipt
                  ? (response?['message'] ?? 'Gold has been successfully added to your locker.')
                  : 'Your payment is successful and has been added to your locker.',
              'commodity_name': data['commodity_name'],
              'total_amount': data['total_amount'] ??
                  (confirmedAmountInr > 0 ? confirmedAmountInr : 0),
              'rate': data['rate'] ?? purchase.ratePerGram,
              'payment_mode': data['payment_mode'],
            },
          ),
        ),
      );
    } else {
      final errorMsg = response?['message'] ??
          response?['error']?['message'] ??
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
