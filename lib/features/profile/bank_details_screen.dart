import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/widgets/gradient_header.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/add_bank_account_sheet.dart';
import '../../core/error/failures.dart';
import '../../routes/app_router.dart';
import 'models/bank_account.dart';
import 'services/bank_details_service.dart';
import 'services/bank_verification_history_service.dart';
import '../kyc/controllers/kyc_controller.dart';

class BankDetailsScreen extends ConsumerWidget {
  const BankDetailsScreen({super.key});

  static const _accentGreen = Color(0xFF1B882C);

  Future<void> _confirmRemove(
      BuildContext context, WidgetRef ref, BankAccount account) async {
    final confirmed = await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Dismiss',
          barrierColor: Colors.black.withOpacity(0.6),
          transitionDuration: const Duration(milliseconds: 280),
          transitionBuilder: (ctx, a1, a2, child) {
            return ScaleTransition(
              scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
              child: FadeTransition(opacity: a1, child: child),
            );
          },
          pageBuilder: (ctx, _, __) => _RemoveBankDialog(account: account),
        ) ??
        false;
    if (confirmed != true) return;

    try {
      await ref.read(bankDetailsServiceProvider).removeBank(account.idBank);
      ref.invalidate(bankAccountsProvider);
      // The KYC checklist's Bank Account Validation card (and its PAN-Bank
      // Link / RPD sub-items) read bavHistoryProvider/rpdHistoryProvider/
      // verificationStatusProvider — without this, a KYC screen already
      // open in the widget tree keeps showing the removed account as
      // Verified until it's reopened.
      ref.invalidate(bavHistoryProvider);
      ref.invalidate(rpdHistoryProvider);
      ref.invalidate(verificationStatusProvider);
      if (context.mounted) {
        AppToast.show(context, 'Bank account removed', type: ToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        final message =
            e is Failure ? e.message : 'Could not remove this bank account.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  /// Pending accounts previously had no way forward from this screen at
  /// all — the card just showed an "Pending Verification" label with no
  /// tap target. Sends the customer straight to the ₹1 penny-drop screen
  /// for THIS account; on success, refreshes the list so it re-renders as
  /// Verified immediately.
  Future<void> _verifyPendingAccount(
      BuildContext context, WidgetRef ref, BankAccount account) async {
    final verified = await Navigator.pushNamed(
      context,
      AppRouter.reversePennyDrop,
      arguments: {'cbankId': account.idBank},
    );
    if (verified == true) {
      ref.invalidate(bankAccountsProvider);
    }
  }

  /// "+Add UPI" on a Verified account — reuses the SAME ₹1 Reverse Penny
  /// Drop flow [_verifyPendingAccount] uses, rather than a standalone VPA
  /// text-field verify: RPD is the only mechanism that actually proves a
  /// UPI pays from THIS specific account (see reverse_penny_drop_status's
  /// account-match on the backend), so this is the one path that can add
  /// an entry to [BankAccount.linkedUpis] at all.
  Future<void> _addUpi(
      BuildContext context, WidgetRef ref, BankAccount account) async {
    final verified = await Navigator.pushNamed(
      context,
      AppRouter.reversePennyDrop,
      arguments: {'cbankId': account.idBank},
    );
    if (verified == true) {
      ref.invalidate(bankAccountsProvider);
    }
  }

  Future<void> _confirmRemoveUpi(
      BuildContext context, WidgetRef ref, LinkedUpi upi) async {
    final confirmed = await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Dismiss',
          barrierColor: Colors.black.withOpacity(0.6),
          transitionDuration: const Duration(milliseconds: 280),
          transitionBuilder: (ctx, a1, a2, child) {
            return ScaleTransition(
              scale: CurvedAnimation(parent: a1, curve: Curves.easeOutBack),
              child: FadeTransition(opacity: a1, child: child),
            );
          },
          pageBuilder: (ctx, _, __) => _RemoveUpiDialog(upi: upi),
        ) ??
        false;
    if (confirmed != true) return;

    try {
      await ref.read(bankDetailsServiceProvider).removeUpi(upi.id);
      ref.invalidate(bankAccountsProvider);
      if (context.mounted) {
        AppToast.show(context, 'UPI removed', type: ToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is Failure ? e.message : 'Could not remove this UPI.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  Future<void> _setPrimary(
      BuildContext context, WidgetRef ref, BankAccount account) async {
    try {
      await ref.read(bankDetailsServiceProvider).setPrimary(account.idBank);
      ref.invalidate(bankAccountsProvider);
      if (context.mounted) {
        AppToast.show(context, '${account.bankName} set as Primary account',
            type: ToastType.success);
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is Failure
            ? e.message
            : 'Could not set this account as Primary.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accountsAsync = ref.watch(bankAccountsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Bank Details'),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.invalidate(bankAccountsProvider),
              child: accountsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator(color: _accentGreen)),
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
                      _buildBankCard(context, ref, account, isDark),
                    if (accounts.any((a) => a.isVerified)) ...[
                      SizedBox(height: 8.h),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: () => Navigator.pushNamed(
                              context, AppRouter.bankVerificationHub),
                          child: Text(
                            'Bank Account Validation History',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                              color: _accentGreen,
                              decoration: TextDecoration.underline,
                              decorationColor: _accentGreen,
                            ),
                          ),
                        ),
                      ),
                    ],
                    SizedBox(height: 12.h),
                    _buildAddButton(context, ref, isDark),
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

  Widget _buildBankCard(
      BuildContext context, WidgetRef ref, BankAccount account, bool isDark) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                    Text(account.bankName,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        )),
                    SizedBox(height: 2.h),
                    Text('${account.accountNumberMasked}  •  ${account.ifscCode}',
                        style: GoogleFonts.lora(
                          fontSize: 12.sp,
                          color: isDark ? Colors.white54 : Colors.black54,
                        )),
                  ],
                ),
              ),
              if (account.isPrimary)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
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
          SizedBox(height: 12.h),
          Row(
            children: [
              Icon(
                account.isVerified
                    ? Icons.verified_rounded
                    : Icons.hourglass_top_rounded,
                size: 14.sp,
                color: account.isVerified ? _accentGreen : Colors.orange,
              ),
              SizedBox(width: 4.w),
              Text(
                account.isVerified ? 'Verified' : 'Pending Verification',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: account.isVerified ? _accentGreen : Colors.orange,
                ),
              ),
              const Spacer(),
              if (!account.isVerified)
                TextButton(
                  onPressed: () => _verifyPendingAccount(context, ref, account),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8.w)),
                  child: Text('Verify Now',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade800)),
                )
              else if (!account.isPrimary)
                TextButton(
                  onPressed: () => _setPrimary(context, ref, account),
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 8.w)),
                  child: Text('Set as Primary',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: _accentGreen)),
                ),
              IconButton(
                onPressed: () => _confirmRemove(context, ref, account),
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20.sp, color: Colors.red.withOpacity(0.7)),
                tooltip: 'Remove',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          // UPI(s) proven (via Reverse Penny Drop) to pay from THIS account —
          // see BankAccount.linkedUpis. Only offered once the account itself
          // is Verified; a UPI added here has no bank to link to until an
          // RPD attempt cross-checks it against this specific account.
          if (account.isVerified) ...[
            SizedBox(height: 12.h),
            Wrap(
              spacing: 8.w,
              runSpacing: 8.h,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final upi in account.linkedUpis)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: _accentGreen.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(100.r),
                      border: Border.all(color: _accentGreen.withOpacity(0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified_rounded, size: 12.sp, color: _accentGreen),
                        SizedBox(width: 4.w),
                        Text(upi.upiId,
                            style: GoogleFonts.lora(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : const Color(0xFF1E293B),
                            )),
                        SizedBox(width: 4.w),
                        InkWell(
                          onTap: () => _confirmRemoveUpi(context, ref, upi),
                          borderRadius: BorderRadius.circular(100.r),
                          child: Icon(Icons.close_rounded,
                              size: 13.sp, color: _accentGreen.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                InkWell(
                  onTap: () => _addUpi(context, ref, account),
                  borderRadius: BorderRadius.circular(100.r),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100.r),
                      border: Border.all(color: _accentGreen.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, size: 13.sp, color: _accentGreen),
                        SizedBox(width: 2.w),
                        Text('Add UPI',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w700,
                              color: _accentGreen,
                            )),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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

/// Destructive-action confirmation for Remove Bank Account — mirrors the
/// styled dialog on the Delete Account screen (icon badge, rounded card,
/// gradient confirm button) instead of a default AlertDialog, so it matches
/// the app's design system.
class _RemoveBankDialog extends StatelessWidget {
  final BankAccount account;

  const _RemoveBankDialog({required this.account});

  static const _danger = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(28.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _danger.withOpacity(0.08),
                border: Border.all(color: _danger.withOpacity(0.2), width: 1.5),
              ),
              child: Icon(Icons.delete_outline_rounded, color: _danger, size: 30.sp),
            ),
            SizedBox(height: 20.h),
            Text(
              'Remove Bank Account?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              '${account.bankName}  ${account.accountNumberMasked}',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151),
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                'You can add this account again anytime — your verification\nhistory is kept.',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
            ),
            SizedBox(height: 24.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: BorderSide(color: Colors.black.withOpacity(0.12)),
                      minimumSize: Size(0, 50.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50.r),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 14.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment(-0.87, -0.5),
                        end: Alignment(0.87, 0.5),
                        colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
                      ),
                      borderRadius: BorderRadius.circular(50.r),
                      boxShadow: [
                        BoxShadow(
                          color: _danger.withOpacity(0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        minimumSize: Size(0, 50.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50.r),
                        ),
                      ),
                      child: Text(
                        'Yes, Remove',
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 14.sp, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveUpiDialog extends StatelessWidget {
  final LinkedUpi upi;

  const _RemoveUpiDialog({required this.upi});

  static const _danger = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.all(28.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.w,
              height: 64.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _danger.withOpacity(0.08),
                border: Border.all(color: _danger.withOpacity(0.2), width: 1.5),
              ),
              child: Icon(Icons.delete_outline_rounded, color: _danger, size: 30.sp),
            ),
            SizedBox(height: 20.h),
            Text(
              'Remove UPI?',
              style: GoogleFonts.playfairDisplay(
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              upi.upiId,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 14.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF374151),
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: _danger.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Text(
                'You can add it again anytime with a fresh ₹1 verification.',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
            ),
            SizedBox(height: 24.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: BorderSide(color: Colors.black.withOpacity(0.12)),
                      minimumSize: Size(0, 50.h),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(50.r),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 14.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment(-0.87, -0.5),
                        end: Alignment(0.87, 0.5),
                        colors: [Color(0xFFB91C1C), Color(0xFFEF4444)],
                      ),
                      borderRadius: BorderRadius.circular(50.r),
                      boxShadow: [
                        BoxShadow(
                          color: _danger.withOpacity(0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        minimumSize: Size(0, 50.h),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(50.r),
                        ),
                      ),
                      child: Text(
                        'Yes, Remove',
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 14.sp, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
