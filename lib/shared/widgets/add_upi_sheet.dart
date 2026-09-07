import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import '../../core/providers/user_provider.dart';
import '../../core/utils/kyc_validator.dart';
import '../../features/profile/services/bank_details_service.dart';
import 'custom_button.dart';
import 'app_toast.dart';
import 'secure_clipboard.dart';

/// Shared "Add UPI" bottom sheet — same field/verify pattern as Withdrawal's
/// UPI form (upi_selection_screen.dart), reused here for Profile → Bank
/// Details so a customer can add a VPA without leaving that screen. The
/// added UPI is verified standalone (no bank_id sent) — it is NOT
/// automatically shown under any one bank card; only a UPI Reverse Penny
/// Drop has proven paid from that specific account gets that link (see
/// BankAccount.linkedUpis / CustomerUPI.cupi_cbank_id on the backend).
///
/// Returns the Future from the underlying showModalBottomSheet() call —
/// same fire-and-forget-or-await contract as showAddBankAccountSheet().
Future<void> showAddUpiSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool isDark,
  required VoidCallback onAdded,
}) {
  const accentGreen = Color(0xFF1B882C);
  const gradientDark = Color(0xFF003716);

  final ctrl = TextEditingController();
  bool isVerifying = false;

  Future<void> processAdd(
    BuildContext sheetCtx,
    StateSetter setModalState,
  ) async {
    final upi = ctrl.text.trim();
    final upiError = KycValidator.validateUPI(upi);
    if (upiError != null) {
      AppToast.show(sheetCtx, upiError, type: ToastType.error);
      return;
    }
    final user = ref.read(userProvider);
    if (user == null) return;

    setModalState(() => isVerifying = true);
    try {
      final result = await ref
          .read(bankDetailsServiceProvider)
          .verifyAndAddUpi(mobile: user.mobile, upiId: upi);
      if (!sheetCtx.mounted) return;
      if (result['success'] == true) {
        Navigator.pop(sheetCtx);
        onAdded();
        if (context.mounted) {
          AppToast.show(
            context,
            result['message'] ?? 'UPI verified successfully',
            type: ToastType.success,
          );
        }
      } else {
        setModalState(() => isVerifying = false);
        AppToast.show(sheetCtx, result['message'] ?? 'Verification failed',
            type: ToastType.error);
      }
    } catch (e) {
      if (sheetCtx.mounted) {
        setModalState(() => isVerifying = false);
        AppToast.show(sheetCtx, 'Could not verify UPI. Please try again.',
            type: ToastType.error);
      }
    }
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setModalState) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF0F172A)])
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFDEF9DF), Color(0xFFFFFFFF)],
                      stops: [-0.3775, 1.0],
                    ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36.w,
                    height: 4.h,
                    decoration: BoxDecoration(
                        color: Colors.black12, borderRadius: BorderRadius.circular(4.r)),
                  ),
                ),
                SizedBox(height: 20.h),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Add UPI', style: AppTextStyles.titleLarge(isDark)),
                    GestureDetector(
                      onTap: isVerifying ? null : () => Navigator.pop(sheetCtx),
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.05),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.close_rounded, size: 18.sp, color: Colors.black54),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4.h),
                Text(
                  'Add a UPI ID for quick payments and withdrawals.',
                  style: AppTextStyles.fieldHelper(isDark),
                ),
                SizedBox(height: 24.h),
                Text('Enter UPI ID', style: AppTextStyles.fieldLabel(isDark)),
                SizedBox(height: 8.h),
                TextField(
                  controller: ctrl,
                  enabled: !isVerifying,
                  onChanged: (_) => setModalState(() {}),
                  contextMenuBuilder: SecureClipboard.none,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._@-]')),
                    LengthLimitingTextInputFormatter(256),
                  ],
                  style: AppTextStyles.kycFieldInput(isDark),
                  decoration: InputDecoration(
                    hintText: 'example@upi',
                    hintStyle: AppTextStyles.kycFieldHint(isDark),
                    errorStyle: AppTextStyles.fieldError(isDark),
                    filled: true,
                    fillColor: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF3F4F6),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14.r),
                        borderSide: const BorderSide(color: accentGreen, width: 1.5)),
                    contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
                  ),
                ),
                SizedBox(height: 28.h),
                CustomButton(
                  text: 'Verify & Add',
                  isLoading: isVerifying,
                  loadingText: 'Verifying...',
                  onPressed: (ctrl.text.trim().isNotEmpty && !isVerifying)
                      ? () => processAdd(sheetCtx, setModalState)
                      : null,
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [accentGreen, gradientDark],
                  ),
                  boxShadow: (ctrl.text.trim().isNotEmpty && !isVerifying)
                      ? [
                          BoxShadow(
                            color: accentGreen.withOpacity(0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                SizedBox(height: 8.h),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
