import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/core/security/app_lifecycle_observer.dart';
import 'package:startgold/core/utils/kyc_validator.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';
import 'package:startgold/features/kyc/screens/kyc_screen.dart' show NameMismatchDialog, UpperCaseFormatter;
import 'package:startgold/features/kyc/screens/manual_kyc_upload_screen.dart';
import 'package:startgold/features/profile/profile_controller.dart' as pc;
import 'package:startgold/routes/app_router.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import 'package:startgold/shared/utils/aadhaar_input_formatter.dart';
import 'package:startgold/shared/utils/pan_input_formatter.dart';
import 'package:startgold/shared/utils/upper_case_words_formatter.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/custom_button.dart';
import 'package:startgold/shared/widgets/secure_clipboard.dart';

/// PAN + Aadhaar DigiLocker orchestration for [KycVerificationScreen],
/// adapted from `_KycScreenState` (kyc/screens/kyc_screen.dart) so the new
/// merged-checklist screen drives the exact same backend flow/providers
/// (`aadhaarProvider`, `kycDocumentsProvider`, `kycRepositoryProvider`)
/// without touching the live screen. Dedup sets (`AadhaarNotifier.handled*`)
/// are the SAME static sets the live screen and MainScreen's app-shell
/// fallback use — reusing them, not local copies, is what stops a
/// mismatch/failure outcome from being shown twice across screens.
mixin KycVerificationFlowMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  final panNameController = TextEditingController();
  final panNumberController = TextEditingController();
  final panFormKey = GlobalKey<FormState>();
  final aadhaarNumberController = TextEditingController();
  final aadhaarNameController = TextEditingController();
  final aadhaarFormKey = GlobalKey<FormState>();

  /// How many KYC host screens are mounted right now.
  ///
  /// MainScreen's app-shell fallback exists to show a pending outcome when
  /// NO host screen is around to show it itself. It decided that by racing
  /// the shared `handled*` claim sets on a 150 ms timer -- but a host can
  /// only claim an outcome it can already see, and
  /// [checkAadhaarOutcomeRecoveryOnLoad] runs once on mount, before
  /// `kyc/document-types` has answered. When the prompt only arrives with
  /// that response (`pending_action: CONFIRM_PROFILE_NAME`, say), the host
  /// never claims it, the fallback wins the race by default, and pushes a
  /// SECOND copy of the checklist on top of the one the customer is already
  /// looking at. That reads as "Back doesn't work": the first Back pops the
  /// duplicate and reveals the identical screen underneath.
  ///
  /// Counting mounted hosts answers the question the fallback is actually
  /// asking, and does not depend on when the data lands.
  static int _mountedHosts = 0;
  static bool get hasMountedHost => _mountedHosts > 0;

  bool _aadhaarSeeded = false;
  bool _aadhaarReconciled = false;
  bool aadhaarEditing = false;
  bool retryingPanOnly = false;
  bool verifyingAadhaar = false;
  bool completingKyc = false;

  /// Called once a docs-status refresh (triggered by [checkAndHandleCompletion])
  /// finishes reacting to a verify attempt — whether or not KYC is fully
  /// complete yet. No-op by default: the merged checklist screen just keeps
  /// showing the refreshed step statuses in place. [KycIdVerificationScreen]
  /// overrides this to pop back to the checklist so the user sees the
  /// updated PAN/Aadhaar status there.
  void onKycStepCompleted() {}

  @override
  void initState() {
    super.initState();
    _mountedHosts++;
  }

  @override
  void dispose() {
    _mountedHosts--;
    panNameController.dispose();
    panNumberController.dispose();
    aadhaarNumberController.dispose();
    aadhaarNameController.dispose();
    super.dispose();
  }

  /// Seeds/reconciles the Aadhaar provider from the latest `document-types`
  /// fetch — call once per build with the freshest [result]. Mirrors
  /// `_seedAadhaarIfApproved`/`_reconcileAadhaarWithBackend`.
  void syncAadhaarWithBackend(KycDocumentsResult result) {
    if (!_aadhaarSeeded && result.aadhaarApproved) {
      _aadhaarSeeded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(aadhaarProvider.notifier).seedApproved(
                maskedNumber: result.aadhaarMaskedNumber,
                name: result.aadhaarName,
                dob: result.aadhaarDob,
              );
        }
      });
    }
    if (!_aadhaarReconciled) {
      _aadhaarReconciled = true;
      if (!result.aadhaarApproved && ref.read(aadhaarProvider).phase == AadhaarPhase.approved) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) ref.read(aadhaarProvider.notifier).reset();
        });
      }
    }
  }

  bool _outcomeCheckedOnLoad = false;

  /// Recovery check for a freshly-(re)mounted host screen — mirrors
  /// `_checkAadhaarOutcomeRecoveryOnLoad` (kyc_screen.dart). Reads
  /// aadhaarProvider's CURRENT state directly (not ref.listen, which only
  /// fires on FUTURE transitions) and shows whichever pending outcome
  /// dialog applies. Covers the case where MainScreen's app-shell fallback
  /// (`_navigateToKycAndLetItHandle`) navigated back to a freshly-(re)pushed
  /// host screen because its own listener caught a pending mismatch/
  /// failure/approved outcome while no host screen was mounted to show it.
  /// Guarded to fire at most once per screen instance — call from a
  /// postFrameCallback since dialogs need a laid-out context.
  void checkAadhaarOutcomeRecoveryOnLoad(String requestFrom) {
    if (_outcomeCheckedOnLoad) return;
    _outcomeCheckedOnLoad = true;
    if (!mounted) return;
    handleAadhaarStateChange(requestFrom, ref.read(aadhaarProvider));
  }

  /// The actual outcome-handling logic, extracted so it can run both once
  /// on load (above) AND reactively on every later transition via a
  /// ref.listen the host screen's build() should register
  /// (`ref.listen<AadhaarState>(aadhaarProvider, (_, next) =>
  /// handleAadhaarStateChange(requestFrom, next))`).
  ///
  /// The on-load call alone isn't enough: SurePass's native DigiLocker SDK
  /// Activity can leave THIS host screen instance disposed by the time
  /// pollUntilTerminal()'s result actually lands (a fresh instance gets
  /// (re)mounted instead, whose own on-load check already ran and found
  /// nothing, since the poll hadn't resolved yet at that instant) — see
  /// kyc_screen.dart's identical `ref.listen` in build() for the same
  /// documented cause. Without a listener catching the LATER transition
  /// too, the customer sees no visible update at all until manually
  /// refreshing (pull-to-refresh or leaving and reopening the screen).
  ///
  /// Safe to call repeatedly for the same outcome from multiple call
  /// sites — every branch below is guarded by the same shared
  /// per-verificationId dedupe sets (AadhaarNotifier.handled*), so
  /// whichever caller reaches a given outcome first is the only one that
  /// actually acts on it.
  void handleAadhaarStateChange(String requestFrom, AadhaarState state) {
    if (state.phase == AadhaarPhase.awaitingNameMismatchConfirm && state.aadhaarMismatchPrompt != null) {
      _maybeShowAadhaarMismatchDialog(requestFrom, state.aadhaarMismatchPrompt!);
    }
    if (state.panMismatchPrompt != null) {
      _maybeShowPanMismatchDialog(requestFrom, state.panMismatchPrompt!);
    }
    if (state.phase == AadhaarPhase.expired ||
        state.phase == AadhaarPhase.rejected ||
        state.phase == AadhaarPhase.failed) {
      _maybeShowAadhaarFailureDialog(requestFrom, state);
    }
    if (state.phase == AadhaarPhase.approved && state.verificationId != null) {
      if (AadhaarNotifier.handledApprovedKeys.add(state.verificationId!)) {
        checkAndHandleCompletion(requestFrom);
      }
    }
    if (state.phase == AadhaarPhase.aadhaarNotShared && state.verificationId != null) {
      if (AadhaarNotifier.handledApprovedKeys.add(state.verificationId!)) {
        checkAndHandleCompletion(requestFrom);
      }
    }
  }

  bool get verificationInFlight {
    final phase = ref.read(aadhaarProvider).phase;
    return verifyingAadhaar ||
        completingKyc ||
        phase == AadhaarPhase.initiating ||
        phase == AadhaarPhase.polling;
  }

  Future<void> verifyPanAndAadhaar(String requestFrom) async {
    if (verifyingAadhaar) return;
    if (panFormKey.currentState?.validate() == false) return;
    if (aadhaarFormKey.currentState?.validate() == false) return;
    setState(() => verifyingAadhaar = true);
    try {
      await _runVerify(requestFrom);
    } finally {
      verifyingAadhaar = false;
      if (mounted) setState(() {});
    }
  }

  /// Redo DigiLocker consent purely to (re)fetch PAN after Aadhaar already
  /// approved without it (e.g. "PAN Verification Record" left unchecked).
  /// Only the PAN form is validated/shown — no Aadhaar number/name re-entry
  /// needed: the backend resolves the customer's existing approved Aadhaar
  /// identity from the KYC log when allow_reverify is set and those fields
  /// are blank (see KYCService._initiate_aadhaar_kyc). Aadhaar's own
  /// provider phase is left alone (never reset to idle), so its card keeps
  /// showing the Verified banner throughout — see [retryingPanOnly].
  Future<void> retryPan(String requestFrom) async {
    if (verifyingAadhaar) return;
    if (panFormKey.currentState?.validate() == false) return;
    setState(() {
      verifyingAadhaar = true;
      retryingPanOnly = true;
    });
    try {
      await _runVerify(requestFrom, panOnlyResume: true);
    } finally {
      verifyingAadhaar = false;
      retryingPanOnly = false;
      if (mounted) setState(() {});
    }
  }

  /// Reopens the Aadhaar form for a genuine correction (the user tapping
  /// "Edit" on an already-verified Aadhaar card) — NOT used by [retryPan]
  /// anymore, which no longer needs the customer to retype anything.
  void editAadhaar() {
    setState(() => aadhaarEditing = true);
    ref.read(aadhaarProvider.notifier).reset();
  }

  Future<void> _runVerify(String requestFrom, {bool panOnlyResume = false}) async {
    final notifier = ref.read(aadhaarProvider.notifier);
    AppLifecycleObserver.suppressAppLock = true;
    notifier.pauseAutoDispose();
    try {
      await notifier.initiate(
        requestFrom,
        aadhaarNumber: panOnlyResume ? '' : AadhaarInputFormatter.unformat(aadhaarNumberController.text),
        fullName: panOnlyResume ? '' : aadhaarNameController.text.trim(),
        panName: panNameController.text.trim(),
        panNumber: PanInputFormatter.unformat(panNumberController.text),
        allowReverify: panOnlyResume ? true : aadhaarEditing,
      );
      if (!mounted) return;

      final afterInitiate = ref.read(aadhaarProvider);
      if (afterInitiate.phase == AadhaarPhase.awaitingConsent && afterInitiate.consentUrl != null) {
        final consentConfirmed = await Navigator.pushNamed(
          context,
          AppRouter.aadhaarVerification,
          arguments: {'consentUrl': afterInitiate.consentUrl},
        );
        if (!mounted) return;
        if (consentConfirmed == true) {
          await ref.read(aadhaarProvider.notifier).pollUntilTerminal(requestFrom);
        }
      } else if (afterInitiate.phase == AadhaarPhase.awaitingSdk && afterInitiate.sdkToken != null) {
        final sdkConfirmed = await Navigator.pushNamed(
          context,
          AppRouter.digilockerSdk,
          arguments: {
            'sdkToken': afterInitiate.sdkToken,
            'clientId': afterInitiate.providerClientId,
            'environment': afterInitiate.sdkEnvironment,
          },
        );
        if (!mounted) return;
        if (sdkConfirmed == true) {
          await ref.read(aadhaarProvider.notifier).pollUntilTerminal(requestFrom);
        }
      }

      if (!mounted) return;
      var finalState = ref.read(aadhaarProvider);

      if (finalState.panMismatchPrompt != null) {
        await _maybeShowPanMismatchDialog(requestFrom, finalState.panMismatchPrompt!);
        if (!mounted) return;
        finalState = ref.read(aadhaarProvider);
      }

      if (finalState.phase == AadhaarPhase.expired ||
          finalState.phase == AadhaarPhase.rejected ||
          finalState.phase == AadhaarPhase.failed) {
        _maybeShowAadhaarFailureDialog(requestFrom, finalState);
        return;
      }

      if (finalState.phase == AadhaarPhase.aadhaarNotShared) {
        if (mounted && finalState.message != null) {
          AppToast.show(context, finalState.message!, type: ToastType.info);
        }
        if (!mounted) return;
        await checkAndHandleCompletion(requestFrom);
        return;
      }

      if (finalState.phase == AadhaarPhase.approved) {
        AadhaarNotifier.handledApprovedKeys.add(finalState.verificationId ?? 'approved-${finalState.maskedNumber}');
        await checkAndHandleCompletion(requestFrom);
        return;
      }

      if (finalState.phase == AadhaarPhase.awaitingNameMismatchConfirm) {
        await _maybeShowAadhaarMismatchDialog(requestFrom, finalState.aadhaarMismatchPrompt!);
        return;
      }

      if (finalState.message != null && mounted) {
        AppToast.show(context, finalState.message!, type: ToastType.info);
      }
    } finally {
      AppLifecycleObserver.suppressAppLock = false;
      notifier.resumeAutoDispose();
    }
  }

  Future<void> _maybeShowAadhaarMismatchDialog(String requestFrom, NameMismatchPrompt prompt) async {
    if (!AadhaarNotifier.handledMismatchIds.add(prompt.verificationId)) return;
    final resolved = await _showMismatchDialog(requestFrom, prompt);
    if (!mounted) return;
    if (resolved) await checkAndHandleCompletion(requestFrom, expectDocumentApproved: prompt.document);
  }

  Future<void> _maybeShowPanMismatchDialog(String requestFrom, NameMismatchPrompt prompt) async {
    if (!AadhaarNotifier.handledMismatchIds.add(prompt.verificationId)) return;
    final resolved = await _showMismatchDialog(requestFrom, prompt);
    if (!mounted) return;
    if (resolved) await checkAndHandleCompletion(requestFrom, expectDocumentApproved: prompt.document);
  }

  Future<bool> _showMismatchDialog(String requestFrom, NameMismatchPrompt prompt) async {
    final resolved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => NameMismatchDialog(
        prompt: prompt,
        onSubmit: (name, dob) => prompt.document == 'PAN'
            ? _confirmPanMismatch(prompt.verificationId, name, dob)
            : ref.read(aadhaarProvider.notifier).confirmNameMismatch(requestFrom, name: name, dob: dob),
      ),
    );
    return resolved ?? false;
  }

  Future<(NameMismatchOutcome, String?)> _confirmPanMismatch(String panKycId, String name, String dob) async {
    try {
      final data = await ref.read(kycRepositoryProvider).confirmPanNameMismatch(
            panKycId: panKycId,
            confirm: true,
            name: name,
            dob: dob,
          );
      final status = (data['status'] ?? '').toString();
      if (status == 'APPROVED') return (NameMismatchOutcome.resolved, null);
      return (NameMismatchOutcome.stillMismatched, data['message']?.toString());
    } catch (e) {
      var msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring('Exception: '.length);
      return (NameMismatchOutcome.stillMismatched, msg);
    }
  }

  Future<void> _maybeShowAadhaarFailureDialog(String requestFrom, AadhaarState state) async {
    final key = '${state.verificationId ?? state.message}-${state.phase}';
    if (!AadhaarNotifier.handledFailureKeys.add(key)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Aadhaar Verification'),
        content: Text(state.message ?? 'Aadhaar verification failed. Please try again.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
          // DigiLocker isn't the only way through — a customer whose consent
          // was denied, or hit an upstream gateway error, had no way forward
          // from this dialog besides dismissing and retrying the same failing
          // path. Route straight to the manual-upload screen instead, same
          // as the checklist card's own "Upload Manually" button.
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              openManualUpload('2', requestFrom);
            },
            child: const Text('Upload Manually'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    ref.invalidate(kycDocumentsProvider(requestFrom));
  }

  Future<void> checkAndHandleCompletion(String requestFrom, {String? expectDocumentApproved}) async {
    if (mounted) setState(() => completingKyc = true);
    try {
      if (AadhaarNotifier.completionInFlight != null) {
        await AadhaarNotifier.completionInFlight;
        return;
      }
      final future = _doCheckAndHandleCompletion(requestFrom, expectDocumentApproved: expectDocumentApproved);
      AadhaarNotifier.completionInFlight = future;
      try {
        await future;
      } finally {
        AadhaarNotifier.completionInFlight = null;
      }
    } finally {
      if (mounted) setState(() => completingKyc = false);
    }
  }

  bool _isDocumentApproved(KycDocumentsResult result, String document) {
    if (document == 'AADHAAR') return result.aadhaarApproved;
    return result.documents.any(
      (d) => (d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN')) && d.alreadyUploaded,
    );
  }

  Future<void> _doCheckAndHandleCompletion(String requestFrom, {String? expectDocumentApproved}) async {
    if (!mounted) return;
    final wasAlreadyConfirmed = ref.read(kycDocumentsProvider(requestFrom)).valueOrNull?.kycConfirmed ?? false;
    KycDocumentsResult result;
    try {
      result = await ref.refresh(kycDocumentsProvider(requestFrom).future);
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          "Couldn't refresh your verification status. Please check your connection and try again.",
          type: ToastType.error,
        );
      }
      return;
    }
    if (!mounted) return;

    // A mismatch-confirmation write may not have reached the DB replica
    // this read hits yet (same reasoning as _profileAlreadyMatches's own
    // retry below) — a customer who just resolved AADHAAR/PAN's name
    // mismatch would otherwise see the checklist still show it as pending
    // immediately after, only clearing once they leave and reopen the
    // screen much later. One retry after a short pause is enough to let a
    // typical replica catch up without meaningfully delaying the customer
    // who's already staring at the "Updating your validation status…"
    // loader this whole method runs under.
    if (expectDocumentApproved != null && !_isDocumentApproved(result, expectDocumentApproved)) {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      try {
        result = await ref.refresh(kycDocumentsProvider(requestFrom).future);
      } catch (_) {
        // Keep the first (stale) result rather than losing the whole
        // completion flow over a retry-only failure.
      }
      if (!mounted) return;
    }

    setState(() {
      aadhaarEditing = false;
      retryingPanOnly = false;
    });

    if (result.aadhaarApproved) {
      ref.read(aadhaarProvider.notifier).updateVerifiedDetails(
            maskedNumber: result.aadhaarMaskedNumber,
            name: result.aadhaarName,
            dob: result.aadhaarDob,
          );
    }

    final bothComplete = result.documents.every((d) => d.alreadyUploaded) && result.aadhaarApproved;
    if (!bothComplete || wasAlreadyConfirmed) {
      if (!wasAlreadyConfirmed && mounted) {
        final pendingDocs = result.documents.where((d) => !d.alreadyUploaded);
        final message = !result.aadhaarApproved
            ? 'PAN verified. Aadhaar verification is still pending.'
            : pendingDocs.isNotEmpty
                ? 'Aadhaar verified. ${pendingDocs.first.name} verification is still pending.'
                : 'Verification status updated.';
        AppToast.show(context, message, type: ToastType.success);
      }
      onKycStepCompleted();
      return;
    }

    // The PAN document's verified name/DOB used to be looked up here to feed
    // the removed per-document confirmation popup — nothing consumes them now.
    await _runCompletionSequence();
    if (mounted) onKycStepCompleted();
  }

  /// Unlike the live screen, this does NOT `Navigator.pop` on completion —
  /// the merged checklist keeps the user on this same page to continue into
  /// bank verification (steps 5-7). Backward-compat for existing blocked-
  /// action callers (SIP/Withdraw/Investment) is preserved separately: this
  /// screen isn't wired into `KycVerificationFlow.start` yet (see plan).
  /// Success animation, then done — the customer is finished.
  ///
  /// The per-document "PAN Verified"/"Aadhaar Verified" confirmation popup
  /// (`KycVerifiedDetailsDialog`) that used to run here was **removed**
  /// (2026-09-07, product decision — see `BUSINESS_RULES.md` RULE-KYC-007).
  /// A verification that already matched has nothing for the customer to
  /// confirm; the only case where their name/DOB genuinely needs re-entry is
  /// a mismatch, and `NameMismatchDialog` already handles that earlier in the
  /// flow. The popup's parameters are gone with it — this no longer needs the
  /// verified name/DOB at all.
  ///
  /// **Safe to drop the popup's server call.** Its Save was the only client
  /// trigger for `update_profile_name_from_kyc` → `confirm_and_sync()`, but
  /// that call is idempotent: `_check_aadhaar_kyc`'s and
  /// `_try_persist_digilocker_pan`'s APPROVED branches each already run
  /// `sync_from_kyc_log()` for their own document at verification time, which
  /// is what `is_kyc_complete()` actually reads. The mismatch path keeps its
  /// own `confirm_and_sync()` inside `_finalize_name_mismatch_confirmation`.
  /// Consequence to be aware of: the profile name/DOB is no longer overwritten
  /// with the document's version on a clean match — it keeps whatever the
  /// customer already had, which is exactly what "it matched" means.
  Future<void> _runCompletionSequence() async {
    await _showSuccessAnimation();
    if (!mounted) return;

    ref.read(pc.profileProvider.notifier).fetchProfileDetails();
  }

  Future<void> _showSuccessAnimation() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: Padding(
          padding: EdgeInsets.all(32.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('KYC Validation', style: AppTextStyles.titleMedium(isDark).copyWith(color: const Color(0xFF643D41))),
              SizedBox(height: 24.h),
              Container(
                width: 72.r,
                height: 72.r,
                decoration: const BoxDecoration(color: Color(0xFF52B76E), shape: BoxShape.circle),
                child: Icon(Icons.check, color: Colors.white, size: 40.sp),
              ),
              SizedBox(height: 24.h),
              Text(
                'PAN & Aadhaar Verified\nKYC Completed Successfully',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleLarge(isDark).copyWith(height: 1.4, color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context);
  }

  Future<void> openManualUpload(String docType, String requestFrom) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ManualKycUploadScreen(docType: docType, requestFrom: requestFrom)),
    );
    if (result == true && mounted) {
      ref.invalidate(kycDocumentsProvider(requestFrom));
      ref.read(pc.profileProvider.notifier).fetchProfileDetails();
    }
  }

  // ─── Field widgets (content only — the outer card/status chrome is the
  // caller's KycStepRow) ─────────────────────────────────────────────────

  Widget buildGovIdHeader({
    required String hindiTitle,
    required String englishTitle,
    required IconData icon,
    required Color color,
    String? rightHindiTitle,
    String? rightEnglishTitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(hindiTitle, style: GoogleFonts.lora(color: color, fontSize: 10.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 2.h),
              Text(englishTitle,
                  style: GoogleFonts.playfairDisplay(color: color, fontSize: 12.sp, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ],
          ),
        ),
        SizedBox(width: 8.w),
        Icon(icon, color: color, size: 18.sp),
        if (rightHindiTitle != null && rightEnglishTitle != null) ...[
          SizedBox(width: 10.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(rightHindiTitle, style: GoogleFonts.lora(color: color, fontSize: 10.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 2.h),
              Text(rightEnglishTitle,
                  style: GoogleFonts.playfairDisplay(color: color, fontSize: 11.sp, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ],
          ),
        ],
      ],
    );
  }

  Widget buildPanFieldsCard(bool isDark) {
    const cardBg = Color(0xFFEAF3FB);
    const cardBorder = Color(0xFFBFDDF5);
    const textColor = Color(0xFF0B3D91);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F26) : cardBg,
        border: Border.all(color: isDark ? Colors.white24 : cardBorder),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Form(
        key: panFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildGovIdHeader(
              hindiTitle: 'आयकर विभाग',
              englishTitle: 'INCOME TAX DEPARTMENT',
              icon: Icons.verified_outlined,
              color: isDark ? Colors.white : textColor,
              rightHindiTitle: 'भारत सरकार',
              rightEnglishTitle: 'GOVT. OF INDIA',
            ),
            SizedBox(height: 16.h),
            Text('NAME AS ON PAN', style: AppTextStyles.fieldLabel(isDark)),
            SizedBox(height: 8.h),
            TextFormField(
              controller: panNameController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                KycUpperCaseNameFormatter(),
                LengthLimitingTextInputFormatter(60),
              ],
              contextMenuBuilder: SecureClipboard.none,
              style: AppTextStyles.kycFieldInput(isDark),
              decoration: InputDecoration(
                hintText: 'RAHUL SHARMA',
                hintStyle: AppTextStyles.kycFieldHint(isDark),
                errorStyle: AppTextStyles.fieldError(isDark),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a valid name' : null,
            ),
            SizedBox(height: 16.h),
            Text('PERMANENT ACCOUNT NUMBER', style: AppTextStyles.fieldLabel(isDark)),
            SizedBox(height: 8.h),
            TextFormField(
              controller: panNumberController,
              textCapitalization: TextCapitalization.characters,
              keyboardType: TextInputType.text,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                UpperCaseFormatter(),
                LengthLimitingTextInputFormatter(10),
              ],
              contextMenuBuilder: SecureClipboard.none,
              style: AppTextStyles.kycFieldInput(isDark),
              decoration: InputDecoration(
                hintText: 'ABCDE1234F',
                hintStyle: AppTextStyles.kycFieldHint(isDark),
                errorStyle: AppTextStyles.fieldError(isDark),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              validator: (v) => KycValidator.validatePAN(PanInputFormatter.unformat(v ?? '')),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildAadhaarFieldsCard(
    bool isDark, {
    required String helperText,
    required bool showAlreadyVerifiedHint,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1F26) : const Color(0xFFFCF3E3),
        border: Border.all(color: isDark ? Colors.white24 : const Color(0xFFEEDDBB)),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Form(
        key: aadhaarFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildGovIdHeader(
              hindiTitle: 'भारत सरकार',
              englishTitle: 'GOVERNMENT OF INDIA',
              icon: Icons.qr_code_scanner_outlined,
              color: isDark ? Colors.white : const Color(0xFF5A3E1B),
            ),
            SizedBox(height: 16.h),
            if (showAlreadyVerifiedHint) ...[
              Row(
                children: [
                  Icon(Icons.check_circle, size: 16.sp, color: const Color(0xFF16A34A)),
                  SizedBox(width: 6.w),
                  Text('Aadhaar Verified', style: AppTextStyles.fieldLabel(isDark).copyWith(color: const Color(0xFF16A34A))),
                ],
              ),
              SizedBox(height: 8.h),
            ],
            Text(helperText, style: AppTextStyles.fieldHelper(isDark)),
            SizedBox(height: 16.h),
            Text('NAME AS ON AADHAAR', style: AppTextStyles.fieldLabel(isDark)),
            SizedBox(height: 8.h),
            TextFormField(
              controller: aadhaarNameController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                KycUpperCaseNameFormatter(),
                LengthLimitingTextInputFormatter(60),
              ],
              contextMenuBuilder: SecureClipboard.none,
              style: AppTextStyles.kycFieldInput(isDark),
              decoration: InputDecoration(
                hintText: 'RAHUL SHARMA',
                hintStyle: AppTextStyles.kycFieldHint(isDark),
                errorStyle: AppTextStyles.fieldError(isDark),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              validator: (v) => (v == null || v.trim().length < 2) ? 'Enter a valid name' : null,
            ),
            SizedBox(height: 16.h),
            Text('AADHAAR NUMBER', style: AppTextStyles.fieldLabel(isDark)),
            SizedBox(height: 8.h),
            TextFormField(
              controller: aadhaarNumberController,
              keyboardType: TextInputType.number,
              inputFormatters: [AadhaarInputFormatter()],
              contextMenuBuilder: SecureClipboard.none,
              style: AppTextStyles.kycFieldInput(isDark),
              decoration: InputDecoration(
                hintText: 'XXXX XXXX XXXX',
                hintStyle: AppTextStyles.kycFieldHint(isDark),
                errorStyle: AppTextStyles.fieldError(isDark),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none),
                contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              ),
              validator: (v) {
                final digits = AadhaarInputFormatter.unformat(v ?? '');
                if (digits.length != 12) return 'Enter a valid 12-digit Aadhaar number';
                if (!RegExp(r'^[2-9]').hasMatch(digits)) return 'Enter a valid 12-digit Aadhaar number';
                if (RegExp(r'^(\d)\1{11}$').hasMatch(digits)) return 'Enter a valid 12-digit Aadhaar number';
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }
}

DateTime? _parseKycDob(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final ddmmyyyy = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(raw);
  if (ddmmyyyy != null) {
    return DateTime(int.parse(ddmmyyyy.group(3)!), int.parse(ddmmyyyy.group(2)!), int.parse(ddmmyyyy.group(1)!));
  }
  return DateTime.tryParse(raw);
}

// DD-MM-YYYY — the one format the backend's KYCService._parse_flexible_date
// tries first; must stay paired with that server-side parser.
String _formatKycDob(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

InputDecoration _kycInputBoxDecoration(bool isDark) {
  final borderColor = isDark ? Colors.white24 : Colors.black12;
  return InputDecoration(
    filled: true,
    fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: borderColor)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide(color: borderColor)),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12.r),
      borderSide: const BorderSide(color: Color(0xFF52B76E), width: 1.5),
    ),
  );
}

/// Converts name input to ALL UPPERCASE, letters+spaces only — matches PAN
/// card format. Public counterpart to kyc_screen.dart's private
/// `_UpperCaseNameFormatter`.
class KycUpperCaseNameFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r'[a-zA-Z ]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned = newValue.text.split('').where((c) => _allowed.hasMatch(c)).join();
    final upper = cleaned.toUpperCase();
    return newValue.copyWith(text: upper, selection: TextSelection.collapsed(offset: upper.length));
  }
}
