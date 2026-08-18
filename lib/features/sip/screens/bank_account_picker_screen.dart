import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/add_bank_account_sheet.dart';
import '../../profile/models/bank_account.dart';
import '../../profile/services/bank_details_service.dart';

const _accentGreen = Color(0xFF1B882C);

/// Full-page bank-account picker — used by both the Setup Auto Savings flow
/// (KYC gate → this page → payment method) and Withdrawal's payout-account
/// selection. Reuses [bankAccountsProvider]/[BankAccount] from the Bank
/// Details screen — this is a select-and-return picker, not a management
/// screen, so only verified accounts are tappable. Push with
/// `Navigator.push<BankAccount>` and await the popped result (null if the
/// customer backs out without selecting).
class BankAccountPickerScreen extends ConsumerWidget {
  final String subtitle;

  const BankAccountPickerScreen({
    super.key,
    this.subtitle = 'Auto Savings debits from this registered account.',
  });

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
                subtitle,
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
    return GestureDetector(
      onTap: selectable ? () => Navigator.pop(context, account) : null,
      child: Container(
        margin: EdgeInsets.only(bottom: 12.h),
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: account.isPrimary
                ? _accentGreen
                : (isDark ? Colors.white12 : const Color(0x330E5723)),
            width: account.isPrimary ? 1.5 : 0.5,
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Opacity(
          opacity: selectable ? 1 : 0.55,
          child: Row(
            children: [
              // ── Verified/pending indicator dot ──────────────────────
              Container(
                width: 22.w,
                height: 22.w,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selectable
                      ? _accentGreen
                      : Colors.orange.withOpacity(0.15),
                  border: Border.all(
                    color: selectable ? _accentGreen : Colors.orange,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  selectable
                      ? Icons.check_rounded
                      : Icons.hourglass_top_rounded,
                  color: selectable ? Colors.white : Colors.orange,
                  size: 13.sp,
                ),
              ),
              SizedBox(width: 14.w),

              // ── Text ─────────────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.bankName,
                        style: GoogleFonts.playfairDisplay(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                          color: isDark ? Colors.white : Colors.black87,
                        )),
                    SizedBox(height: 2.h),
                    Text('${account.accountNumberMasked}  •  ${account.ifscCode}',
                        style: GoogleFonts.lora(
                          fontSize: 12.sp,
                          color: isDark ? Colors.white54 : Colors.black45,
                        )),
                  ],
                ),
              ),

              // ── Badge ────────────────────────────────────────────────
              if (account.isPrimary)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: _accentGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text('primary',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                        color: _accentGreen,
                      )),
                )
              else if (!selectable)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Text('pending',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.orange,
                      )),
                ),
            ],
          ),
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
