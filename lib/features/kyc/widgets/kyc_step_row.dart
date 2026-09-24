import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

enum KycStepStatus { locked, actionable, inProgress, underReview, verified, failed }

/// One collapsible row in [KycVerificationScreen]'s checklist — leading
/// status circle, title/subtitle, trailing status pill, expandable body.
/// Mirrors the app's existing menu-item/card conventions (white card,
/// 15-20.r radius, faint border+shadow — see profile_screen.dart's
/// `_buildMenuItem`) rather than the mockup's raw colors.
class KycStepRow extends StatelessWidget {
  final int index;
  final String title;
  final String subtitle;
  final KycStepStatus status;
  final String pillLabel;
  final bool expanded;
  final VoidCallback? onToggle;
  final Widget? detail;
  final String? lockedHint;

  const KycStepRow({
    super.key,
    required this.index,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.pillLabel,
    required this.expanded,
    this.onToggle,
    this.detail,
    this.lockedHint,
  });

  Color get _accentColor {
    switch (status) {
      case KycStepStatus.verified:
        return const Color(0xFF0E5723);
      case KycStepStatus.failed:
        return const Color(0xFFDC2626);
      case KycStepStatus.inProgress:
        return const Color(0xFF2563EB);
      case KycStepStatus.underReview:
        return const Color(0xFF2563EB);
      case KycStepStatus.actionable:
        return const Color(0xFF0E5723);
      case KycStepStatus.locked:
        return Colors.grey;
    }
  }

  Widget _buildLeading() {
    final isLocked = status == KycStepStatus.locked;
    final isVerified = status == KycStepStatus.verified;
    return Container(
      width: 36.r,
      height: 36.r,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isVerified ? _accentColor : _accentColor.withOpacity(0.1),
        border: isVerified ? null : Border.all(color: _accentColor.withOpacity(0.4)),
      ),
      alignment: Alignment.center,
      child: isVerified
          ? Icon(Icons.check, color: Colors.white, size: 18.sp)
          : isLocked
              ? Icon(Icons.lock_outline_rounded, color: _accentColor, size: 16.sp)
              : Text(
                  '$index',
                  style: GoogleFonts.lora(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: _accentColor,
                  ),
                ),
    );
  }

  Widget _buildPill(bool isDark) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(100.r),
      ),
      child: Text(
        pillLabel.toUpperCase(),
        style: GoogleFonts.playfairDisplay(
          fontSize: 10.sp,
          fontWeight: FontWeight.w800,
          color: _accentColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLocked = status == KycStepStatus.locked;

    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F26) : Colors.white,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: isLocked ? null : onToggle,
            borderRadius: BorderRadius.circular(18.r),
            child: Padding(
              padding: EdgeInsets.all(16.r),
              child: Row(
                children: [
                  _buildLeading(),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: AppTextStyles.bodyLarge(isDark).copyWith(fontWeight: FontWeight.w700)),
                        SizedBox(height: 2.h),
                        Text(
                          isLocked && lockedHint != null ? lockedHint! : subtitle,
                          style: AppTextStyles.bodySmall(isDark),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  _buildPill(isDark),
                ],
              ),
            ),
          ),
          if (expanded && detail != null && !isLocked)
            Padding(
              padding: EdgeInsets.fromLTRB(16.r, 0, 16.r, 16.r),
              child: detail!,
            ),
        ],
      ),
    );
  }
}

/// Shared "Verified" summary card — same visual language as the live KYC
/// screen's `_buildVerifiedBanner` (kyc_screen.dart) so PAN/Aadhaar/Bank
/// verified rows read identically to the rest of the app.
class KycVerifiedBanner extends StatelessWidget {
  final String? numberLabel;
  final String? maskedValue;
  final String? nameLabel;
  final String? verifiedName;
  final VoidCallback? onEdit;
  final bool? linkedToAadhaar;

  const KycVerifiedBanner({
    super.key,
    this.numberLabel,
    this.maskedValue,
    this.nameLabel,
    this.verifiedName,
    this.onEdit,
    this.linkedToAadhaar,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = const Color(0xFF0E5723).withOpacity(0.65);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF0E5723).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFF0E5723).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded, color: const Color(0xFF0E5723), size: 16.sp),
              SizedBox(width: 8.w),
              Text(
                'Verified',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0E5723),
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined, size: 14.sp, color: const Color(0xFF0E5723)),
                        SizedBox(width: 4.w),
                        Text(
                          'Edit',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0E5723),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (maskedValue != null && maskedValue!.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Text(numberLabel ?? 'Number',
                style: GoogleFonts.playfairDisplay(fontSize: 11.sp, color: labelColor, fontWeight: FontWeight.w600)),
            SizedBox(height: 2.h),
            Text(maskedValue!,
                style: GoogleFonts.lora(fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.black87)),
          ],
          if (verifiedName != null && verifiedName!.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(nameLabel ?? 'Name',
                style: GoogleFonts.playfairDisplay(fontSize: 11.sp, color: labelColor, fontWeight: FontWeight.w600)),
            SizedBox(height: 2.h),
            Text(verifiedName!,
                style: GoogleFonts.playfairDisplay(fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.black87)),
          ],
          if (linkedToAadhaar != null) ...[
            SizedBox(height: 10.h),
            Row(
              children: [
                Icon(
                  linkedToAadhaar! ? Icons.link_rounded : Icons.link_off_rounded,
                  size: 14.sp,
                  color: linkedToAadhaar! ? const Color(0xFF0E5723) : Colors.orange[800],
                ),
                SizedBox(width: 6.w),
                Text(
                  linkedToAadhaar! ? 'Linked to your Aadhaar' : 'Not linked to your Aadhaar',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: linkedToAadhaar! ? const Color(0xFF0E5723) : Colors.orange[800],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
