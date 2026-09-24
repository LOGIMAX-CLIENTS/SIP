import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routes/app_router.dart';
import '../../../core/providers/portfolio_provider.dart';
import '../../../core/providers/home_dashboard_provider.dart';
import '../../profile/profile_controller.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/theme/app_text_styles.dart';

class WithdrawalSuccessScreen extends ConsumerWidget {
  final Map<String, dynamic> data;

  const WithdrawalSuccessScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = isDark ? Colors.white : const Color(0xFF1A1A2E);
    final secondaryText = isDark ? Colors.white54 : const Color(0xFF6B7280);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
        child: Column(
          children: [
            // â”€â”€ Non-scrollable content (fits the screen) â”€â”€â”€â”€â”€â”€â”€â”€
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // â”€â”€ Success icon (animated) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    SizedBox(
                      width: 90.w,
                      height: 90.w,
                      child: Image.asset(
                        'assets/withdraw/successtik.gif',
                        fit: BoxFit.contain,
                      ),
                    ),

                    SizedBox(height: 16.h),

                    // â”€â”€ Title â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Text(
                      'Withdrawal Successful!',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF003716),
                      ),
                    ),

                    SizedBox(height: 6.h),

                    // â”€â”€ Subtitle â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12.w),
                      child: Text(
                        'Your withdrawal request has been successfully processed. The amount will be credited to your account.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 12.sp,
                          color: secondaryText,
                          height: 1.4,
                        ),
                      ),
                    ),

                    SizedBox(height: 20.h),

                    // â”€â”€ Dark green summary card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24.r),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF0D4A1A),
                            Color(0xFF002E0F),
                          ],
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
                          // â”€ Top section: commodity + amount â”€â”€
                          Padding(
                            padding: EdgeInsets.fromLTRB(24.w, 18.h, 24.w, 14.h),
                            child: Column(
                              children: [
                                // Commodity badge
                                Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 14.w, vertical: 5.h),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20.r),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.auto_awesome,
                                        color: const Color(0xFFFFD700),
                                        size: 13.sp,
                                      ),
                                      SizedBox(width: 6.w),
                                      NumericStyledText(
                                        _getCommodityLabel(),
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),

                                SizedBox(height: 12.h),

                                // Amount
                                Text(
                                  '\u20b9${data['amount'] ?? '0.00'}',
                                  style: GoogleFonts.lora(
                                    fontSize: 32.sp,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 2.h),
                                Text(
                                  'Total Amount',
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 12.sp,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // â”€ Bottom section: detail rows â”€â”€â”€â”€â”€â”€
                          Container(
                            width: double.infinity,
                            padding: EdgeInsets.symmetric(
                                horizontal: 20.w, vertical: 8.h),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.06)
                                  : Colors.white,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(24.r),
                                bottomRight: Radius.circular(24.r),
                              ),
                            ),
                            child: Column(
                              children: [
                                _detailRow(
                                  icon: Icons.receipt_long_outlined,
                                  label: 'Transaction ID',
                                  value: _truncateId(data['txnId'] ?? 'â€”'),
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  showCopy: (data['txnId'] ?? '').toString().isNotEmpty,
                                  fullValue: data['txnId'] ?? '',
                                  context: context,
                                ),
                                _rowDivider(isDark),
                                _detailRow(
                                  icon: Icons.account_balance_wallet_outlined,
                                  label: 'Target Account',
                                  value: data['account'] ?? 'â€”',
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  context: context,
                                ),
                                _rowDivider(isDark),
                                _detailRow(
                                  icon: Icons.check_circle_outline,
                                  label: 'Status',
                                  value: data['status'] ?? 'COMPLETED',
                                  primaryText: primaryText,
                                  secondaryText: secondaryText,
                                  valueColor: const Color(0xFF16A34A),
                                  context: context,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // â”€â”€ Done button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 24.h),
              child: CustomButton(
                text: 'BACK TO HOME', svgIconPath: 'assets/buttons/back-home.svg',
                onPressed: () => _navigateHome(context, ref),
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
            ),
          ],
        ),    // closes Column
      ),      // closes SafeArea (body:)
    ),        // closes Scaffold (child:)
  );          // closes PopScope
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  String _getCommodityLabel() {
    final commodity = (data['commodity'] ?? '').toString().toUpperCase().trim();
    if (commodity.contains('GOLD')) return 'Gold 24K';
    if (commodity.contains('SILVER')) return 'Silver 999';
    // Fallback: return the raw value from API if available
    return commodity.isNotEmpty ? commodity : 'Gold 24K';
  }

  String _truncateId(String id) {
    if (id.length > 12) return '${id.substring(0, 12)}...';
    return id;
  }

  Widget _detailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color primaryText,
    required Color secondaryText,
    required BuildContext context,
    Color? valueColor,
    bool showCopy = false,
    String fullValue = '',
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
          Text(
            value,
            style: GoogleFonts.lora(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: valueColor ?? primaryText,
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
                AppToast.show(context, 'Transaction ID copied',
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

  Widget _rowDivider(bool isDark) {
    return Divider(
      height: 1,
      thickness: 1,
      color: isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFF3F4F6),
    );
  }

  void _navigateHome(BuildContext context, WidgetRef ref) {
    final container = ProviderScope.containerOf(context);
    container.read(portfolioProvider.notifier).fetchPortfolio();
    container.invalidate(homeDashboardProvider);
    container.invalidate(profileProvider);

    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRouter.home,
      (route) => false,
    );
  }
}
