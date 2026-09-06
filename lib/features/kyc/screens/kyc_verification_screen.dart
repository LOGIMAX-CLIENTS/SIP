import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/controllers/kyc_verification_flow_mixin.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';
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
                verificationStatus: verificationStatusAsync.valueOrNull,
                bankDataLoading: bankAccountsAsync.isLoading || bavHistoryAsync.isLoading,
                profileName: profileName,
              );
            },
          ),
        ),
      ),
    );
  }

  /// Reads a nested `verifications[key].is_active` flag from the persisted
  /// status map — absent (no VerificationGatewayRouting row yet, or a key
  /// with no routable capability, e.g. the two profile-match keys) means
  /// active, same default the backend itself uses.
  bool _isActive(Map<String, dynamic>? verificationStatus, String key) {
    final entry = verificationStatus?[key];
    if (entry is Map) return entry['is_active'] != false;
    return true;
  }

  /// Reads `verifications[key].is_mandatory` — unlike [_isActive], absent
  /// means NOT mandatory (Optional), matching the backend's own default for
  /// every capability that can be marked Optional (aadhaar_pan_link,
  /// pan_bank_link, reverse_penny_drop — see VerificationStatusService's
  /// _MANDATORY_CAPABILITY_FOR_KEY). Used to decide whether an unresolved
  /// check reads as "Optional" (informational, never blocks) or as an
  /// actionable prompt the customer needs to complete.
  bool _isMandatory(Map<String, dynamic>? verificationStatus, String key) {
    final entry = verificationStatus?[key];
    if (entry is Map) return entry['is_mandatory'] == true;
    return false;
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

    // VGR-driven visibility — DIGILOCKER_KYC covers PAN+Aadhaar together,
    // AADHAAR_PAN_LINK/PAN_BANK_LINK/RPD are each their own capability. A
    // capability with no routing row configured yet defaults to active,
    // same as the backend's own default.
    final digilockerActive = _isActive(verificationStatus, 'digilocker_pan') && _isActive(verificationStatus, 'digilocker_aadhaar');
    final aadhaarPanLinkActive = _isActive(verificationStatus, 'aadhaar_pan_link');
    final panBankLinkActive = _isActive(verificationStatus, 'pan_bank_link');
    final rpdActive = _isActive(verificationStatus, 'reverse_penny_drop');

    // Step: PAN
    KycStepStatus panStatus;
    String panPill;
    if (panDone) {
      panStatus = KycStepStatus.verified;
      panPill = 'Verified';
    } else if (panUnderReview) {
      panStatus = KycStepStatus.underReview;
      panPill = 'Under Review';
    } else if (panSkippedInConsent) {
      panStatus = KycStepStatus.failed;
      panPill = 'Retry';
    } else {
      panStatus = KycStepStatus.actionable;
      panPill = 'Pending';
    }

    // Step: Aadhaar
    KycStepStatus aadhaarStatus;
    String aadhaarPill;
    if (aadhaarDone) {
      aadhaarStatus = KycStepStatus.verified;
      aadhaarPill = 'Verified';
    } else if (aadhaarUnderReview) {
      aadhaarStatus = KycStepStatus.underReview;
      aadhaarPill = 'Under Review';
    } else if (aadhaarBusy) {
      aadhaarStatus = KycStepStatus.inProgress;
      aadhaarPill = 'In Progress';
    } else if (aadhaarFailedPhase) {
      aadhaarStatus = KycStepStatus.failed;
      aadhaarPill = 'Retry';
    } else {
      aadhaarStatus = KycStepStatus.actionable;
      aadhaarPill = 'Pending';
    }

    final bothIdVerified = (panDone && aadhaarDone) || !digilockerActive;

    // Step: Name & DOB Match — comes before PAN-Aadhaar Link in display
    // order now (previously the other way around).
    KycStepStatus nameDobStatus;
    String nameDobPill;
    String nameDobSubtitle;
    if (!bothIdVerified) {
      nameDobStatus = KycStepStatus.locked;
      nameDobPill = 'Locked';
      nameDobSubtitle = 'Unlocks once PAN and Aadhaar are verified';
    } else if (docsResult.kycConfirmed) {
      nameDobStatus = KycStepStatus.verified;
      nameDobPill = 'Matched';
      nameDobSubtitle = 'PAN / Aadhaar matched with profile';
    } else {
      nameDobStatus = KycStepStatus.inProgress;
      nameDobPill = 'Pending';
      nameDobSubtitle = 'Confirm your verified details to finish this step';
    }

    // Step: PAN-Aadhaar Link — the live-session field (freshest, from the
    // verify call that just ran) takes priority; falls back to the
    // persisted CustomerVerificationStatus mirror so the real result still
    // shows after navigating away or reopening the app, not just within
    // the session that ran the check. See verificationStatusProvider's
    // docstring for the vgr_is_mandatory=1 prerequisite that mirror needs.
    final persistedPanAadhaarLink = (verificationStatus?['aadhaar_pan_link'] as Map?)?['status'] as String?;
    // Same is_mandatory-driven "Optional" labeling as PAN-Bank Link — the
    // retry action (see _retryAadhaarPanLink) is always available and
    // always safe to tap regardless of mandatory status.
    final panAadhaarLinkMandatory = _isMandatory(verificationStatus, 'aadhaar_pan_link');
    KycStepStatus panAadhaarLinkStatus;
    String panAadhaarLinkPill;
    String panAadhaarLinkSubtitle;
    if (!bothIdVerified) {
      panAadhaarLinkStatus = KycStepStatus.locked;
      panAadhaarLinkPill = 'Locked';
      panAadhaarLinkSubtitle = 'Unlocks once PAN and Aadhaar are verified';
    } else if (aadhaarState.aadhaarPanLinked == true || persistedPanAadhaarLink == 'LINKED') {
      panAadhaarLinkStatus = KycStepStatus.verified;
      panAadhaarLinkPill = 'Verified';
      panAadhaarLinkSubtitle = 'Linked as per Income Tax records';
    } else if (aadhaarState.aadhaarPanLinked == false || persistedPanAadhaarLink == 'NOT_LINKED') {
      panAadhaarLinkStatus = KycStepStatus.failed;
      panAadhaarLinkPill = 'Not Linked';
      panAadhaarLinkSubtitle = 'Not linked as per Income Tax records. You can retry to refresh this.';
    } else if (!panAadhaarLinkMandatory) {
      panAadhaarLinkStatus = KycStepStatus.underReview;
      panAadhaarLinkPill = 'Optional';
      panAadhaarLinkSubtitle = 'This check isn\'t required right now — you can still check it.';
    } else {
      panAadhaarLinkStatus = KycStepStatus.underReview;
      panAadhaarLinkPill = 'Pending';
      panAadhaarLinkSubtitle = 'Link status refreshes the next time you verify';
    }

    // Step: Bank Account Validation (BAV)
    final sortedBav = [...?bavHistory]..sort((a, b) => (b.attemptedOn ?? DateTime(0)).compareTo(a.attemptedOn ?? DateTime(0)));
    final latestBav = sortedBav.isEmpty ? null : sortedBav.first;
    final nameDobDone = nameDobStatus == KycStepStatus.verified;
    KycStepStatus bavStatus;
    String bavPill;
    String bavSubtitle;
    if (!nameDobDone) {
      bavStatus = KycStepStatus.locked;
      bavPill = 'Locked';
      bavSubtitle = 'Unlocks after Name & DOB Match clears';
    } else if (latestBav != null && latestBav.isApproved) {
      bavStatus = KycStepStatus.verified;
      bavPill = 'Verified';
      bavSubtitle = latestBav.accountLast4 != null ? 'Account ending ${latestBav.accountLast4}' : 'Penny-less BAV verified';
    } else if (latestBav != null && latestBav.status.toLowerCase() == 'rejected') {
      bavStatus = KycStepStatus.failed;
      bavPill = 'Retry';
      bavSubtitle = 'Bank verification failed. Please try again.';
    } else {
      bavStatus = KycStepStatus.actionable;
      bavPill = 'Initiate';
      bavSubtitle = 'Penny-less — no debit from your account';
    }

    // Resolved early — the PAN-Bank Link sub-item's retry action needs it
    // too, not just Reverse Penny Drop's.
    final primaryAccounts = (bankAccounts ?? const <BankAccount>[]).where((a) => a.isPrimary);
    final fallbackCbankId = primaryAccounts.isEmpty ? null : primaryAccounts.first.idBank;
    final cbankId = latestBav?.cbankId ?? fallbackCbankId;

    // PAN-Bank Link sub-item (inside BAV) — a REAL, separate provider check
    // (BankVerificationSurePassService.verify_pan_account_linkage), not
    // Bank Account Validation's own beneficiary-name match. Only ever
    // rendered once BAV itself verifies, so there's no "locked" branch here
    // any more. Read from the persisted CustomerVerificationStatus mirror;
    // see verificationStatusProvider's docstring for the vgr_is_mandatory=1
    // prerequisite this needs to ever leave NOT_STARTED. Runs automatically
    // right after a successful BAV (see BankAccountService.
    // check_pan_account_linkage), but the customer can also retry it
    // directly here — see _buildPanBankLinkSubItem.
    final persistedPanBankLink = (verificationStatus?['pan_bank_link'] as Map?)?['status'] as String?;
    // is_mandatory only changes the LABEL/whether this can block anything
    // — the check itself is always retryable (the backend no longer
    // refuses the call while Optional). While Optional and never yet
    // checked, this reads as "Optional" rather than an actionable prompt,
    // but the action button stays available (tapping it is harmless — see
    // _buildBavDetail). The moment an admin flips PAN_BANK_LINK back to
    // Mandatory, is_mandatory flips to true here (next refresh) and the
    // pill becomes the actionable Retry/Check Now prompt on its own — that
    // IS the "instruct the customer to complete it" behavior, driven by
    // the persisted flag rather than a separate one-off notification.
    final panBankLinkMandatory = _isMandatory(verificationStatus, 'pan_bank_link');
    KycStepStatus panBankLinkStatus;
    String panBankLinkPill;
    String panBankLinkSubtitle;
    if (persistedPanBankLink == 'LINKED') {
      panBankLinkStatus = KycStepStatus.verified;
      panBankLinkPill = 'Verified';
      panBankLinkSubtitle = 'Your PAN is linked to this bank account';
    } else if (persistedPanBankLink == 'NOT_LINKED') {
      panBankLinkStatus = KycStepStatus.failed;
      panBankLinkPill = 'Not Linked';
      panBankLinkSubtitle = 'Your PAN does not appear to be linked to this bank account';
    } else if (!panBankLinkMandatory) {
      panBankLinkStatus = KycStepStatus.underReview;
      panBankLinkPill = 'Optional';
      panBankLinkSubtitle = 'This check isn\'t required right now.';
    } else {
      panBankLinkStatus = KycStepStatus.actionable;
      panBankLinkPill = persistedPanBankLink == 'PENDING' ? 'Retry' : 'Check Now';
      panBankLinkSubtitle = 'Check whether your PAN is linked to this bank account';
    }

    // Reverse Penny Drop (RPD) sub-item (inside BAV) — same "no locked
    // branch" reasoning as PAN-Bank Link above.
    final sortedRpd = (rpdHistory ?? const <RpdHistoryItem>[]).where((r) => cbankId != null && r.cbankId == cbankId).toList()
      ..sort((a, b) => (b.createdOn ?? DateTime(0)).compareTo(a.createdOn ?? DateTime(0)));
    final latestRpd = sortedRpd.isEmpty ? null : sortedRpd.first;
    KycStepStatus rpdStatus;
    String rpdPill;
    String rpdSubtitle;
    if (latestRpd != null && latestRpd.status.toLowerCase() == 'success') {
      rpdStatus = KycStepStatus.verified;
      rpdPill = 'Verified';
      rpdSubtitle = 'Ownership confirmed';
    } else if (latestRpd != null && latestRpd.status.toLowerCase() == 'failed') {
      rpdStatus = KycStepStatus.failed;
      rpdPill = 'Retry';
      rpdSubtitle = latestRpd.failureReason ?? 'Additional verification failed. Please try again.';
    } else if (cbankId == null) {
      rpdStatus = KycStepStatus.locked;
      rpdPill = 'Locked';
      rpdSubtitle = 'Add a bank account to continue';
    } else {
      rpdStatus = KycStepStatus.actionable;
      rpdPill = 'Start';
      rpdSubtitle = 'Confirm ownership with a ₹1 transfer from your bank app';
    }

    // Auto-push into Additional Verification the moment it becomes
    // actionable (i.e. right after BAV clears) — no "Start" tap required.
    // Fires once per cbankId: never re-fires on every rebuild, and never
    // fires on top of a failed attempt (rpdStatus is `failed`, not
    // `actionable`, in that case) — a failed attempt shows its own Retry
    // action instead of being relaunched automatically.
    if (rpdActive && rpdStatus == KycStepStatus.actionable && cbankId != null && _autoLaunchedRpdCbankId != cbankId) {
      _autoLaunchedRpdCbankId = cbankId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startRpd(cbankId);
      });
    }

    // Dynamic numbering/progress — hidden (VGR-inactive) capabilities don't
    // consume a step number or count toward the ring, and PAN-Bank
    // Link/RPD (now BAV sub-items) don't factor into top-level progress at
    // all: BAV counts done as soon as BAV itself is approved.
    int stepCounter = 0;
    int total = 0;
    int completed = 0;
    void tally(KycStepStatus status) {
      total++;
      if (status == KycStepStatus.verified) completed++;
    }

    int? panIndex, aadhaarIndex;
    if (digilockerActive) {
      panIndex = ++stepCounter;
      aadhaarIndex = ++stepCounter;
      tally(panStatus);
      tally(aadhaarStatus);
    }
    final nameDobIndex = ++stepCounter;
    tally(nameDobStatus);
    int? panAadhaarLinkIndex;
    if (aadhaarPanLinkActive) {
      panAadhaarLinkIndex = ++stepCounter;
      tally(panAadhaarLinkStatus);
    }
    final bavIndex = ++stepCounter;
    tally(bavStatus);

    final bavNeedsSubItemAttention = bavStatus == KycStepStatus.verified &&
        ((panBankLinkActive &&
                (panBankLinkStatus == KycStepStatus.actionable || panBankLinkStatus == KycStepStatus.failed)) ||
            (rpdActive && rpdStatus != KycStepStatus.verified && rpdStatus != KycStepStatus.locked));

    // Which card should auto-expand / drive the footer CTA — first
    // actionable, unlocked step in display order; BAV also counts as
    // "needing attention" once verified if a sub-item still needs action.
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
    } else if (bavNeedsSubItemAttention) {
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
    } else if (bavStatus != KycStepStatus.verified && bavStatus != KycStepStatus.locked) {
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
                padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 100.h),
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
                      detail: _buildNameDobDetail(isDark, nameDobStatus, nameDobSubtitle),
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
                      title: 'Bank Account Validation',
                      subtitle: bavSubtitle,
                      status: bavStatus,
                      pillLabel: bavPill,
                      expanded: _expanded.contains('bav'),
                      onToggle: bavStatus == KycStepStatus.locked ? null : () => setState(() => _toggle('bav')),
                      lockedHint: bavStatus == KycStepStatus.locked ? bavSubtitle : null,
                      detail: _buildBavDetail(
                        isDark: isDark,
                        bavStatus: bavStatus,
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

  /// Name & DOB Match's own Retry — this status is recomputed fresh from
  /// CustomerPan/CustomerAadhaar on every fetch (KYCService.is_kyc_complete,
  /// not a separate mirror row), so a stuck "Pending" here is almost always
  /// a stale read shortly after DigiLocker approval (see kyc_screen.dart's
  /// `_checkCompletionRecoveryOnLoad` docstring for the exact race) —
  /// simply refetching resolves it, no write/confirm call needed.
  Widget _buildNameDobDetail(bool isDark, KycStepStatus status, String message) {
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
            onPressed: () => _retryNameDobMatch(),
            gradient: AppTheme.greenGradient,
          ),
        ],
      ],
    );
  }

  Future<void> _retryNameDobMatch() async {
    setState(() => _refreshingNameDob = true);
    try {
      ref.invalidate(kycDocumentsProvider(widget.requestFrom));
      ref.invalidate(verificationStatusProvider);
      await ref.read(kycDocumentsProvider(widget.requestFrom).future);
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
        if (mounted) {
          AppToast.show(context, 'Please re-verify PAN to refresh this link status.', type: ToastType.info);
        }
        await _openIdVerificationScreen();
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
    required KycStepStatus bavStatus,
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
    if (bavStatus != KycStepStatus.verified) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Validate a bank account with a penny-less check — no money is debited or credited.',
            style: AppTextStyles.fieldHelper(isDark),
          ),
          SizedBox(height: 12.h),
          CustomButton(
            text: bavStatus == KycStepStatus.failed ? 'Retry Bank Validation' : 'Initiate Bank Validation',
            svgIconPath: 'assets/buttons/tick.svg',
            isLoading: bankDataLoading,
            onPressed: () => _initiateBav(isDark),
            gradient: AppTheme.greenGradient,
          ),
        ],
      );
    }

    // BAV itself is verified — PAN-Bank Link and Reverse Penny Drop render
    // as sub-items here rather than their own top-level steps.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const KycVerifiedBanner(),
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
            title: 'Additional Verification',
            status: rpdStatus,
            pillLabel: rpdPill,
            subtitle: rpdSubtitle,
            actionLabel: rpdStatus == KycStepStatus.verified || rpdStatus == KycStepStatus.locked
                ? null
                : (rpdStatus == KycStepStatus.failed ? 'Retry Additional Verification' : 'Start Additional Verification'),
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
