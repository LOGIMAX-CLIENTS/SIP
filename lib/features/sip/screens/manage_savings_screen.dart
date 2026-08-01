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

/// Manage Savings screen – shows subscription details with Pause / Cancel / Support actions.
class ManageSavingsScreen extends ConsumerStatefulWidget {
  final String subscriptionId;

  const ManageSavingsScreen({
    super.key,
    required this.subscriptionId,
  });

  @override
  ConsumerState<ManageSavingsScreen> createState() =>
      _ManageSavingsScreenState();
}

class _ManageSavingsScreenState extends ConsumerState<ManageSavingsScreen> {
  bool _isLoading = true;
  bool _isActioning = false;
  SipManageDetails? _details;
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
      final service = ref.read(sipServiceProvider);
      final details = await service.getManageDetails(
        subscriptionId: widget.subscriptionId,
      );
      if (mounted) {
        setState(() {
          _details = details;
          _isLoading = false;
        });
      }
    } catch (e) {
      SecureLogger.e('SIP: Failed to load manage details: $e');
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

  Widget _buildContent(SipManageDetails details) {
    final isActive = details.status.toUpperCase() == 'ACTIVE';
    final isPaused = details.status.toUpperCase() == 'PAUSED';

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
                  // Subscription ID row
                  _buildDetailRow(
                    icon: Icons.tag_rounded,
                    label: 'Subscription ID',
                    value: details.subscriptionId,
                  ),
                  _divider(),
                  _buildDetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Start Date',
                    value: details.startDate,
                  ),
                  _divider(),
                  _buildDetailRow(
                    icon: Icons.repeat_rounded,
                    label: 'Frequency',
                    value: details.frequency,
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
                  if (details.day != null) ...[
                    _divider(),
                    _buildDetailRow(
                      icon: Icons.today_rounded,
                      label: 'Day',
                      value: details.day!,
                      isNumeric: false,
                    ),
                  ],
                  if (details.date != null) ...[
                    _divider(),
                    _buildDetailRow(
                      icon: Icons.event_rounded,
                      label: 'Date',
                      value: '${details.date}',
                    ),
                  ],
                  _divider(),
                  _buildStatusRow(details.status),
                ],
              ),
            ),

            SizedBox(height: 28.h),

            // ── Actions ───────────────────────────────
            if (isActive || isPaused) ...[
              // Pause / Resume
              if (isActive)
                _buildActionButton(
                  icon: Icons.pause_circle_rounded,
                  label: 'Pause Savings',
                  subtitle: 'Temporarily stop auto savings',
                  color: const Color(0xFFD97706),
                  onTap: () => _confirmPause(details),
                ),
              if (isPaused)
                _buildActionButton(
                  icon: Icons.play_circle_rounded,
                  label: 'Resume Savings',
                  subtitle: 'Continue auto savings',
                  color: const Color(0xFF16A34A),
                  onTap: () => _confirmResume(details),
                ),

              SizedBox(height: 12.h),

              // Cancel
              _buildActionButton(
                icon: Icons.cancel_rounded,
                label: 'Cancel Savings',
                subtitle: 'Stop and remove this plan',
                color: const Color(0xFFDC2626),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRouter.sipCancel,
                    arguments: {
                      'subscription_id': details.subscriptionId,
                      'cancel_eligible_at':
                          details.cancelEligibleAt?.toIso8601String(),
                      'can_cancel_now': details.canCancelNow,
                    },
                  ).then((_) => _loadDetails());
                },
              ),

              SizedBox(height: 12.h),

              // Support
              _buildActionButton(
                icon: Icons.support_agent_rounded,
                label: 'Get Support',
                subtitle: 'Need help with your savings?',
                color: const Color(0xFF2563EB),
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    AppRouter.enquiryForm,
                    arguments: {
                      'initial_type': 'Auto Savings',
                    },
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

  /// [isNumeric] selects the value's font family: numeric/amount/rate/date/ID
  /// values (default) use Lora; textual/categorical values (e.g. Frequency
  /// name, Commodity name, Day name) should pass isNumeric: false to use
  /// Playfair Display.
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
          Text(
            value,
            style: valueStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String status) {
    final isActive = status.toUpperCase() == 'ACTIVE';
    final color =
        isActive ? const Color(0xFF16A34A) : const Color(0xFFD97706);
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
  void _confirmPause(SipManageDetails details) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'Pause Savings?',
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Your auto savings will be temporarily paused. You can resume anytime.',
          style: GoogleFonts.playfairDisplay(
            fontSize: 13.sp,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.playfairDisplay(
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executePause(details);
            },
            child: Text(
              'Pause',
              style: GoogleFonts.playfairDisplay(
                color: const Color(0xFFD97706),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executePause(SipManageDetails details) async {
    setState(() => _isActioning = true);
    try {
      final service = ref.read(sipServiceProvider);
      final response =
          await service.pauseSip(subscriptionId: details.subscriptionId);
      if (mounted) {
        AppToast.show(
          context,
          response['message'] ?? 'Savings paused successfully',
          type: ToastType.success,
        );
        _loadDetails();
        ref.invalidate(sipDetailsProvider);
      }
    } catch (e) {
      SecureLogger.e('SIP: Pause failed: $e');
      if (mounted) {
        AppToast.show(
          context,
          'Failed to pause plan. Please try again.',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isActioning = false);
    }
  }

  // ─── Resume Confirmation ────────────────────────────────────────────────
  void _confirmResume(SipManageDetails details) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.r),
        ),
        title: Text(
          'Resume Savings?',
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Your auto savings will resume as per the original schedule.',
          style: GoogleFonts.playfairDisplay(
            fontSize: 13.sp,
            color: Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: GoogleFonts.playfairDisplay(
                color: Colors.black45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _executeResume(details);
            },
            child: Text(
              'Resume',
              style: GoogleFonts.playfairDisplay(
                color: const Color(0xFF16A34A),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _executeResume(SipManageDetails details) async {
    setState(() => _isActioning = true);
    try {
      final service = ref.read(sipServiceProvider);
      final response =
          await service.resumeSip(subscriptionId: details.subscriptionId);
      if (mounted) {
        AppToast.show(
          context,
          response['message'] ?? 'Savings resumed successfully',
          type: ToastType.success,
        );
        _loadDetails();
        ref.invalidate(sipDetailsProvider);
      }
    } catch (e) {
      SecureLogger.e('SIP: Resume failed: $e');
      if (mounted) {
        AppToast.show(
          context,
          'Failed to resume plan. Please try again.',
          type: ToastType.error,
        );
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
