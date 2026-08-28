import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'package:pinput/pinput.dart';
import '../controller/auth_controller.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../core/utils/masking_utils.dart';

/// Shows the inline email-OTP verification bottom sheet used by the
/// Personal Information (registration) screen. Returns true once the
/// email has been successfully verified.
Future<bool?> showEmailOtpSheet(
  BuildContext context, {
  required String email,
  required String otpReferenceId,
  String? firstName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EmailOtpSheet(
      email: email,
      otpReferenceId: otpReferenceId,
      firstName: firstName,
    ),
  );
}

class EmailOtpSheet extends ConsumerStatefulWidget {
  final String email;
  final String otpReferenceId;
  final String? firstName;

  const EmailOtpSheet({
    super.key,
    required this.email,
    required this.otpReferenceId,
    this.firstName,
  });

  @override
  ConsumerState<EmailOtpSheet> createState() => _EmailOtpSheetState();
}

class _EmailOtpSheetState extends ConsumerState<EmailOtpSheet> {
  final TextEditingController _otpController = TextEditingController();
  late String _otpReferenceId;
  int _timerSeconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _otpReferenceId = widget.otpReferenceId;
    _startTimer();
    _otpController.addListener(() => setState(() {}));
  }

  void _startTimer() {
    setState(() => _timerSeconds = 30);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timerSeconds == 0) {
        timer.cancel();
      } else {
        setState(() => _timerSeconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  // NOTE: no ref.listen<AuthState> here for error toasts — the parent
  // RegistrationScreen already listens on the same shared authControllerProvider
  // and would show the same error a second time if this sheet listened too.

  Future<void> _resendOtp() async {
    _otpController.clear();
    ref.read(authControllerProvider.notifier).clearError();

    final success = await ref
        .read(authControllerProvider.notifier)
        .sendEmailOtp(widget.email, firstName: widget.firstName);

    if (!mounted) return;
    if (success) {
      final data = ref.read(authControllerProvider).data;
      _otpReferenceId = data?['otp_reference_id'] ?? _otpReferenceId;
      _startTimer();
      AppToast.show(context, 'OTP resent successfully!', type: ToastType.success);
    }
  }

  Future<void> _verifyOtp(String otp) async {
    final success = await ref
        .read(authControllerProvider.notifier)
        .verifyEmailOtp(widget.email, otp, _otpReferenceId);

    if (!mounted) return;
    if (success) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF666666);
    final accentGreen = const Color(0xFF064E3B);
    final canVerify = _otpController.text.length == 6;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        ),
        padding: EdgeInsets.fromLTRB(
          24.w, 12.h, 24.w, 24.h + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: primaryTextColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ),
            SizedBox(height: 20.h),
            Text(
              'Verify your email',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'We sent an OTP to ${MaskingUtils.maskEmail(widget.email)}',
              style: GoogleFonts.playfairDisplay(
                fontSize: 14.sp,
                color: secondaryTextColor,
              ),
            ),
            SizedBox(height: 24.h),
            Center(
              child: Pinput(
                length: 6,
                controller: _otpController,
                keyboardType: TextInputType.number,
                contextMenuBuilder: SecureClipboard.none,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                defaultPinTheme: PinTheme(
                  width: 45.w,
                  height: 52.h,
                  textStyle: GoogleFonts.lora(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w600,
                    color: primaryTextColor,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: primaryTextColor.withOpacity(0.15)),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                focusedPinTheme: PinTheme(
                  width: 45.w,
                  height: 52.h,
                  textStyle: AppTextStyles.valueLarge(isDark)
                      .copyWith(color: accentGreen),
                  decoration: BoxDecoration(
                    border: Border.all(color: accentGreen, width: 1.5),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                ),
                onCompleted: _verifyOtp,
              ),
            ),
            SizedBox(height: 16.h),
            Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                children: [
                  Text(
                    "Didn't receive the OTP? ",
                    style: GoogleFonts.playfairDisplay(fontSize: 13.sp, color: secondaryTextColor),
                  ),
                  _timerSeconds > 0
                      ? Text(
                          'Request a new one in ${_timerSeconds}s',
                          style: GoogleFonts.lora(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold,
                            color: accentGreen,
                          ),
                        )
                      : GestureDetector(
                          onTap: _resendOtp,
                          child: Text(
                            'Resend Code',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.bold,
                              color: accentGreen,
                            ),
                          ),
                        ),
                ],
              ),
            ),
            SizedBox(height: 24.h),
            CustomButton(
              text: 'Verify OTP',
              isLoading: authState.isLoading,
              onPressed: canVerify ? () => _verifyOtp(_otpController.text) : null,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: canVerify
                    ? const [Color(0xFF1B882C), Color(0xFF003716)]
                    : [
                        const Color(0xFF1B882C).withOpacity(0.5),
                        const Color(0xFF003716).withOpacity(0.5),
                      ],
              ),
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
