import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../core/utils/navigation_utils.dart';
import '../theme/app_text_styles.dart';

/// Reusable green-gradient page header matching the app-wide design system.
///
/// Usage:
/// ```dart
/// GradientHeader(title: 'Account Details')
/// ```
class GradientHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  /// Optional widgets placed in the trailing slot (right side of the header).
  final Widget? trailing;

  const GradientHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
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
      decoration: const BoxDecoration(
        gradient: _kGradient,
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8.w, 4.h, 16.w, 12.h),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20.sp),
                onPressed: onBack ?? () => NavigationUtils.safePop(context),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.left,
                  style: AppTextStyles.titleMedium(false)
                      .copyWith(color: Colors.white),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
