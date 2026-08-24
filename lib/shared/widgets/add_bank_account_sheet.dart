import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import '../../core/providers/user_provider.dart';
import '../../core/error/failures.dart';
import '../../features/withdrawal/services/withdrawal_service.dart';
import '../../features/profile/services/bank_details_service.dart';
import '../../features/profile/screens/bank_penny_verify_screen.dart';
import 'custom_button.dart';
import 'app_toast.dart';
import 'secure_clipboard.dart';

/// Shared "Add Bank Account" bottom sheet — penny-drop verify & save, with a
/// live Beneficiary Name check (on field-blur) against the customer's
/// verified PAN/Aadhaar name before "Verify & Add" is enabled. Used by both
/// the Withdrawal bank-selection screen and Profile → Bank Details, so the
/// add-bank flow only exists once. The server (verify_bank) is the
/// authoritative gate — this is a pre-flight UX check only.
final _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');

void showAddBankAccountSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool isDark,
  required VoidCallback onAdded,
}) {
  const accentGreen = Color(0xFF1B882C);
  const gradientDark = Color(0xFF003716);

  final nameCtrl = TextEditingController();
  final accCtrl = TextEditingController();
  final confirmAccCtrl = TextEditingController();
  final ifscCtrl = TextEditingController();
  final nameFocus = FocusNode();
  bool isVerifying = false;
  bool isCheckingName = false;
  String? nameError;
  bool nameMatched = false;

  // StatefulBuilder hands back the SAME StateSetter across rebuilds (it's
  // bound to the underlying State), so capturing it here and registering
  // the FocusNode listener ONCE outside builder is safe — and necessary:
  // registering inside builder would re-add a new listener on every
  // rebuild, firing checkName() multiple times per single field blur.
  StateSetter? modalSetState;

  Future<void> checkName() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      modalSetState?.call(() {
        nameError = null;
        nameMatched = false;
      });
      return;
    }
    modalSetState?.call(() => isCheckingName = true);
    try {
      final result =
          await ref.read(bankDetailsServiceProvider).checkBeneficiaryName(name);
      modalSetState?.call(() {
        isCheckingName = false;
        nameMatched = result['matched'] == true;
        nameError = nameMatched ? null : result['message']?.toString();
      });
    } catch (_) {
      // Non-blocking: server-side verify_bank() still enforces this
      // rule, so a transient check failure shouldn't lock the form.
      modalSetState?.call(() {
        isCheckingName = false;
        nameMatched = true;
        nameError = null;
      });
    }
  }

  nameFocus.addListener(() {
    if (!nameFocus.hasFocus) checkName();
  });

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        modalSetState = setModalState;

        final canSubmit = nameCtrl.text.trim().isNotEmpty &&
            nameMatched &&
            accCtrl.text.trim().length >= 9 &&
            confirmAccCtrl.text.trim() == accCtrl.text.trim() &&
            _ifscRegex.hasMatch(ifscCtrl.text.trim().toUpperCase()) &&
            !isVerifying &&
            !isCheckingName;

        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: Container(
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF0F172A)])
                  : const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFDEF9DF), Color(0xFFFFFFFF)],
                      stops: [-0.3775, 1.0],
                    ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(4.r)),
                    ),
                  ),
                  SizedBox(height: 20.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Add Bank Account',
                          style: AppTextStyles.titleLarge(isDark)),
                      GestureDetector(
                        onTap: () {
                          if (!isVerifying) Navigator.pop(sheetCtx);
                        },
                        child: Container(
                          padding: EdgeInsets.all(6.w),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.close_rounded,
                              size: 18.sp, color: Colors.black54),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  _field('Beneficiary Name', 'Enter full name', nameCtrl,
                      isDark,
                      focusNode: nameFocus,
                      forceUpperCase: true,
                      lettersOnly: true,
                      errorText: nameError,
                      suffix: isCheckingName
                          ? SizedBox(
                              width: 16.w,
                              height: 16.w,
                              child: const CircularProgressIndicator(
                                  strokeWidth: 2, color: accentGreen),
                            )
                          : (nameMatched
                              ? Icon(Icons.check_circle_rounded,
                                  color: accentGreen, size: 20.sp)
                              : null),
                      onChanged: (_) => setModalState(() {
                        nameMatched = false;
                        nameError = null;
                      })),
                  SizedBox(height: 12.h),
                  _field('Account Number', 'Enter account number', accCtrl,
                      isDark,
                      kbd: TextInputType.number,
                      digitsOnly: true,
                      onChanged: (_) => setModalState(() {})),
                  SizedBox(height: 12.h),
                  _field('Confirm Account Number', 'Re-enter account number',
                      confirmAccCtrl, isDark,
                      kbd: TextInputType.number,
                      digitsOnly: true,
                      onChanged: (_) => setModalState(() {})),
                  if (confirmAccCtrl.text.isNotEmpty &&
                      accCtrl.text.trim() != confirmAccCtrl.text.trim()) ...[
                    SizedBox(height: 6.h),
                    Text('Account numbers do not match',
                        style: AppTextStyles.fieldError(isDark)),
                  ],
                  SizedBox(height: 12.h),
                  _field('IFSC Code', 'e.g. SBIN0001234', ifscCtrl, isDark,
                      forceUpperCase: true,
                      ifscOnly: true,
                      onChanged: (_) => setModalState(() {})),
                  SizedBox(height: 28.h),
                  CustomButton(
                    text: 'Verify & Add',
                    isLoading: isVerifying,
                    loadingText: 'Verifying...',
                    onPressed: canSubmit
                        ? () async {
                            final user = ref.read(userProvider);
                            if (user == null) return;
                            setModalState(() => isVerifying = true);
                            try {
                              final withdrawalSvc = ref.read(withdrawalServiceProvider);
                              // Which BAV method the active KYC gateway supports —
                              // never hardcode a provider name client-side (see
                              // getActiveBankVerificationMethod's doc comment).
                              final method =
                                  await withdrawalSvc.getActiveBankVerificationMethod();
                              final isPennyless = method == 'pennyless';

                              final result = isPennyless
                                  ? await withdrawalSvc.verifyAndAddBankPennyless(
                                      holderName: nameCtrl.text.trim(),
                                      accNo: accCtrl.text.trim(),
                                      ifsc: ifscCtrl.text.trim(),
                                    )
                                  : await withdrawalSvc.verifyAndAddBank(
                                      customerId: user.id,
                                      mobile: user.mobile,
                                      holderName: nameCtrl.text.trim(),
                                      bankName: '',
                                      accNo: accCtrl.text.trim(),
                                      ifsc: ifscCtrl.text.trim(),
                                    );
                              if (!sheetCtx.mounted) return;
                              if (result['success'] == true) {
                                Navigator.pop(sheetCtx);
                                // Defer the provider invalidation, toast, and
                                // next-screen push to the following frame —
                                // stacking a ref.invalidate() (rebuilds the
                                // Bank Details screen underneath), an
                                // AppToast (inserts its own OverlayEntry),
                                // and a Navigator.push all synchronously
                                // right after Navigator.pop(), with no frame
                                // to let the popped sheet's route actually
                                // finish tearing down, is what was causing
                                // "_dependents.isEmpty" InheritedElement
                                // crashes when navigating back through Bank
                                // Details.
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  onAdded();
                                  if (context.mounted) {
                                    AppToast.show(
                                      context,
                                      result['message'] ??
                                          'Bank account verified successfully',
                                      type: ToastType.success,
                                    );
                                  }
                                  // ── ₹1 verify layer — runs after Cashfree BAV succeeds only ──
                                  // id_payout is CustomerBank.cbank_id (see
                                  // CashfreeService.verify_bank()'s response —
                                  // the key name is a holdover from its payout-
                                  // beneficiary registration, not a payout itself).
                                  // SurePass Pennyless BAV is already instant/complete —
                                  // no extra payment step here; Reverse Penny Drop is a
                                  // separate OPTIONAL check reached from the Bank
                                  // Verification Hub instead (see reverse_penny_drop_screen.dart).
                                  final cbankId = (result['data']
                                          as Map<String, dynamic>?)?['id_payout']
                                      ?.toString();
                                  if (!isPennyless &&
                                      cbankId != null &&
                                      cbankId.isNotEmpty &&
                                      context.mounted) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BankPennyVerifyScreen(
                                            cbankId: cbankId),
                                      ),
                                    );
                                  }
                                });
                              } else {
                                setModalState(() => isVerifying = false);
                                final errMsg = result['message'] ??
                                    (result['error']
                                            as Map<String, dynamic>?)?['message'] ??
                                    (result['data']
                                            as Map<String, dynamic>?)?['message'] ??
                                    'Verification failed';
                                AppToast.show(sheetCtx, errMsg,
                                    type: ToastType.error);
                              }
                            } catch (e) {
                              if (sheetCtx.mounted) {
                                setModalState(() => isVerifying = false);
                                final message = e is Failure
                                    ? e.message
                                    : 'Could not verify bank details. Please try again.';
                                AppToast.show(sheetCtx, message,
                                    type: ToastType.error);
                              }
                            }
                          }
                        : null,
                    gradient: const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [accentGreen, gradientDark],
                    ),
                    boxShadow: canSubmit
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
        );
      },
    ),
  ).whenComplete(() => nameFocus.dispose());
}

