import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// White card row with a tinted SVG icon tile, title and trailing arrow —
/// the menu row used on Profile and on Legal, so both pages look the same.
class MenuTile extends StatelessWidget {
  final String title;
  final String iconPath;
  final VoidCallback onTap;
  final bool isDestructive;

  /// Replaces the default arrow (e.g. Profile's KYC progress badge).
  final Widget? trailing;

  const MenuTile({
    super.key,
    required this.title,
    required this.iconPath,
    required this.onTap,
    this.isDestructive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  padding: EdgeInsets.all(10.w),
                  decoration: BoxDecoration(
                    color: (isDestructive ? Colors.red : const Color(0xFF0E5723))
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: SvgPicture.asset(
                    iconPath,
                    colorFilter: ColorFilter.mode(
                        isDestructive ? Colors.red : const Color(0xFF0E5723),
                        BlendMode.srcIn),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color:
                          isDestructive ? Colors.red : const Color(0xFF4B5563),
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20.sp,
                      color: Colors.black26,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
