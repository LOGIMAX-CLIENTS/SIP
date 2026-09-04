import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../core/security/secure_logger.dart';
import '../../../routes/app_router.dart';
import '../controller/sip_controller.dart';
import '../models/sip_models.dart';

/// Manage screen for one Custom SIP scheme — full screen (subscription
/// details + Pause/Resume/Cancel/Support), mirroring ManageSavingsScreen's
/// layout for regular SIP. Custom SIP has no single Day/Date value (it can
/// run on several dates each month), so this shows a "Custom Dates" row
/// instead. Cancel navigates to CustomSipCancelScreen — a separate route
/// mirroring regular SIP's SipCancelScreen — rather than toggling reasons
/// inline; Custom SIP still has no cancel-eligibility-window concept, so
/// that screen has no blocked-state gate the way SipCancelScreen does.
class ManageCustomSavingsScreen extends ConsumerStatefulWidget {
  final int schemeId;

  const ManageCustomSavingsScreen({super.key, required this.schemeId});

  @override
  ConsumerState<ManageCustomSavingsScreen> createState() =>
      _ManageCustomSavingsScreenState();
}

class _ManageCustomSavingsScreenState
    extends ConsumerState<ManageCustomSavingsScreen> {
  bool _isLoading = true;
  bool _isActioning = false;
  CustomSipSchemeDetail? _details;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    try {
      final service = ref.read(customSipServiceProvider);
      final details = await service.getSchemeStatus(schemeId: widget.schemeId);
      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      SecureLogger.e('CustomSIP: Failed to load manage details: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMsg = 'Unable to load details';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Manage Savings',
            onBack: () => Navigator.pop(context),
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      color: const Color(0xFF064E3B),
                      strokeWidth: 2.5,
                    ),
                  )
                : _errorMsg != null
                    ? _buildError()
                    : _details != null
                        ? _buildContent(_details!)
                        : _buildError(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(CustomSipSchemeDetail details) {
    final isActive = details.isActive;
    final isPaused = details.isPaused;
    final sortedDates = [...details.customDates]..sort();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 24.h),

            // ── Plan info card ─────────────────────────
            Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    icon: Icons.tag_rounded,
                    label: 'Subscription ID',
                    value: details.subscriptionId,
                  ),
                  _divider(),
                  if (details.startDate != null) ...[
                    _buildDetailRow(
                      icon: Icons.calendar_today_rounded,
                      label: 'Start Date',
                      value: details.startDate!,
                    ),
                    _divider(),
                  ],
                  _buildDetailRow(
                    icon: Icons.repeat_rounded,
                    label: 'Frequency',
                    value: 'Custom',
                    isNumeric: false,
                  ),
                  _divider(),
                  _buildDetailRow(
                    icon: Icons.event_repeat_rounded,
                    label: 'Runs on',
                    value: sortedDates.join(', '),
                    isNumeric: false,
                  ),
                  _divider(),
                  _buildDetailRow(
                    icon: Icons.currency_rupee_rounded,
                    label: 'Amount',
                    value: '₹${details.amount.toStringAsFixed(0)}',
                  ),
                  _divider(),
                  _buildDetailRow(
                    icon: Icons.diamond_rounded,
                    label: 'Commodity',
                    value: details.commodityName,
                    isNumeric: false,
                  ),
                  _divider(),
                  _buildStatusRow(details.status),
                ],
              ),
            ),

            SizedBox(height: 28.h),

            // ── Actions ─────────
            if (isActive || isPaused) ...[
              if (isActive)
                _buildActionButton(
                  icon: Icons.pause_circle_rounded,
                  label: 'Pause Savings',
                  subtitle: 'Temporarily stop this Custom AutoGold',
                  color: const Color(0xFFD97706),
                  onTap: () => _confirmPause(),
                ),
              if (isPaused)
                _buildActionButton(
                  icon: Icons.play_circle_rounded,
                  label: 'Resume Savings',
                  subtitle: 'Continue this Custom AutoGold',
                  color: const Color(0xFF16A34A),
                  onTap: () => _confirmResume(),
                ),
              SizedBox(height: 12.h),
              _buildActionButton(
                icon: Icons.cancel_rounded,
                label: 'Cancel Savings',
                subtitle: 'Stop and free up these dates',
                color: const Color(0xFFDC2626),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRouter.sipCancel,
                    arguments: {
                      'subscription_id': details.subscriptionId,
                      'is_custom': true,
                      'scheme_id': widget.schemeId,
                      'cancel_eligible_at':
                          details.cancelEligibleAt?.toIso8601String(),
                      'can_cancel_now': details.canCancelNow,
                    },
                  ).then((_) => _loadDetails());
                },
              ),
              SizedBox(height: 12.h),
              _buildActionButton(
                icon: Icons.support_agent_rounded,
                label: 'Get Support',
                subtitle: 'Need help with your savings?',
                color: const Color(0xFF2563EB),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRouter.enquiryForm,
                    // 'Custom SIP' matched no key in kTicketTypes (enquiry_
                    // service.dart), so this never actually preselected a
                    // type — 'Auto Savings' is both the renamed term and a
                    // real key, fixing that dead argument as a side effect.
                    arguments: {'initial_type': 'Auto Savings'},
                  );
                },
              ),
            ],

            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }

  /// [isNumeric] selects the value's font family — see ManageSavingsScreen's
  /// identical convention (numeric/ID/amount values use Lora; textual
  /// values like Frequency/Commodity/dates use Playfair Display).
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    bool isNumeric = true,
  }) {
    final valueStyle = isNumeric
        ? GoogleFonts.lora(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
          )
        : GoogleFonts.playfairDisplay(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF1A1A2E),
          );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 18.sp, color: const Color(0xFF064E3B)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: valueStyle,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String status) {
    final isActive = status.toUpperCase() == 'ACTIVE';
    final color = isActive ? const Color(0xFF16A34A) : const Color(0xFFD97706);
    final bg = isActive ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: const Color(0xFF064E3B).withOpacity(0.06),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(Icons.info_outline_rounded,
                size: 18.sp, color: const Color(0xFF064E3B)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              'Status',
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              status,
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isActioning ? null : onTap,
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, size: 22.sp, color: color),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 11.sp,
                      color: Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            if (_isActioning)
              SizedBox(
                width: 18.w,
                height: 18.w,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(Icons.chevron_right_rounded,
                  size: 22.sp, color: Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Divider(
        height: 1,
        color: Colors.black.withOpacity(0.04),
      );

  // ─── Pause Confirmation ─────────────────────────────────────────────────
  void _confirmPause() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text(
          'Pause Savings?',
          style: GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This Custom AutoGold will be temporarily paused. You can resume anytime.',
          style: GoogleFonts.playfairDisplay(fontSize: 13.sp, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.playfairDisplay(
                    color: Colors.black45, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executePause();
            },
            child: Text('Pause',
                style: GoogleFonts.playfairDisplay(
                    color: const Color(0xFFD97706), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _executePause() async {
    setState(() => _isActioning = true);
    try {
      final service = ref.read(customSipServiceProvider);
      final response = await service.pauseScheme(schemeId: widget.schemeId);
      if (mounted) {
        AppToast.show(
          context,
          (response['message'] ?? 'Paused successfully').toString(),
          type: ToastType.success,
        );
        ref.invalidate(customSipSchemesProvider);
        await _loadDetails();
      }
    } catch (e) {
      SecureLogger.e('CustomSIP: Pause failed: $e');
      if (mounted) {
        AppToast.show(context, 'Failed to pause plan. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  // ─── Resume Confirmation ────────────────────────────────────────────────
  void _confirmResume() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        title: Text(
          'Resume Savings?',
          style: GoogleFonts.playfairDisplay(fontSize: 16.sp, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This Custom AutoGold will resume on its original dates.',
          style: GoogleFonts.playfairDisplay(fontSize: 13.sp, color: Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.playfairDisplay(
                    color: Colors.black45, fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeResume();
            },
            child: Text('Resume',
                style: GoogleFonts.playfairDisplay(
                    color: const Color(0xFF16A34A), fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _executeResume() async {
    setState(() => _isActioning = true);
    try {
      final service = ref.read(customSipServiceProvider);
      final response = await service.resumeScheme(schemeId: widget.schemeId);
      if (mounted) {
        AppToast.show(
          context,
          (response['message'] ?? 'Resumed successfully').toString(),
          type: ToastType.success,
        );
        ref.invalidate(customSipSchemesProvider);
        await _loadDetails();
      }
    } catch (e) {
      SecureLogger.e('CustomSIP: Resume failed: $e');
      if (mounted) {
        AppToast.show(context, 'Failed to resume plan. Please try again.',
            type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }


  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 48.sp, color: Colors.black26),
          SizedBox(height: 12.h),
          Text(
            _errorMsg ?? 'Something went wrong',
            style: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              fontWeight: FontWeight.w600,
              color: Colors.black45,
            ),
          ),
          SizedBox(height: 16.h),
          TextButton.icon(
            onPressed: _loadDetails,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
