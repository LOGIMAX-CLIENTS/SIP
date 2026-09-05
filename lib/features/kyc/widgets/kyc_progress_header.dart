import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:startgold/core/utils/navigation_utils.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

/// Hero header for [KycVerificationScreen] — same green diagonal gradient as
/// [GradientHeader] (shared/widgets/gradient_header.dart), extended with a
/// rounded bottom edge and a circular "N/total DONE" progress ring, matching
/// the merged KYC checklist mockup's header.
class KycProgressHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final int completed;
  final int total;
  final VoidCallback? onBack;

  const KycProgressHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.completed,
    required this.total,
    this.onBack,
  });

  static const _kGradient = LinearGradient(
    begin: Alignment(-0.87, -0.5),
    end: Alignment(0.87, 0.5),
    colors: [Color(0xFF003716), Color(0xFF167525)],
    stops: [0.0223, 0.9399],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: _kGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32.r),
          bottomRight: Radius.circular(32.r),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8.w, 4.h, 20.w, 20.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20.sp),
                    onPressed: onBack ?? () => NavigationUtils.safePop(context),
                  ),
                  Text(
                    'KYC Verification',
                    style: AppTextStyles.titleMedium(false)
                        .copyWith(color: Colors.white),
                  ),
                ],
              ),
              SizedBox(height: 8.h),
              Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildRing(),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: AppTextStyles.titleLarge(false)
                                .copyWith(color: Colors.white),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            subtitle,
                            style: AppTextStyles.bodyMedium(false)
                                .copyWith(color: Colors.white.withOpacity(0.85)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRing() {
    final value = total == 0 ? 0.0 : completed / total;
    return SizedBox(
      width: 56.r,
      height: 56.r,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56.r,
            height: 56.r,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 4.r,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white.withOpacity(0.22)),
            ),
          ),
          SizedBox(
            width: 56.r,
            height: 56.r,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 4.r,
              backgroundColor: Colors.transparent,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFDE047)),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$completed/$total',
                style: AppTextStyles.numericSmall(false).copyWith(color: Colors.white),
              ),
              Text(
                'DONE',
                style: AppTextStyles.labelSmall(false).copyWith(
                  color: const Color(0xFFFDE047),
                  fontSize: 8.sp,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
