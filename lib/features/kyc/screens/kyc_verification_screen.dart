import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/controllers/kyc_verification_flow_mixin.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/widgets/kyc_progress_header.dart';
import 'package:startgold/features/kyc/widgets/kyc_step_row.dart';
import 'package:startgold/features/profile/models/bank_account.dart';
import 'package:startgold/features/profile/models/bank_verification_history.dart';
import 'package:startgold/features/profile/profile_controller.dart' as pc;
import 'package:startgold/features/profile/services/bank_details_service.dart';
import 'package:startgold/features/profile/services/bank_verification_history_service.dart';
import 'package:startgold/routes/app_router.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import 'package:startgold/shared/widgets/add_bank_account_sheet.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/custom_button.dart';

/// Single-page, 7-step KYC + bank verification checklist:
/// PAN -> Aadhaar -> PAN-Aadhaar Link -> Name & DOB Match ->
/// Bank Account Verification (BAV) -> PAN-Bank Link -> Reverse Penny Drop.
///
/// PAN/Aadhaar are real, independently-verified backend flows (driven by
/// [KycVerificationFlowMixin], reusing the exact same providers as the live
/// `/kyc` screen). PAN-Aadhaar Link, Name & DOB Match, and PAN-Bank Link are
/// PRESENTATIONAL sub-statuses derived from fields the backend already
/// returns (`aadhaarPanLinked`, `kycConfirmed`, `BavHistoryItem.nameMatched`)
/// — there is no separate API call for any of them. Bank verification
/// (BAV/RPD) launches the app's EXISTING screens (`add_bank_account_sheet`,
/// `ReversePennyDropScreen`) rather than re-implementing those forms here —
/// bank account LISTING/UPI management stays on its own separate page.
class KycVerificationScreen extends ConsumerStatefulWidget {
  final String requestFrom;
  final Map<String, dynamic>? extraData;

  /// Set by [KycVerificationFlow.start] (the SIP/Withdrawal/Investment
  /// "KYC required" gate) — that caller only cares about PAN+Aadhaar, not
  /// the rest of the checklist's bank-verification steps, so this pops the
  /// screen with `true` the moment both are verified instead of leaving the
  /// user on the checklist to continue into bank verification. Left `false`
  /// for a plain Profile visit, where staying to walk the rest of the
  /// checklist is the point.
  final bool popWhenIdVerified;

  const KycVerificationScreen({
    super.key,
    required this.requestFrom,
    this.extraData,
    this.popWhenIdVerified = false,
  });

  @override
  ConsumerState<KycVerificationScreen> createState() => _KycVerificationScreenState();
}

