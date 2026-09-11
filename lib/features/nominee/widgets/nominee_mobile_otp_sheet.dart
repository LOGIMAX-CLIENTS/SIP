import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pinput/pinput.dart';

import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/masking_utils.dart';

/// OTP bottom sheet for verifying a nominee's mobile number.
///
/// Self-contained — calls [AuthService] directly rather than going through
/// authControllerProvider (which is scoped to the login/registration flow
/// and would save tokens/session on a successful verify). Returns true once
/// the number has been successfully verified.
Future<bool?> showNomineeMobileOtpSheet(
  BuildContext context, {
  required String mobile,
  required String countryCode,
  required String idCountry,
  required String otpReferenceId,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => NomineeMobileOtpSheet(
      mobile: mobile,
      countryCode: countryCode,
      idCountry: idCountry,
      otpReferenceId: otpReferenceId,
    ),
  );
}

class NomineeMobileOtpSheet extends StatefulWidget {
  final String mobile;
  final String countryCode;
  final String idCountry;
  final String otpReferenceId;

  const NomineeMobileOtpSheet({
    super.key,
    required this.mobile,
    required this.countryCode,
    required this.idCountry,
    required this.otpReferenceId,
  });

  @override
  State<NomineeMobileOtpSheet> createState() => _NomineeMobileOtpSheetState();
}

/// Extracts a user-facing message from this app's standard error response
/// shape: {"error": {"message": ...}, "data": {"message": ...}, "message": ...}.
String _extractErrorMessage(Map<String, dynamic> response, String fallback) {
  final errorObj = response['error'];
  final dataObj = response['data'];
  return (errorObj is Map ? errorObj['message'] as String? : null) ??
      (dataObj is Map ? dataObj['message'] as String? : null) ??
      response['message'] as String? ??
      fallback;
}

class _NomineeMobileOtpSheetState extends State<NomineeMobileOtpSheet> {
  static const int _resendCooldownSeconds = 30; // mirrors OtpScreen's own timer
  final AuthService _authService = AuthService();
  final TextEditingController _otpController = TextEditingController();
  late String _otpReferenceId;
  int _timerSeconds = _resendCooldownSeconds;
  Timer? _timer;
  bool _isVerifying = false;
  bool _isResending = false;

  @override
  void initState() {
    super.initState();
    _otpReferenceId = widget.otpReferenceId;
    _startTimer();
    _otpController.addListener(() => setState(() {}));
  }

  void _startTimer() {
    setState(() => _timerSeconds = _resendCooldownSeconds);
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

  Future<void> _resendOtp() async {
    setState(() => _isResending = true);
    _otpController.clear();
    try {
      final data = await _authService.sendOtp(
        mobile: widget.mobile,
        countryCode: widget.countryCode,
        idCountry: widget.idCountry,
        type: 'RESEND',
      );
      if (!mounted) return;
      if (data['success'] == true) {
        final newRefId = data['data']?['otp_reference_id'];
        if (newRefId != null) _otpReferenceId = newRefId;
        _startTimer();
        AppToast.show(context, 'OTP resent successfully!', type: ToastType.success);
      } else {
        AppToast.show(context, _extractErrorMessage(data, 'Failed to resend OTP. Please try again.'),
            type: ToastType.error);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed to resend OTP. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _verifyOtp(String otp) async {
    setState(() => _isVerifying = true);
    try {
      final data = await _authService.verifyMobileOtpOnly(
        mobile: widget.mobile,
        otp: otp,
        otpReferenceId: _otpReferenceId,
      );
      if (!mounted) return;
      if (data['success'] == true) {
        Navigator.pop(context, true);
      } else {
        AppToast.show(
          context,
          _extractErrorMessage(data, 'Invalid or expired OTP. Please try again.'),
          type: ToastType.error,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Invalid or expired OTP. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              'Verify nominee\'s mobile number',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'We sent an OTP to ${MaskingUtils.maskMobile(widget.mobile)}',
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
                enabled: !_isVerifying,
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
                          onTap: _isResending ? null : _resendOtp,
                          child: Text(
                            _isResending ? 'Resending...' : 'Resend Code',
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
              isLoading: _isVerifying,
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
