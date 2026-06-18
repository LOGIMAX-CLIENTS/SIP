import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/app_toast.dart';

class PanVerificationScreen extends StatefulWidget {
  const PanVerificationScreen({super.key});

  @override
  State<PanVerificationScreen> createState() => _PanVerificationScreenState();
}

class _PanVerificationScreenState extends State<PanVerificationScreen> {
  final _panController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _panController.dispose();
    super.dispose();
  }

  static final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$');

  void _handleVerify() async {
    final pan = _panController.text.trim().toUpperCase();
    if (pan.length != 10) {
      AppToast.show(context, 'PAN must be exactly 10 characters', type: ToastType.warning);
      return;
    }
    if (!_panRegex.hasMatch(pan)) {
      AppToast.show(context, 'Invalid PAN format. Expected: ABCDE1234F', type: ToastType.warning);
      return;
    }

    setState(() => _isLoading = true);
    await Future.delayed(const Duration(seconds: 2)); // Simulate API call
    if (mounted) {
      _showSuccessDialog();
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  shape: BoxShape.circle),
              child: Icon(Icons.verified_user_rounded,
                  color: Colors.greenAccent[400], size: 48.sp),
            ),
            SizedBox(height: 24.h),
            Text('Verification Sent',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20.sp, fontWeight: FontWeight.w900)),
            SizedBox(height: 12.h),
            Text(
                'We are validating your documents. You will be notified once verified.',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.playfairDisplay(fontSize: 14.sp, color: Colors.black54)),
            SizedBox(height: 32.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, AppRouter.home, (route) => false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.arcticBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child:
                    const Text('GOT IT', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('PAN Verification',
            style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w700)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FadeInAnimation(
              delay: const Duration(milliseconds: 100),
              child: Text(
                'Enter Permanent Account\nNumber (PAN) Details',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 24.sp,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
            ),
            SizedBox(height: 12.h),
            Text(
              'Required for tax reporting on your investments.',
              style: GoogleFonts.playfairDisplay(
                  color: isDark ? Colors.white54 : Colors.black54),
            ),
            SizedBox(height: 48.h),
            _buildInputField(
              'PAN Number',
              'ABCDE1234F',
              _panController,
              isDark,
              TextInputType.text,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                // Block special chars — allow only A-Z and 0-9
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                // Force uppercase
                TextInputFormatter.withFunction((old, nv) =>
                    nv.copyWith(text: nv.text.toUpperCase())),
                // Hard limit to 10 characters
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            const Spacer(),
            CustomButton(
              text: 'VERIFY & PROCEED',
              svgIconPath: 'assets/buttons/tick.svg',
              isLoading: _isLoading,
              onPressed: _handleVerify,
              backgroundColor: AppTheme.arcticBlue,
            ),
            SizedBox(height: 24.h),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String label, String hint,
      TextEditingController controller, bool isDark, TextInputType type,
      {TextCapitalization textCapitalization = TextCapitalization.none,
      List<TextInputFormatter>? inputFormatters}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.playfairDisplay(
                fontWeight: FontWeight.w700, fontSize: 14.sp)),
        SizedBox(height: 12.h),
        TextField(
          controller: controller,
          keyboardType: type,
          textCapitalization: textCapitalization,
          inputFormatters: inputFormatters,
          contextMenuBuilder: SecureClipboard.none,
          style:
              GoogleFonts.lora(fontSize: 18.sp, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.playfairDisplay(fontSize: 16.sp, color: isDark ? Colors.white38 : Colors.black38),
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16.r),
                borderSide: BorderSide.none),
            contentPadding: EdgeInsets.all(18.w),
          ),
        ),
      ],
    );
  }
}
