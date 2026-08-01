import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_text_styles.dart';

/// Premium fintech action button with gradient support and in-button loading.
///
/// When [isLoading] is true the button stays fully visible but disabled,
/// the label fades out and a "Processing…" label + small spinner fades in
/// with a smooth cross-fade transition.
///
/// [svgIconPath] — optional path to an SVG icon rendered to the left of text.
class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final String? loadingText;
  final Color? backgroundColor;
  final Color? textColor;
  final Gradient? gradient;
  final List<BoxShadow>? boxShadow;
  final String? svgIconPath;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.loadingText,
    this.backgroundColor,
    this.textColor,
    this.gradient,
    this.boxShadow,
    this.svgIconPath,
  });

  /// Acronym-aware Title Case: "confirm order" → "Confirm Order"
  /// Preserves known acronyms like OTP, PIN, MPIN, UPI, KYC, GST, SIP, ID.
  static const _acronyms = {'OTP', 'PIN', 'MPIN', 'UPI', 'KYC', 'GST', 'SIP', 'ID'};

  static String _toTitleCase(String input) {
    if (input.isEmpty) return input;
    return input
        .split(' ')
        .map((word) {
          if (word.isEmpty) return '';
          final upper = word.toUpperCase();
          if (_acronyms.contains(upper)) return upper;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBg = backgroundColor ?? Theme.of(context).primaryColor;
    final effectiveColor = textColor ?? Colors.white;
    final displayLoadingText = loadingText ?? 'Processing...';

    final button = SizedBox(
      width: double.infinity,
      height: 56.h,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: gradient != null ? Colors.transparent : effectiveBg,
          disabledBackgroundColor:
              gradient != null ? Colors.transparent : effectiveBg.withOpacity(0.5),
          foregroundColor: effectiveColor,
          disabledForegroundColor: effectiveColor.withOpacity(0.8),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50.r),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: isLoading
              ? Row(
                  key: const ValueKey('loading'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 18.h,
                      height: 18.h,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(effectiveColor.withOpacity(0.9)),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Text(
                      displayLoadingText,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                        color: effectiveColor.withOpacity(0.9),
                      ),
                    ),
                  ],
                )
              : Row(
                  key: const ValueKey('label'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (svgIconPath != null) ...[
                      SvgPicture.asset(
                        svgIconPath!,
                        width: 20.w,
                        height: 20.w,
                        colorFilter: ColorFilter.mode(
                          effectiveColor,
                          BlendMode.srcIn,
                        ),
                      ),
                      SizedBox(width: 8.w),
                    ],
                    Text(
                      _toTitleCase(text),
                      style: AppTextStyles.button(isDark).copyWith(
                        letterSpacing: 0.5,
                        color: effectiveColor,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );

    if (gradient == null) return button;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      width: double.infinity,
      height: 56.h,
      decoration: BoxDecoration(
        gradient: isLoading
            ? gradient!.scale(0.7)
            : (onPressed != null ? gradient : gradient!.scale(0.5)),
        borderRadius: BorderRadius.circular(50.r),
        boxShadow: isLoading ? [] : boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(50.r),
        child: button,
      ),
    );
  }
}
