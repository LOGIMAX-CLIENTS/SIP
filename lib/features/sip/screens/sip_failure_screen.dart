import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/custom_button.dart';
import '../../../routes/app_router.dart';

/// SIP payment failure screen.
///
/// Displayed when Cashfree payment callback reports a failure.
/// Provides Retry and Back options.
class SipFailureScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const SipFailureScreen({super.key, required this.data});

  @override
  State<SipFailureScreen> createState() => _SipFailureScreenState();
}

class _SipFailureScreenState extends State<SipFailureScreen> {

  @override
  Widget build(BuildContext context) {
    final message = widget.data['message'] ?? 'Payment could not be completed.';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // ── Failure GIF ─────────────────────────────
              Image.asset(
                'assets/withdraw/failuretik.gif',
                width: 90.w,
                height: 90.w,
              ),

              SizedBox(height: 32.h),

              FadeTransition(
                opacity: const AlwaysStoppedAnimation(1.0),
                child: Column(
                  children: [
                    Text(
                      'Payment Failed',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 24.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 14.sp,
                        color: Colors.black45,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // ── Retry ──────────────────────────────────
              CustomButton(
                text: 'Retry',
                svgIconPath: 'assets/buttons/back-home.svg',
                onPressed: () {
                  Navigator.pop(context, 'retry');
                },
                gradient: const LinearGradient(
                  colors: [Color(0xFF003716), Color(0xFF167525)],
                ),
              ),

              SizedBox(height: 12.h),

              // ── Back ───────────────────────────────────
              OutlinedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRouter.main,
                    (route) => false,
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF064E3B),
                  side: const BorderSide(color: Color(0xFF064E3B), width: 1.5),
                  minimumSize: Size(double.infinity, 52.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100.r),
                  ),
                ),
                child: Text(
                  'Back To Home',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF064E3B),
                  ),
                ),
              ),

              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }
}
