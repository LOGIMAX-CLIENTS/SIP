import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfsubscriptioncheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsubssession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cftheme/cftheme.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../core/security/secure_logger.dart';
import '../../../core/error/failures.dart';
import '../../../core/security/app_lifecycle_observer.dart';
import '../../../core/providers/user_provider.dart';
import '../../../routes/app_router.dart';
import '../controller/sip_controller.dart';

/// SIP Payment screen – opens the active gateway's mandate-authorization
/// checkout, selected via `paymentData['payment_gateway']` ('cashfree' | 'razorpay').
///
/// Cashfree path uses the Cashfree Flutter SDK's **Subscription flow**:
///   • `CFSubscriptionSessionBuilder` — builds a subscription session
///   • `CFSubscriptionPaymentBuilder` — builds the payment object
///   • `CFPaymentGatewayService.doPayment()` — launches the checkout
///
/// This is different from the regular payment flow (`CFWebCheckoutPayment`)
/// which only supports one-time payments.
///
/// Ref: https://www.cashfree.com/docs/payments/subscription/subscription_checkout_flutter_sdk
///
/// Razorpay path uses Razorpay Standard Checkout, same SDK/pattern already
/// used for one-time purchases in
/// lib/features/instant_saving/razorpay_payment_handler.dart, adapted here
/// for AutoPay/eMandate registration. `paymentData['mode']` selects which
/// Checkout option shape to use — 'subscriptions' (`subscription_id`) or
/// 'recurring' (`order_id` + `recurring: '1'`) — see _launchRazorpayAutoPay.
/// Both paths converge on the same `_verifyMandateStatus()` call — the
/// backend's `sip/confirm` endpoint is already gateway-agnostic.
class SipPaymentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> paymentData;

  const SipPaymentScreen({super.key, required this.paymentData});

  @override
  ConsumerState<SipPaymentScreen> createState() => _SipPaymentScreenState();
}