Widget _field(
    String label, String hint, TextEditingController ctrl, bool isDark,
    {TextInputType kbd = TextInputType.text,
    bool forceUpperCase = false,
    bool lettersOnly = false,
    bool digitsOnly = false,
    bool ifscOnly = false,
    FocusNode? focusNode,
    String? errorText,
    Widget? suffix,
    ValueChanged<String>? onChanged}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppTextStyles.fieldLabel(isDark)),
      SizedBox(height: 8.h),
      TextField(
        controller: ctrl,
        focusNode: focusNode,
        onChanged: onChanged,
        keyboardType: kbd,
        contextMenuBuilder: SecureClipboard.none,
        textCapitalization:
            forceUpperCase ? TextCapitalization.characters : TextCapitalization.none,
        inputFormatters: [
          // Beneficiary name: letters and spaces only — no digits/symbols.
          if (lettersOnly) FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
          if (lettersOnly) LengthLimitingTextInputFormatter(60),
          // Account number: digits only — keyboardType alone doesn't block
          // letters/symbols pasted in or typed via an alternate keyboard.
          if (digitsOnly) FilteringTextInputFormatter.digitsOnly,
          if (digitsOnly) LengthLimitingTextInputFormatter(20),
          // IFSC: letters+digits only, exactly 11 chars (AAAA0999999).
          if (ifscOnly) FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          if (ifscOnly) LengthLimitingTextInputFormatter(11),
          if (forceUpperCase)
            TextInputFormatter.withFunction((oldValue, newValue) =>
                newValue.copyWith(text: newValue.text.toUpperCase())),
        ],
        style: AppTextStyles.kycFieldInput(isDark),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: AppTextStyles.kycFieldHint(isDark),
          errorStyle: AppTextStyles.fieldError(isDark),
          filled: true,
          fillColor:
              isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF3F4F6),
          suffixIcon: suffix != null
              ? Padding(padding: EdgeInsets.all(12.w), child: suffix)
              : null,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: const BorderSide(color: Color(0xFF1B882C), width: 1.5)),
          contentPadding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 16.h),
        ),
      ),
      if (errorText != null) ...[
        SizedBox(height: 6.h),
        Text(errorText, style: AppTextStyles.fieldError(isDark)),
      ],
    ],
  );
}
