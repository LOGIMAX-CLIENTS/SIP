import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/core/utils/validators.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import 'package:startgold/shared/widgets/custom_button.dart';
import 'package:startgold/shared/widgets/secure_clipboard.dart';

/// Asks for an e-mail address on the KYC checklist itself, for a customer
/// who registered without one (RULE-KYC-022) — so the E-mail step never has
/// to send them off to Account Details. [onSend] sends the code; the sheet
/// stays open when it fails (the caller toasts why, e.g. an address another
/// account already uses) and pops with the trimmed address once it succeeds,
/// ready for [showEmailOtpSheet].
Future<String?> showKycAddEmailSheet(
  BuildContext context, {
  required Future<bool> Function(String email) onSend,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => KycAddEmailSheet(onSend: onSend),
  );
}

class KycAddEmailSheet extends StatefulWidget {
  final Future<bool> Function(String email) onSend;

  const KycAddEmailSheet({super.key, required this.onSend});

  @override
  State<KycAddEmailSheet> createState() => _KycAddEmailSheetState();
}

class _KycAddEmailSheetState extends State<KycAddEmailSheet> {
  final TextEditingController _emailController = TextEditingController();
  String? _error;
  bool _sending = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _emailController.text.trim();
    final error = Validators.validateEmail(email);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });
    final sent = await widget.onSend(email);
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) Navigator.pop(context, email);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF666666);

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
              'Add your e-mail',
              style: GoogleFonts.playfairDisplay(
                fontSize: 22.sp,
                fontWeight: FontWeight.bold,
                color: primaryTextColor,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              "We'll send a code to confirm it's yours.",
              style: GoogleFonts.playfairDisplay(
                fontSize: 14.sp,
                color: secondaryTextColor,
              ),
            ),
            SizedBox(height: 24.h),
            TextField(
              controller: _emailController,
              autofocus: true,
              enabled: !_sending,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              contextMenuBuilder: SecureClipboard.none,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _send(),
              style: AppTextStyles.bodyLarge(isDark).copyWith(color: primaryTextColor),
              decoration: InputDecoration(
                hintText: 'Enter Your E-Mail',
                hintStyle: AppTextStyles.inputHint(isDark)
                    .copyWith(color: primaryTextColor.withOpacity(0.6)),
                errorText: _error,
                contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.h),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: BorderSide(color: primaryTextColor.withOpacity(0.1)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.r),
                  borderSide: BorderSide(color: primaryTextColor.withOpacity(0.1)),
                ),
              ),
            ),
            SizedBox(height: 24.h),
            CustomButton(
              text: 'Send Code',
              isLoading: _sending,
              onPressed: _sending ? null : _send,
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF1B882C), Color(0xFF003716)],
              ),
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
