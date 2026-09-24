import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/models/app_control_model.dart';
import '../../core/providers/app_control_provider.dart';
import '../../shared/theme/app_text_styles.dart';

/// Full-screen maintenance mode gate.
///
/// Behaviour:
///   • No AppBar / back button
///   • Hardware back press → exit app (Android) / no-op (iOS)
///   • Periodically retries backend. If maintenance lifts, routes to [resumeRoute]
///   • All content (title / subtitle / expected resume time) comes from backend
class MaintenanceScreen extends ConsumerStatefulWidget {
  /// The route to push when maintenance is lifted (e.g. AppRouter.home)
  final String resumeRoute;

  const MaintenanceScreen({super.key, required this.resumeRoute});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _pulseAnim;
  late Animation<double> _fadeAnim;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _pulseAnim = Tween<double>(begin: 0.92, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    // Start periodic refresh so maintenance lift is detected automatically
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(appControlProvider.notifier).startMaintenancePolling();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  /// Listen for maintenance being lifted and resume normal routing
  void _checkResume(AppControlState appControl) {
    if (!appControl.isMaintenance && !_hasNavigated && mounted) {
      _hasNavigated = true;
      Navigator.of(context).pushNamedAndRemoveUntil(
        widget.resumeRoute,
        (route) => false,
      );
    }
  }

  /// Exit app on back press
  Future<bool> _onWillPop() async {
    if (Platform.isAndroid) {
      SystemNavigator.pop();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final appControl = ref.watch(appControlProvider);
    _checkResume(appControl);

    final info = appControl.data?.maintenance ?? MaintenanceInfo.off;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A2332);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF555555);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        // No AppBar — maintenance screen must be standalone
        backgroundColor: Colors.transparent,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFBE6), Color(0xFFFFF3CC)],
            ),
          ),
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 32.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 2),

                    // ── Pulsing brand logo ───────────────────────────────
                    ScaleTransition(
                      scale: _pulseAnim,
                      child: Container(
                        width: 120.w,
                        height: 120.w,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFE27903).withOpacity(0.20),
                              blurRadius: 40,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(16.w),
                          child: SvgPicture.asset(
                            'assets/images/startGold.svg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: 40.h),

                    // ── Title ────────────────────────────────────────────
                    Text(
                      info.title.isNotEmpty
                          ? info.title
                          : 'Under Maintenance',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 26.sp,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                        height: 1.2,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    SizedBox(height: 16.h),

                    // ── Subtitle ─────────────────────────────────────────
                    Text(
                      info.subtitle.isNotEmpty
                          ? info.subtitle
                          : "We're upgrading our systems to serve you better.",
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 15.sp,
                        color: textSecondary,
                        height: 1.65,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // ── Expected resume time (optional) ──────────────────
                    if (info.expectedResume != null &&
                        info.expectedResume!.isNotEmpty) ...[
                      SizedBox(height: 28.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 20.w, vertical: 14.h),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE27903).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16.r),
                          border: Border.all(
                            color: const Color(0xFFE27903).withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.schedule_rounded,
                                size: 18.sp,
                                color: const Color(0xFFE27903)),
                            SizedBox(width: 8.w),
                            Flexible(
                              child: Text(
                                info.expectedResume!,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 13.sp,
                                  color: const Color(0xFFE27903),
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Spacer(flex: 2),

                    // ── Auto-refresh notice ──────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 12.w,
                          height: 12.w,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: textSecondary,
                          ),
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Checking status automatically…',
                          style: AppTextStyles.labelMedium(isDark)
                              .copyWith(color: textSecondary),
                        ),
                      ],
                    ),

                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
