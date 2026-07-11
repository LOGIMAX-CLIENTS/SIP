// lib/features/instant_saving/hdfc_payment_handler.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// HdfcPaymentHandler — HDFC SmartGateway (Juspay HyperSDK) Payment Orchestrator
//
// Mirrors PaymentHandler (Cashfree) but uses Juspay's HyperSDK for checkout.
// Only used for Instant Savings (one-time gold/silver purchases).
//
// Flow:
//   1. Caller provides the PurchaseInitiateResponse (already obtained via
//      savings/initiate API which returned payment_gateway == "hdfc")
//   2. Pre-warm HyperSDK with initiate() using merchant credentials
//   3. Launch payment page with sdkPayload from backend
//   4. Handle SDK callbacks (process_result, hide_loader, backpress)
//   5. On completion → call savings/confirm-payment → navigate to result screen
//
// Usage (from PaymentHandler._launchHdfc()):
//
//   final hdfc = HdfcPaymentHandler(ref: ref, context: context);
//   await hdfc.launchPayment(
//     purchase: purchaseResponse,
//     confirmedAmountInr: confirmedAmount,
//     onLoadingStart: () => ...,
//     onLoadingEnd: () => ...,
//   );
//
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hypersdkflutter/hypersdkflutter.dart';

import '../../core/error/failures.dart';
import '../../core/security/app_lifecycle_observer.dart';
import '../../core/security/secure_logger.dart';
import '../../shared/widgets/app_toast.dart';
import 'controller/saving_controller.dart';
import 'models/saving_models.dart';
import 'screens/purchase_success_screen.dart';

class HdfcPaymentHandler {
  final WidgetRef ref;
  final BuildContext context;

  /// Juspay HyperSDK instance — single instance per handler.
  final HyperSDK _hyperSDK = HyperSDK();

  /// Server-confirmed amount (used in success/failure screen).
  double _confirmedAmountInr = 0;

  /// Callbacks to toggle loading state on the caller widget.
  VoidCallback? _onLoadingStart;
  VoidCallback? _onLoadingEnd;

  /// Whether HyperSDK has been initiated (pre-warmed).
  bool _isInitiated = false;

  HdfcPaymentHandler({required this.ref, required this.context});

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Launch HDFC payment using data from savings/initiate response.
  ///
  /// The [purchase] must have payment_gateway == "hdfc" with valid
  /// sdkPayload, merchantId, and clientId.
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

    _onLoadingStart?.call();

    // Suppress app lock during payment — the user may leave the app
    // (e.g. bank OTP page in browser) and we must NOT trigger MPIN/
    // session-check on resume, as that would invalidate the auth token
    // before confirm-payment can run.
    AppLifecycleObserver.suppressAppLock = true;

