import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../routes/app_router.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/theme/app_theme.dart';
import '../controller/sip_controller.dart';
import '../../history/models/history_models.dart';

/// SIP Transaction Details screen.
///
/// • Design mirrors the main Transaction Details page exactly.
/// • Fetches fresh data every time the screen is entered.
/// • Shows top card, timeline, scheme info, and expandable order details.
class SipTransactionDetailsScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> transactionData;

  const SipTransactionDetailsScreen({
    super.key,
    required this.transactionData,
  });

  @override
  ConsumerState<SipTransactionDetailsScreen> createState() =>
      _SipTransactionDetailsScreenState();
}

class _SipTransactionDetailsScreenState
    extends ConsumerState<SipTransactionDetailsScreen> {
  bool _isOrderDetailsExpanded = false;

  @override
  void initState() {
    super.initState();
    // Always fetch fresh data on screen entry
    Future.microtask(() {
      ref.invalidate(
          sipTransactionDetailsProvider(widget.transactionData['id']));
    });
  }

  @override
  Widget build(BuildContext context) {
    final transactionId = widget.transactionData['id'];
    final detailsState = ref.watch(sipTransactionDetailsProvider(transactionId));
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.lightGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(title: 'SIP Transaction Details'),
            Expanded(
              child: detailsState.when(
                data: (response) {
                  final data = response['data'] as Map<String, dynamic>? ?? {};
                  final details = TransactionDetailResponse.fromJson(data);
                  return _buildContent(context, details, isDark);
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF064E3B),
                    strokeWidth: 2.5,
                  ),
                ),
                error: (err, stack) {
                  final errorMessage =
                      err.toString().replaceAll('Exception: ', '');
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: const Color(0xFFDC2626), size: 48.sp),
                        SizedBox(height: 16.h),
                        Text(
                          'Failed to load details',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          errorMessage,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 14.sp,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
      BuildContext context, TransactionDetailResponse details, bool isDark) {
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final mutedTextColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final cardColor = isDark ? Colors.white.withOpacity(0.04) : Colors.white;
    final borderColor =
        isDark ? Colors.white10 : Colors.black.withOpacity(0.05);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 80.h),
      child: Column(
        children: [
          _buildTopCard(
              details, cardColor, borderColor, textColor, mutedTextColor),
          SizedBox(height: 16.h),
          _buildStatusCard(details, cardColor, borderColor, textColor,
              mutedTextColor, isDark),
          if (details.schemeInfo != null) ...[
            SizedBox(height: 16.h),
            _buildSchemeInfoCard(details.schemeInfo!, cardColor, borderColor,
                textColor, mutedTextColor, isDark),
          ],
          SizedBox(height: 16.h),
          _buildOrderDetails(details, cardColor, borderColor, textColor,
              mutedTextColor, isDark),
          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  // ── Top Card ───────────────────────────────────────────────────────
  Widget _buildTopCard(
      TransactionDetailResponse details,
      Color cardColor,
      Color borderColor,
      Color textColor,
      Color mutedTextColor) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SvgPicture.asset(
            _getSipIcon(details.metalName),
            width: 50.w,
            height: 50.w,
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NumericStyledText(
                  details.metalName,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
                SizedBox(height: 4.h),
                Text(
                  'SIP Autopay',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF0D9488),
                  ),
                ),
                if (details.subtitle.isNotEmpty) ...[
                  SizedBox(height: 2.h),
                  NumericStyledText(
                    details.subtitle,
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w500,
                    color: mutedTextColor,
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${details.amount}',
                style: GoogleFonts.lora(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                '${details.weightGrams.toStringAsFixed(6)} gm',
                style: GoogleFonts.lora(
                  fontSize: 13.sp,
                  color: mutedTextColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Status / Timeline Card ─────────────────────────────────────────
  Widget _buildStatusCard(
      TransactionDetailResponse details,
      Color cardColor,
      Color borderColor,
      Color textColor,
      Color mutedTextColor,
      bool isDark) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transaction Status',
            style: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          SizedBox(height: 14.h),
          ...details.timeline
              .map((step) => _buildTimelineStep(step,
                  isDark: isDark,
                  textColor: textColor,
                  mutedTextColor: mutedTextColor,
                  isLast: details.timeline.last == step,
                  isFirst: details.timeline.first == step))
              .toList(),
          SizedBox(height: 8.h),
          Divider(color: borderColor, height: 1),
          SizedBox(height: 8.h),
          Text(
            details.footerMessage,
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              color: mutedTextColor,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              if (details.invoiceUrl.isNotEmpty)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final url = Uri.parse(details.invoiceUrl);
                      try {
                        final launched = await launchUrl(
                          url,
                          mode: LaunchMode.externalApplication,
                        );
                        if (!launched && context.mounted) {
                          AppToast.show(
                              context, 'No app found to open the invoice',
                              type: ToastType.warning);
                        }
                      } catch (e) {
                        if (context.mounted) {
                          AppToast.show(context, 'Could not open invoice',
                              type: ToastType.error);
                        }
                      }
                    },
                    icon: Icon(Icons.download_rounded,
                        color: textColor, size: 20.sp),
                    label: Text('Invoice',
                        style: TextStyle(
                            color: textColor,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black26),
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100.r)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Timeline Step ──────────────────────────────────────────────────
  Widget _buildTimelineStep(TimelineStep step,
      {bool isFirst = false,
      bool isLast = false,
      required Color textColor,
      required Color mutedTextColor,
      required bool isDark}) {
    final statusLower = step.status.toLowerCase();
    final bool isFailed = statusLower == 'failed' ||
        statusLower == 'failure' ||
        statusLower == 'cancelled';
    final bool isPending =
        statusLower == 'pending' || statusLower == 'processing';

    final Color stepColor;
    final Color badgeBgColor;
    final Color badgeTextColor;
    final IconData stepIcon;

    if (isFailed) {
      stepColor = const Color(0xFFDC2626);
      badgeBgColor = const Color(0xFFDC2626).withOpacity(0.12);
      badgeTextColor =
          isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      stepIcon = Icons.cancel_rounded;
    } else if (isPending) {
      stepColor = const Color(0xFFF59E0B);
      badgeBgColor = const Color(0xFFF59E0B).withOpacity(0.12);
      badgeTextColor =
          isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
      stepIcon = Icons.schedule_rounded;
    } else {
      stepColor = const Color(0xFF10B981);
      badgeBgColor = const Color(0xFF10B981).withOpacity(0.15);
      badgeTextColor =
          isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
      stepIcon = Icons.check_circle;
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24.w,
            child: Column(
              children: [
                if (!isFirst)
                  Container(
                      width: 2.w,
                      height: 12.h,
                      color: stepColor.withOpacity(0.4)),
                Icon(stepIcon, color: stepColor, size: 18.sp),
                if (!isLast)
                  Expanded(
                      child: Container(
                          width: 2.w, color: stepColor.withOpacity(0.4))),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: 14.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      NumericStyledText(step.stepName,
                          fontSize: 14.sp,
                          fontWeight: FontWeight.w600,
                          color: textColor),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8.w, vertical: 4.h),
                        decoration: BoxDecoration(
                          color: badgeBgColor,
                          borderRadius: BorderRadius.circular(6.r),
                        ),
                        child: Text(
                          step.status,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                            color: badgeTextColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    step.time,
                    style: GoogleFonts.lora(
                        fontSize: 12.sp, color: mutedTextColor),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Scheme Info Card ───────────────────────────────────────────────
  Widget _buildSchemeInfoCard(SchemeInfo scheme, Color cardColor,
      Color borderColor, Color textColor, Color mutedTextColor, bool isDark) {
    final statusColor = scheme.status.toLowerCase() == 'active'
        ? const Color(0xFF10B981)
        : scheme.status.toLowerCase() == 'paused'
            ? const Color(0xFFF59E0B)
            : const Color(0xFFDC2626);

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SIP Plan Details',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Text(
                  scheme.status,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          _buildDetailRow('Plan', scheme.label, textColor, mutedTextColor),
          _buildDetailRow(
              'Frequency', scheme.frequency, textColor, mutedTextColor),
          _buildDetailRow(
              'SIP Amount', '₹${scheme.amount}', textColor, mutedTextColor),
          _buildDetailRow('Total Saved', '₹${scheme.totalSaved}', textColor,
              mutedTextColor),
          _buildDetailRow('Cycles Done', '${scheme.cyclesDone}', textColor,
              mutedTextColor),
        ],
      ),
    );
  }

  // ── Order Details (Expandable) ─────────────────────────────────────
  Widget _buildOrderDetails(
      TransactionDetailResponse details,
      Color cardColor,
      Color borderColor,
      Color textColor,
      Color mutedTextColor,
      bool isDark) {
    final rateLabel = '${details.metalName} Rate';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      padding: EdgeInsets.symmetric(
          horizontal: 20.w, vertical: _isOrderDetailsExpanded ? 20.h : 8.h),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isOrderDetailsExpanded = !_isOrderDetailsExpanded;
              });
            },
            borderRadius: BorderRadius.circular(8.r),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SIP Order Details',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.bold,
                        color: textColor),
                  ),
                  AnimatedRotation(
                    turns: _isOrderDetailsExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: textColor, size: 24.sp),
                  ),
                ],
              ),
            ),
          ),
          if (_isOrderDetailsExpanded) ...[
            SizedBox(height: 4.h),
            _buildDetailRow(rateLabel, details.priceBreakdown.rate, textColor,
                mutedTextColor),
            _buildDetailRow('Gold Quantity', details.priceBreakdown.quantity,
                textColor, mutedTextColor),
            _buildDetailRow('Gold Value', details.priceBreakdown.value,
                textColor, mutedTextColor),
            _buildDetailRow(
                'GST', details.priceBreakdown.gst, textColor, mutedTextColor),
            Divider(color: borderColor, height: 16.h),
            _buildDetailRow('Amount', details.priceBreakdown.totalAmount,
                textColor, mutedTextColor,
                isBold: true),
            SizedBox(height: 12.h),
            Text(
              'Transaction Details',
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                fontWeight: FontWeight.bold,
                color: textColor,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8.h),
            _buildDetailRow(
                'Order ID', details.orderId, textColor, mutedTextColor,
                showCopy: true),
            _buildDetailRow(
                'Transaction ID',
                details.technicalDetails.transactionIdDisplay,
                textColor,
                mutedTextColor,
                showCopy: true),
            _buildDetailRow('Placed On', details.technicalDetails.placedOn,
                textColor, mutedTextColor),
            _buildDetailRow('Paid Via', details.technicalDetails.paidVia,
                textColor, mutedTextColor),
          ]
        ],
      ),
    );
  }

  // ── Detail Row ─────────────────────────────────────────────────────
  Widget _buildDetailRow(
      String label, String value, Color textColor, Color mutedTextColor,
      {bool isBold = false, bool showCopy = false}) {
    if (value.isEmpty || value == 'N/A' || value == 'null') {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? textColor : mutedTextColor,
            ),
          ),
          Row(
            children: [
              Text(
                value,
                style: GoogleFonts.lora(
                  fontSize: 13.sp,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (showCopy) ...[
                SizedBox(width: 8.w),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    // Auto-clear clipboard after 60s — prevents clipboard sniffing
                    Future.delayed(const Duration(seconds: 60), () {
                      Clipboard.setData(const ClipboardData(text: ''));
                    });
                    AppToast.show(context, '$label copied!',
                        type: ToastType.info);
                  },
                  child: Icon(Icons.copy_outlined,
                      color: mutedTextColor, size: 14.sp),
                ),
              ]
            ],
          )
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────
  String _getSipIcon(String metalName) {
    final isGold = metalName.toLowerCase().contains('gold');
    return isGold
        ? 'assets/withdraw/sip_gold.svg'
        : 'assets/withdraw/sip_silver.svg';
  }
}
