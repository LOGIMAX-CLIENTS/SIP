import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/providers/app_control_provider.dart';
import '../../routes/app_router.dart';
import '../../main.dart' show navigatorKey;
import '../theme/app_text_styles.dart';

/// Pre-action maintenance gate.
///
/// Call [MaintenanceGate.check] before any critical transaction
/// (payment, withdrawal, SIP creation). It does a **fresh** fetch
/// from the server and blocks the action with a premium dialog
/// if maintenance is active.
///
/// Usage:
/// ```dart
/// final allowed = await MaintenanceGate.check(ref, context);
/// if (!allowed) return; // blocked — dialog already shown
/// // ... proceed with action
/// ```
class MaintenanceGate {
  MaintenanceGate._();

  /// Returns `true` if the action is allowed, `false` if blocked.
  /// When blocked, shows a premium dialog and optionally redirects
  /// to the maintenance screen.
  static Future<bool> check(WidgetRef ref, BuildContext context) async {
    final result = await ref
        .read(appControlProvider.notifier)
        .checkBeforeAction();

    if (!result.blocked) return true;

    // If full maintenance → redirect to maintenance screen
    if (result.isMaintenance && context.mounted) {
      await Future.delayed(const Duration(milliseconds: 50));
      navigatorKey.currentState?.pushNamedAndRemoveUntil(
        AppRouter.maintenance,
        (route) => false,
        arguments: {'resumeRoute': AppRouter.login},
      );
      return false;
    }

    // Show blocking dialog for warnings
    if (context.mounted) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => _MaintenanceBlockedDialog(
          title: result.title,
          message: result.message,
        ),
      );
    }

    return false;
  }
}

/// Premium blocking dialog shown when server blocks a transaction.
class _MaintenanceBlockedDialog extends StatelessWidget {
  final String title;
  final String message;

  const _MaintenanceBlockedDialog({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF7C3AED).withOpacity(0.15),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Icon ──
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD97706).withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 32.sp,
              ),
            ),

            SizedBox(height: 20.h),

            // ── Title ──
            Text(
              title.isNotEmpty ? title : 'Action Unavailable',
              textAlign: TextAlign.center,
              style: AppTextStyles.titleMedium(false)
                  .copyWith(color: const Color(0xFF1A1A2E)),
            ),

            SizedBox(height: 12.h),

            // ── Message ──
            Text(
              message.isNotEmpty
                  ? message
                  : 'This action is temporarily unavailable. Please try again later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                color: const Color(0xFF64748B),
                height: 1.5,
              ),
            ),

            SizedBox(height: 24.h),

            // ── OK Button ──
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1B882C),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'Got it',
                  style: AppTextStyles.button(false),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
