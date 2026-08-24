import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import '../models/bank_verification_history.dart';
import '../services/bank_verification_history_service.dart';
import '../../../routes/app_router.dart';

/// Profile > "Bank Account Verification" — one card per verification
/// attempt, each card holding up to 3 lines: BAV / Rs.1 Payment / Rs.1
/// Refund. Replaces the previous 3-card nav hub with a single page.
class BankVerificationHubScreen extends ConsumerWidget {
  const BankVerificationHubScreen({super.key});

  static const _accentGreen = Color(0xFF1B882C);

  String _formatDate(DateTime? dt) {
    if (dt == null) return '--';
    return DateFormat('dd/MM/yyyy, h:mm a').format(dt.toLocal());
  }

  Color _statusColor(BankTimelineEntry entry) {
    final s = entry.status.toLowerCase();
    if (s == 'approved' || s == 'paid' || s == 'success') return _accentGreen;
    if (s == 'rejected' || s == 'failed') return Colors.red;
    if (s == 'not initiated') return Colors.grey;
    return Colors.orange; // pending / initiated
  }

  IconData _kindIcon(BankTimelineKind kind) {
    switch (kind) {
      case BankTimelineKind.bav:
        return Icons.account_balance_rounded;
      case BankTimelineKind.pennyPayment:
        return Icons.currency_rupee_rounded;
      case BankTimelineKind.pennyRefund:
        return Icons.replay_circle_filled_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bavAsync = ref.watch(bavHistoryProvider);
    final pennyAsync = ref.watch(pennyVerifyHistoryProvider);

    final isLoading = bavAsync.isLoading || pennyAsync.isLoading;
    final hasError = bavAsync.hasError || pennyAsync.hasError;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Bank Account Verification'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(bavHistoryProvider);
                ref.invalidate(pennyVerifyHistoryProvider);
              },
              child: isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accentGreen))
                  : hasError
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: 120.h),
                            Center(
                              child: Text(
                                'Could not load verification history.',
                                style: GoogleFonts.playfairDisplay(
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : _buildCards(
                          context,
                          ref,
                          isDark,
                          BankVerificationCard.build(
                            bavAsync.value ?? [],
                            pennyAsync.value ?? [],
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCards(
    BuildContext context,
    WidgetRef ref,
    bool isDark,
    List<BankVerificationCard> cards,
  ) {
    if (cards.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: 80.h),
          Center(
            child: Text(
              'No bank account verification activity yet.',
              style: GoogleFonts.playfairDisplay(
                  fontSize: 14.sp,
                  color: isDark ? Colors.white54 : Colors.black54),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.all(20.w),
      itemCount: cards.length,
      itemBuilder: (context, index) =>
          _buildCard(context, ref, cards[index], isDark),
    );
  }

  Widget _buildCard(
    BuildContext context,
    WidgetRef ref,
    BankVerificationCard card,
    bool isDark,
  ) {
    final lines = [card.bav, card.payment, card.refund]
        .whereType<BankTimelineEntry>()
        .toList();

    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
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
          NumericStyledText(
            card.bankLabel,
            fontSize: 13.sp,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1E293B),
          ),
          SizedBox(height: 10.h),
          for (int i = 0; i < lines.length; i++) ...[
            if (i > 0) ...[
              SizedBox(height: 8.h),
              Divider(
                  height: 1,
                  color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06)),
              SizedBox(height: 8.h),
            ],
            _buildLine(lines[i], isDark),
          ],
          // Optional SurePass extra check — only shown once BAV is Verified
          // AND the backend resolved a live cbank_id for it (see
          // BavHistoryItem.cbankId doc comment). Separate from the
          // Rs.1-payment lines above (Cashfree's own layer).
          if (card.bav != null &&
              card.bav!.displayStatus == 'Verified' &&
              card.bav!.cbankId != null) ...[
            SizedBox(height: 10.h),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final confirmed = await Navigator.pushNamed(
                    context,
                    AppRouter.reversePennyDrop,
                    arguments: {'cbankId': card.bav!.cbankId},
                  );
                  if (confirmed == true) {
                    ref.invalidate(bavHistoryProvider);
                    ref.invalidate(pennyVerifyHistoryProvider);
                  }
                },
                icon: Icon(Icons.verified_user_outlined, size: 16.sp, color: _accentGreen),
                label: Text(
                  'Additional Verification (Reverse Penny Drop)',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLine(BankTimelineEntry entry, bool isDark) {
    final color = _statusColor(entry);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(9.r),
          ),
          child: Icon(_kindIcon(entry.kind), color: color, size: 16.sp),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.title,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(100.r),
                    ),
                    child: Text(entry.displayStatus,
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w800,
                            color: color)),
                  ),
                ],
              ),
              SizedBox(height: 4.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  NumericStyledText(
                    _formatDate(entry.dateTime),
                    fontSize: 11.sp,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  if (entry.provider != null)
                    Text(
                      entry.provider!,
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
        ),
      ],
    );
  }
}
