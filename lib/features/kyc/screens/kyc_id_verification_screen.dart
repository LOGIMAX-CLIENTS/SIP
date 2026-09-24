import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/controllers/kyc_verification_flow_mixin.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/widgets/kyc_progress_header.dart';
import 'package:startgold/features/kyc/widgets/kyc_step_row.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/custom_button.dart';

/// Dedicated data-entry page for the PAN + Aadhaar identity-verification
/// step, pushed from [KycVerificationScreen] when the user taps the "PAN
/// Verification" or "Aadhaar Verification" checklist row. Previously these
/// input fields expanded in place on the checklist page itself, which read
/// as if the checklist were broken/duplicated; this screen keeps document
/// data-entry off the checklist while reusing the exact same DigiLocker
/// flow via [KycVerificationFlowMixin].
class KycIdVerificationScreen extends ConsumerStatefulWidget {
  final String requestFrom;

  const KycIdVerificationScreen({super.key, required this.requestFrom});

  @override
  ConsumerState<KycIdVerificationScreen> createState() => _KycIdVerificationScreenState();
}

class _KycIdVerificationScreenState extends ConsumerState<KycIdVerificationScreen>
    with KycVerificationFlowMixin<KycIdVerificationScreen> {
  @override
  void onKycStepCompleted() {
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _handleRefresh() async {
    ref.invalidate(kycDocumentsProvider(widget.requestFrom));
    if (mounted) AppToast.show(context, 'Refreshing verification status…', type: ToastType.info);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(kycDocumentsProvider(widget.requestFrom));
    final aadhaarState = ref.watch(aadhaarProvider);

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
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: docsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (docsResult) {
                syncAadhaarWithBackend(docsResult);
                return _buildBody(isDark: isDark, docsResult: docsResult, aadhaarState: aadhaarState);
              },
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
  }) {
    final panDoc = docsResult.documents.where(
      (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
    );
    final panDocValue = panDoc.isEmpty ? null : panDoc.first;
    final panDone = panDocValue?.alreadyUploaded ?? false;
    final panUnderReview = panDocValue?.isUnderReview ?? false;

    final aadhaarBusy = verifyingAadhaar || aadhaarState.phase == AadhaarPhase.initiating || aadhaarState.phase == AadhaarPhase.polling;
    final aadhaarDone = aadhaarState.phase == AadhaarPhase.approved ||
        (docsResult.aadhaarApproved && !aadhaarEditing && (!aadhaarBusy || retryingPanOnly));
    final aadhaarUnderReview = docsResult.aadhaarUnderReview && !aadhaarEditing;
    final aadhaarFailedPhase = aadhaarState.phase == AadhaarPhase.expired ||
        aadhaarState.phase == AadhaarPhase.rejected ||
        aadhaarState.phase == AadhaarPhase.failed;
    final panSkippedInConsent = !panDone && !aadhaarEditing && (aadhaarState.phase == AadhaarPhase.approved || docsResult.aadhaarApproved);

    final panAllowManualUpload = docsResult.digilockerAttempted ||
        docsResult.aadhaarApproved ||
        (panDocValue?.status.toUpperCase() == 'REJECTED');
    final aadhaarAllowManualUpload = docsResult.digilockerAttempted || panDone || docsResult.aadhaarRejected;

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

    final completed = (panDone ? 1 : 0) + (aadhaarDone ? 1 : 0);
    final bothDone = completed == 2;
    final headline = bothDone ? 'PAN & Aadhaar Verified' : 'Verify PAN & Aadhaar';
    final subtitle = bothDone
        ? "You're all set — head back to continue the rest of your KYC."
        : panSkippedInConsent
            ? 'Aadhaar is verified. Retry PAN verification below.'
            : 'Complete PAN and Aadhaar verification to continue.';

    return Column(
      children: [
        KycProgressHeader(
          title: headline,
          subtitle: subtitle,
          completed: completed,
          total: 2,
          onRefresh: _handleRefresh,
        ),
        Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                // Generous bottom clearance for the floating footer CTA and plenty
                // of scroll headroom when the keyboard is open so input fields can
                // be scrolled comfortably clear into view.
                padding: EdgeInsets.fromLTRB(
                    20.w, 20.h, 20.w, (bothDone || panSkippedInConsent) ? 60.h : 260.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                      expanded: true,
                      detail: _buildStep1Detail(isDark, panDone, panUnderReview, panSkippedInConsent, panAllowManualUpload, panDocValue),
                    ),
                    KycStepRow(
                      index: 2,
                      title: 'Aadhaar Verification',
                      subtitle: aadhaarDone
                          ? (aadhaarState.maskedNumber ?? docsResult.aadhaarMaskedNumber ?? 'Aadhaar verified')
                          : 'via DigiLocker',
                      status: step2Status,
                      pillLabel: step2Pill,
                      expanded: true,
                      detail: _buildStep2Detail(isDark, aadhaarState, docsResult, aadhaarDone, aadhaarUnderReview, aadhaarAllowManualUpload),
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
              // Covers the whole post-consent window — DigiLocker polling
              // (aadhaarBusy) through the final status refresh
              // (completingKyc) — so there's continuous full-screen loading
              // feedback from the moment DigiLocker closes until this screen
              // pops back to the checklist, instead of just a small spinner
              // on the footer button during polling.
              if (completingKyc || aadhaarBusy)
                Positioned.fill(
                  child: Container(
                    color: (isDark ? Colors.black : Colors.white).withOpacity(0.75),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        SizedBox(height: 16.h),
                        Text(
                          completingKyc ? 'Updating your verification status…' : 'Verifying with DigiLocker…',
                          style: AppTextStyles.fieldHelper(isDark),
                        ),
                      ],
                    ),
                  ),
                ),
              // Hidden once Aadhaar is verified and PAN is the only step left
              // (panSkippedInConsent). In that state this button ran a FULL
              // DigiLocker re-consent purely to retry PAN — pointless now that
              // the PAN card offers "Verify PAN", which checks the typed number
              // against the provider's PAN API directly (RULE-KYC-019). Showing
              // both invited the customer down the slower, heavier route.
              if (!bothDone && !panSkippedInConsent)
                Positioned(
                  left: 20.w,
                  right: 20.w,
                  bottom: 16.h,
                  child: _buildFooterCta(aadhaarBusy, panSkippedInConsent),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The single "Verify via DigiLocker" action lives here, outside/below
  /// both cards, rather than embedded inside the Aadhaar card — this is the
  /// one action button for the page, whichever card still needs it.
  Widget _buildFooterCta(bool aadhaarBusy, bool panSkippedInConsent) {
    return CustomButton(
      text: panSkippedInConsent ? 'Retry PAN Verification' : 'Verify via DigiLocker',
      svgIconPath: 'assets/buttons/tick.svg',
      isLoading: aadhaarBusy,
      onPressed: aadhaarBusy
          ? null
          : () {
              if (panSkippedInConsent) {
                retryPan(widget.requestFrom);
              } else {
                verifyPanAndAadhaar(widget.requestFrom);
              }
            },
      gradient: AppTheme.greenGradient,
    );
  }

  /// [panSkippedInConsent] means Aadhaar is already verified and PAN is the
  /// ONLY pending step — the page-level footer CTA (see [_buildFooterCta])
  /// switches to "Retry PAN Verification" in this case, so this card only
  /// needs to show the warning + editable fields, plus its own manual-upload
  /// fallback.
  Widget _buildStep1Detail(
    bool isDark,
    bool panDone,
    bool panUnderReview,
    bool panSkippedInConsent,
    bool allowManualUpload,
    KycDocumentType? panDocValue,
  ) {
    // Verified PAN, and the customer has tapped Edit on it — show the form
    // again so they can correct the number/name and re-verify. Checked BEFORE
    // panDone so edit mode wins over the verified banner.
    if (panDone && panEditing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildPanFieldsCard(isDark),
          SizedBox(height: 12.h),
          // Submits with allow_reverify (see the mixin's panEditing doc) —
          // without it the backend short-circuits as "already approved" and
          // the corrected value is silently ignored.
          buildVerifyPanDirectButton(widget.requestFrom),
          // Same fallback ordering as everywhere else — a human-reviewed
          // upload is offered only once the automatic route has failed.
          if (panDirectFailed) ...[
            SizedBox(height: 8.h),
            _manualUploadButton('1'),
          ],
          // Cancel sits LAST, below both actions: it's the way out of edit
          // mode, not one of the ways forward, so it shouldn't separate the
          // primary action from its fallback.
          SizedBox(height: 8.h),
          Center(
            child: TextButton(
              onPressed: verifyingPanDirect
                  ? null
                  : () => setState(() => panEditing = false),
              child: Text(
                'Cancel',
                style: AppTextStyles.fieldLabel(isDark),
              ),
            ),
          ),
        ],
      );
    }
    if (panDone) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KycVerifiedBanner(
            numberLabel: 'PAN Number',
            maskedValue: panDocValue?.maskedValue,
            nameLabel: 'Name as on PAN',
            verifiedName: panDocValue?.verifiedName,
          ),
        ],
      );
    }
    if (panUnderReview) {
      return _underReviewNotice(isDark, 'PAN');
    }
    if (panSkippedInConsent) {
      const warningColor = Color(0xFFD97706);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16.r),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 18.sp, color: warningColor),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    "Aadhaar is verified, but PAN wasn't shared during DigiLocker consent, so it couldn't be verified.",
                    style: AppTextStyles.fieldHelper(isDark).copyWith(color: const Color(0xFF78350F)),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          buildPanFieldsCard(isDark),
          SizedBox(height: 12.h),
          // Primary route (RULE-KYC-019): verify the TYPED PAN against the
          // provider's standalone PAN API. DigiLocker has already given
          // everything it will here — Aadhaar is approved, PAN simply wasn't
          // in that consent — so re-running the whole consent to retry PAN
          // achieves nothing.
          buildVerifyPanDirectButton(widget.requestFrom),
          // Manual upload needs a human to review a document, so it appears
          // only once the automatic route above has actually been tried and
          // failed — not as a peer option beside it.
          if (panDirectFailed) ...[
            SizedBox(height: 8.h),
            _manualUploadButton('1'),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildPanFieldsCard(isDark),
        // NOT gated on panDirectFailed here, unlike the panSkippedInConsent
        // branch above. This is the Aadhaar-NOT-yet-verified state, and the
        // backend only allows standalone PAN verification once Aadhaar is
        // APPROVED (RULE-KYC-019) — so there is no automatic route to try
        // first, and hiding manual upload behind a failure that can never
        // happen would strand the customer with no way forward at all.
        if (allowManualUpload) ...[
          SizedBox(height: 8.h),
          _manualUploadButton('1'),
        ],
      ],
    );
  }

  Widget _underReviewNotice(bool isDark, String label) {
    const infoColor = Color(0xFF2563EB);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.hourglass_top_rounded, size: 18.sp, color: infoColor),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              "Your manually uploaded $label is under review. We'll notify you once it's verified.",
              style: AppTextStyles.fieldHelper(isDark).copyWith(color: const Color(0xFF1E3A5F)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Detail(
    bool isDark,
    AadhaarState aadhaarState,
    KycDocumentsResult docsResult,
    bool aadhaarDone,
    bool aadhaarUnderReview,
    bool allowManualUpload,
  ) {
    if (aadhaarDone) {
      return KycVerifiedBanner(
        numberLabel: 'Aadhaar Number',
        maskedValue: aadhaarState.maskedNumber ?? docsResult.aadhaarMaskedNumber,
        nameLabel: 'Name as on Aadhaar',
        verifiedName: aadhaarState.verifiedName ?? docsResult.aadhaarName,
        linkedToAadhaar: aadhaarState.aadhaarPanLinked,
      );
    }
    if (aadhaarUnderReview) {
      return _underReviewNotice(isDark, 'Aadhaar');
    }
    final showAlreadyVerifiedHint = docsResult.aadhaarApproved && aadhaarEditing;
    const defaultHelperText = 'Enter your Aadhaar number, then verify via DigiLocker to complete KYC.';
    const editHelperText = 'Redo verification if any of your Aadhaar details have changed.';
    final isErrorPhase = aadhaarState.phase == AadhaarPhase.failed ||
        aadhaarState.phase == AadhaarPhase.expired ||
        aadhaarState.phase == AadhaarPhase.rejected;
    final helperText = showAlreadyVerifiedHint ? editHelperText : (isErrorPhase ? defaultHelperText : (aadhaarState.message ?? defaultHelperText));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildAadhaarFieldsCard(
          isDark,
          helperText: helperText,
          showAlreadyVerifiedHint: showAlreadyVerifiedHint,
        ),
        if (!showAlreadyVerifiedHint && allowManualUpload) ...[
          SizedBox(height: 8.h),
          _manualUploadButton('2'),
        ],
      ],
    );
  }

  Widget _manualUploadButton(String docType) {
    return CustomButton(
      text: 'Upload Manually',
      svgIconPath: 'assets/buttons/folder-add.svg',
      backgroundColor: const Color(0xFFE3F1E7),
      textColor: const Color(0xFF0E5723),
      onPressed: () => openManualUpload(docType, widget.requestFrom),
    );
  }
}
