import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/add_bank_account_sheet.dart';
import '../../profile/models/bank_account.dart';
import '../../profile/services/bank_details_service.dart';

const _accentGreen = Color(0xFF1B882C);

/// Full-page bank-account picker for the Setup Auto Savings flow
/// (KYC gate → this page → payment method). Reuses [bankAccountsProvider]/
/// [BankAccount] from the Bank Details screen — this is a select-and-return
/// picker, not a management screen, so only verified accounts are tappable.
/// Push with `Navigator.push<BankAccount>` and await the popped result
/// (null if the customer backs out without selecting).
class BankAccountPickerScreen extends ConsumerWidget {
  const BankAccountPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accountsAsync = ref.watch(bankAccountsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Select Bank Account'),
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 4.h),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Auto Savings debits from this registered account.',
                style: GoogleFonts.lora(
                  fontSize: 12.sp,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(bankAccountsProvider),
              child: accountsAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(color: _accentGreen)),
                error: (err, _) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(height: 120.h),
                    Center(
                      child: Text('Could not load bank accounts.',
                          style: GoogleFonts.playfairDisplay(
                              color: isDark ? Colors.white54 : Colors.black54)),
                    ),
                  ],
                ),
                data: (accounts) => ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.all(20.w),
                  children: [
                    if (accounts.isEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 80.h),
                        child: Center(
                          child: Text(
                            'No bank accounts added yet.',
                            style: GoogleFonts.playfairDisplay(
                                fontSize: 14.sp,
                                color: isDark ? Colors.white54 : Colors.black54),
                          ),
                        ),
                      ),
                    for (final account in accounts)
                      _buildAccountTile(context, ref, account, isDark),
                    SizedBox(height: 12.h),
                    _buildAddButton(context, ref, isDark),
                    SizedBox(height: 40.h),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTile(BuildContext context, WidgetRef ref,
      BankAccount account, bool isDark) {
    final selectable = account.isVerified;
    return InkWell(
      onTap: selectable ? () => Navigator.pop(context, account) : null,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        margin: EdgeInsets.only(bottom: 14.h),
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: account.isPrimary
                ? _accentGreen.withOpacity(0.4)
                : (isDark ? Colors.white10 : Colors.black.withOpacity(0.08)),
            width: account.isPrimary ? 1.4 : 1,
          ),
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
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: _accentGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(Icons.account_balance_rounded,
                  color: _accentGreen, size: 20.sp),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(account.bankName,
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 15.sp,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            )),
                      ),
                      if (account.isPrimary)
                        Container(
                          padding:
                              EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: _accentGreen.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(100.r),
                          ),
                          child: Text('Primary',
                              style: GoogleFonts.playfairDisplay(
                                  fontSize: 10.sp,
                                  fontWeight: FontWeight.w800,
                                  color: _accentGreen)),
                        ),
                    ],
                  ),
                  SizedBox(height: 2.h),
                  Text('${account.accountNumberMasked}  •  ${account.ifscCode}',
                      style: GoogleFonts.lora(
                        fontSize: 12.sp,
                        color: isDark ? Colors.white54 : Colors.black54,
                      )),
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Icon(
                        selectable
                            ? Icons.verified_rounded
                            : Icons.hourglass_top_rounded,
                        size: 13.sp,
                        color: selectable ? _accentGreen : Colors.orange,
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        selectable ? 'Verified' : 'Pending Verification',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w600,
                          color: selectable ? _accentGreen : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (selectable)
              Icon(Icons.chevron_right_rounded,
                  color: isDark ? Colors.white38 : Colors.black26),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton(BuildContext context, WidgetRef ref, bool isDark) {
    return InkWell(
      onTap: () => showAddBankAccountSheet(
        context,
        ref,
        isDark: isDark,
        onAdded: () => ref.invalidate(bankAccountsProvider),
      ),
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 16.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: _accentGreen.withOpacity(0.4),
            style: BorderStyle.solid,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline_rounded, color: _accentGreen, size: 18.sp),
            SizedBox(width: 8.w),
            Text('Add Bank Account',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: _accentGreen)),
          ],
        ),
      ),
    );
  }
}
