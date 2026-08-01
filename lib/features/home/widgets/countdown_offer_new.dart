import 'dart:async';
import 'package:flutter/material.dart';

import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../routes/app_router.dart';
import '../models/countdown_offer_model.dart';
import 'offer_webview_screen.dart';

/// New Customer UI for the 100-Day Grand Launch Countdown Offer.
///
/// Displays a countdown timer, reward details, and a CTA to start investing.
/// Matches Figma Design 2 from the implementation plan.
///
/// Font strategy:
///   Ã¢â‚¬Â¢ Text content Ã¢â€ â€™ PlayfairDisplay
///   Ã¢â‚¬Â¢ Numeric values Ã¢â€ â€™ Lora
class CountdownOfferNew extends StatefulWidget {
  final NewCustomerOffer offer;

  const CountdownOfferNew({
    super.key,
    required this.offer,
  });

  @override
  State<CountdownOfferNew> createState() => _CountdownOfferNewState();
}

class _CountdownOfferNewState extends State<CountdownOfferNew> {
  late int _days;
  late int _hours;
  late int _minutes;
  late int _seconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _days = widget.offer.remainingDays;
    _hours = widget.offer.remainingHours;
    _minutes = widget.offer.remainingMinutes;
    _seconds = widget.offer.remainingSeconds;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_seconds > 0) {
          _seconds--;
        } else if (_minutes > 0) {
          _minutes--;
          _seconds = 59;
        } else if (_hours > 0) {
          _hours--;
          _minutes = 59;
          _seconds = 59;
        } else if (_days > 0) {
          _days--;
          _hours = 23;
          _minutes = 59;
          _seconds = 59;
        } else {
          _timer?.cancel();
        }
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isExpired =>
      _days == 0 && _hours == 0 && _minutes == 0 && _seconds == 0;

  /// Splits a string into alternating text and number segments.
  /// Example: "100-DAY GRAND LAUNCH" Ã¢â€ â€™ ["100", "-DAY GRAND LAUNCH"]
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

  @override
  Widget build(BuildContext context) {
    if (_isExpired) return const SizedBox.shrink();

    return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          // Only bottom corners rounded Ã¢â‚¬â€ top sits flush under green header
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(24.r),
            bottomRight: Radius.circular(24.r),
          ),
          // Card background Ã¢â‚¬â€ bottom-to-top gold gradient
          gradient: const LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Color(0xFFFFC752),       // bottom
              Color(0x80FFE7B1),       // 60.98% Ã¢â‚¬â€ rgba(255,231,177,0.5)
              Color(0xCCFFF0CB),       // 29.76% Ã¢â‚¬â€ rgba(255,240,203,0.8)
              Color(0xFFFFF0CB),       // top
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
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(height: 16.h),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Green Ribbon Banner (title-bgbar.png) Ã¢â€â‚¬Ã¢â€â‚¬
            _buildBadgeBanner(),
            SizedBox(height: 14.h),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Date Range with decorative gradient lines Ã¢â€â‚¬Ã¢â€â‚¬
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Left gradient line (fades from left)
                Container(
                  width: 56.w,
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFFFF1CF), Color(0xFFDE6A02)],
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                // Date text
                Builder(builder: (_) {
                  final dateParts = _splitTextAndNumbers(
                    '${widget.offer.offerStartDate} \u2013 ${widget.offer.offerEndDate}',
                  );
                  return RichText(
                    text: TextSpan(
                      children: dateParts.map((part) {
                        final isNum = RegExp(r'^\d+$').hasMatch(part);
                        return TextSpan(
                          text: part,
                          style: isNum
                              ? GoogleFonts.lora(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFDE6A02),
                                  letterSpacing: 0.8,
                                )
                              : GoogleFonts.playfairDisplay(
                                  fontSize: 18.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFDE6A02),
                                  letterSpacing: 0.8,
                                ),
                        );
                      }).toList(),
                    ),
                  );
                }),
                SizedBox(width: 12.w),
                // Right gradient line (fades to right)
                Container(
                  width: 56.w,
                  height: 1,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFDE6A02), Color(0xFFFFF1CF)],
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16.h),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Countdown Timer Card Ã¢â€â‚¬Ã¢â€â‚¬
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: _buildCountdownCard(),
            ),
            SizedBox(height: 24.h),

            // Ã¢â€â‚¬Ã¢â€â‚¬ Offer Description + Bullets | Gold/Silver Image Ã¢â€â‚¬Ã¢â€â‚¬
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Ã¢â€â‚¬Ã¢â€â‚¬ Column 1: Description + Separator + Bullets Ã¢â€â‚¬Ã¢â€â‚¬
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOfferDescription(),
                        SizedBox(height: 16.h),
                        // Vector line separator
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 185.w,
                            height: 0.8,
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFDE6A02), Color(0xFFFFF1CF)],
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 20.h),
                        _buildBulletSection(),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  // Ã¢â€â‚¬Ã¢â€â‚¬ Column 2: Gold/Silver Image + Know More Ã¢â€â‚¬Ã¢â€â‚¬
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        Image.asset(
                          'assets/offer/gold-silver-offer.png',
                          fit: BoxFit.contain,
                        ),
                        SizedBox(height: 12.h),
                        GestureDetector(
                          onTap: () => _showOfferBenefitsSheet(context),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Know more',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF003716),
                                  decoration: TextDecoration.underline,
                                  decorationColor: const Color(0xFF003716),
                                ),
                              ),
                              SizedBox(width: 4.w),
                              Padding(
                                padding: EdgeInsets.only(top: 3.h),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 14.sp,
                                  color: const Color(0xFF003716),
                                ),
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
            SizedBox(height: 24.h),

            // Ã¢â€â‚¬Ã¢â€â‚¬ CTA Button Ã¢â€â‚¬Ã¢â€â‚¬
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 40.w),
              child: _buildCtaButton(),
            ),
            SizedBox(height: 20.h),
          ],
        ),
    );
  }

  Widget _buildBadgeBanner() {

    return Stack(
      alignment: Alignment.center,
      children: [
        // Green ribbon background image
        Image.asset(
          'assets/offer/title-bgbar.png',
          width: 340.w,
          fit: BoxFit.contain,
        ),
        // Text overlay Ã¢â‚¬â€ gold gradient via ShaderMask
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            begin: Alignment(-0.98, -0.19),
            end: Alignment(0.98, 0.19),
            colors: [Color(0xFFFFB500), Color(0xFFFFCA49)],
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text(
            widget.offer.offerName.toUpperCase(),
            style: GoogleFonts.playfairDisplay(
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Dark green countdown card with stopwatch SVG Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _buildCountdownCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 16.w),
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
            color: const Color(0xFF1B4D2E).withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          // Ã¢â€â‚¬Ã¢â€â‚¬ Timer section Ã¢â€â‚¬Ã¢â€â‚¬
          Expanded(
            child: Column(
              children: [
                Text(
                  'Offer Ends in',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xE5FFFFFF),
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    _buildTimeUnit(
                      _days.toString().padLeft(2, '0'),
                      'Days',
                    ),
                    _buildTimeSeparator(),
                    _buildTimeUnit(
                      _hours.toString().padLeft(2, '0'),
                      'Hrs',
                    ),
                    _buildTimeSeparator(),
                    _buildTimeUnit(
                      _minutes.toString().padLeft(2, '0'),
                      'Min',
                    ),
                    _buildTimeSeparator(),
                    _buildTimeUnit(
                      _seconds.toString().padLeft(2, '0'),
                      'Sec',
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Ã¢â€â‚¬Ã¢â€â‚¬ Divider + Stopwatch SVG Ã¢â€â‚¬Ã¢â€â‚¬
          Container(
            width: 1,
            height: 60.h,
            margin: EdgeInsets.symmetric(horizontal: 8.w),
            color: Colors.white.withValues(alpha: 0.2),
          ),
          Image.asset(
            'assets/offer/countdown-watch.png',
            width: 55.w,
            height: 60.h,
            fit: BoxFit.contain,
          ),
        ],
      ),
    );
  }

  Widget _buildTimeUnit(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment(-0.98, -0.19),
              end: Alignment(0.98, 0.19),
              colors: [Color(0xFFFFB500), Color(0xFFFFCA49)],
            ).createShader(bounds),
            blendMode: BlendMode.srcIn,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: GoogleFonts.lora(
                fontSize: 32.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 11.sp,
              fontWeight: FontWeight.w400,
              color: const Color(0xE5FFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSeparator() {
    return Padding(
      padding: EdgeInsets.only(bottom: 18.h),
      child: ShaderMask(
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment(-0.98, -0.19),
          end: Alignment(0.98, 0.19),
          colors: [Color(0xFFFFB500), Color(0xFFFFCA49)],
        ).createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: Text(
          ':',
          style: GoogleFonts.lora(
            fontSize: 28.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  // ── Offer description — driven by API fields ──
  Widget _buildOfferDescription() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.offer.descriptionTitle,
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xCC010101),
          ),
        ),
        SizedBox(height: 4.h),
        Text(
          widget.offer.descriptionBody,
          style: GoogleFonts.playfairDisplay(
            fontSize: 20.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFDE6A02),
            height: 26 / 20,
          ),
        ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ Bullets + Know more Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _buildBulletSection() {
    return Column(
      children: [
        // Bullet 1 Ã¢â‚¬â€ Reward
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/offer/tick-shield.png',
              width: 40.w,
              height: 40.h,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1B4D2E).withValues(alpha: 0.9),
                    height: 19 / 13,
                  ),
                  children: [
                    const TextSpan(text: 'Lock in your '),
                    TextSpan(
                      text: '${widget.offer.rewardPercentage}%',
                      style: GoogleFonts.lora(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFDE6A02),
                        height: 19 / 13,
                      ),
                    ),
                    const TextSpan(
                      text:
                          ' reward\nfrom Day 1 and enjoy the\nsame benefit every day. Till\nend of the offer.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 14.h),

        // Bullet 2 Ã¢â‚¬â€ Penalty + Know more
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              'assets/offer/ratehistory.png',
              width: 40.w,
              height: 40.h,
              fit: BoxFit.contain,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF1B4D2E).withValues(alpha: 0.9),
                    height: 19 / 13,
                  ),
                  children: [
                    TextSpan(
                      text: 'Miss a day? ',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFDE6A02),
                        height: 19 / 13,
                      ),
                    ),
                    const TextSpan(text: 'Your reward\ndrops by '),
                    TextSpan(
                      text: '${widget.offer.dailyPenaltyPercentage}%',
                      style: GoogleFonts.lora(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFDE6A02),
                        height: 19 / 13,
                      ),
                    ),
                    const TextSpan(
                      text: ' starting from\nthe next day.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Ã¢â€â‚¬Ã¢â€â‚¬ "Start Investing" green gradient CTA Ã¢â€â‚¬Ã¢â€â‚¬
  Widget _buildCtaButton() {
    return SizedBox(
      height: 40.h,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1B882C), Color(0xFF003716)],
          ),
          borderRadius: BorderRadius.circular(50.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1B882C).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () {
            Navigator.pushNamed(context, AppRouter.instantSaving);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.symmetric(vertical: 0, horizontal: 28.w),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: Size.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(50.r),
            ),
          ),
          child: Text(
            widget.offer.ctaText,
            style: GoogleFonts.playfairDisplay(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // -- "Know more" → navigates to WebView offer benefits page --
  void _showOfferBenefitsSheet(BuildContext context) {
    final url = widget.offer.webviewUrl;
    if (url == null || url.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OfferWebViewScreen(url: url),
      ),
    );
  }
}