class _SipPaymentScreenState extends ConsumerState<SipPaymentScreen>
    with WidgetsBindingObserver {
  final _cfPaymentGatewayService = CFPaymentGatewayService();
  Razorpay? _razorpay;
  bool _isProcessing = true;
  bool _isVerifying = false;
  bool _sdkCallbackReceived = false;
  String? _error;

  /// Which checkout to launch: 'cashfree' (default) or 'razorpay'.
  String get _gateway =>
      (widget.paymentData['payment_gateway'] as String?)?.toLowerCase() ??
      'cashfree';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (_gateway == 'razorpay') {
      // Launch checkout after frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _launchRazorpayAutoPay();
      });
    } else {
      // Register subscription-specific callbacks
      _cfPaymentGatewayService.setCallback(
        _onSubscriptionVerify,
        _onSubscriptionFailure,
      );
      // Launch checkout after frame renders
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _launchSubscriptionCheckout();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _razorpay?.clear();
    super.dispose();
  }

  /// Fallback: When the Cashfree webview closes and the app resumes,
  /// if the SDK callback never fired, auto-trigger verification.
  /// This handles the SANDBOX redirect issue where the callback
  /// doesn't fire even though the mandate was successfully authorized.
  ///
  /// A 2-second delay is added to let the SDK callback fire first —
  /// the SDK may deliver its callback shortly after the app resumes.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SecureLogger.d('SIP PAYMENT: Lifecycle → $state '
        '(sdkCallback=$_sdkCallbackReceived, verifying=$_isVerifying)');
    if (state == AppLifecycleState.resumed &&
        !_sdkCallbackReceived &&
        !_isVerifying &&
        _error == null) {
      // Delay slightly so the SDK callback has a chance to fire first.
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        if (_sdkCallbackReceived || _isVerifying) {
          SecureLogger.d(
              'SIP PAYMENT: SDK callback arrived during delay — skipping fallback');
          return;
        }
        SecureLogger.d(
            'SIP PAYMENT: App resumed without SDK callback — triggering fallback verify');
        _verifyMandateStatus();
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CASHFREE SUBSCRIPTION CHECKOUT
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _launchSubscriptionCheckout() async {
    try {
      final subscriptionId =
          widget.paymentData['subscription_id'] as String? ?? '';
      final sessionId = widget.paymentData['session_id'] as String? ?? '';
      final envString =
          widget.paymentData['environment'] as String? ?? 'SANDBOX';
      final orderId = widget.paymentData['order_id']?.toString() ?? '';

      SecureLogger.d('SIP PAYMENT: paymentData received:');
      SecureLogger.d('  subscription_id: $subscriptionId');
      SecureLogger.d('  session_id: ${sessionId.isNotEmpty ? '${sessionId.substring(0, 20)}...' : 'EMPTY'}');
      SecureLogger.d('  environment: $envString');
      SecureLogger.d('  order_id: $orderId');

      if (subscriptionId.isEmpty || sessionId.isEmpty) {
        SecureLogger.e('SIP PAYMENT: Missing subscriptionId or sessionId!');
        setState(() {
          _isProcessing = false;
          _error = 'Invalid payment session. Please try again.';
        });
        return;
      }

      // Determine environment
      final environment = envString.toUpperCase() == 'PRODUCTION'
          ? CFEnvironment.PRODUCTION
          : CFEnvironment.SANDBOX;

      SecureLogger.d(
          'SIP PAYMENT: Launching Cashfree Subscription Checkout ($envString) '
          'for order $orderId, subscription $subscriptionId');

      // Step 1: Build subscription session
      final subscriptionSession = CFSubscriptionSessionBuilder()
          .setEnvironment(environment)
          .setSubscriptionId(subscriptionId)
          .setSubscriptionSessionId(sessionId)
          .build();

      // Step 2: Build theme (match app's green theme)
      final theme = CFThemeBuilder()
          .setNavigationBarBackgroundColorColor("#003716")
          .setNavigationBarTextColor("#ffffff")
          .build();

      // Step 3: Build subscription payment object
      final cfSubscriptionCheckout = CFSubscriptionPaymentBuilder()
          .setSession(subscriptionSession)
          .setTheme(theme)
          .build();

      // Step 4: Launch
      SecureLogger.d('SIP PAYMENT: Calling doPayment with subscription checkout object...');
      _cfPaymentGatewayService.doPayment(cfSubscriptionCheckout);
    } on CFException catch (e) {
      SecureLogger.e('SIP PAYMENT: CFException: ${e.message}');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = e.message;
        });
      }
    } catch (e) {
      SecureLogger.e('SIP PAYMENT: Error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'Failed to start payment. Please try again.';
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CASHFREE CALLBACKS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Called when subscription checkout completes successfully.
  /// The subscriptionId is returned — verify with backend.
  void _onSubscriptionVerify(String subscriptionId) {
    _sdkCallbackReceived = true;
    SecureLogger.d(
        'SIP PAYMENT: ✅ Subscription VERIFY callback → $subscriptionId');
    _verifyMandateStatus();
  }

  /// Called when subscription checkout fails.
  void _onSubscriptionFailure(CFErrorResponse errorResponse, String data) {
    _sdkCallbackReceived = true;
    final errorMsg = errorResponse.getMessage() ?? 'Payment failed';
    SecureLogger.e('SIP PAYMENT: ❌ Subscription FAILURE callback → $errorMsg');
    SecureLogger.e('SIP PAYMENT: Failure data: $data');

    if (!mounted) return;

    final orderId = widget.paymentData['order_id']?.toString();

    Navigator.pushReplacementNamed(
      context,
      AppRouter.sipFailure,
      arguments: {
        'message': errorMsg,
        'order_id': orderId ?? '',
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RAZORPAY AUTOPAY CHECKOUT
  // ═══════════════════════════════════════════════════════════════════════════

  /// Launches Razorpay Standard Checkout for AutoPay/eMandate registration.
  /// Same SDK/pattern as the one-time purchase flow
  /// (instant_saving/razorpay_payment_handler.dart).
  ///
  /// Two distinct Razorpay Checkout invocations exist depending on
  /// `paymentData['mode']` (see shared/services/sip.py create_scheme):
  ///   'subscriptions' (default) → order_id is a real sub_xxx id; Checkout
  ///                               takes `subscription_id`.
  ///   'recurring'               → order_id is a real order_xxx id (a UPI
  ///                               Autopay token registration order);
  ///                               Checkout takes `order_id` + `recurring: '1'`
  ///                               instead. Passing the wrong shape to the
  ///                               wrong option is rejected by Checkout.
  Future<void> _launchRazorpayAutoPay() async {
    try {
      final razorpayOrderOrSubId =
          widget.paymentData['order_id']?.toString() ?? '';
      final keyId = widget.paymentData['key_id']?.toString() ?? '';
      final mode =
          (widget.paymentData['mode'] as String?)?.toLowerCase() ??
          'subscriptions';
      final isRecurring = mode == 'recurring';
      // Recurring Payments mode only — Razorpay support identified
      // omitting this as a likely cause of "Token absent for recurring
      // payment": Checkout must be told which Customer the order/token was
      // registered against, matching the customer_id used at order
      // creation (see RazorpayRecurringService.create_subscription).
      final customerId = widget.paymentData['customer_id']?.toString() ?? '';

      SecureLogger.d('SIP PAYMENT: Razorpay paymentData received:');
      SecureLogger.d('  mode: $mode');
      SecureLogger.d('  razorpay_order_or_subscription_id: $razorpayOrderOrSubId');
      SecureLogger.d('  key_id set: ${keyId.isNotEmpty}');
      SecureLogger.d('  customer_id set: ${customerId.isNotEmpty}');

      if (razorpayOrderOrSubId.isEmpty || keyId.isEmpty) {
        SecureLogger.e('SIP PAYMENT: Missing Razorpay subscription/order id or key_id!');
        setState(() {
          _isProcessing = false;
          _error = 'Invalid payment session. Please try again.';
        });
        return;
      }

      _razorpay = Razorpay();
      _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRazorpaySuccess);
      _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onRazorpayError);
      _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onRazorpayExternalWallet);

      final user = ref.read(userProvider);

      // Suppress app lock — the user may leave the app to authorize via a
      // UPI app (Google Pay / PhonePe / etc.) and resume shortly after;
      // an MPIN/session-check must not fire mid-authorization.
      AppLifecycleObserver.suppressAppLock = true;

      final options = {
        'key': keyId,
        ...isRecurring
            ? {
                'order_id': razorpayOrderOrSubId,
                'recurring': '1',
                if (customerId.isNotEmpty) 'customer_id': customerId,
              }
            : {'subscription_id': razorpayOrderOrSubId},
        'name': 'startGOLD',
        'description': 'Auto Savings Plan Authorization',
        'prefill': {
          'contact': user?.mobile ?? '',
          'email': user?.email ?? '',
        },
      };

      SecureLogger.d('SIP PAYMENT: Opening Razorpay AutoPay checkout (mode=$mode)...');
      _razorpay!.open(options);
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      SecureLogger.e('SIP PAYMENT: Razorpay launch error: $e');
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _error = (e is Failure)
              ? e.message
              : 'Failed to start payment. Please try again.';
        });
      }
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // RAZORPAY CALLBACKS
  // ═══════════════════════════════════════════════════════════════════════════

  void _onRazorpaySuccess(PaymentSuccessResponse response) {
    _sdkCallbackReceived = true;
    AppLifecycleObserver.suppressAppLock = false;
    SecureLogger.d(
        'SIP PAYMENT: ✅ Razorpay mandate authorized — paymentId=${response.paymentId}');
    _verifyMandateStatus();
  }

  /// Maps a Razorpay failure to a user-friendly message.
  ///
  /// `response.message` is unreliable — the SDK sometimes returns the
  /// literal string "undefined" (not null) instead of a real description,
  /// which bypasses a plain `?? fallback`. Known error codes are mapped
  /// first; free-text messages are only used when they look genuine.
  String _friendlyRazorpayErrorMessage(PaymentFailureResponse response) {
    switch (response.code) {
      case Razorpay.NETWORK_ERROR:
        return 'Network error. Please check your internet connection and try again.';
      case Razorpay.INVALID_OPTIONS:
        return 'This payment could not be started. Please try again or contact support.';
      case Razorpay.PAYMENT_CANCELLED:
        return 'Payment was cancelled.';
      case Razorpay.TLS_ERROR:
        return "A secure connection could not be established. Please update your device's security settings and try again.";
    }
    final msg = response.message?.trim();
    if (msg == null ||
        msg.isEmpty ||
        msg.toLowerCase() == 'undefined' ||
        msg.toLowerCase() == 'null') {
      return 'Your payment could not be completed. Please try again.';
    }
    return msg;
  }

  void _onRazorpayError(PaymentFailureResponse response) {
    _sdkCallbackReceived = true;
    AppLifecycleObserver.suppressAppLock = false;
    final errorMsg = _friendlyRazorpayErrorMessage(response);
    SecureLogger.e(
        'SIP PAYMENT: ❌ Razorpay FAILURE → code=${response.code} rawMessage=${response.message}');

    if (!mounted) return;

    final orderId = widget.paymentData['order_id']?.toString();
    Navigator.pushReplacementNamed(
      context,
      AppRouter.sipFailure,
      arguments: {
        'message': errorMsg,
        'order_id': orderId ?? '',
      },
    );
  }

  void _onRazorpayExternalWallet(ExternalWalletResponse response) {
    SecureLogger.d('SIP PAYMENT: Razorpay external wallet: ${response.walletName}');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // VERIFY MANDATE STATUS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _verifyMandateStatus() async {
    if (_isVerifying) return;

    final orderId = widget.paymentData['order_id']?.toString();
    if (orderId == null) return;

    setState(() {
      _isProcessing = false;
      _isVerifying = true;
    });

    SecureLogger.d('SIP PAYMENT: Verifying mandate status for order $orderId');

    final subscriptionId = widget.paymentData['subscription_id']?.toString();

    try {
      final response = await ref.read(sipServiceProvider).confirmSip(
            orderId: orderId,
            subscriptionId: subscriptionId,
          );

      if (!mounted) return;

      // Refresh SIP details list
      ref.invalidate(sipDetailsProvider);

      if (response['success'] == true) {
        final status = response['data']?['status']?.toString().toUpperCase();

        if (status == 'ACTIVE' || status == 'BANK_APPROVAL_PENDING') {
          Navigator.pushReplacementNamed(
            context,
            AppRouter.sipSuccess,
            arguments: {
              'subscription_id': response['data']?['subscription_id'] ??
                  widget.paymentData['subscription_id'],
              'message': response['message'] ??
                  (status == 'BANK_APPROVAL_PENDING'
                      ? 'Your mandate is pending bank approval. It will be activated within 2-3 business days.'
                      : 'Your auto savings plan has been activated successfully!'),
            },
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            AppRouter.sipFailure,
            arguments: {
              'message':
                  response['message'] ?? 'Authorization status: $status',
              'order_id': orderId,
            },
          );
        }
      } else {
        Navigator.pushReplacementNamed(
          context,
          AppRouter.sipFailure,
          arguments: {
            'message': response['message'] ??
                response['error']?['message'] ??
                'Authorization could not be verified.',
            'order_id': orderId,
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      SecureLogger.e('SIP PAYMENT: Verify failed: $e');
      Navigator.pushReplacementNamed(
        context,
        AppRouter.sipFailure,
        arguments: {
          'message': (e is Failure)
              ? e.message
              : 'Payment verification failed. Please try again.',
          'order_id': orderId,
        },
      );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // UI
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Secure Payment',
            onBack: () {
              if (!_isProcessing && !_isVerifying) Navigator.pop(context);
            },
          ),
          Expanded(
            child: _isVerifying
                ? _buildVerifyingState()
                : _error != null
                    ? _buildErrorState()
                    : _buildProcessingState(),
          ),
        ],
      ),
    );
  }

  /// Shown while launching the Cashfree SDK checkout.
  Widget _buildProcessingState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48.w,
            height: 48.w,
            child: const CircularProgressIndicator(
              color: Color(0xFF064E3B),
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 24.h),
          Text(
            'Opening Payment…',
            style: GoogleFonts.playfairDisplay(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1A1A2E),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Please wait while we prepare your\nsubscription checkout',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp, color: Colors.black45),
          ),
        ],
      ),
    );
  }

  /// Shown while verifying mandate status with backend.
  Widget _buildVerifyingState() {
    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 30.h),
        margin: EdgeInsets.symmetric(horizontal: 40.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48.w,
              height: 48.w,
              child: const CircularProgressIndicator(
                color: Color(0xFF064E3B),
                strokeWidth: 3,
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Verifying Authorization…',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please wait while we confirm your\nmandate authorization',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                color: Colors.black45,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Shown when SDK initialization fails.
  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded,
                  size: 28.sp, color: const Color(0xFFDC2626)),
            ),
            SizedBox(height: 16.h),
            Text(
              _error ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 24.h),
            CustomButton(
              text: 'Retry',
              svgIconPath: 'assets/buttons/back-home.svg',
              onPressed: () {
                setState(() {
                  _isProcessing = true;
                  _error = null;
                });
                if (_gateway == 'razorpay') {
                  _launchRazorpayAutoPay();
                } else {
                  _launchSubscriptionCheckout();
                }
              },
              gradient: const LinearGradient(
                colors: [Color(0xFF003716), Color(0xFF167525)],
              ),
            ),
            SizedBox(height: 12.h),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Go Back',
                style: GoogleFonts.playfairDisplay(
                  color: Colors.black45,
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
