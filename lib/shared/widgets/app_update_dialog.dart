import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/models/app_control_model.dart';
import '../theme/app_text_styles.dart';

/// Blocking app update dialog.
///
/// When an update is available the user MUST update.
/// - "Update Now" → opens the store
/// - Hardware back button / system back → exits the app
/// - No "Remind me later" option
class AppUpdateDialog extends StatelessWidget {
  final AppVersionInfo versionInfo;
  final bool forceUpdate;
  final VoidCallback? onDismiss;

  const AppUpdateDialog({
    super.key,
    required this.versionInfo,
    required this.forceUpdate,
    this.onDismiss,
  });

  static Future<void> show(
    BuildContext context, {
    required AppVersionInfo versionInfo,
    required bool forceUpdate,
    VoidCallback? onDismiss,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AppUpdateDialog(
        versionInfo: versionInfo,
        forceUpdate: forceUpdate,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final msg = versionInfo.current;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1A2332) : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A2332);
    final textSecondary = isDark ? Colors.white60 : const Color(0xFF666666);

    return PopScope(
      // Back button → exit the app
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (Platform.isAndroid) {
            SystemNavigator.pop();
          }
        }
      },
      child: Dialog(
        backgroundColor: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 32.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Update Icon ────────────────────────────────────────
              Container(
                width: 72.w,
                height: 72.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B882C), Color(0xFF003716)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B882C).withOpacity(0.3),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: Icon(Icons.system_update_rounded,
                    color: Colors.white, size: 32.sp),
              ),
              SizedBox(height: 20.h),

              // ── Title ─────────────────────────────────────────────
              Text(
                msg.title.isNotEmpty ? msg.title : 'Update Available',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8.h),

              // ── Version badge ─────────────────────────────────────
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B882C).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  'v${msg.latestVersion}',
                  style: GoogleFonts.lora(
                    fontSize: 12.sp,
                    color: const Color(0xFF1B882C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(height: 16.h),

              // ── Message ───────────────────────────────────────────
              Text(
                msg.message.isNotEmpty
                    ? msg.message
                    : 'A new version is available. Update now for the latest features and security improvements.',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14.sp,
                  color: textSecondary,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 28.h),

              // ── Update Button ─────────────────────────────────────
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B882C), Color(0xFF003716)],
                    ),
                    borderRadius: BorderRadius.circular(50.r),
                  ),
                  child: ElevatedButton(
                    onPressed: () => _openStore(msg.storeUrl),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50.r)),
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                    ),
                    child: Text(
                      msg.buttonText.isNotEmpty ? msg.buttonText : 'Update Now',
                      style: AppTextStyles.button(isDark),
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

  Future<void> _openStore(String url) async {
    try {
      if (url.isNotEmpty && await canLaunchUrl(Uri.parse(url))) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }
}
