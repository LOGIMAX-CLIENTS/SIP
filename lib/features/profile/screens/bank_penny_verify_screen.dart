import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../core/providers/user_provider.dart';
import '../../../core/security/app_lifecycle_observer.dart';
import '../../../core/security/secure_logger.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import '../../instant_saving/widgets/payment_method_sheet.dart';
import '../services/bank_penny_verify_service.dart';
import '../services/bank_details_service.dart';

const _accentGreen = Color(0xFF1B882C);

final bankPennyVerifyServiceProvider =
    Provider((ref) => BankPennyVerifyService());

/// ₹1 payment-deduction verification — shown right after Cashfree BAV
/// succeeds on Add Bank Account. Pop with `true` if verified, `false`/null
/// otherwise, so the caller can refresh bankAccountsProvider either way.
class BankPennyVerifyScreen extends ConsumerStatefulWidget {
  final String cbankId;
  const BankPennyVerifyScreen({super.key, required this.cbankId});

  @override
  ConsumerState<BankPennyVerifyScreen> createState() =>
      _BankPennyVerifyScreenState();
}

class _BankPennyVerifyScreenState extends ConsumerState<BankPennyVerifyScreen> {
  bool _isProcessing = false;
  String? _internalOrderId;

  final CFPaymentGatewayService _cfPaymentGatewayService =
      CFPaymentGatewayService();
  final Razorpay _razorpay = Razorpay();

