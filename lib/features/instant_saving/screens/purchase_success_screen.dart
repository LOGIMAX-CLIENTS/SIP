import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../routes/app_router.dart';
import '../../../core/providers/portfolio_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../profile/profile_controller.dart';
import '../../main/main_screen.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/numeric_styled_text.dart';

class PurchaseSuccessScreen extends ConsumerWidget {
  final Map<String, dynamic> data;

  const PurchaseSuccessScreen({super.key, required this.data});

  // ── Formatters ─────────────────────────────────────────────────────

  String _formatPaymentMode(String? mode) {
    if (mode == null || mode.isEmpty) return 'Online';
    switch (mode.toUpperCase()) {
      case 'WALLET':
        return 'Wallet';
      case 'UPI':
        return 'UPI';
      case 'CARD':
        return 'Card';
      case 'NET_BANKING':
        return 'Net Banking';
      default:
        return mode[0].toUpperCase() + mode.substring(1).toLowerCase();
    }
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '₹0.00';
    final num val = amount is num ? amount : num.tryParse('$amount') ?? 0;
    return '₹${val.toStringAsFixed(2)}';
  }

  String _formatRate(dynamic rate) {
    if (rate == null) return '₹0.00/gm';
    final num val = rate is num ? rate : num.tryParse('$rate') ?? 0;
    return '₹${val.toStringAsFixed(2)}/gm';
  }

  String _formatWeight(dynamic weight) {
    if (weight == null) return '0.000000 gm';
    final num val = weight is num ? weight : num.tryParse('$weight') ?? 0;
    return '${val.toStringAsFixed(6)} gm';
  }

  bool _isDisplayable(dynamic val) {
    if (val == null) return false;
    final s = val.toString().trim();
    return s.isNotEmpty && s != 'N/A' && s != 'null';
  }

  String _truncateId(String id) {
    if (id.length > 14) return '${id.substring(0, 14)}...';
    return id;
  }

  // ── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isSuccess = data['isSuccess'] ?? true;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── Non-scrollable content (fits the screen) ──────────
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // ── Status icon ───────────────────
                    SizedBox(
                      width: 90.w,
                      height: 90.w,
                      child: Image.asset(
                        isSuccess
                            ? 'assets/withdraw/successtik.gif'
                            : 'assets/withdraw/failuretik.gif',
                        fit: BoxFit.contain,
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // ── Title ────────────────────
                    Text(
                      isSuccess ? 'Purchase Successful!' : 'Payment Failed',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: isSuccess
                            ? const Color(0xFF003716)
                            : const Color(0xFF991B1B),
                      ),
                    ),

                    SizedBox(height: 6.h),

                    // ── Subtitle (failure only) ──────────
                    if (!isSuccess)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12.w),
                        child: Text(
                          data['message'] ??
                              'Something went wrong. Please try again.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            color: const Color(0xFF991B1B).withOpacity(0.7),
                            height: 1.4,
                          ),
                        ),
                      ),

                    SizedBox(height: 20.h),

                    // ── Card ───────────────────────
                    if (isSuccess)
                      _buildSuccessCard(context, isDark)
                    else
                      _buildFailureCard(context),
                  ],
                ),
              ),
            ),

            // ── Bottom button ────────────────────
            _buildBottomButton(context, isSuccess),
          ],
        ),    // closes Column
      ),      // closes SafeArea
    ),        // closes Scaffold
  );          // closes PopScope
  }

  // ── Success card ───────────────────────────────────────────────────

  Widget _buildSuccessCard(BuildContext context, bool isDark) {
    final orderId = data['orderId'] ?? '';
    final commodityName = data['commodity_name'] ?? 'Gold 24K';
    final totalAmount = data['total_amount'];
    final rate = data['rate'];
    final gramsCredited = data['weight'];
    final paymentMode = data['payment_mode'];

    final isGold = commodityName.toString().toLowerCase().contains('gold');

    final primaryText = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);
    final dividerColor =
        isDark ? Colors.white.withOpacity(0.08) : const Color(0xFFF3F4F6);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0D4A1A), Color(0xFF002E0F)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF003716).withOpacity(0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Top: commodity badge + amount ──
          Padding(
            padding: EdgeInsets.fromLTRB(24.w, 18.h, 24.w, 14.h),
            child: Column(
              children: [
                // Commodity badge
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isGold ? Icons.auto_awesome : Icons.diamond_rounded,
                        color: isGold
                            ? const Color(0xFFFFD700)
                            : const Color(0xFFC0C0C0),
                        size: 14.sp,
                      ),
                      SizedBox(width: 6.w),
                      NumericStyledText(
                        commodityName,
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16.h),

                // Amount
                Text(
                  _formatAmount(totalAmount),
                  style: GoogleFonts.lora(
                    fontSize: 36.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  'Total Amount',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),

          // ── Bottom: detail rows on white bg ──
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(24.r),
                bottomRight: Radius.circular(24.r),
              ),
            ),
            child: Column(
              children: [
                if (_isDisplayable(orderId)) ...[
                  _detailRow(
                    context: context,
                    icon: Icons.receipt_long_outlined,
                    label: 'Order ID',
                    value: _truncateId(orderId.toString()),
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    showCopy: true,
                    fullValue: orderId.toString(),
                  ),
                  Divider(height: 1, thickness: 1, color: dividerColor),
                ],
                if (_isDisplayable(gramsCredited)) ...[
                  _detailRow(
                    context: context,
                    icon: Icons.scale_rounded,
                    label: 'Weight Credited',
                    value: _formatWeight(gramsCredited),
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                  Divider(height: 1, thickness: 1, color: dividerColor),
                ],
                if (_isDisplayable(rate)) ...[
                  _detailRow(
                    context: context,
                    icon: Icons.trending_up_rounded,
                    label: 'Buy Rate',
                    value: _formatRate(rate),
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                  ),
                  Divider(height: 1, thickness: 1, color: dividerColor),
                ],
                if (_isDisplayable(paymentMode))
                  _detailRow(
                    context: context,
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Payment Mode',
                    value: _formatPaymentMode(paymentMode),
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    isNumericValue: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Detail row ─────────────────────────────────────────────────────

  Widget _detailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    required Color primaryText,
    required Color secondaryText,
    bool showCopy = false,
    String fullValue = '',
    bool isNumericValue = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10.h),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: const Color(0xFF1B882C).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 18.sp, color: const Color(0xFF1B882C)),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.bodySmall(isDark)
                  .copyWith(color: secondaryText),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: isNumericValue
                  ? GoogleFonts.lora(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: primaryText,
                    )
                  : GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: primaryText,
                    ),
            ),
          ),
          if (showCopy) ...[
            SizedBox(width: 6.w),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(text: fullValue));
                // Auto-clear clipboard after 60s — prevents clipboard sniffing
                Future.delayed(const Duration(seconds: 60), () {
                  Clipboard.setData(const ClipboardData(text: ''));
                });
                AppToast.show(context, 'Order ID copied!',
                    type: ToastType.success);
              },
              child: Icon(
                Icons.copy_rounded,
                size: 16.sp,
                color: secondaryText.withOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Failure card ───────────────────────────────────────────────────

  Widget _buildFailureCard(BuildContext context) {
    final orderId = data['orderId'];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        color: const Color(0xFF991B1B).withOpacity(0.08),
        border: Border.all(
          color: const Color(0xFF991B1B).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          if (orderId != null && orderId.toString().isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order ID',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    color: const Color(0xFF7F1D1D).withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: orderId.toString()));
                    // Auto-clear clipboard after 60s — prevents clipboard sniffing
                    Future.delayed(const Duration(seconds: 60), () {
                      Clipboard.setData(const ClipboardData(text: ''));
                    });
                    AppToast.show(context, 'Order ID copied!',
                        type: ToastType.success);
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        orderId.toString(),
                        style: GoogleFonts.lora(
                          fontSize: 12.sp,
                          color: const Color(0xFF7F1D1D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      Icon(
                        Icons.copy_rounded,
                        color: const Color(0xFF7F1D1D).withOpacity(0.5),
                        size: 14.sp,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 20.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: const Color(0xFF7F1D1D).withOpacity(0.5),
                size: 14.sp,
              ),
              SizedBox(width: 6.w),
              Text(
                'No amount has been deducted',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 11.sp,
                  color: const Color(0xFF7F1D1D).withOpacity(0.5),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom button ──────────────────────────────────────────────────

  Widget _buildBottomButton(BuildContext context, bool isSuccess) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
      child: CustomButton(
        text: isSuccess ? 'BACK TO HOME' : 'TRY AGAIN',
        svgIconPath: 'assets/buttons/back-home.svg',
        onPressed: () {
          if (isSuccess) {
            // "Back to Home" — navigate to home tab on main screen.
            //
            // PaymentHandler pushes PurchaseSuccessScreen via pushReplacement
            // with an anonymous MaterialPageRoute (no route name), so
            // popUntil's name checks always evaluate null and never match.
            // Fix: pushNamedAndRemoveUntil clears the stack unconditionally.
            final container = ProviderScope.containerOf(context);
            Navigator.of(context).pushNamedAndRemoveUntil(
              AppRouter.main,
              (route) => false, // remove ALL routes
            );
            Future.delayed(const Duration(milliseconds: 350), () {
              container.read(selectedTabProvider.notifier).state = 0; // Home tab
            });
            Future.delayed(const Duration(milliseconds: 650), () {
              container.read(portfolioProvider.notifier).fetchPortfolio();
              container.invalidate(homeDashboardProvider);
              container.invalidate(profileProvider);
            });
          } else {
            // "Try Again" — go back to InvestScreen (Invest tab on main screen).
            //
            // PaymentHandler uses Navigator.pushReplacement with an anonymous
            // MaterialPageRoute, so route.settings.name is null for this screen.
            // popUntil's name check never matched, leaving the user stuck here.
            //
            // Fix: use pushNamedAndRemoveUntil to unconditionally clear the
            // entire back stack and land cleanly on the main screen, then
            // switch to the Invest tab so the user can retry immediately.
            final container = ProviderScope.containerOf(context);
            Navigator.of(context).pushNamedAndRemoveUntil(
              AppRouter.main,
              (route) => false, // remove ALL routes
            );
            Future.delayed(const Duration(milliseconds: 350), () {
              container.read(selectedTabProvider.notifier).state = 1; // Invest tab
            });
          }
        },
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF1B882C), Color(0xFF003716)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B882C).withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        textColor: Colors.white,
      ),
    );
  }
}
