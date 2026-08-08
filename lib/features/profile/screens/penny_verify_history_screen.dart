import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import '../models/bank_verification_history.dart';
import '../services/bank_verification_history_service.dart';

class PennyVerifyHistoryScreen extends ConsumerWidget {
  const PennyVerifyHistoryScreen({super.key});

  static const _accentGreen = Color(0xFF1B882C);

  String _formatDate(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('dd/MM/yyyy, h:mm a').format(dt.toLocal());
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return _accentGreen;
      case 'failed':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final historyAsync = ref.watch(pennyVerifyHistoryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Rs.1 Payment Verification History'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(pennyVerifyHistoryProvider),
              child: historyAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: _accentGreen)),
                error: (err, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 120.h),
                    Center(
                      child: Text('Could not load payment history.',
                          style: GoogleFonts.playfairDisplay(
                              color: isDark ? Colors.white54 : Colors.black54)),
                    ),
                  ],
                ),
                data: (items) => ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.all(20.w),
                  children: [
                    if (items.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 80.h),
                        child: Center(
                          child: Text(
                            'No Rs.1 verification payments yet.',
                            style: GoogleFonts.playfairDisplay(
                                fontSize: 14.sp,
                                color: isDark ? Colors.white54 : Colors.black54),
                          ),
                        ),
                      ),
                    for (final item in items) _buildCard(item, isDark),
                    SizedBox(height: 100.h),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(PennyVerifyHistoryItem item, bool isDark) {
    final color = _statusColor(item.status);
    return Container(
      margin: EdgeInsets.only(bottom: 14.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.08)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10.w),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(Icons.currency_rupee_rounded, color: color, size: 20.sp),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    NumericStyledText(
                      '${item.bankName ?? 'Bank'}${item.accountLast4 != null ? ' •• ${item.accountLast4}' : ''}',
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                    ),
                    SizedBox(height: 2.h),
                    NumericStyledText(
                      _formatDate(item.createdOn),
                      fontSize: 11.sp,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(100.r),
                ),
                child: Text(item.status,
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 10.sp, fontWeight: FontWeight.w800, color: color)),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          Divider(color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
          SizedBox(height: 8.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              NumericStyledText(
                'Amount: ₹${item.amount}',
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              if (item.paymentMethod != null)
                Text(
                  item.paymentMethod!.toUpperCase(),
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