class _KycVerificationScreenState extends ConsumerState<KycVerificationScreen>
    with KycVerificationFlowMixin<KycVerificationScreen> {
  final Set<int> _expanded = {};
  bool _defaultExpansionSet = false;
  int? _lastActiveIndex;
  bool _poppedForIdVerified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => checkAadhaarOutcomeRecoveryOnLoad(widget.requestFrom));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(kycDocumentsProvider(widget.requestFrom));
    final aadhaarState = ref.watch(aadhaarProvider);
    final bankAccountsAsync = ref.watch(bankAccountsProvider);
    final bavHistoryAsync = ref.watch(bavHistoryProvider);
    final rpdHistoryAsync = ref.watch(rpdHistoryProvider);
    final profileName = ref.watch(pc.profileProvider).user.name;

    return PopScope(
      canPop: !verificationInFlight,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        AppToast.show(context, 'Please wait — verification is in progress.', type: ToastType.info);
      },
      child: Container(
        decoration: BoxDecoration(gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: docsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (docsResult) {
              syncAadhaarWithBackend(docsResult);
              return _buildBody(
                isDark: isDark,
                docsResult: docsResult,
                aadhaarState: aadhaarState,
                bankAccounts: bankAccountsAsync.valueOrNull,
                bavHistory: bavHistoryAsync.valueOrNull,
                rpdHistory: rpdHistoryAsync.valueOrNull,
                bankDataLoading: bankAccountsAsync.isLoading || bavHistoryAsync.isLoading,
                profileName: profileName,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody({
    required bool isDark,
    required KycDocumentsResult docsResult,
    required AadhaarState aadhaarState,
    required List<BankAccount>? bankAccounts,
    required List<BavHistoryItem>? bavHistory,
    required List<RpdHistoryItem>? rpdHistory,
    required bool bankDataLoading,
    required String profileName,
  }) {
    final panDoc = docsResult.documents.where(
      (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
    );
    final panDocValue = panDoc.isEmpty ? null : panDoc.first;
    final panDone = panDocValue?.alreadyUploaded ?? false;
    final panUnderReview = panDocValue?.isUnderReview ?? false;

    final aadhaarBusy = verifyingAadhaar || aadhaarState.phase == AadhaarPhase.initiating || aadhaarState.phase == AadhaarPhase.polling;
    // During a PAN-only retry (retryingPanOnly), the Aadhaar provider phase
    // transitions through initiating/polling too (it's the SAME DigiLocker
    // session) even though Aadhaar itself isn't being re-verified — its
    // card must keep showing the Verified banner throughout, not flicker
    // back to a form.
    final aadhaarDone = aadhaarState.phase == AadhaarPhase.approved ||
        (docsResult.aadhaarApproved && !aadhaarEditing && (!aadhaarBusy || retryingPanOnly));
    final aadhaarUnderReview = docsResult.aadhaarUnderReview && !aadhaarEditing;
    final aadhaarFailedPhase = aadhaarState.phase == AadhaarPhase.expired ||
        aadhaarState.phase == AadhaarPhase.rejected ||
        aadhaarState.phase == AadhaarPhase.failed;
    final panSkippedInConsent = !panDone && !aadhaarEditing && (aadhaarState.phase == AadhaarPhase.approved || docsResult.aadhaarApproved);

    if (widget.popWhenIdVerified && panDone && aadhaarDone && !_poppedForIdVerified) {
      _poppedForIdVerified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    }

    // Step 1: PAN
    KycStepStatus step1Status;
    String step1Pill;
    if (panDone) {
      step1Status = KycStepStatus.verified;
      step1Pill = 'Verified';
    } else if (panUnderReview) {
      step1Status = KycStepStatus.underReview;
      step1Pill = 'Under Review';
    } else if (panSkippedInConsent) {
      step1Status = KycStepStatus.failed;
      step1Pill = 'Retry';
    } else {
      step1Status = KycStepStatus.actionable;
      step1Pill = 'Pending';
    }

    // Step 2: Aadhaar
    KycStepStatus step2Status;
    String step2Pill;
    if (aadhaarDone) {
      step2Status = KycStepStatus.verified;
      step2Pill = 'Verified';
    } else if (aadhaarUnderReview) {
      step2Status = KycStepStatus.underReview;
      step2Pill = 'Under Review';
    } else if (aadhaarBusy) {
      step2Status = KycStepStatus.inProgress;
      step2Pill = 'In Progress';
    } else if (aadhaarFailedPhase) {
      step2Status = KycStepStatus.failed;
      step2Pill = 'Retry';
    } else {
      step2Status = KycStepStatus.actionable;
      step2Pill = 'Pending';
    }

    // Step 3: PAN-Aadhaar Link (derived, live-session only)
    final bothIdVerified = panDone && aadhaarDone;
    KycStepStatus step3Status;
    String step3Pill;
    String step3Subtitle;
    if (!bothIdVerified) {
      step3Status = KycStepStatus.locked;
      step3Pill = 'Locked';
      step3Subtitle = 'Unlocks once PAN and Aadhaar are verified';
    } else if (aadhaarState.aadhaarPanLinked == true) {
      step3Status = KycStepStatus.verified;
      step3Pill = 'Verified';
      step3Subtitle = 'Linked as per Income Tax records';
    } else if (aadhaarState.aadhaarPanLinked == false) {
      step3Status = KycStepStatus.failed;
      step3Pill = 'Not Linked';
      step3Subtitle = 'Not linked as per Income Tax records';
    } else {
      step3Status = KycStepStatus.underReview;
      step3Pill = 'Pending';
      step3Subtitle = 'Link status refreshes the next time you verify';
    }

    // Step 4: Name & DOB Match
    KycStepStatus step4Status;
    String step4Pill;
    String step4Subtitle;
    if (!bothIdVerified) {
      step4Status = KycStepStatus.locked;
      step4Pill = 'Locked';
      step4Subtitle = 'Unlocks once PAN and Aadhaar are verified';
    } else if (docsResult.kycConfirmed) {
      step4Status = KycStepStatus.verified;
      step4Pill = 'Matched';
      step4Subtitle = 'PAN / Aadhaar matched with profile';
    } else {
      step4Status = KycStepStatus.inProgress;
      step4Pill = 'Pending';
      step4Subtitle = 'Confirm your verified details to finish this step';
    }

    // Step 5: Bank Account Verification (BAV)
    final sortedBav = [...?bavHistory]..sort((a, b) => (b.attemptedOn ?? DateTime(0)).compareTo(a.attemptedOn ?? DateTime(0)));
    final latestBav = sortedBav.isEmpty ? null : sortedBav.first;
    final step4Done = step4Status == KycStepStatus.verified;
    KycStepStatus step5Status;
    String step5Pill;
    String step5Subtitle;
    if (!step4Done) {
      step5Status = KycStepStatus.locked;
      step5Pill = 'Locked';
      step5Subtitle = 'Unlocks after Name & DOB Match clears';
    } else if (latestBav != null && latestBav.isApproved) {
      step5Status = KycStepStatus.verified;
      step5Pill = 'Verified';
      step5Subtitle = latestBav.accountLast4 != null ? 'Account ending ${latestBav.accountLast4}' : 'Penny-less BAV verified';
    } else if (latestBav != null && latestBav.status.toLowerCase() == 'rejected') {
      step5Status = KycStepStatus.failed;
      step5Pill = 'Retry';
      step5Subtitle = 'Bank verification failed. Please try again.';
    } else {
      step5Status = KycStepStatus.actionable;
      step5Pill = 'Initiate';
      step5Subtitle = 'Penny-less — no debit from your account';
    }

    // Step 6: PAN-Bank Link (derived — server-side inside BAV, no separate call)
    KycStepStatus step6Status;
    String step6Pill;
    String step6Subtitle;
    if (step5Status != KycStepStatus.verified) {
      step6Status = KycStepStatus.locked;
      step6Pill = 'Locked';
      step6Subtitle = 'Runs automatically once bank verification clears';
    } else if (latestBav?.nameMatched == true) {
      step6Status = KycStepStatus.verified;
      step6Pill = 'Verified';
      step6Subtitle = 'Bank beneficiary name matches your profile';
    } else if (latestBav?.nameMatched == false) {
      step6Status = KycStepStatus.failed;
      step6Pill = 'Mismatch';
      step6Subtitle = 'Bank beneficiary name did not match your profile';
    } else {
      step6Status = KycStepStatus.underReview;
      step6Pill = 'Pending';
      step6Subtitle = 'Waiting for the bank name-match result';
    }

    // Step 7: Reverse Penny Drop (RPD)
    final primaryAccounts = (bankAccounts ?? const <BankAccount>[]).where((a) => a.isPrimary);
    final fallbackCbankId = primaryAccounts.isEmpty ? null : primaryAccounts.first.idBank;
    final cbankId = latestBav?.cbankId ?? fallbackCbankId;
    final sortedRpd = (rpdHistory ?? const <RpdHistoryItem>[]).where((r) => cbankId != null && r.cbankId == cbankId).toList()
      ..sort((a, b) => (b.createdOn ?? DateTime(0)).compareTo(a.createdOn ?? DateTime(0)));
    final latestRpd = sortedRpd.isEmpty ? null : sortedRpd.first;
    KycStepStatus step7Status;
    String step7Pill;
    String step7Subtitle;
    if (step5Status != KycStepStatus.verified) {
      step7Status = KycStepStatus.locked;
      step7Pill = 'Locked';
      step7Subtitle = 'Final step · unlocks after bank verification';
    } else if (latestRpd != null && latestRpd.status.toLowerCase() == 'success') {
      step7Status = KycStepStatus.verified;
      step7Pill = 'Verified';
      step7Subtitle = 'Ownership confirmed via reverse penny drop';
    } else if (latestRpd != null && latestRpd.status.toLowerCase() == 'failed') {
      step7Status = KycStepStatus.failed;
      step7Pill = 'Retry';
      step7Subtitle = latestRpd.failureReason ?? 'Reverse penny drop failed. Please try again.';
    } else if (cbankId == null) {
      step7Status = KycStepStatus.locked;
      step7Pill = 'Locked';
      step7Subtitle = 'Add a bank account to continue';
    } else {
      step7Status = KycStepStatus.actionable;
      step7Pill = 'Start';
      step7Subtitle = 'Confirm ownership with a ₹1 transfer from your bank app';
    }

    final statuses = [step1Status, step2Status, step3Status, step4Status, step5Status, step6Status, step7Status];
    final completed = statuses.where((s) => s == KycStepStatus.verified).length;
    final activeIndex = () {
      for (var i = 0; i < statuses.length; i++) {
        if (statuses[i] != KycStepStatus.verified && statuses[i] != KycStepStatus.locked) return i + 1;
      }
      return null;
    }();

    // PAN/Aadhaar no longer expand in place — tapping either row (or the
    // footer CTA) pushes [KycIdVerificationScreen] instead, so there's
    // nothing to auto-expand for those two indices.
    void expandDefault(int index) {
      if (index == 1 || index == 2) return;
      _expanded.add(index);
    }

    if (!_defaultExpansionSet) {
      _defaultExpansionSet = true;
      if (activeIndex != null) expandDefault(activeIndex);
      _lastActiveIndex = activeIndex;
    } else if (activeIndex != null && activeIndex != _lastActiveIndex) {
      expandDefault(activeIndex);
      _lastActiveIndex = activeIndex;
    }

    final subtitle = completed == 7
        ? "You're fully verified — withdrawals and gold delivery are unlocked."
        : completed >= 4
            ? 'Finish bank verification to unlock withdrawals and gold delivery.'
            : 'Complete PAN and Aadhaar verification to continue.';
    final headline = completed == 7
        ? 'All done${profileName.isNotEmpty ? ', $profileName' : ''}!'
        : 'Almost there${profileName.isNotEmpty ? ', $profileName' : ''}';

    return Column(
      children: [
        KycProgressHeader(title: headline, subtitle: subtitle, completed: completed, total: 7),
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 100.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Verification checklist', style: AppTextStyles.titleMedium(isDark)),
                    SizedBox(height: 4.h),
                    Text('Each check runs automatically once the previous one clears.', style: AppTextStyles.bodySmall(isDark)),
                    SizedBox(height: 20.h),
                    KycStepRow(
                      index: 1,
                      title: 'PAN Verification',
                      subtitle: panDone
                          ? (panDocValue?.maskedValue ?? 'PAN verified')
                          : panSkippedInConsent
                              ? 'Verify separately via DigiLocker'
                              : 'Validated together with Aadhaar via DigiLocker',
                      status: step1Status,
                      pillLabel: step1Pill,
                      expanded: false,
                      onToggle: () => _openIdVerificationScreen(),
                    ),
                    KycStepRow(
                      index: 2,
                      title: 'Aadhaar Verification',
                      subtitle: aadhaarDone
                          ? (aadhaarState.maskedNumber ?? docsResult.aadhaarMaskedNumber ?? 'Aadhaar verified')
                          : 'via DigiLocker',
                      status: step2Status,
                      pillLabel: step2Pill,
                      expanded: false,
                      onToggle: () => _openIdVerificationScreen(),
                    ),
                    KycStepRow(
                      index: 3,
                      title: 'PAN – Aadhaar Link',
                      subtitle: step3Subtitle,
                      status: step3Status,
                      pillLabel: step3Pill,
                      expanded: _expanded.contains(3),
                      onToggle: () => setState(() => _toggle(3)),
                      lockedHint: step3Status == KycStepStatus.locked ? step3Subtitle : null,
                      detail: _buildDerivedDetail(isDark, step3Status, step3Subtitle),
                    ),
                    KycStepRow(
                      index: 4,
                      title: 'Name & DOB Match',
                      subtitle: step4Subtitle,
                      status: step4Status,
                      pillLabel: step4Pill,
                      expanded: _expanded.contains(4),
                      onToggle: () => setState(() => _toggle(4)),
                      lockedHint: step4Status == KycStepStatus.locked ? step4Subtitle : null,
                      detail: _buildDerivedDetail(isDark, step4Status, step4Subtitle),
                    ),
                    KycStepRow(
                      index: 5,
                      title: 'Bank Account Verification',
                      subtitle: step5Subtitle,
                      status: step5Status,
                      pillLabel: step5Pill,
                      expanded: _expanded.contains(5),
                      onToggle: step5Status == KycStepStatus.locked ? null : () => setState(() => _toggle(5)),
                      lockedHint: step5Status == KycStepStatus.locked ? step5Subtitle : null,
                      detail: _buildStep5Detail(isDark, step5Status, bankDataLoading),
                    ),
                    KycStepRow(
                      index: 6,
                      title: 'PAN – Bank Account Link',
                      subtitle: step6Subtitle,
                      status: step6Status,
                      pillLabel: step6Pill,
                      expanded: _expanded.contains(6),
                      onToggle: () => setState(() => _toggle(6)),
                      lockedHint: step6Status == KycStepStatus.locked ? step6Subtitle : null,
                      detail: _buildDerivedDetail(isDark, step6Status, step6Subtitle),
                    ),
                    KycStepRow(
                      index: 7,
                      title: 'Reverse Penny Drop (RPD)',
                      subtitle: step7Subtitle,
                      status: step7Status,
                      pillLabel: step7Pill,
                      expanded: _expanded.contains(7),
                      onToggle: step7Status == KycStepStatus.locked ? null : () => setState(() => _toggle(7)),
                      lockedHint: step7Status == KycStepStatus.locked ? step7Subtitle : null,
                      detail: _buildStep7Detail(isDark, step7Status, cbankId),
                    ),
                    SizedBox(height: 8.h),
                    Center(
                      child: Text(
                        'Details are encrypted and used only for KYC verification.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.labelMedium(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              if (completingKyc)
                Positioned.fill(
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withOpacity(0.75),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        SizedBox(height: 16.h),
                        Text('Updating your verification status…', style: AppTextStyles.fieldHelper(isDark)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 20.w,
                right: 20.w,
                bottom: 16.h,
                child: _buildFooterCta(activeIndex, panSkippedInConsent, cbankId),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Info panel for the three PRESENTATIONAL steps (3, 4, 6) — these have no
  /// user action of their own (see class doc comment), so expanding them
  /// just surfaces why they're in their current state.
  Widget _buildDerivedDetail(bool isDark, KycStepStatus status, String message) {
    late Color bg, border, textColor;
    late IconData icon;
    switch (status) {
      case KycStepStatus.verified:
        bg = const Color(0xFF0E5723).withOpacity(0.08);
        border = const Color(0xFF0E5723).withOpacity(0.15);
        textColor = const Color(0xFF0E5723);
        icon = Icons.verified_user_rounded;
        break;
      case KycStepStatus.failed:
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFCA5A5);
        textColor = const Color(0xFFB91C1C);
        icon = Icons.error_outline_rounded;
        break;
      default:
        bg = const Color(0xFFEFF6FF);
        border = const Color(0xFFBFDBFE);
        textColor = const Color(0xFF1E3A5F);
        icon = Icons.hourglass_top_rounded;
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16.r), border: Border.all(color: border)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18.sp, color: textColor),
          SizedBox(width: 10.w),
          Expanded(child: Text(message, style: AppTextStyles.fieldHelper(isDark).copyWith(color: textColor))),
        ],
      ),
    );
  }

  void _toggle(int index) {
    if (_expanded.contains(index)) {
      _expanded.remove(index);
    } else {
      _expanded.add(index);
    }
  }

  Widget _buildStep5Detail(bool isDark, KycStepStatus status, bool bankDataLoading) {
    if (status == KycStepStatus.verified) {
      return const KycVerifiedBanner();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verify a bank account with a penny-less check — no money is debited or credited.',
          style: AppTextStyles.fieldHelper(isDark),
        ),
        SizedBox(height: 12.h),
        CustomButton(
          text: status == KycStepStatus.failed ? 'Retry Bank Verification' : 'Initiate Bank Verification',
          svgIconPath: 'assets/buttons/tick.svg',
          isLoading: bankDataLoading,
          onPressed: () => _initiateBav(isDark),
          gradient: AppTheme.greenGradient,
        ),
      ],
    );
  }

  Widget _buildStep7Detail(bool isDark, KycStepStatus status, String? cbankId) {
    if (status == KycStepStatus.verified) {
      return const KycVerifiedBanner();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Confirm ownership with a ₹1 transfer from your own bank app. It is refunded to the same account within 24 hours.',
          style: AppTextStyles.fieldHelper(isDark),
        ),
        SizedBox(height: 12.h),
        CustomButton(
          text: status == KycStepStatus.failed ? 'Retry Reverse Penny Drop' : 'Start Reverse Penny Drop',
          svgIconPath: 'assets/buttons/tick.svg',
          onPressed: cbankId == null ? null : () => _startRpd(cbankId),
          gradient: AppTheme.greenGradient,
        ),
      ],
    );
  }

  Future<void> _initiateBav(bool isDark) async {
    await showAddBankAccountSheet(
      context,
      ref,
      isDark: isDark,
      onAdded: () {
        ref.invalidate(bankAccountsProvider);
        ref.invalidate(bavHistoryProvider);
        ref.invalidate(rpdHistoryProvider);
      },
    );
  }

  Future<void> _startRpd(String cbankId) async {
    final result = await Navigator.pushNamed(context, AppRouter.reversePennyDrop, arguments: {'cbankId': cbankId});
    if (result == true && mounted) {
      ref.invalidate(bankAccountsProvider);
      ref.invalidate(rpdHistoryProvider);
    }
  }

  /// PAN/Aadhaar data entry lives on its own page now — tapping the row or
  /// this footer CTA both land here instead of expanding fields in place.
  Future<void> _openIdVerificationScreen() async {
    final result = await Navigator.pushNamed(
      context,
      AppRouter.kycIdVerification,
      arguments: {'request_from': widget.requestFrom},
    );
    if (result == true && mounted) {
      ref.invalidate(kycDocumentsProvider(widget.requestFrom));
    }
  }

  Widget _buildFooterCta(int? activeIndex, bool panSkippedInConsent, String? cbankId) {
    if (activeIndex == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String label;
    VoidCallback? onTap;
    switch (activeIndex) {
      case 1:
      case 2:
        label = panSkippedInConsent ? 'Retry PAN Verification' : 'Continue Verification';
        onTap = () => _openIdVerificationScreen();
        break;
      case 5:
        label = 'Continue Verification';
        onTap = () => _initiateBav(isDark);
        break;
      case 7:
        label = 'Continue Verification';
        onTap = cbankId == null ? null : () => _startRpd(cbankId);
        break;
      default:
        return const SizedBox.shrink();
    }

    return CustomButton(
      text: label,
      onPressed: onTap,
      gradient: AppTheme.greenGradient,
    );
  }
}
