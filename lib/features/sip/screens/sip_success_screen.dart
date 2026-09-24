import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/custom_button.dart';
import '../../../routes/app_router.dart';

/// SIP creation success screen.
///
/// Shown after successful SIP plan creation + payment.
/// Matches the premium success patterns used in
/// [WithdrawalSuccessScreen] and purchase flows.
class SipSuccessScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const SipSuccessScreen({super.key, required this.data});

  @override
  State<SipSuccessScreen> createState() => _SipSuccessScreenState();
}

class _SipSuccessScreenState extends State<SipSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionId = widget.data['subscription_id'] ?? '';
    final message = widget.data['message'] ?? 'Auto Save is On!';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),

              // â”€â”€ Success GIF â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Image.asset(
                'assets/withdraw/successtik.gif',
                width: 90.w,
                height: 90.w,
              ),

              SizedBox(height: 32.h),

              // â”€â”€ Title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              FadeTransition(
                opacity: _fadeAnim,
                child: Column(
                  children: [
                    Text(
                      'Auto Save is On!',
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
                    if (subscriptionId.isNotEmpty) ...[
                      SizedBox(height: 24.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 20.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFF064E3B).withOpacity(0.06),
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tag_rounded,
                                size: 16.sp, color: const Color(0xFF064E3B)),
                            SizedBox(width: 8.w),
                            Text(
                              subscriptionId,
                              style: GoogleFonts.lora(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF064E3B),
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Spacer(flex: 3),

              // â”€â”€ Back to Home â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              CustomButton(
                text: 'Back to Home', svgIconPath: 'assets/buttons/back-home.svg',
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRouter.main,
                    (route) => false,
                  );
                },
                gradient: const LinearGradient(
                  colors: [Color(0xFF003716), Color(0xFF167525)],
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
