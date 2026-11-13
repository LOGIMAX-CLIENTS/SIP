import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import '../utils/airpay_mandate_poller.dart';

/// Airpay AutoPay: "approve it in your UPI app" wait.
///
/// There is no checkout to open — the server has already sent a UPI AutoPay
/// (collect) request to [approveVpa]. This view tells the customer where to
/// approve it, counts down [timeout], and asks `sip/confirm` (through
/// [confirm]) every [pollInterval], plus right away on "I've approved it" and
/// whenever the app comes back to the foreground (from the UPI app).
///
/// It reports, once: [onApproved] with the ACTIVE `sip/confirm` body,
/// [onFailed] with the server's reason, or [onTimedOut] when time runs out —
/// the view then shows a "not approved yet" note whose button calls
/// [onTimedOutExit]. [onCancel] is the customer closing the wait. Polling
/// stops in every case, and when the view is disposed.
class AirpayAutoPayWaitView extends StatefulWidget {
  /// The UPI ID the request went to ('' if the server didn't say).
  final String approveVpa;
  final Future<Map<String, dynamic>> Function() confirm;
  final void Function(Map<String, dynamic> response) onApproved;
  final void Function(String message) onFailed;
  final VoidCallback? onTimedOut;
  final VoidCallback onTimedOutExit;
  final VoidCallback onCancel;
  final Duration timeout;
  final Duration pollInterval;

  /// Clock for the countdown; tests pass a fake one.
  final DateTime Function()? now;

  const AirpayAutoPayWaitView({
    super.key,
    required this.approveVpa,
    required this.confirm,
    required this.onApproved,
    required this.onFailed,
    this.onTimedOut,
    required this.onTimedOutExit,
    required this.onCancel,
    this.timeout = const Duration(minutes: 10),
    this.pollInterval = const Duration(seconds: 5),
    this.now,
  });

  static const timedOutMessage =
      "We didn't get your approval yet. If you approved it, it may take a few "
      'minutes to show — check AutoGold later.';

  @override
  State<AirpayAutoPayWaitView> createState() => _AirpayAutoPayWaitViewState();
}

class _AirpayAutoPayWaitViewState extends State<AirpayAutoPayWaitView>
    with WidgetsBindingObserver {
  static const _green = Color(0xFF064E3B);
  static const _ink = Color(0xFF1A1A2E);

  late final AirpayMandatePoller _poller;
  late Duration _remaining;
  bool _checkingNow = false;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _poller = AirpayMandatePoller(
      confirm: widget.confirm,
      onFinished: _onFinished,
      onTick: (left) {
        if (mounted) setState(() => _remaining = left);
      },
      pollInterval: widget.pollInterval,
      timeout: widget.timeout,
      now: widget.now,
    );
    _remaining = widget.timeout;
    _poller.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller.dispose();
    super.dispose();
  }

  /// Back from the UPI app: check now instead of waiting for the next poll,
  /// and catch the countdown up with the time spent away.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _poller.isDone) return;
    setState(() => _remaining = _poller.remaining);
    _poller.pollNow();
  }

  void _onFinished(AirpayMandateUpdate update) {
    if (!mounted) return;
    switch (update.status) {
      case AirpayMandateStatus.active:
        widget.onApproved(update.response);
      case AirpayMandateStatus.failed:
        widget.onFailed(
            update.message ?? 'Mandate authorization failed. Please try again.');
      case AirpayMandateStatus.timedOut:
        setState(() => _timedOut = true);
        widget.onTimedOut?.call();
      case AirpayMandateStatus.pending:
        break;
    }
  }

  Future<void> _checkNow() async {
    if (_checkingNow || _poller.isDone) return;
    setState(() => _checkingNow = true);
    await _poller.pollNow();
    if (mounted) setState(() => _checkingNow = false);
  }

  static String _mmss(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24.w, 24.h, 24.w, 24.h),
      child: _timedOut ? _buildTimedOut() : _buildWaiting(),
    );
  }

  Widget _buildWaiting() {
    return Column(
      children: [
        _card(
          children: [
            _badge(Icons.phonelink_ring_rounded, _green),
            SizedBox(height: 16.h),
            Text(
              'Approve AutoPay in your UPI app',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              widget.approveVpa.isNotEmpty
                  ? "We've sent an AutoPay request to"
                  : "We've sent an AutoPay request to your UPI ID.",
              textAlign: TextAlign.center,
              style: _bodyStyle,
            ),
            if (widget.approveVpa.isNotEmpty) ...[
              SizedBox(height: 10.h),
              _vpaTile(widget.approveVpa),
            ],
            SizedBox(height: 10.h),
            Text(
              'Open your UPI app (Google Pay, PhonePe, Paytm, BHIM…) and '
              'approve it.',
              textAlign: TextAlign.center,
              style: _bodyStyle,
            ),
            SizedBox(height: 22.h),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18.w,
                  height: 18.w,
                  child: const CircularProgressIndicator(
                    color: _green,
                    strokeWidth: 2.5,
                  ),
                ),
                SizedBox(width: 10.w),
                Text(
                  'Waiting for approval',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            SizedBox(height: 6.h),
            NumericStyledText(
              _mmss(_remaining),
              key: const ValueKey('airpay-countdown'),
              fontSize: 28.sp,
              fontWeight: FontWeight.w700,
              color: _green,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 2.h),
            Text(
              'Time left to approve',
              style: GoogleFonts.playfairDisplay(
                fontSize: 11.sp,
                color: Colors.black45,
              ),
            ),
          ],
        ),
        SizedBox(height: 24.h),
        CustomButton(
          text: "I've approved it",
          svgIconPath: 'assets/buttons/tick.svg',
          isLoading: _checkingNow,
          loadingText: 'Checking…',
          onPressed: _checkNow,
          gradient: const LinearGradient(
            colors: [Color(0xFF003716), Color(0xFF167525)],
          ),
        ),
        SizedBox(height: 8.h),
        TextButton(
          onPressed: widget.onCancel,
          child: Text(
            'Cancel',
            style: GoogleFonts.playfairDisplay(
              color: Colors.black45,
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimedOut() {
    return Column(
      children: [
        _card(
          children: [
            _badge(Icons.schedule_rounded, const Color(0xFFB45309)),
            SizedBox(height: 16.h),
            Text(
              'Still waiting for approval',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              AirpayAutoPayWaitView.timedOutMessage,
              textAlign: TextAlign.center,
              style: _bodyStyle,
            ),
          ],
        ),
        SizedBox(height: 24.h),
        CustomButton(
          text: 'Back to Home',
          svgIconPath: 'assets/buttons/back-home.svg',
          onPressed: widget.onTimedOutExit,
          gradient: const LinearGradient(
            colors: [Color(0xFF003716), Color(0xFF167525)],
          ),
        ),
      ],
    );
  }

  TextStyle get _bodyStyle => GoogleFonts.playfairDisplay(
        fontSize: 13.sp,
        color: Colors.black54,
        height: 1.5,
      );

  /// White card, same as SipPaymentScreen's "Verifying Authorization…" state.
  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
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
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _badge(IconData icon, Color color) {
    return Container(
      width: 64.w,
      height: 64.w,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 28.sp, color: color),
    );
  }

  /// The UPI ID, styled like the selected tile in UpiIdSheet / the UPI ID
  /// card on SipPaymentScreen.
  Widget _vpaTile(String vpa) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF1B882C).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFF1B882C).withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 40.r,
            height: 40.r,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: const Color(0xFF1B882C), size: 20.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              vpa,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.playfairDisplay(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
