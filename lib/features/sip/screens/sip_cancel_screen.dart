import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../core/security/secure_logger.dart';
import '../controller/sip_controller.dart';
import '../models/sip_models.dart';

/// Cancel Savings screen â€“ reason selection + confirmation.
///
/// Shared between regular (Daily/Weekly/Monthly) SIP and Custom SIP — set
/// [isCustom] + [schemeId] to route the cancel action to the Custom SIP
/// scheme-based endpoint instead of the regular subscription-id endpoint.
///
/// â€¢ Cannot cancel within 24 hours of creation — same rule for both regular
///   SIP and Custom SIP. [cancelEligibleAt] is computed server-side
///   (SIPSchemeService.get_manage_details / CustomSIPService.get_scheme_status)
///   from the same creation timestamp each service's cancel method enforces,
///   so the displayed date/time can never drift from the actual rule.
///   Re-checked dynamically against DateTime.now() on every build, not just
///   once at navigation time.
/// â€¢ Reason is mandatory (only relevant once cancellation is allowed).
class SipCancelScreen extends ConsumerStatefulWidget {
  final String subscriptionId;
  final DateTime? cancelEligibleAt;
  final bool canCancelNow;
  final bool isCustom;
  final int? schemeId;

  const SipCancelScreen({
    super.key,
    required this.subscriptionId,
    this.cancelEligibleAt,
    this.canCancelNow = true,
    this.isCustom = false,
    this.schemeId,
  });

  @override
  ConsumerState<SipCancelScreen> createState() => _SipCancelScreenState();
}

class _SipCancelScreenState extends ConsumerState<SipCancelScreen> {
  String? _selectedReason;
  bool _isCancelling = false;

  /// Re-derived from the live clock on every build (not cached), so if the
  /// user sits on this screen across the eligibility boundary, the UI
  /// updates on next rebuild without needing a fresh API call.
  bool get _isBlocked =>
      !widget.canCancelNow ||
      (widget.cancelEligibleAt != null &&
          DateTime.now().isBefore(widget.cancelEligibleAt!));

  String get _blockedMessage {
    final eligible = widget.cancelEligibleAt;
    if (eligible == null) {
      return 'You cannot cancel a plan within 24 hours of creation. '
          'Please try again later.';
    }
    final formatted = DateFormat('d MMM yyyy, h:mm a').format(eligible);
    return 'You cannot cancel this AutoGold before $formatted.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isBlocked) {
      return _buildBlockedState(context);
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Cancel Savings',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 24.h),

                    Text(
                      'Why are you cancelling?',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A2E),
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Please select a reason to proceed',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        color: Colors.black45,
                      ),
                    ),

                    SizedBox(height: 16.h),

                    ...sipCancelReasons.map((reason) {
                      final isSelected = _selectedReason == reason.value;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedReason = reason.value),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: EdgeInsets.only(bottom: 10.h),
                          padding: EdgeInsets.symmetric(
                              horizontal: 16.w, vertical: 14.h),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF064E3B).withOpacity(0.06)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: isSelected
                                  ? const Color(0xFF064E3B)
                                  : Colors.black.withOpacity(0.06),
                              width: isSelected ? 1.5 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF064E3B)
                                          .withOpacity(0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    )
                                  ]
                                : null,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 22.w,
                                height: 22.w,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? const Color(0xFF064E3B)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: isSelected
                                        ? const Color(0xFF064E3B)
                                        : Colors.black.withOpacity(0.15),
                                    width: isSelected ? 0 : 1.5,
                                  ),
                                ),
                                child: isSelected
                                    ? Icon(Icons.check,
                                        size: 14.sp, color: Colors.white)
                                    : null,
                              ),
                              SizedBox(width: 12.w),
                              Text(
                                reason.label,
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 14.sp,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? const Color(0xFF064E3B)
                                      : const Color(0xFF1A1A2E),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    SizedBox(height: 16.h),
                  ],
                ),
              ),
            ),
          ),
          // â”€â”€ Pinned Cancel button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
          SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h),
              color: Colors.transparent,
              child: CustomButton(
                text: 'Cancel Savings', svgIconPath: 'assets/buttons/tick.svg',
                isLoading: _isCancelling,
                loadingText: 'Cancelling...',
                onPressed: _selectedReason != null && !_isCancelling
                    ? _executeCancelConfirmation
                    : null,
                backgroundColor: const Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown instead of the reason-selection flow while cancellation is
  /// blocked by the 24-hour creation guard — cancellation is fully disabled
  /// here rather than merely greyed out, since attempting it would only
  /// fail server-side anyway.
  Widget _buildBlockedState(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Cancel Savings',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 24.h),

                    // ── Error box: cancellation not yet allowed ──────────
                    Container(
                      padding: EdgeInsets.all(16.w),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEE2E2),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: const Color(0xFFDC2626).withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.all(4.w),
                            decoration: const BoxDecoration(
                              color: Color(0xFFDC2626),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.priority_high_rounded,
                                size: 14.sp, color: Colors.white),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: Text(
                              _blockedMessage,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 13.5.sp,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF991B1B),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 32.h),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h),
              color: Colors.transparent,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF064E3B),
                  side: const BorderSide(color: Color(0xFF064E3B), width: 1.5),
                  minimumSize: Size(double.infinity, 52.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100.r),
                  ),
                ),
                child: Text(
                  'Back',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF064E3B),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _executeCancelConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'Are you sure?',
          style: GoogleFonts.playfairDisplay(
              fontSize: 16.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This action will permanently cancel your auto savings plan. '
          'You can create a new plan anytime.',
          style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Go Back',
              style: GoogleFonts.playfairDisplay(
                  color: Colors.black45, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeCancel();
            },
            child: Text(
              'Yes, Cancel',
              style: GoogleFonts.playfairDisplay(
                color: const Color(0xFFDC2626),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeCancel() async {
    setState(() => _isCancelling = true);
    try {
      final Map<String, dynamic> response;
      if (widget.isCustom) {
        final service = ref.read(customSipServiceProvider);
        response = await service.cancelScheme(
          schemeId: widget.schemeId!,
          reason: _selectedReason!,
        );
      } else {
        final service = ref.read(sipServiceProvider);
        response = await service.cancelSip(
          subscriptionId: widget.subscriptionId,
          reason: _selectedReason!,
        );
      }

      if (mounted) {
        final success = response['success'] == true;
        if (success) {
          if (widget.isCustom) {
            ref.invalidate(customSipSchemesProvider);
          } else {
            ref.invalidate(sipDetailsProvider);
          }
          AppToast.show(
            context,
            response['message'] ?? 'Savings cancelled successfully',
            type: ToastType.success,
          );
          Navigator.pop(context); // Back to manage screen
        } else {
          final errorObj = response['error'];
          final dataObj = response['data'];
          final serverMsg = (errorObj is Map ? errorObj['message'] : null) ??
              (dataObj is Map ? dataObj['message'] : null) ??
              response['message'] ??
              'Unable to cancel at this time';
          AppToast.show(
            context,
            serverMsg,
            type: ToastType.error,
          );
        }
      }
    } catch (e) {
      SecureLogger.e('SIP: Cancel failed: $e');
      if (mounted) {
        AppToast.show(
          context,
          'Something went wrong. Please try again.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }
}
