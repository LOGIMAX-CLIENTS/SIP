import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_text_styles.dart';

import '../../../routes/app_router.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/animations.dart';

class RegistrationSuccessScreen extends ConsumerWidget {
  final String fullName;

  const RegistrationSuccessScreen({
    super.key,
    required this.fullName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? Colors.white : const Color(0xFF2D2D2D);
    final accentGreen = const Color(0xFF064E3B);
    final secondaryTextColor =
        isDark ? Colors.white60 : const Color(0xFF555555);

    // Extract first name for the greeting
    final firstName = fullName.split(' ').first;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              // ── Main Content ───────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32.w),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Spacer(flex: 2),

                      // Logo Image
                      FadeInAnimation(
                        delay: const Duration(milliseconds: 100),
                        child: Center(
                          child: SvgPicture.asset(
                            'assets/images/startGold.svg',
                            height: 120.h,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),

                      SizedBox(height: 12.h),

                      // // "startGOLD" Brand Wordmark
                      // FadeInAnimation(
                      //   delay: const Duration(milliseconds: 200),
                      //   child: RichText(
                      //     text: TextSpan(
                      //       children: [
                      //         TextSpan(
                      //           text: 'start',
                      //           style: GoogleFonts.playfairDisplay(
                      //             fontSize: 20.sp,
                      //             fontWeight: FontWeight.w600,
                      //             foreground: Paint()
                      //               ..shader = const LinearGradient(
                      //                 begin: Alignment.topCenter,
                      //                 end: Alignment.bottomCenter,
                      //                 colors: [
                      //                   Color(0xFF49B44B),
                      //                   Color(0xFF1A6F2D),
                      //                 ],
                      //               ).createShader(
                      //                 const Rect.fromLTWH(0, 0, 60, 30),
                      //               ),
                      //           ),
                      //         ),
                      //         TextSpan(
                      //           text: 'GOLD',
                      //           style: GoogleFonts.playfairDisplay(
                      //             fontSize: 20.sp,
                      //             fontWeight: FontWeight.w800,
                      //             foreground: Paint()
                      //               ..shader = const LinearGradient(
                      //                 begin: Alignment.topCenter,
                      //                 end: Alignment.bottomCenter,
                      //                 colors: [
                      //                   Color(0xFFFFB941),
                      //                   Color(0xFFE27903),
                      //                 ],
                      //               ).createShader(
                      //                 const Rect.fromLTWH(0, 0, 80, 30),
                      //               ),
                      //           ),
                      //         ),
                      //       ],
                      //     ),
                      //   ),
                      // ),

                      SizedBox(height: 48.h),

                      // Greeting Heading
                      FadeInAnimation(
                        delay: const Duration(milliseconds: 350),
                        child: Text(
                          'Hi $firstName!',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 26.sp,
                            fontWeight: FontWeight.bold,
                            color: primaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),

                      SizedBox(height: 14.h),

                      // Subheading
                      FadeInAnimation(
                        delay: const Duration(milliseconds: 500),
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 16.sp,
                              color: secondaryTextColor,
                              height: 1.6,
                            ),
                            children: [
                              const TextSpan(
                                  text:
                                      'Your golden future starts smart \nwith '),
                              TextSpan(
                                text: 'startGOLD',
                                style: GoogleFonts.playfairDisplay(
                                  color: accentGreen,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const Spacer(flex: 3),
                    ],
                  ),
                ),
              ),

              // ── Pinned Footer ──────────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 12.h),
                child: FadeInAnimation(
                  delay: const Duration(milliseconds: 700),
                  child: CustomButton(
                    text: 'Get Started',
                    svgIconPath: 'assets/buttons/getstart.svg',
                    onPressed: () => Navigator.pushNamedAndRemoveUntil(
                      context,
                      AppRouter.home,
                      (route) => false,
                    ),
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Color(0xFF1B882C), Color(0xFF003716)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8F4C05).withOpacity(0.06),
                        offset: const Offset(0, 4),
                        blurRadius: 10,
                      ),
                    ],
                    textColor: Colors.white,
                  ),
                ),
              ),

              // "Powered by: startGOLD" Footer
              FadeInAnimation(
                delay: const Duration(milliseconds: 900),
                child: Padding(
                  padding: EdgeInsets.only(bottom: 20.h),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Powered by: ',
                          style: AppTextStyles.labelMedium(isDark).copyWith(
                            color: isDark
                                ? Colors.white38
                                : const Color(0xFF888888),
                          ),
                        ),
                        TextSpan(
                          text: 'start',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFF49B44B),
                                  Color(0xFF1A6F2D),
                                ],
                              ).createShader(
                                const Rect.fromLTWH(0, 0, 30, 16),
                              ),
                          ),
                        ),
                        TextSpan(
                          text: 'GOLD',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w800,
                            foreground: Paint()
                              ..shader = const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Color(0xFFFFB941),
                                  Color(0xFFE27903),
                                ],
                              ).createShader(
                                const Rect.fromLTWH(0, 0, 50, 16),
                              ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