  @override
  void initState() {
    super.initState();
    _cfPaymentGatewayService.setCallback(_onCashfreeSuccess, _onCashfreeError);
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onRazorpaySuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onRazorpayError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (_) {});
  }

  @override
  void dispose() {
    _razorpay.clear();
    super.dispose();
  }

  void _onPayTapped() {
    if (_isProcessing || !mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PaymentMethodSheet(
        onProceed: (String paymentMethod) => _startVerification(paymentMethod),
      ),
    );
  }

  Future<void> _startVerification(String paymentMethod) async {
    setState(() => _isProcessing = true);
    AppLifecycleObserver.suppressAppLock = true;

    try {
      final result = await ref.read(bankPennyVerifyServiceProvider).initiate(
            cbankId: widget.cbankId,
            paymentMethod: paymentMethod,
          );
      _internalOrderId = result['internal_order_id']?.toString();
      final gateway = (result['payment_gateway'] ?? '').toString().toUpperCase();

      if (gateway == 'RAZORPAY') {
        _launchRazorpay(result);
      } else {
        _launchCashfree(result);
      }
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      setState(() => _isProcessing = false);
      if (mounted) {
        AppToast.show(context, e.toString().replaceAll('Exception: ', ''),
            type: ToastType.error);
      }
    }
  }

  // ── Cashfree ─────────────────────────────────────────────────────────────

  void _launchCashfree(Map<String, dynamic> result) {
    final sdkPayload = Map<String, dynamic>.from(result['sdk_payload'] ?? {});
    final sessionId = result['session_id']?.toString();
    if (sessionId == null || sessionId.isEmpty || _internalOrderId == null) {
      AppLifecycleObserver.suppressAppLock = false;
      setState(() => _isProcessing = false);
      if (mounted) {
        AppToast.show(context, 'Failed to start verification. Please try again.',
            type: ToastType.error);
      }
      return;
    }
    try {
      final env = (result['environment']?.toString().toUpperCase() == 'PRODUCTION')
          ? CFEnvironment.PRODUCTION
          : CFEnvironment.SANDBOX;
      final session = CFSessionBuilder()
          .setEnvironment(env)
          .setOrderId(sdkPayload['order_id']?.toString() ?? _internalOrderId!)
          .setPaymentSessionId(sessionId)
          .build();
      final cfWebCheckoutPayment =
          CFWebCheckoutPaymentBuilder().setSession(session).build();
      _cfPaymentGatewayService.doPayment(cfWebCheckoutPayment);
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      setState(() => _isProcessing = false);
      if (mounted) {
        AppToast.show(context, 'Could not open payment screen. Please try again.',
            type: ToastType.error);
      }
    }
  }

  void _onCashfreeSuccess(String orderId) {
    AppLifecycleObserver.suppressAppLock = false;
    _confirmAndFinish();
  }

  void _onCashfreeError(CFErrorResponse errorResponse, String orderId) {
    AppLifecycleObserver.suppressAppLock = false;
    _confirmAndFinish(fallbackErrorMsg: errorResponse.getMessage());
  }

  // ── Razorpay ─────────────────────────────────────────────────────────────

  void _launchRazorpay(Map<String, dynamic> result) {
    final sdkPayload = Map<String, dynamic>.from(result['sdk_payload'] ?? {});
    final keyId = sdkPayload['key']?.toString();
    final orderId = sdkPayload['order_id']?.toString() ?? result['session_id']?.toString();
    if (keyId == null || keyId.isEmpty || orderId == null || orderId.isEmpty) {
      AppLifecycleObserver.suppressAppLock = false;
      setState(() => _isProcessing = false);
      if (mounted) {
        AppToast.show(context, 'Failed to start verification. Please try again.',
            type: ToastType.error);
      }
      return;
    }
    final user = ref.read(userProvider);
    try {
      final options = {
        'key': keyId,
        'amount': sdkPayload['amount'] ?? 100,
        'currency': sdkPayload['currency'] ?? 'INR',
        'name': 'startGOLD',
        'description': 'Bank account verification',
        'order_id': orderId,
        'prefill': {
          'contact': user?.mobile ?? '',
          'email': user?.email ?? '',
        },
      };
      _razorpay.open(options);
    } catch (e) {
      AppLifecycleObserver.suppressAppLock = false;
      setState(() => _isProcessing = false);
      _razorpay.clear();
      if (mounted) {
        AppToast.show(context, 'Could not open payment screen. Please try again.',
            type: ToastType.error);
      }
    }
  }

  void _onRazorpaySuccess(PaymentSuccessResponse response) {
    AppLifecycleObserver.suppressAppLock = false;
    _confirmAndFinish();
    _razorpay.clear();
  }

  void _onRazorpayError(PaymentFailureResponse response) {
    AppLifecycleObserver.suppressAppLock = false;
    final err = response.error;
    SecureLogger.e(
        'BANK PENNY VERIFY: ❌ Razorpay FAILURE → code=${response.code} rawMessage=${response.message} '
        'description=${err?['description']} source=${err?['source']} step=${err?['step']} '
        'reason=${err?['reason']} metadata=${err?['metadata']}');
    _confirmAndFinish(fallbackErrorMsg: response.message ?? 'Payment failed.');
    _razorpay.clear();
  }

  // ── Confirm (server-authoritative) ──────────────────────────────────────

  Future<void> _confirmAndFinish({String? fallbackErrorMsg}) async {
    if (_internalOrderId == null) {
      setState(() => _isProcessing = false);
      return;
    }
    try {
      final result = await ref
          .read(bankPennyVerifyServiceProvider)
          .confirm(internalOrderId: _internalOrderId!);
      final verified = result['verified'] == true;

      setState(() => _isProcessing = false);
      if (!mounted) return;

      if (verified) {
        ref.invalidate(bankAccountsProvider);
        AppToast.show(context, 'Bank account verified successfully.',
            type: ToastType.success);
        Navigator.pop(context, true);
      } else {
        AppToast.show(
          context,
          fallbackErrorMsg ?? 'Payment was not completed. Please try again.',
          type: ToastType.error,
        );
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        AppToast.show(context, e.toString().replaceAll('Exception: ', ''),
            type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Verify Bank Account'),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(20.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 20.h),
                  Container(
                    padding: EdgeInsets.all(20.w),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        NumericStyledText(
                          'Pay ₹1 to verify',
                          fontSize: 17.sp,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                        SizedBox(height: 6.h),
                        NumericStyledText(
                          'Open your payment app and complete the ₹1 request to verify this account.',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w400,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                        SizedBox(height: 16.h),
                        Divider(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
                        SizedBox(height: 12.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Amount',
                                style: GoogleFonts.playfairDisplay(
                                    fontSize: 13.sp,
                                    color: isDark ? Colors.white54 : Colors.black54)),
                            Text('₹1.00',
                                style: GoogleFonts.lora(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : const Color(0xFF1E293B))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 52.h,
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _onPayTapped,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accentGreen,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(50.r)),
                        ),
                        child: _isProcessing
                            ? SizedBox(
                                width: 20.w,
                                height: 20.w,
                                child: const CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : NumericStyledText(
                                'Pay ₹1 & Verify',
                                fontSize: 15.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
