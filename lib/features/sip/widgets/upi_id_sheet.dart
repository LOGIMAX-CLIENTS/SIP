// lib/features/sip/widgets/upi_id_sheet.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// UpiIdSheet — Bottom Sheet for picking which UPI ID the SIP mandate uses
//
// Shown by auto_savings_screen.dart right after PaymentMethodSheet when the
// customer picks "UPI". Lists the UPI IDs linked (via Reverse Penny Drop) to
// the bank account chosen in the Bank Listing picker — see
// BankAccount.linkedUpis. Always shown, even when there's only one UPI ID,
// so the customer explicitly confirms the VPA being mandated.
//
// Styled to match PaymentMethodSheet. Returns the selected LinkedUpi via
// onProceed; its id is the backend CustomerUPI pk sent as `upi_id`.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

import '../../profile/models/bank_account.dart';

class UpiIdSheet extends StatefulWidget {
  final List<LinkedUpi> upis;

  /// Callback when user taps "Proceed to Pay" with the selected UPI ID.
  final void Function(LinkedUpi upi) onProceed;

  const UpiIdSheet({
    super.key,
    required this.upis,
    required this.onProceed,
  });

  @override
  State<UpiIdSheet> createState() => _UpiIdSheetState();
}

class _UpiIdSheetState extends State<UpiIdSheet> {
  late String _selectedId = widget.upis.first.id;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drag handle ────────────────────────────────────────────
              Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),

              // ── Header row ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select UPI ID',
                    style: AppTextStyles.titleLarge(isDark)
                        .copyWith(color: Colors.black),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.05),
                      ),
                      child: Icon(Icons.close,
                          size: 18.sp, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              // ── UPI ID options card ────────────────────────────────────
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(color: Colors.black.withOpacity(0.06)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      children: widget.upis.asMap().entries.map((entry) {
                        final upi = entry.value;
                        final isLast = entry.key == widget.upis.length - 1;
                        return Column(
                          children: [
                            _buildOptionTile(upi, _selectedId == upi.id),
                            if (!isLast)
                              Divider(
                                height: 1,
                                indent: 16.w,
                                endIndent: 16.w,
                                color: Colors.black.withOpacity(0.06),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24.h),

              // ── Proceed to Pay button ──────────────────────────────────
              GestureDetector(
                onTap: () {
                  final upi =
                      widget.upis.firstWhere((u) => u.id == _selectedId);
                  Navigator.pop(context); // close sheet
                  // Deferred to the next frame — same reason as
                  // PaymentMethodSheet's "Proceed to Pay" (see its comment).
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.onProceed(upi);
                  });
                },
                child: Container(
                  width: double.infinity,
                  height: 56.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B882C), Color(0xFF003716)],
                    ),
                    borderRadius: BorderRadius.circular(50.r),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1B882C).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.white, size: 22.sp),
                      SizedBox(width: 10.w),
                      Text(
                        'Proceed to Pay',
                        style: AppTextStyles.button(isDark)
                            .copyWith(letterSpacing: 0.3),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile(LinkedUpi upi, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selectedId = upi.id),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            // ── Icon ──
            Container(
              width: 44.r,
              height: 44.r,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1B882C).withOpacity(0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1B882C).withOpacity(0.2)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              child: Icon(
                Icons.account_balance_wallet_rounded,
                color: isSelected ? const Color(0xFF1B882C) : Colors.black38,
                size: 22.sp,
              ),
            ),
            SizedBox(width: 14.w),

            // ── UPI ID + verified label ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upi.upiId,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  if (upi.isVerified) ...[
                    SizedBox(height: 4.h),
                    Row(
                      children: [
                        Icon(Icons.verified_rounded,
                            size: 12.sp, color: const Color(0xFF1B882C)),
                        SizedBox(width: 4.w),
                        Text(
                          'Verified',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            // ── Radio indicator ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24.r,
              height: 24.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF1B882C) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1B882C)
                      : Colors.black.withOpacity(0.2),
                  width: isSelected ? 0 : 2,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 16.sp, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
