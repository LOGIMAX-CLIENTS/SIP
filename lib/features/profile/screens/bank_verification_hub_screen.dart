import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/gradient_header.dart';

/// Profile > "Bank Account Verification" hub — links to the 3 history
/// screens for the BAV / Rs.1 payment / refund verification layers.
class BankVerificationHubScreen extends StatelessWidget {
  const BankVerificationHubScreen({super.key});

  static const _accentGreen = Color(0xFF1B882C);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Bank Account Verification'),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(20.w),
              children: [
                _buildItem(
                  context,
                  isDark,
                  icon: Icons.fact_check_rounded,
                  title: 'Bank Account Verification History',
                  subtitle: 'Every BAV attempt on your bank accounts',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRouter.bavHistory),
                ),
                SizedBox(height: 14.h),
                _buildItem(
                  context,
                  isDark,
                  icon: Icons.currency_rupee_rounded,
                  title: 'Bank Account Rs.1 Payment Verification History',
                  subtitle: 'Rs.1 payments made to verify your accounts',
                  onTap: () => Navigator.pushNamed(
                      context, AppRouter.pennyVerifyHistory),
                ),
                SizedBox(height: 14.h),
                _buildItem(
                  context,
                  isDark,
                  icon: Icons.replay_circle_filled_rounded,
                  title: 'Bank Account Refund Verification History',
                  subtitle: 'Refund status of every Rs.1 verification payment',
                  onTap: () =>
                      Navigator.pushNamed(context, AppRouter.refundHistory),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    bool isDark, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08)),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: _accentGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(icon, color: _accentGreen, size: 22.sp),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        )),
                    SizedBox(height: 4.h),
                    Text(subtitle,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 11.sp,
                          color: isDark ? Colors.white54 : Colors.black54,
                        )),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  size: 18.sp, color: Colors.black26),
            ],
          ),
        ),
      ),
    );
  }
}
