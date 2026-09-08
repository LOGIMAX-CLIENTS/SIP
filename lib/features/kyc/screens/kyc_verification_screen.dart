import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/controllers/kyc_verification_flow_mixin.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';
import 'package:startgold/features/kyc/utils/kyc_step_status.dart';
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

/// Single-page KYC + bank validation checklist. Display order:
/// PAN -> Aadhaar -> Name & DOB Match -> PAN-Aadhaar Link ->
/// Bank Account Validation (BAV, with PAN-Bank Link and Reverse Penny Drop
/// folded in as sub-items once BAV itself clears).
///
/// PAN/Aadhaar are real, independently-verified backend flows (driven by
/// [KycVerificationFlowMixin], reusing the exact same providers as the live
/// `/kyc` screen). PAN-Aadhaar Link and Name & DOB Match are PRESENTATIONAL
/// sub-statuses derived from fields the backend already returns
/// (`aadhaarPanLinked`, `kycConfirmed`) — there is no separate provider call
/// backing either one's ongoing display, though PAN-Aadhaar Link does have a
/// real "Retry" recompute endpoint (see [_retryAadhaarPanLink]). Bank
/// verification (BAV/RPD) launches the app's EXISTING screens
/// (`add_bank_account_sheet`, `ReversePennyDropScreen`) rather than
/// re-implementing those forms here — bank account LISTING/UPI management
/// stays on its own separate page.
///
/// Any step whose backing `VerificationGatewayRouting.vgr_is_active` is
/// switched off server-side (see `verification-status`'s `is_active` field)
/// is skipped entirely — it's not rendered, not counted in the progress
/// ring, and consumes no step number.
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
  final Set<String> _expanded = {};
  bool _defaultExpansionSet = false;
  String? _lastAttentionKey;
  bool _poppedForIdVerified = false;
  bool _checkingPanBankLink = false;
  bool _retryingPanAadhaarLink = false;
  bool _refreshingNameDob = false;
  // cbankId of the account we've already auto-pushed the customer into
  // Additional Verification for — prevents re-triggering the navigation on
  // every rebuild once BAV clears; only fires once per account, and never
  // on top of a failed attempt (that shows its own Retry action instead).
  String? _autoLaunchedRpdCbankId;

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
    final verificationStatusAsync = ref.watch(verificationStatusProvider);
    final profileName = ref.watch(pc.profileProvider).user.name;

    // Reactive fallback for state transitions that land after this SPECIFIC
    // screen instance's own await chain (verifyPanAndAadhaar/retryPan) has
    // already been disposed and recreated by a DigiLocker SDK bounce — see
    // handleAadhaarStateChange's doc comment. Without this, checkAadhaarOutcomeRecoveryOnLoad's
    // one-shot on-mount check is the only thing watching, and it always
    // runs before the poll resolves, so the customer saw no update at all
    // until manually refreshing.
    ref.listen<AadhaarState>(aadhaarProvider, (previous, next) {
      handleAadhaarStateChange(widget.requestFrom, next);
    });

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
          // AnimatedSwitcher cross-fades the loading spinner into the
          // checklist content instead of the previous hard cut (the
          // "flickers during loading" half of this bug) — each branch has
          // an explicit key so the switcher can tell them apart.
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: docsAsync.when(
                loading: () => const Center(key: ValueKey('kyc-checklist-loading'), child: CircularProgressIndicator()),
                error: (e, _) => Center(key: const ValueKey('kyc-checklist-error'), child: Text('Error: $e')),
                data: (docsResult) {
                  syncAadhaarWithBackend(docsResult);
                  return KeyedSubtree(
                    key: const ValueKey('kyc-checklist-data'),
                    child: _buildBody(
                      isDark: isDark,
                      docsResult: docsResult,
                      aadhaarState: aadhaarState,
                      bankAccounts: bankAccountsAsync.valueOrNull,
                      bavHistory: bavHistoryAsync.valueOrNull,
                      rpdHistory: rpdHistoryAsync.valueOrNull,
                      verificationStatus: verificationStatusAsync.valueOrNull,
                      bankDataLoading: bankAccountsAsync.isLoading || bavHistoryAsync.isLoading,
                      profileName: profileName,
                    ),
                  );
                },
              ),
            ),
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
    required Map<String, dynamic>? verificationStatus,
    required bool bankDataLoading,
    required String profileName,
  }) {
    // Step-status derivation lives in computeKycStepStatuses() (kyc/utils/
    // kyc_step_status.dart) — shared with kycProgressProvider so the
    // Profile page's "N/total" badge can never disagree with this screen's
    // own progress ring, since both run the exact same function over the
    // same data.
    final statuses = computeKycStepStatuses(
      docsResult: docsResult,
      aadhaarState: aadhaarState,
      verificationStatus: verificationStatus,
      bankAccounts: bankAccounts,
      bavHistory: bavHistory,
      rpdHistory: rpdHistory,
      verifyingAadhaar: verifyingAadhaar,
      aadhaarEditing: aadhaarEditing,
      retryingPanOnly: retryingPanOnly,
    );
    final panDone = statuses.panDone;
    final aadhaarDone = statuses.aadhaarDone;
    final panDocValue = statuses.panDocValue;
    final panSkippedInConsent = statuses.panSkippedInConsent;

    // Gates on the FULL checklist (every active step, including bank
    // verification) — not just PAN+Aadhaar or even idKycComplete (PAN +
    // Aadhaar + Mandatory PAN-Aadhaar Link). A gated caller (Auto Savings/
    // Withdrawal/Investment) separately re-checks the backend's kycStatus
    // flag after this pops; popping early on a narrower condition sent the
    // customer right back into this same screen (re-prompted for Aadhaar)
    // on their very next tap whenever anything past that narrower
    // condition was still outstanding.
    if (widget.popWhenIdVerified && statuses.completed == statuses.total && !_poppedForIdVerified) {
      _poppedForIdVerified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
    }

    final digilockerActive = statuses.digilockerActive;
    final aadhaarPanLinkActive = statuses.aadhaarPanLinkActive;
    final panBankLinkActive = statuses.panBankLinkActive;
    final rpdActive = statuses.rpdActive;

    final panStatus = statuses.panStatus;
    final panPill = statuses.panPill;
    final aadhaarStatus = statuses.aadhaarStatus;
    final aadhaarPill = statuses.aadhaarPill;
    final bothIdVerified = statuses.bothIdVerified;

    final nameDobStatus = statuses.nameDobStatus;
    final nameDobPill = statuses.nameDobPill;
    final nameDobSubtitle = statuses.nameDobSubtitle;

    final panAadhaarLinkMandatory = statuses.panAadhaarLinkMandatory;
    final panAadhaarLinkStatus = statuses.panAadhaarLinkStatus;
    final panAadhaarLinkPill = statuses.panAadhaarLinkPill;
    final panAadhaarLinkSubtitle = statuses.panAadhaarLinkSubtitle;

    final pennylessBavStatus = statuses.pennylessBavStatus;

    final cbankId = statuses.cbankId;

    final panBankLinkStatus = statuses.panBankLinkStatus;
    final panBankLinkPill = statuses.panBankLinkPill;
    final panBankLinkSubtitle = statuses.panBankLinkSubtitle;

    final rpdStatus = statuses.rpdStatus;
    final rpdPill = statuses.rpdPill;
    final rpdSubtitle = statuses.rpdSubtitle;

    final bavStatus = statuses.bavStatus;
    final bavPill = statuses.bavPill;
    final bavSubtitle = statuses.bavSubtitle;

    // Auto-push into Additional Verification the moment it becomes
    // actionable (i.e. right after BAV clears) — no "Start" tap required.
    // Fires once per cbankId: never re-fires on every rebuild, and never
    // fires on top of a failed attempt (rpdStatus is `failed`, not
    // `actionable`, in that case) — a failed attempt shows its own Retry
    // action instead of being relaunched automatically.
    // Only when the customer came here to FINISH verification (a purchase,
    // withdrawal or SIP gate sent them). Opening the checklist from Profile
    // to look at it is not a request to start paying, and `actionable` only
    // means "RPD can be done now" -- not "BAV just cleared" -- so from
    // Profile this fired on every visit, for as long as RPD stayed
    // NOT_STARTED.
    final cameHereToFinish = widget.requestFrom != 'profile';
    if (cameHereToFinish && rpdActive && rpdStatus == KycStepStatus.actionable && cbankId != null && _autoLaunchedRpdCbankId != cbankId) {
      _autoLaunchedRpdCbankId = cbankId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRpd(cbankId);
      });
    }

    // Dynamic numbering — pure display numbering, recomputed locally since
    // it isn't part of the shared completed/total tally.
    int stepCounter = 0;
    int? panIndex, aadhaarIndex;
    if (digilockerActive) {
      panIndex = ++stepCounter;
      aadhaarIndex = ++stepCounter;
    }
    final nameDobIndex = ++stepCounter;
    int? panAadhaarLinkIndex;
    if (aadhaarPanLinkActive) {
      panAadhaarLinkIndex = ++stepCounter;
    }
    final bavIndex = ++stepCounter;

    final total = statuses.total;
    final completed = statuses.completed;

    // Which card should auto-expand / drive the footer CTA — first
    // actionable, unlocked step in display order. bavStatus is now the
    // COMPOSITE status (pennyless + mandatory sub-items), so this one
    // check already covers "pennyless done but a mandatory sub-item still
    // needs action" — no separate sub-item-attention check needed.
    String? attentionKey;
    if (nameDobStatus != KycStepStatus.verified && nameDobStatus != KycStepStatus.locked) {
      attentionKey = 'name_dob';
    } else if (aadhaarPanLinkActive &&
        (panAadhaarLinkStatus == KycStepStatus.failed ||
            (panAadhaarLinkMandatory && panAadhaarLinkStatus == KycStepStatus.underReview))) {
      // A real NOT_LINKED result always deserves attention; an unresolved
      // "Pending" only nags while Mandatory — while Optional it reads as
      // "Optional" instead and doesn't force attention (see
      // panAadhaarLinkStatus's computation above).
      attentionKey = 'pan_aadhaar_link';
    } else if (bavStatus != KycStepStatus.verified && bavStatus != KycStepStatus.locked) {
      attentionKey = 'bav';
    }

    // PAN/Aadhaar no longer expand in place — tapping either row (or the
    // footer CTA) pushes [KycIdVerificationScreen] instead, so there's
    // nothing to auto-expand for those two.
    if (!_defaultExpansionSet) {
      _defaultExpansionSet = true;
      if (attentionKey != null) _expanded.add(attentionKey);
      _lastAttentionKey = attentionKey;
    } else if (attentionKey != null && attentionKey != _lastAttentionKey) {
      _expanded.add(attentionKey);
      _lastAttentionKey = attentionKey;
    }

    final subtitle = completed == total
        ? "You're fully verified — withdrawals and gold delivery are unlocked."
        : completed >= (total - 1).clamp(0, total)
            ? 'Finish bank validation to unlock withdrawals and gold delivery.'
            : 'Complete PAN and Aadhaar validation to continue.';
    final headline = completed == total
        ? 'All done${profileName.isNotEmpty ? ', $profileName' : ''}!'
        : 'Almost there${profileName.isNotEmpty ? ', $profileName' : ''}';

    // Footer CTA — the two genuine entry points (start ID verification,
    // start/retry bank validation). Name & DOB Match and PAN-Aadhaar Link
    // are presentational (retry lives inline in their own card), and the
    // BAV sub-items' actions live inside BAV's own expanded card.
    String? footerKey;
    if (digilockerActive && !bothIdVerified) {
      footerKey = 'id';
    } else if (pennylessBavStatus != KycStepStatus.verified && pennylessBavStatus != KycStepStatus.locked) {
      // Checked against the pennyless-only status, not the composite
      // bavStatus — once pennyless itself is done, there's nothing left to
      // "Initiate"; a pending mandatory sub-item has its own action button
      // inside the expanded BAV card instead of a footer CTA.
      footerKey = 'bav';
    }

    return Column(
      children: [
        KycProgressHeader(
          title: headline,
          subtitle: subtitle,
          completed: completed,
          total: total,
          onRefresh: _handleRefresh,
        ),
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 200.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Validation checklist', style: AppTextStyles.titleMedium(isDark)),
                    SizedBox(height: 4.h),
                    Text('Each check runs automatically once the previous one clears.', style: AppTextStyles.bodySmall(isDark)),
                    SizedBox(height: 20.h),
                    if (digilockerActive) ...[
                      KycStepRow(
                        index: panIndex!,
                        title: 'PAN Verification',
                        subtitle: panDone
                            ? (panDocValue?.maskedValue ?? 'PAN verified')
                            : panSkippedInConsent
                                ? 'Verify separately via DigiLocker'
                                : 'Validated together with Aadhaar via DigiLocker',
                        status: panStatus,
                        pillLabel: panPill,
                        expanded: false,
                        onToggle: () => _openIdVerificationScreen(),
                      ),
                      KycStepRow(
                        index: aadhaarIndex!,
                        title: 'Aadhaar Verification',
                        subtitle: aadhaarDone
                            ? (aadhaarState.maskedNumber ?? docsResult.aadhaarMaskedNumber ?? 'Aadhaar verified')
                            : 'via DigiLocker',
                        status: aadhaarStatus,
                        pillLabel: aadhaarPill,
                        expanded: false,
                        onToggle: () => _openIdVerificationScreen(),
                      ),
                    ],
                    KycStepRow(
                      index: nameDobIndex,
                      title: 'Name & DOB Match',
                      subtitle: nameDobSubtitle,
                      status: nameDobStatus,
                      pillLabel: nameDobPill,
                      expanded: _expanded.contains('name_dob'),
                      onToggle: () => setState(() => _toggle('name_dob')),
                      lockedHint: nameDobStatus == KycStepStatus.locked ? nameDobSubtitle : null,
                      detail: _buildNameDobDetail(
                        isDark, nameDobStatus, nameDobSubtitle,
                        aadhaarName: docsResult.aadhaarName,
                        aadhaarDob: docsResult.aadhaarDob,
                        panName: panDocValue?.verifiedName,
                        panDob: panDocValue?.verifiedDob,
                      ),
                    ),
                    if (aadhaarPanLinkActive)
                      KycStepRow(
                        index: panAadhaarLinkIndex!,
                        title: 'PAN – Aadhaar Link',
                        subtitle: panAadhaarLinkSubtitle,
                        status: panAadhaarLinkStatus,
                        pillLabel: panAadhaarLinkPill,
                        expanded: _expanded.contains('pan_aadhaar_link'),
                        onToggle: () => setState(() => _toggle('pan_aadhaar_link')),
                        lockedHint: panAadhaarLinkStatus == KycStepStatus.locked ? panAadhaarLinkSubtitle : null,
                        detail: _buildPanAadhaarLinkDetail(isDark, panAadhaarLinkStatus, panAadhaarLinkSubtitle),
                      ),
                    KycStepRow(
                      index: bavIndex,
                      title: 'Add Bank Account',
                      subtitle: bavSubtitle,
                      status: bavStatus,
                      pillLabel: bavPill,
                      expanded: _expanded.contains('bav'),
                      onToggle: bavStatus == KycStepStatus.locked ? null : () => setState(() => _toggle('bav')),
                      lockedHint: bavStatus == KycStepStatus.locked ? bavSubtitle : null,
                      detail: _buildBavDetail(
                        isDark: isDark,
                        pennylessBavStatus: pennylessBavStatus,
                        bankDataLoading: bankDataLoading,
                        panBankLinkActive: panBankLinkActive,
                        panBankLinkStatus: panBankLinkStatus,
                        panBankLinkPill: panBankLinkPill,
                        panBankLinkSubtitle: panBankLinkSubtitle,
                        rpdActive: rpdActive,
                        rpdStatus: rpdStatus,
                        rpdPill: rpdPill,
                        rpdSubtitle: rpdSubtitle,
                        cbankId: cbankId,
                      ),
                    ),
                    SizedBox(height: 8.h),
                    Center(
                      child: Text(
                        'Details are encrypted and used only for KYC validation.',
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
                        Text('Updating your validation status…', style: AppTextStyles.fieldHelper(isDark)),
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 20.w,
                right: 20.w,
                bottom: 16.h,
                child: _buildFooterCta(footerKey, panSkippedInConsent),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Info panel for the PRESENTATIONAL steps (Name & DOB Match,
  /// PAN-Aadhaar Link) — these have no user action of their own beyond
  /// their own Retry (see class doc comment), so expanding them just
  /// surfaces why they're in their current state.
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

  void _toggle(String key) {
    if (_expanded.contains(key)) {
      _expanded.remove(key);
    } else {
      _expanded.add(key);
    }
  }

  /// Name & DOB Match's own Retry — resolves a stuck "Pending" caused by a
  /// stale read shortly after DigiLocker approval (see kyc_screen.dart's
  /// `_checkCompletionRecoveryOnLoad` docstring for the exact race) by
  /// refetching.
  ///
  /// It deliberately does NOT re-open a profile confirm dialog for a genuine
  /// profile-vs-document mismatch: that popup was removed (RULE-KYC-007), and
  /// a real mismatch is now caught at verification time by the backend's name
  /// gate, which raises NameMismatchDialog and writes the corrected name
  /// (RULE-KYC-015). If a stuck Pending is ever seen here again, the fix
  /// belongs in that gate, not in a second confirmation surface.
  Widget _buildNameDobDetail(
    bool isDark, KycStepStatus status, String message, {
    required String? aadhaarName,
    required String? aadhaarDob,
    required String? panName,
    required String? panDob,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDerivedDetail(isDark, status, message),
        if (status == KycStepStatus.inProgress) ...[
          SizedBox(height: 12.h),
          CustomButton(
            text: 'Retry',
            svgIconPath: 'assets/buttons/tick.svg',
            isLoading: _refreshingNameDob,
            onPressed: () => _retryNameDobMatch(
              aadhaarName: aadhaarName, aadhaarDob: aadhaarDob, panName: panName, panDob: panDob,
            ),
            gradient: AppTheme.greenGradient,
          ),
        ],
      ],
    );
  }

  Future<void> _retryNameDobMatch({
    String? aadhaarName,
    String? aadhaarDob,
    String? panName,
    String? panDob,
  }) async {
    setState(() => _refreshingNameDob = true);
    try {
      ref.invalidate(kycDocumentsProvider(widget.requestFrom));
      ref.invalidate(verificationStatusProvider);
      await ref.read(kycDocumentsProvider(widget.requestFrom).future);
      if (!mounted) return;
      // Refetch only. The profile name/DOB confirm dialog this used to open
      // (retryNameDobConfirm) was removed along with the rest of the
      // post-verification confirmation popup — see BUSINESS_RULES.md
      // RULE-KYC-007. A genuine profile-vs-document mismatch is now caught at
      // verification time by the backend's name gate, which raises
      // NameMismatchDialog and writes the corrected name to the profile
      // (RULE-KYC-015), so there is no longer a stuck state for this button
      // to unstick by re-showing a confirm dialog.
      if (mounted) AppToast.show(context, 'Validation status refreshed.', type: ToastType.info);
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not refresh status. Please try again.', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _refreshingNameDob = false);
    }
  }

  /// Same info-banner look as [_buildDerivedDetail], plus a Retry button
  /// that recomputes from the stored PAN record server-side (see
  /// KycRepository.retryAadhaarPanLink) — falls back to the PAN DigiLocker
  /// re-verify flow only if the backend reports there's nothing stored to
  /// recompute from.
  Widget _buildPanAadhaarLinkDetail(bool isDark, KycStepStatus status, String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDerivedDetail(isDark, status, message),
        if (status == KycStepStatus.failed || status == KycStepStatus.underReview) ...[
          SizedBox(height: 12.h),
          CustomButton(
            text: 'Retry PAN-Aadhaar Link',
            svgIconPath: 'assets/buttons/tick.svg',
            isLoading: _retryingPanAadhaarLink,
            onPressed: () => _retryAadhaarPanLink(),
            gradient: AppTheme.greenGradient,
          ),
        ],
      ],
    );
  }

  Future<void> _retryAadhaarPanLink() async {
    setState(() => _retryingPanAadhaarLink = true);
    try {
      final result = await ref.read(kycRepositoryProvider).retryAadhaarPanLink();
      ref.invalidate(verificationStatusProvider);
      if (result['needs_reverify'] == true) {
        // Stays on the checklist — this is just a status recheck, not a
        // reason to send the customer through a full PAN DigiLocker
        // re-verification (that's a much bigger ask for an Optional check).
        if (mounted) {
          AppToast.show(context, "Couldn't refresh the link status right now. Please try again shortly.", type: ToastType.info);
        }
        return;
      }
      if (mounted) AppToast.show(context, 'PAN-Aadhaar link status refreshed.', type: ToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _retryingPanAadhaarLink = false);
    }
  }

  Widget _buildBavDetail({
    required bool isDark,
    required KycStepStatus pennylessBavStatus,
    required bool bankDataLoading,
    required bool panBankLinkActive,
    required KycStepStatus panBankLinkStatus,
    required String panBankLinkPill,
    required String panBankLinkSubtitle,
    required bool rpdActive,
    required KycStepStatus rpdStatus,
    required String rpdPill,
    required String rpdSubtitle,
    required String? cbankId,
  }) {
    if (pennylessBavStatus != KycStepStatus.verified) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Validate a bank account with a penny-less check — no money is debited or credited.',
            style: AppTextStyles.fieldHelper(isDark),
          ),
          SizedBox(height: 12.h),
          CustomButton(
            text: pennylessBavStatus == KycStepStatus.failed ? 'Retry Bank Validation' : 'Initiate Bank Validation',
            svgIconPath: 'assets/buttons/tick.svg',
            isLoading: bankDataLoading,
            onPressed: () => _initiateBav(isDark),
            gradient: AppTheme.greenGradient,
          ),
        ],
      );
    }

    // Pennyless BAV passed — PAN-Bank Link and Additional Verification
    // render as sub-items here rather than their own top-level steps. No
    // separate "Verified" banner: the row header above already shows that
    // (and, once every mandatory sub-item is also resolved, the composite
    // bavStatus/pill reflect that too) — repeating it here said nothing new.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (panBankLinkActive) ...[
          SizedBox(height: 16.h),
          _buildBavSubItem(
            isDark: isDark,
            title: 'PAN – Bank Account Link',
            status: panBankLinkStatus,
            pillLabel: panBankLinkPill,
            subtitle: panBankLinkSubtitle,
            // The action stays available even while Optional (underReview
            // here means "Optional, not yet checked") — the backend no
            // longer refuses the check just because it isn't required, so
            // checking anyway is harmless; it just never blocks anything.
            actionLabel: panBankLinkStatus == KycStepStatus.verified
                ? null
                : (panBankLinkPill == 'Retry' ? 'Retry PAN-Bank Link' : 'Check PAN-Bank Link'),
            isLoadingAction: _checkingPanBankLink,
            onAction: cbankId == null ? null : () => _checkPanBankLink(cbankId),
          ),
        ],
        if (rpdActive) ...[
          SizedBox(height: 16.h),
          _buildBavSubItem(
            isDark: isDark,
            title: 'Verify Bank Account',
            status: rpdStatus,
            pillLabel: rpdPill,
            subtitle: rpdSubtitle,
            // Kept short — the card's own title right above already says
            // "Verify Bank Account"; repeating it here was too long to
            // fit this narrow sub-item button and overflowed.
            actionLabel: rpdStatus == KycStepStatus.verified || rpdStatus == KycStepStatus.locked
                ? null
                : (rpdStatus == KycStepStatus.failed ? 'Retry Verification' : 'Start Verification'),
            onAction: cbankId == null ? null : () => _startRpd(cbankId),
          ),
        ],
      ],
    );
  }

  /// Compact sub-item card for BAV's folded-in PAN-Bank Link / Reverse
  /// Penny Drop statuses — same accent-by-status language as
  /// [KycStepRow]/[_buildDerivedDetail], scaled down since these live
  /// inside BAV's own expanded detail rather than as their own row.
  Widget _buildBavSubItem({
    required bool isDark,
    required String title,
    required KycStepStatus status,
    required String pillLabel,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
    bool isLoadingAction = false,
  }) {
    final Color accent = status == KycStepStatus.verified
        ? const Color(0xFF0E5723)
        : status == KycStepStatus.failed
            ? const Color(0xFFDC2626)
            : const Color(0xFF2563EB);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: accent.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == KycStepStatus.verified ? Icons.verified_user_rounded : Icons.link_rounded,
                size: 16.sp,
                color: accent,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(title, style: AppTextStyles.bodyMedium(isDark).copyWith(fontWeight: FontWeight.w700)),
              ),
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(100.r)),
                child: Text(
                  pillLabel.toUpperCase(),
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 9.sp,
                    fontWeight: FontWeight.w800,
                    color: accent,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6.h),
          Text(subtitle, style: AppTextStyles.bodySmall(isDark)),
          if (actionLabel != null) ...[
            SizedBox(height: 10.h),
            SizedBox(
              width: double.infinity,
              child: CustomButton(
                text: actionLabel,
                svgIconPath: 'assets/buttons/tick.svg',
                isLoading: isLoadingAction,
                onPressed: onAction,
                gradient: AppTheme.greenGradient,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _checkPanBankLink(String cbankId) async {
    setState(() => _checkingPanBankLink = true);
    try {
      final result = await ref.read(bankVerificationHistoryServiceProvider).checkPanBankLink(cbankId: cbankId);
      ref.invalidate(verificationStatusProvider);
      if (mounted) {
        // The provider's own reason (e.g. "Bank account and PAN holder
        // names do not match") when available — falls back to a generic
        // confirmation only if the provider didn't supply one.
        final message = (result['message'] as String?)?.trim();
        AppToast.show(
          context,
          message?.isNotEmpty == true ? message! : 'PAN-Bank account linkage checked.',
          type: result['linked'] == true ? ToastType.success : ToastType.info,
        );
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _checkingPanBankLink = false);
    }
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
    await Navigator.pushNamed(context, AppRouter.reversePennyDrop, arguments: {'cbankId': cbankId});
    // Always refresh, not just on a truthy result — a failed/cancelled
    // attempt still writes a real (failed) history row server-side, and
    // the checklist needs that to render "Failed — Retry" immediately
    // rather than requiring a manual pull-to-refresh.
    if (mounted) {
      ref.invalidate(bankAccountsProvider);
      ref.invalidate(rpdHistoryProvider);
    }
  }

  /// Pull-to-refresh (and the header's refresh icon) — re-fetches every
  /// source this screen reads so a stale pill (e.g. a stale kyc_confirmed
  /// read, see [_retryNameDobMatch]'s docstring) clears without the
  /// customer needing to leave and reopen the screen.
  Future<void> _handleRefresh() async {
    ref.invalidate(kycDocumentsProvider(widget.requestFrom));
    ref.invalidate(bankAccountsProvider);
    ref.invalidate(bavHistoryProvider);
    ref.invalidate(rpdHistoryProvider);
    ref.invalidate(verificationStatusProvider);
    if (mounted) AppToast.show(context, 'Refreshing validation status…', type: ToastType.info);
  }

  /// PAN/Aadhaar data entry lives on its own page now — tapping the row or
  /// this footer CTA both land here instead of expanding fields in place.
  Future<void> _openIdVerificationScreen() async {
    final result = await Navigator.pushNamed(
      context,
      AppRouter.kycIdVerification,
      arguments: {'request_from': widget.requestFrom},
    );
    if (!mounted) return;
    if (result == true) {
      ref.invalidate(kycDocumentsProvider(widget.requestFrom));
    }
    // Always refreshed, not just on result == true: a PAN-only re-verify
    // doesn't necessarily pop with true the way a first-time step
    // completion does, but it can still change the persisted
    // aadhaar_pan_link status this screen's PAN-Aadhaar Link step reads.
    ref.invalidate(verificationStatusProvider);
  }

  Widget _buildFooterCta(String? footerKey, bool panSkippedInConsent) {
    if (footerKey == null) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String label;
    VoidCallback? onTap;
    switch (footerKey) {
      case 'id':
        label = panSkippedInConsent ? 'Retry PAN Verification' : 'Continue Verification';
        onTap = () => _openIdVerificationScreen();
        break;
      case 'bav':
        label = 'Continue Validation';
        onTap = () => _initiateBav(isDark);
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