    try {
      // Validate required HDFC fields
      if (purchase.sdkPayload == null || purchase.sdkPayload!.isEmpty) {
        throw Exception('HDFC SDK payload is missing from server response.');
      }
      if (purchase.merchantId == null || purchase.merchantId!.isEmpty) {
        throw Exception('HDFC merchant ID is missing from server response.');
      }
      if (purchase.clientId == null || purchase.clientId!.isEmpty) {
        throw Exception('HDFC client ID is missing from server response.');
      }

      // Step 1: Initiate (pre-warm) HyperSDK if not already done
      if (!_isInitiated) {
        await _initiateHyperSDK(purchase);
      }

      // Step 2: Open payment page with backend's sdkPayload
      await _openPaymentPage(purchase, paymentMethod);
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      _onLoadingEnd?.call();
      if (context.mounted) {
        final message = (e is Failure)
            ? e.message
            : 'HDFC payment initiation failed. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 1 — Initiate (pre-warm) HyperSDK
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initiateHyperSDK(PurchaseInitiateResponse purchase) async {
    final initiatePayload = {
      'requestId': DateTime.now().millisecondsSinceEpoch.toString(),
      'service': 'in.juspay.hyperpay',
      'payload': {
        'action': 'initiate',
        'merchantId': purchase.merchantId!,
        'clientId': purchase.clientId!,
        'environment': purchase.hdfcEnvironment ?? 'production',
      },
    };

    SecureLogger.d('[HdfcPaymentHandler] Initiating HyperSDK...');

    await _hyperSDK.initiate(
      initiatePayload,
      _initiateCallbackHandler,
    );

    _isInitiated = true;
    SecureLogger.d('[HdfcPaymentHandler] HyperSDK initiated successfully.');
  }

  /// Callback for initiate — typically just logs; no user-facing action needed.
  void _initiateCallbackHandler(MethodCall methodCall) {
    SecureLogger.d(
        '[HdfcPaymentHandler] Initiate callback: ${methodCall.method}');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 2 — Open Payment Page
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _openPaymentPage(PurchaseInitiateResponse purchase, String? paymentMethod) async {
    SecureLogger.d(
        '[_openPaymentPage] Opening HDFC payment page for order ${purchase.orderId} with paymentMethod=$paymentMethod');
    SecureLogger.d(
        '[_openPaymentPage] sdkPayload keys: ${purchase.sdkPayload?.keys.toList()}');

    try {
      // Deep-copy the SDK payload so we don't mutate the original.
      final sdkPayload = Map<String, dynamic>.from(purchase.sdkPayload!);

      // Override returnUrl — the SDK's WebView opens this URL after payment.
      // We don't want it hitting our authenticated confirm-payment endpoint.
      // The REAL confirmation is done by the app via process_result callback
      // (with auth token), exactly like the Cashfree flow.
      if (sdkPayload['payload'] is Map) {
        final payload = Map<String, dynamic>.from(sdkPayload['payload']);
        payload['returnUrl'] = 'about:blank';
        
        // Dynamically configure payment restrictions based on SavingConfig.
        final config = ref.read(savingConfigProvider).valueOrNull;
        if (paymentMethod != null && config != null && config.paymentMethods[paymentMethod] == 'hdfc') {
          // Map to Juspay's paymentMethodType (case sensitive)
          String? juspayMethodType;
          if (paymentMethod == 'upi') {
            juspayMethodType = 'UPI';
          } else if (paymentMethod == 'card') {
            juspayMethodType = 'CARD';
          } else if (paymentMethod == 'netbanking') {
            juspayMethodType = 'NB';
          }

          if (juspayMethodType != null) {
            // Apply Juspay Payment Locking payload filter to restrict UI
            payload['payment_filter'] = {
              'allowDefaultOptions': false,
              'options': [
                {
                  'enable': true,
                  'paymentMethodType': juspayMethodType,
                }
              ]
            };
          }

          final juspayMethod = paymentMethod.toUpperCase();
          payload['paymentMethod'] = juspayMethod;
          payload['paymentMethodList'] = juspayMethod;
          SecureLogger.d('[HdfcPaymentHandler] Configured sdkPayload payload for $juspayMethod restriction based on config.');
        }

        sdkPayload['payload'] = payload;
        SecureLogger.d(
            '[HdfcPaymentHandler] returnUrl overridden to about:blank');
      }

      final result = await _hyperSDK.openPaymentPage(
        sdkPayload,
        _hyperSDKCallbackHandler,
      );
      SecureLogger.d('[HdfcPaymentHandler] openPaymentPage result: $result');

      // Loading stays active — cleared inside the callback handler.
    } catch (e, stack) {
      SecureLogger.e('[HdfcPaymentHandler] openPaymentPage error: $e');
      SecureLogger.e('[HdfcPaymentHandler] Stack: $stack');
      _onLoadingEnd?.call();
      if (context.mounted) {
        final message = (e is Failure)
            ? e.message
            : 'Failed to open HDFC payment page. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3 — HyperSDK Callback Handler
  // ─────────────────────────────────────────────────────────────────────────

  void _hyperSDKCallbackHandler(MethodCall methodCall) {
    SecureLogger.d(
        '[_hyperSDKCallbackHandler] SDK callback: ${methodCall.method}');

    switch (methodCall.method) {
      case 'hide_loader':
        // SDK has rendered its own UI — hide our loading indicator.
        _onLoadingEnd?.call();
        break;

      case 'process_result':
        _handleProcessResult(methodCall);
        break;

      case 'initiate_result':
        SecureLogger.d(
            '[HdfcPaymentHandler] initiate_result received (informational)');
        break;

      case 'microapp_versions':
        SecureLogger.d(
            '[HdfcPaymentHandler] microapp_versions received');
        break;

      default:
        SecureLogger.d(
            '[HdfcPaymentHandler] Unhandled SDK event: ${methodCall.method}');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 3a — Process Result (success / failure / user abort)
  // ─────────────────────────────────────────────────────────────────────────

  void _handleProcessResult(MethodCall methodCall) {
    _onLoadingEnd?.call();
    AppLifecycleObserver.suppressAppLock = false;

    try {
      final args = methodCall.arguments is String
          ? json.decode(methodCall.arguments)
          : methodCall.arguments;

      final payload = args['payload'] ?? {};
      final status = payload['status']?.toString() ?? '';
      final orderId = args['orderId']?.toString() ?? '';

      SecureLogger.d(
          '[HdfcPaymentStartHandler] process_result → status=$status, orderId=$orderId');

      switch (status) {
        case 'backpressed':
        case 'user_aborted':
          SecureLogger.d(
              '[HdfcPaymentHandler] User cancelled payment (status=$status)');
          AppLifecycleObserver.suppressAppLock = false;
          if (orderId.isEmpty) {
            if (context.mounted) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => PurchaseSuccessScreen(
                    data: {
                      'isSuccess': false,
                      'orderId': 'N/A',
                      'message': 'Sorry! Your order could not be processed. Please try again.',
                    },
                  ),
                ),
              );
            }
          } else {
            _confirmAndNavigate(orderId, sdkStatus: status);
          }
          break;

        default:

        SecureLogger.d(
          '[HdfcPaymentSuccessHandler] process_result → status=$status, orderId=$orderId');
          // Payment completed (success or failure) — verify with backend.
          // The SDK status may be "charged", "cod_initiated", etc. for success,
          // or "authentication_failed", "authorization_failed", etc. for failure.
          // Always call confirm-payment to let the backend verify server-to-server.
          _confirmAndNavigate(orderId, sdkStatus: status);
      }
    } catch (e) {
      SecureLogger.e('[HdfcPaymentHandler] Error parsing process_result: $e');
      if (context.mounted) {
        AppToast.show(
            context, 'Payment verification error. Please check your orders.',
            type: ToastType.error);
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STEP 4 — savings/confirm-payment → navigate to result screen
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _confirmAndNavigate(
    String orderId, {
    String? sdkStatus,
  }) async {
    Map<String, dynamic>? response;

    // Re-enable app lock now that the payment SDK flow is complete.
    AppLifecycleObserver.suppressAppLock = false;

    try {
      response =
          await ref.read(savingServiceProvider).confirmPayment(orderId);
      SecureLogger.d(
          '[HdfcPaymentHandler] confirm-payment response received');
    } catch (e) {
      SecureLogger.e('[HdfcPaymentHandler] confirm-payment threw: $e');
    }

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
