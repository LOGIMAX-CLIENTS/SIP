import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_router.dart';
import '../models/countdown_offer_model.dart';

/// Existing Customer UI for the 100-Day Grand Launch Countdown Offer.
///
/// Displays the customer's progress — silver earned, invest days,
/// days remaining, current reward percentage — and a CTA to add investment.
/// Matches Figma Design 1 from the implementation plan.
///
/// Font strategy:
///   • Text content → PlayfairDisplay
///   • Numeric values → Lora
class CountdownOfferExisting extends StatelessWidget {
  final ExistingCustomerOffer offer;

  const CountdownOfferExisting({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24.r),
            bottomRight: Radius.circular(24.r),
          ),
          gradient: const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xFFFFC752),
              Color(0x80FFE7B1),
              Color(0xCCFFF0CB),
              Color(0xFFFFF0CB),
            ],
            stops: [0.0, 0.39, 0.70, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFE78400).withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            SizedBox(height: 16.h),

            // ── Green Ribbon Banner ──
            _buildBadgeBanner(),

            // ── Green Progress Card ──
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 20.h),
              child: _buildProgressCard(context),
            ),
          ],
        ),
    );
  }

  /// Splits a string into alternating text and number segments.
  List<String> _splitTextAndNumbers(String input) {
    final regex = RegExp(r'(\d+)');
    final parts = <String>[];
    int lastEnd = 0;
    for (final match in regex.allMatches(input)) {
      if (match.start > lastEnd) {
        parts.add(input.substring(lastEnd, match.start));
      }
      parts.add(match.group(0)!);
      lastEnd = match.end;
    }
    if (lastEnd < input.length) {
      parts.add(input.substring(lastEnd));
    }
    return parts;
  }

  Widget _buildBadgeBanner() {
    final parts = _splitTextAndNumbers(offer.offerName.toUpperCase());

    return Stack(
      alignment: Alignment.center,
      children: [
        // Green ribbon background image
        Image.asset(
          'assets/offer/title-bgbar.png',
          width: 300.w,
          fit: BoxFit.contain,
        ),
        // Text overlay — gold gradient via ShaderMask
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment(-0.98, -0.19),
            end: Alignment(0.98, 0.19),
            colors: [Color(0xFFFFB500), Color(0xFFFFCA49)],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/offer/lightning.png',
                width: 20.w,
                height: 28.h,
                color: Colors.white,
              ),
              SizedBox(width: 6.w),
              Text(
                offer.offerName.toUpperCase(),
                style: GoogleFonts.lora(
                  fontSize: 15.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(BuildContext context) {
    // Outer container = gold gradient border
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(2.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22.r),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFEF9B00),
            Color(0xFFF5AC03),
            Color(0xFFFF9D00),
            Color(0xFFF8C30D),
            Color(0xFFF5A702),
            Color(0xFFE78400),
          ],
          stops: [0.11, 0.26, 0.40, 0.67, 0.94, 1.0],
        ),
      ),
      // Inner container = green card
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: 24.h, horizontal: 20.w),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20.r),
          gradient: const LinearGradient(
            begin: Alignment(-0.87, -0.5),
            end: Alignment(0.87, 0.5),
            colors: [Color(0xFF003716), Color(0xFF167525)],
            stops: [0.0223, 0.9399],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B4D2E).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
      child: Column(
        children: [
          // ── Silver Earned ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/offer/tick-shield.png',
                height: 20.h,
                width: 20.w,
                fit: BoxFit.contain,
              ),
              SizedBox(width: 8.w),
              Text(
                'Silver Earned',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Text(
            '${offer.silverEarned} gm',
            style: GoogleFonts.lora(
              fontSize: 28.sp,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFE8B923),
            ),
          ),
          SizedBox(height: 24.h),

          // ── Invest Days + Days Remaining ──
          Row(
            children: [
              Expanded(
                child: _buildStatColumn(
                  'Invest Days',
                  '${offer.investDays} days',
                ),
              ),
              Container(
                width: 1,
                height: 48.h,
                color: Colors.white.withValues(alpha: 0.15),
              ),
              Expanded(
                child: _buildStatColumn(
                  'Days Remaining',
                  '${offer.daysRemaining}',
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // ── Reward Percentage Message ──
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
              ),
              children: [
                const TextSpan(text: 'You have received a '),
                TextSpan(
                  text: '${offer.currentRewardPercentage}%',
                  style: GoogleFonts.lora(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE8B923),
                  ),
                ),
                const TextSpan(text: ' offer'),
              ],
            ),
          ),
          SizedBox(height: 4.h),
          Builder(builder: (_) {
            final dateStr = 'till ${offer.offerEndDate}';
            final parts = _splitTextAndNumbers(dateStr);
            final numberRegex = RegExp(r'^\d+$');
            return RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                children: parts.map((part) {
                  final isNumber = numberRegex.hasMatch(part);
                  return TextSpan(
                    text: part,
                    style: isNumber
                        ? GoogleFonts.lora(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          )
                        : GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                          ),
                  );
                }).toList(),
              ),
            );
          }),
          SizedBox(height: 24.h),

          // ── CTA Button ──
          _buildCtaButton(context),
        ],
      ),
      ),  // outer border Container
    );
  }

  Widget _buildStatColumn(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.playfairDisplay(
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
        SizedBox(height: 6.h),
        Text(
          value,
          style: GoogleFonts.lora(
            fontSize: 22.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE8B923),
          ),
        ),
      ],
    );
  }

  Widget _buildCtaButton(BuildContext context) {
    return Container(
      width: 308.w,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFFB500), Color(0xFFFFCA49)],
        ),
        borderRadius: BorderRadius.circular(50.r),
      ),
      child: ElevatedButton(
        onPressed: () {
          Navigator.pushNamed(context, AppRouter.instantSaving);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: const Color(0xFF064E3B),
          elevation: 0,
          minimumSize: Size(308.w, 42.h),
          padding: EdgeInsets.symmetric(horizontal: 26.w),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50.r),
          ),
        ),
        child: Text(
          offer.ctaText,
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF064E3B),
          ),
        ),
      ),
    );
  }
}
