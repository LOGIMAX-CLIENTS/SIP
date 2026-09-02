import 'dart:async';

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
  // Persistent inline error — a toast alone can be missed (especially for
  // ACCOUNT_MISMATCH, which the customer needs to actually read and act on,
  // not just glance past). Cleared whenever a new attempt starts.
  String? _errorMessage;

  // Auto-poll instead of relying solely on a manual "I've Paid" tap — the
  // payment happens in an external UPI app (no in-app SDK callback like
  // BankPennyVerifyScreen has), so nothing else tells us when it settles.
  // Capped so it doesn't run forever if the customer leaves this screen
  // open; the manual button below remains available after the cap.
  static const _pollInterval = Duration(seconds: 5);
  static const _maxPollAttempts = 24; // ~2 minutes
  Timer? _pollTimer;
  int _pollAttempts = 0;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _pollAttempts++;
      if (_pollAttempts > _maxPollAttempts) {
        _stopPolling();
        return;
      }
      _checkStatus(silent: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Resets back to the initial "Pay ₹1 & Verify" state after a terminal
  /// failure (ACCOUNT_MISMATCH/FAILED) — previously the UI stayed stuck on
  /// "I've Paid — Verify Now" forever after a failure, which just re-checks
  /// the SAME already-failed client_id/session and returns the same error
  /// every time. The customer had no way to actually pay again from the
  /// correct account.
  void _retryAfterFailure() {
    _stopPolling();
    setState(() {
      _paymentLaunched = false;
      _clientId = null;
      _paymentLink = null;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _startVerification() async {
    if (_isProcessing || !mounted) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      final result = await ref
          .read(reversePennyDropServiceProvider)
          .initiate(cbankId: widget.cbankId);
      if (!mounted) return;

      // Dedup/self-heal on the backend: a retry may find this account was
      // already fully verified by a previous attempt (webhook/earlier check
      // never made it back to us) — nothing to pay, done immediately.
      if (result['already_verified'] == true || result['verified'] == true) {
        Navigator.pop(context, true);
        // Deferred to the next frame — see reverse_penny_drop_screen.dart's
        // sibling case below and add_bank_account_sheet.dart's comment for
        // why stacking an AppToast (root OverlayEntry insert) synchronously
        // with Navigator.pop() causes "_dependents.isEmpty" crashes.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            AppToast.show(context, 'Bank account additionally verified.', type: ToastType.success);
          }
        });
        return;
      }

      setState(() {
        _clientId = result['client_id']?.toString();
        _paymentLink = result['payment_link']?.toString();
      });
      if (_paymentLink != null) {
        final uri = Uri.parse(_paymentLink!);
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (mounted) setState(() => _paymentLaunched = launched);
        if (launched) {
          _startPolling();
        } else if (mounted) {
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

  /// [silent] = true for background auto-polls: suppresses the "still
  /// pending" toast (would otherwise spam every [_pollInterval]) and never
  /// touches [_isProcessing] (so the manual button's spinner isn't driven by
  /// background polling). Terminal outcomes (verified / FAILED /
  /// ACCOUNT_MISMATCH) are always surfaced and always stop the poll timer,
  /// silent or not.
  Future<void> _checkStatus({bool silent = false}) async {
    if (_clientId == null || !mounted) return;
    if (!silent) {
      if (_isProcessing) return;
      setState(() {
        _isProcessing = true;
        _errorMessage = null; // clear any stale banner before this re-check
      });
    }
    try {
      final result = await ref
          .read(reversePennyDropServiceProvider)
          .status(clientId: _clientId!);
      if (!mounted) return;

      final status = result['status']?.toString() ?? '';
      if (result['verified'] == true) {
        _stopPolling();
        Navigator.pop(context, true);
        // Deferred to the next frame — see the sibling case above.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            AppToast.show(context, 'Bank account additionally verified.', type: ToastType.success);
          }
        });
        return;
      }

      if (status == 'PENDING') {
        if (!silent) {
          AppToast.show(
            context,
            'Payment not received yet. Please complete the ₹1 payment and try again.',
            type: ToastType.error,
          );
        }
        return; // Not terminal — keep polling.
      }

      // Terminal failure — always surfaced (toast + persistent banner) and
      // always stops polling, silent or not.
      _stopPolling();
      final message = switch (status) {
        'ACCOUNT_MISMATCH' =>
          'The ₹1 payment came from a different account than the one being verified.',
        'FAILED' => 'Verification failed. Please try again.',
        _ => result['message']?.toString() ?? 'Verification pending.',
      };
      if (mounted) setState(() => _errorMessage = message);
      AppToast.show(context, message, type: ToastType.error);
    } catch (e) {
      if (!silent && mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (!silent && mounted) setState(() => _isProcessing = false);
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
                  if (_errorMessage != null) ...[
                    SizedBox(height: 16.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Colors.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 18.sp, color: Colors.red.shade400),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 12.sp,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                  else if (_errorMessage != null) ...[
                    Text(
                      'Please retry with the correct bank account.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(fontSize: 13.sp, color: isDark ? Colors.white54 : Colors.black54),
                    ),
                    SizedBox(height: 16.h),
                    ElevatedButton(
                      onPressed: _retryAfterFailure,
                      style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
                      child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                    ),
                  ] else ...[
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
