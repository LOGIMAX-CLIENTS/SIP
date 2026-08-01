import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/widgets/numeric_styled_text.dart';
import 'package:startgold/features/support/enquiry_service.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/widgets/animations.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/routes/app_router.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

class EnquiryListScreen extends ConsumerWidget {
  const EnquiryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final enquiriesAsync = ref.watch(enquiriesProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, MediaQuery.of(context).viewPadding.bottom + 16.h),
        decoration: const BoxDecoration(
          color: Colors.transparent,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.greenGradient,
            borderRadius: BorderRadius.circular(50.r),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryGreen.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, AppRouter.enquiryForm)
                .then((_) => ref.refresh(enquiriesProvider)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 14.h),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(50.r)),
            ),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
            label: Text(
              'New Enquiry',
              style: AppTextStyles.button(false),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Gradient Header ─────────────────────────────────────────────
          GradientHeader(
            title: 'My Enquiries',
            trailing: IconButton(
              onPressed: () => Navigator.pushNamed(context, AppRouter.enquiryForm)
                  .then((_) => ref.refresh(enquiriesProvider)),
              icon: Container(
                padding: EdgeInsets.all(8.w),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.add_comment_outlined, color: Colors.white, size: 20.sp),
              ),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Expanded(
            child: enquiriesAsync.when(
              data: (enquiries) {
                if (enquiries.isEmpty) {
                  return _buildEmpty(context);
                }
                return RefreshIndicator(
                  onRefresh: () async => ref.refresh(enquiriesProvider),
                  color: AppTheme.primaryGreen,
                  child: ListView.separated(
                    padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 32.h),
                    itemCount: enquiries.length,
                    separatorBuilder: (_, __) => SizedBox(height: 14.h),
                    itemBuilder: (context, index) => FadeInAnimation(
                      delay: Duration(milliseconds: 60 * index),
                      child: _buildCard(enquiries[index], isDark),
                    ),
                  ),
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: AppTheme.primaryGreen),
              ),
              error: (e, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48.sp, color: Colors.redAccent),
                    SizedBox(height: 12.h),
                    Text(
                      'Could not load enquiries.\nPlease try again.',
                      style: GoogleFonts.playfairDisplay(fontSize: 14.sp, color: Colors.black45),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 20.h),
                    TextButton.icon(
                      onPressed: () => ref.refresh(enquiriesProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Retry'),
                      style: TextButton.styleFrom(foregroundColor: AppTheme.primaryGreen),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88.w,
              height: 88.w,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.07),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.support_agent_outlined,
                  size: 42.sp, color: AppTheme.primaryGreen.withOpacity(0.5)),
            ),
            SizedBox(height: 20.h),
            Text(
              'No Enquiries Yet',
              style: AppTextStyles.titleMedium(isDark),
            ),
            SizedBox(height: 8.h),
            Text(
              'Submit a ticket and our support\nteam will get back to you.',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 13.sp,
                  color: const Color(0xFF888888),
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 28.h),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(Enquiry enquiry, bool isDark) {
    final status = enquiry.status.toLowerCase();

    Color statusColor;
    IconData statusIcon;
    switch (status) {
      case 'open':
        statusColor = const Color(0xFF2563EB);
        statusIcon = Icons.lock_open_rounded;
        break;
      case 'resolved':
        statusColor = const Color(0xFF16A34A);
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = const Color(0xFFDC2626);
        statusIcon = Icons.cancel_rounded;
        break;
      case 'pending':
      default:
        statusColor = const Color(0xFFD97706);
        statusIcon = Icons.timelapse_rounded;
        break;
    }

    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: status badge + date ──────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: statusColor.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 12.sp, color: statusColor),
                    SizedBox(width: 4.w),
                    Text(
                      enquiry.status.toUpperCase(),
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                enquiry.createdAt,
                style: GoogleFonts.lora(
                  fontSize: 11.sp,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),

          // ── Subject ────────────────────────────────────────────────
          Text(
            enquiry.subject,
            style: GoogleFonts.playfairDisplay(
              fontSize: 15.sp,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : const Color(0xFF1A2332),
            ),
          ),

          // ── Type tag (if available) ────────────────────────────────
          if (enquiry.type.isNotEmpty) ...[
            SizedBox(height: 6.h),
            Row(
              children: [
                Icon(Icons.label_outline_rounded,
                    size: 12.sp,
                    color: isDark ? Colors.white38 : Colors.black38),
                SizedBox(width: 4.w),
                Text(
                  enquiry.type,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    color: isDark ? Colors.white38 : Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],

          // ── Ticket ID ──────────────────────────────────────────────
          if (enquiry.enquiryId.isNotEmpty) ...[
            SizedBox(height: 8.h),
            NumericStyledText(
              'Ticket #${enquiry.enquiryId}',
              fontSize: 11.sp,
              color: isDark ? Colors.white24 : Colors.black26,
              fontWeight: FontWeight.w600,
            ),
          ],
        ],
      ),
    );
  }
}
