import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/numeric_styled_text.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/app_text_styles.dart';

class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : Colors.black, size: 20.sp),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Support Center',
            style: AppTextStyles.titleLarge(isDark)
                .copyWith(color: isDark ? Colors.white : Colors.black)),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 20.h),
            _buildSearchBox(isDark),
            SizedBox(height: 32.h),
            Text('Quick Assistance',
                style: AppTextStyles.titleMedium(isDark)
                    .copyWith(color: isDark ? Colors.white : Colors.black87)),
            SizedBox(height: 16.h),
            Row(
              children: [
                _buildSupportAction(
                    Icons.chat_bubble_outline, 'Live Chat', isDark),
                SizedBox(width: 16.w),
                _buildSupportAction(
                    Icons.phone_outlined, 'Call Support', isDark),
              ],
            ),
            SizedBox(height: 32.h),
            Text('Frequently Asked Questions',
                style: AppTextStyles.titleMedium(isDark)
                    .copyWith(color: isDark ? Colors.white : Colors.black87)),
            SizedBox(height: 16.h),
            _buildFaqItem('How to buy digital gold?',
                'Navigate to the Market tab and select Buy Gold.', isDark),
            _buildFaqItem('What are the storage charges?',
                'Zero storage charges for the first 5 years.', isDark),
            _buildFaqItem(
                'Is my investment insured?',
                'Every gram is backed by 24K physical gold in Brink\'s vaults.',
                isDark),
            _buildFaqItem('How long for bank withdrawals?',
                'Withdrawals usually hit your bank in under 24 hours.', isDark),
            SizedBox(height: 40.h),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox(bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      height: 56.h,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Row(
        children: [
          Icon(Icons.search, color: Colors.grey, size: 22.sp),
          SizedBox(width: 12.w),
          Text('Search for help...',
              style: GoogleFonts.playfairDisplay(color: Colors.grey, fontSize: 16.sp)),
        ],
      ),
    );
  }

  Widget _buildSupportAction(IconData icon, String title, bool isDark) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 24.h),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
        ),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.arcticBlue, size: 30.sp),
            SizedBox(height: 12.h),
            Text(title,
                style: GoogleFonts.playfairDisplay(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqItem(String ques, String ans, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.02) : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: NumericStyledText(ques,
                      fontSize: 15.sp,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87)),
              Icon(Icons.add, size: 20.sp, color: AppTheme.arcticBlue),
            ],
          ),
          SizedBox(height: 8.h),
          NumericStyledText(ans,
              fontSize: 13.sp, color: Colors.grey, height: 1.4),
        ],
      ),
    );
  }
}

