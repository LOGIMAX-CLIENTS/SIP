import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/gradient_header.dart';
import '../../shared/theme/app_theme.dart';
import 'jewellery_service.dart';

// ── Provider ────────────────────────────────────────────────────────────
final jewelleryImagesProvider = FutureProvider.autoDispose<List<String>>((ref) {
  return JewelleryService().getJewelleryImages();
});

/// Jewellery "Coming Soon" screen.
///
/// Navigated to from the Jewellery tab in the bottom nav.
/// Fetches card images dynamically from the API (`POST /jewellery/jewellery-image`).
/// The API response images contain all visual content — this screen just displays them.
class JewelleryScreen extends ConsumerWidget {
  const JewelleryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imagesAsync = ref.watch(jewelleryImagesProvider);

    return Scaffold(
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(horizontal: 20.w),
        height: 52.h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: AppTheme.greenGradient,
            borderRadius: BorderRadius.circular(100.r),
            boxShadow: [
              BoxShadow(
                color: AppTheme.buttonShadow,
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ElevatedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.home_rounded, size: 20.sp),
            label: Text(
              'Back to Home',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(100.r),
              ),
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Column(
          children: [
            // ── Header ──
            GradientHeader(title: 'Jewellery'),

            // ── Body ──
            Expanded(
              child: imagesAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryGreen),
                  ),
                ),
                error: (error, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(24.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48.sp, color: Colors.red.shade300),
                        SizedBox(height: 12.h),
                        Text(
                          'Failed to load jewellery data',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        SizedBox(height: 16.h),
                        TextButton.icon(
                          onPressed: () => ref.invalidate(jewelleryImagesProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (imageUrls) => SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 100.h),
                  child: Column(
                    children: [
                      // ── Hero Section ──
                      _buildHeroSection(isDark),
                      SizedBox(height: 28.h),

                      // ── Images from API ──
                      for (int i = 0; i < imageUrls.length; i++)
                        Padding(
                          padding: EdgeInsets.only(bottom: 20.h),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(40.r),
                            child: Image.network(
                              imageUrls[i],
                              width: double.infinity,
                              height: 350.h,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  height: 200.h,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? const Color(0xFF2A2A2A)
                                        : const Color(0xFFF5F0E6),
                                    borderRadius: BorderRadius.circular(40.r),
                                  ),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      value: loadingProgress.expectedTotalBytes != null
                                          ? loadingProgress.cumulativeBytesLoaded /
                                              loadingProgress.expectedTotalBytes!
                                          : null,
                                      valueColor: const AlwaysStoppedAnimation<Color>(
                                        AppTheme.primaryGreen,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              errorBuilder: (_, __, ___) => Container(
                                height: 200.h,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF2A2A2A)
                                      : const Color(0xFFF5F0E6),
                                  borderRadius: BorderRadius.circular(40.r),
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.diamond_rounded,
                                    size: 48.sp,
                                    color: isDark ? Colors.white24 : Colors.black12,
                                  ),
                                ),
                              ),
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
    );
  }

  // ── Hero Section ──────────────────────────────────────────────────────
  Widget _buildHeroSection(bool isDark) {
    return Column(
      children: [
        // "Stay Tuned...!"
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Stay ',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF024E1C),
                ),
              ),
              TextSpan(
                text: 'Tuned...!',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 28.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFDE6A02),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10.h),

        // Bottom line decoration
        Image.asset(
          'assets/images/jewellery-bottomline.png',
          width: 120.w,
          fit: BoxFit.contain,
        ),
        SizedBox(height: 14.h),

        // "Right Route for"
        Text(
          'Right Route for',
          style: GoogleFonts.playfairDisplay(
            fontSize: 14.sp,
            fontWeight: FontWeight.w500,
            color: isDark
                ? Colors.white70
                : const Color(0xFF010101).withOpacity(0.8),
          ),
        ),
        SizedBox(height: 6.h),

        // "Bright Jewellery Solutions"
        RichText(
          textAlign: TextAlign.center,
          text: TextSpan(
            children: [
              TextSpan(
                text: 'Bright Jewellery\n',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF024E1C),
                  height: 1.4,
                ),
              ),
              TextSpan(
                text: 'Solutions',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFDE6A02),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
