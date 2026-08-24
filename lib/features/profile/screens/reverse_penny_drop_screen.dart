import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../services/reverse_penny_drop_service.dart';

const _accentGreen = Color(0xFF1B882C);

final reversePennyDropServiceProvider =
    Provider((ref) => ReversePennyDropService());

/// SurePass Reverse Penny Drop — an OPTIONAL extra live-control check on top
/// of an already Pennyless-verified bank account. Unlike
/// [BankPennyVerifyScreen] (Cashfree/Razorpay in-app SDK payment), this pays
/// via a UPI deep link (no SDK — SurePass's RPD product is payment-link
/// only, see backend bank_verification_surepass.py). Pops `true` if the
/// resolved payer account matched [cbankId], `false`/null otherwise.
class ReversePennyDropScreen extends ConsumerStatefulWidget {
  final String cbankId;
  const ReversePennyDropScreen({super.key, required this.cbankId});

  @override
  ConsumerState<ReversePennyDropScreen> createState() =>
      _ReversePennyDropScreenState();
}

class _ReversePennyDropScreenState extends ConsumerState<ReversePennyDropScreen> {
  bool _isProcessing = false;
  bool _paymentLaunched = false;
  String? _clientId;
  String? _paymentLink;

  Future<void> _startVerification() async {
    if (_isProcessing || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final result = await ref
          .read(reversePennyDropServiceProvider)
          .initiate(cbankId: widget.cbankId);
      if (!mounted) return;
      setState(() {
        _clientId = result['client_id']?.toString();
        _paymentLink = result['payment_link']?.toString();
      });
      if (_paymentLink != null) {
        final uri = Uri.parse(_paymentLink!);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) setState(() => _paymentLaunched = launched);
        if (!launched && mounted) {
          AppToast.show(context, 'No UPI app found to open the payment link.', type: ToastType.error);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _checkStatus() async {
    if (_isProcessing || _clientId == null || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final result = await ref
          .read(reversePennyDropServiceProvider)
          .status(clientId: _clientId!);
      if (!mounted) return;

      final status = result['status']?.toString() ?? '';
      if (result['verified'] == true) {
        AppToast.show(context, 'Bank account additionally verified.', type: ToastType.success);
        Navigator.pop(context, true);
        return;
      }

      final message = switch (status) {
        'PENDING' => 'Payment not received yet. Please complete the ₹1 payment and try again.',
        'ACCOUNT_MISMATCH' =>
          'The ₹1 payment came from a different account than the one being verified.',
        'FAILED' => 'Verification failed. Please try again.',
        _ => result['message']?.toString() ?? 'Verification pending.',
      };
      AppToast.show(context, message, type: ToastType.error);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Reverse Penny Drop Verification'),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.currency_rupee_rounded, size: 48.sp, color: _accentGreen),
                  SizedBox(height: 16.h),
                  Text(
                    'Pay ₹1 from the bank account you want to additionally verify. '
                    'We\'ll match the payer details against this account.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  SizedBox(height: 32.h),
                  if (!_paymentLaunched)
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _startVerification,
                      style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Pay ₹1 & Verify', style: TextStyle(color: Colors.white)),
                    )
                  else ...[
                    Text(
                      'Complete the ₹1 payment in your UPI app, then tap below to confirm.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(fontSize: 13.sp, color: isDark ? Colors.white54 : Colors.black54),
                    ),
                    SizedBox(height: 16.h),
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _checkStatus,
                      style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('I\'ve Paid — Verify Now', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
