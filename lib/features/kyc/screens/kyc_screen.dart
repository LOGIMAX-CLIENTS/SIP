import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';
import 'package:startgold/routes/app_router.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';
import 'package:startgold/shared/utils/aadhaar_input_formatter.dart';
import 'package:startgold/shared/utils/upper_case_words_formatter.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/custom_button.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/shared/widgets/secure_clipboard.dart';

/// Unified KYC hub — shows PAN and Aadhaar verification together.
///
/// KYC is complete only when BOTH PAN and Aadhaar are approved (mirrors the
/// backend's `KYCService.is_kyc_complete`, which every gated action — SIP
/// create, withdrawal, savings — already checks). PAN is a simple field
/// form (`/kyc/document-types` + `/kyc/upload`, id_document="1"). Aadhaar is
/// a DigiLocker consent + poll flow (`/kyc/upload`, id_document="2") that
/// does not come back from `/kyc/document-types` today, so it is rendered
/// as a second, client-side card driven by [aadhaarProvider] rather than by
/// the documents list.
///
/// The "Finish" footer only completes once both are approved, at which
/// point this screen pops `true` — every caller (SIP/Withdrawal/Investment/
/// Profile) awaits that and either retries the original blocked action
/// (see `KycVerificationFlow`) or just refreshes its own status.
class KycScreen extends ConsumerStatefulWidget {
  final String requestFrom;
  final Map<String, dynamic>? extraData;

  const KycScreen({
    super.key,
    required this.requestFrom,
    this.extraData,
  });

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  final Map<String, Map<String, TextEditingController>> _docControllers = {};
  final Map<String, GlobalKey<FormState>> _docFormKeys = {};
  final Set<String> _completedDocIds = {};
  final Set<String> _submittingDocIds = {};
  bool _initialized = false;
  bool _aadhaarSeeded = false;
  // Guards the on-load completion-recovery check below — fires at most
  // once per screen instance, same pattern as _aadhaarSeeded.
  bool _completionCheckedOnLoad = false;
  // Set when the user taps "Edit" on an already-verified Aadhaar card, so
  // the next _onVerifyAadhaar() call tells the backend to bypass its
  // already-approved idempotency short-circuit (see KYCRepository.initiateAadhaar).
  bool _aadhaarEditing = false;

  final _aadhaarNumberController = TextEditingController();
  final _aadhaarNameController = TextEditingController();
  final _aadhaarFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    for (var controllers in _docControllers.values) {
      for (var controller in controllers.values) {
        controller.dispose();
      }
    }
    _aadhaarNumberController.dispose();
    _aadhaarNameController.dispose();
    super.dispose();
  }

  /// Mirrors the backend's `validate_aadhaar_number` (shared/utils/validators.py):
  /// 12 digits, first digit 2-9, and not an obvious placeholder (all same
  /// digit). This is purely a client-side sanity check — actual identity
  /// verification always happens via DigiLocker consent, never this number.
  String? _validateAadhaarNumber(String? value) {
    final digits = AadhaarInputFormatter.unformat(value ?? '');
    if (digits.length != 12) return 'Enter a valid 12-digit Aadhaar number';
    if (!RegExp(r'^[2-9]').hasMatch(digits)) {
      return 'Enter a valid 12-digit Aadhaar number';
    }
    if (RegExp(r'^(\d)\1{11}$').hasMatch(digits)) {
      return 'Enter a valid 12-digit Aadhaar number';
    }
    return null;
  }

  String? _validateAadhaarName(String? value) {
    if (value == null || value.trim().length < 2) return 'Enter a valid name';
    return null;
  }

  void _initControllers(List<KycDocumentType> docs) {
    if (_initialized) return;
    for (var doc in docs) {
      _docControllers[doc.id] = {};
      _docFormKeys[doc.id] = GlobalKey<FormState>();
      final List<KycField> allFields = List.from(doc.fields);
      final isPan = doc.name.toUpperCase().contains('PAN') ||
          doc.code.toUpperCase().contains('PAN');

      if (isPan && !allFields.any((f) => f.name.contains('name'))) {
        allFields
            .add(KycField(name: 'full_name', label: 'Full Name', type: 'text'));
      }

      for (var field in allFields) {
        _docControllers[doc.id]![field.name] = TextEditingController();
      }

      // Seed already-approved documents so their card starts in the
      // Verified state instead of re-prompting for input.
      if (doc.alreadyUploaded || doc.status.toUpperCase() == 'APPROVED') {
        _completedDocIds.add(doc.id);
      }
    }
    _initialized = true;
  }

  /// Seeds the Aadhaar card as already-approved before the user ever sees
  /// the form, if the server reports it's already VERIFIED — mirrors
  /// `_initControllers`'s PAN seeding above. Deferred to a post-frame
  /// callback since it's triggered from `build()` and mutates a provider
  /// this widget also watches.
  void _seedAadhaarIfApproved(bool aadhaarApproved, {String? maskedNumber, String? name, String? dob}) {
    if (_aadhaarSeeded || !aadhaarApproved) return;
    _aadhaarSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(aadhaarProvider.notifier).seedApproved(maskedNumber: maskedNumber, name: name, dob: dob);
      }
    });
  }

  /// Recovers a customer who auto-verified (both PAN and Aadhaar already
  /// log-approved) but never reached the mandatory Profile Name Selection
  /// dialog — e.g. the app was closed right after DigiLocker succeeded.
  /// `_checkAndHandleCompletion()` only re-runs after a LIVE submit, so
  /// merely reopening this screen wouldn't otherwise retry it — the cards
  /// already show "Verified" everywhere, so nothing would look wrong, but
  /// `result.kycConfirmed` (backed by CustomerPan/CustomerAadhaar, which
  /// only flips once this dialog's choice is submitted) would stay false
  /// forever, silently blocking SIP/withdrawals with no visible cause. Fires
  /// at most once per screen instance; once `kycConfirmed` is true this
  /// never fires again.
  void _checkCompletionRecoveryOnLoad(KycDocumentsResult result) {
    if (_completionCheckedOnLoad) return;
    final bothComplete =
        result.documents.every((d) => d.alreadyUploaded) && result.aadhaarApproved;
    if (!bothComplete || result.kycConfirmed) return;
    _completionCheckedOnLoad = true;

    final panDoc = result.documents.isEmpty
        ? null
        : result.documents.firstWhere(
            (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
            orElse: () => result.documents.first,
          );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _runCompletionSequence(
          panName: panDoc?.verifiedName,
          panDob: panDoc?.verifiedDob,
          aadhaarName: result.aadhaarName,
          aadhaarDob: result.aadhaarDob,
        );
      }
    });
  }

  /// Re-opens an already-verified document's form so the user can redo
  /// verification (e.g. fix a typo). PAN just needs its form shown again —
  /// a new/edited PAN number is verified fresh by the backend regardless.
  void _editDocument(KycDocumentType doc) {
    setState(() => _completedDocIds.remove(doc.id));
  }

  /// Re-opens the Aadhaar form for a redo. `_aadhaarEditing` tells the next
  /// `_onVerifyAadhaar()` call to pass `allowReverify: true`, since the
  /// backend otherwise short-circuits any Aadhaar re-verification attempt
  /// once one is already APPROVED.
  void _editAadhaar() {
    setState(() => _aadhaarEditing = true);
    ref.read(aadhaarProvider.notifier).reset();
  }

  /// PAN has no consent of its own — it's fetched from the SAME DigiLocker
  /// session as Aadhaar (see `_buildPanAutoVerifyNotice`'s doc comment and
  /// `MODULE_BRAIN.md` §2). If the user unchecks "PAN Verification Record" on
  /// DigiLocker's document-selection screen, Aadhaar comes back APPROVED but
  /// PAN never does — the only way to retry PAN is a fresh DigiLocker consent.
  /// This re-runs that consent (reusing `_editAadhaar`'s reverify plumbing)
  /// instead of leaving the user staring at a PAN card whose old copy still
  /// said "complete Aadhaar verification below" even though Aadhaar was
  /// already done.
  Future<void> _onRetryPan() async {
    _editAadhaar();
    // The Aadhaar card was showing the verified banner (no Form in the tree)
    // — wait one frame so `_aadhaarFormKey` is attached to the now-visible
    // input form before validating it.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    if (_aadhaarFormKey.currentState?.validate() != true) {
      // Aadhaar was approved in an earlier session, so these fields were
      // never filled in this one — nothing to resubmit yet. Point the user
      // at the now-reopened Aadhaar form below instead of doing nothing.
      AppToast.show(
        context,
        "Re-enter your Aadhaar details below, then verify again — make sure "
        "'PAN Verification Record' is selected on the DigiLocker consent "
        "screen this time.",
        type: ToastType.info,
      );
      return;
    }

    await _onVerifyAadhaar();
    if (!mounted) return;

    // _onVerifyAadhaar() already surfaces its own toast on failure/timeout,
    // and already runs the completion sequence if PAN came back this time.
    // The one gap it doesn't cover: Aadhaar re-approves fine but PAN is
    // AGAIN missing (user skipped the checkbox a second time) — nothing
    // else would tell the user that attempt didn't fix it.
    if (ref.read(aadhaarProvider).phase != AadhaarPhase.approved) return;
    final docs = ref.read(kycDocumentsProvider(widget.requestFrom)).valueOrNull;
    final panStillMissing = docs != null && !docs.documents.every((d) => d.alreadyUploaded);
    if (panStillMissing) {
      AppToast.show(
        context,
        "PAN still isn't verified. Please try again and make sure 'PAN "
        "Verification Record' is checked before tapping Allow on the "
        "DigiLocker consent screen.",
        type: ToastType.error,
      );
    }
  }

  Future<void> _submitDoc(KycDocumentType doc) async {
    final formKey = _docFormKeys[doc.id];
    if (formKey?.currentState?.validate() == false) return;

    setState(() => _submittingDocIds.add(doc.id));
    try {
      final fields = <String, dynamic>{};
      _docControllers[doc.id]?.forEach((key, controller) {
        fields[key] = controller.text;
      });
      // doc.alreadyUploaded means this document was already APPROVED when
      // the screen loaded — the only way its form is visible again is via
      // the "Edit" action (see _editDocument), so this is a deliberate redo.
      // Tells the backend to bypass its already-approved idempotency
      // short-circuit, which would otherwise silently ignore a corrected
      // name/number without ever re-verifying via Cashfree.
      if (doc.alreadyUploaded) {
        fields['allow_reverify'] = true;
      }

      await ref.read(kycSubmitProvider.notifier).submit(
            requestFrom: widget.requestFrom,
            documentId: doc.id,
            fields: fields,
          );

      final result = ref.read(kycSubmitProvider);
      if (result.hasError) {
        if (mounted) {
          String errorMsg = result.error.toString();
          if (errorMsg.startsWith('Exception: ')) {
            errorMsg = errorMsg.substring('Exception: '.length);
          }
          AppToast.show(context, errorMsg, type: ToastType.error);
        }
        return;
      }

      if (mounted) {
        setState(() => _completedDocIds.add(doc.id));
        await _checkAndHandleCompletion();
      }
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.startsWith('Exception: ')) {
          msg = msg.substring('Exception: '.length);
        }
        AppToast.show(context, msg, type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _submittingDocIds.remove(doc.id));
    }
  }

  /// Kicks off (or resumes) the Aadhaar DigiLocker sub-flow. Idempotent on
  /// the backend — if Aadhaar was already approved in a prior attempt this
  /// resolves instantly without opening the WebView (see
  /// `AadhaarNotifier.initiate`).
  Future<void> _onVerifyAadhaar() async {
    if (_aadhaarFormKey.currentState?.validate() == false) return;

    final notifier = ref.read(aadhaarProvider.notifier);
    await notifier.initiate(
      widget.requestFrom,
      aadhaarNumber: AadhaarInputFormatter.unformat(_aadhaarNumberController.text),
      fullName: _aadhaarNameController.text.trim(),
      allowReverify: _aadhaarEditing,
    );
    if (!mounted) return;

    final afterInitiate = ref.read(aadhaarProvider);
    if (afterInitiate.phase == AadhaarPhase.awaitingConsent &&
        afterInitiate.consentUrl != null) {
      // Cashfree — webview consent flow.
      final consentConfirmed = await Navigator.pushNamed(
        context,
        AppRouter.aadhaarVerification,
        arguments: {'consentUrl': afterInitiate.consentUrl},
      );
      if (!mounted) return;
      // Only poll if the user tapped "I've completed verification" — if
      // they backed out (hardware back → pops with a null result) there is
      // nothing new to check yet, so skip the round trip.
      if (consentConfirmed == true) {
        await notifier.pollUntilTerminal(widget.requestFrom);
      }
    } else if (afterInitiate.phase == AadhaarPhase.awaitingSdk &&
        afterInitiate.sdkToken != null) {
      // SurePass — native DigiLocker Flutter SDK flow.
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
        await notifier.pollUntilTerminal(widget.requestFrom);
      }
    }

    if (!mounted) return;
    var finalState = ref.read(aadhaarProvider);

    // PAN's mismatch prompt (if any) is independent of Aadhaar's own
    // phase below — it can be set alongside APPROVED, already-approved, or
    // even REJECTED (see AadhaarState.panMismatchPrompt's doc comment) — so
    // it's handled first, unconditionally, before branching on phase.
    if (finalState.panMismatchPrompt != null) {
      final resolved = await _showMismatchDialog(finalState.panMismatchPrompt!);
      if (!mounted) return;
      if (resolved) await _checkAndHandleCompletion();
      finalState = ref.read(aadhaarProvider);
    }

    if (finalState.phase == AadhaarPhase.expired ||
        finalState.phase == AadhaarPhase.rejected ||
        finalState.phase == AadhaarPhase.failed) {
      if (!mounted) return;
      AppToast.show(
        context,
        finalState.message ?? 'Aadhaar verification failed. Please try again.',
        type: ToastType.error,
      );
      return;
    }

    if (finalState.phase == AadhaarPhase.approved) {
      await _checkAndHandleCompletion();
      return;
    }

    if (finalState.phase == AadhaarPhase.awaitingNameMismatchConfirm) {
      final resolved = await _showMismatchDialog(finalState.aadhaarMismatchPrompt!);
      if (!mounted) return;
      if (resolved) await _checkAndHandleCompletion();
      return;
    }

    // pollUntilTerminal exhausted its retries while DigiLocker was still
    // processing (e.g. the provider's document-fetch/cross-verify chain
    // outran the client's polling window) — it resets to awaitingConsent
    // with an explanatory message instead of a terminal phase. Without this,
    // the user sees the DigiLocker screen close and nothing else: no
    // success, no error. Surface it so they know to check back / retry.
    if (finalState.message != null) {
      if (!mounted) return;
      AppToast.show(context, finalState.message!, type: ToastType.info);
    }
  }

  /// Alternate Aadhaar path — Meon's native DigiLocker SDK, launched
  /// directly with merchant credentials fetched from
  /// `KycRepository.getMeonSdkConfig()` rather than through
  /// `AadhaarNotifier.initiate()` (that notifier's phases only model the
  /// consent_url/sdk_token shapes the GatewayFactory abstraction produces —
  /// Meon's package needs company_name+secret_token directly, which doesn't
  /// fit either). Only succeeds while MEON is the backend's active KYC
  /// gateway; surfaces a toast rather than a button state if it isn't.
  Future<void> _onVerifyAadhaarMeon() async {
    if (_aadhaarFormKey.currentState?.validate() == false) return;

    Map<String, dynamic> config;
    try {
      config = await ref.read(kycRepositoryProvider).getMeonSdkConfig();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(
        context,
        e.toString().replaceFirst('Exception: ', ''),
        type: ToastType.error,
      );
      return;
    }
    if (!mounted) return;

    final confirmed = await Navigator.pushNamed(
      context,
      AppRouter.meonDigilockerSdk,
      arguments: {
        'companyName': config['company_name'] as String,
        'secretToken': config['secret_token'] as String,
        'redirectUrl': (config['redirect_url'] as String?) ?? '',
      },
    );
    if (!mounted) return;

    if (confirmed == true) {
      // Meon's SDK returns full verification data inline — no separate
      // poll step like the webview/SurePass paths need. Refresh
      // document-types the same way a completed submission does elsewhere.
      await _checkAndHandleCompletion();
    }
  }

  /// Fires after EVERY successful PAN submit and EVERY successful Aadhaar
  /// approval (first-time or via Edit/reverify — see _submitDoc and
  /// _onVerifyAadhaar). Re-fetches document-types so the completion check —
  /// and the names shown in the mandatory popup below — always reflect the
  /// verification that JUST happened, never stale pre-edit data. Only forms
  /// call this, so it can never fire from merely viewing an already-verified
  /// screen (e.g. opened from Profile).
  Future<void> _checkAndHandleCompletion() async {
    if (!mounted) return;
    final KycDocumentsResult result;
    try {
      result = await ref.refresh(kycDocumentsProvider(widget.requestFrom).future);
    } catch (_) {
      return; // Couldn't refresh — nothing reliable to show, don't block on it.
    }
    if (!mounted) return;

    // Sync the Aadhaar card's own display (separate from this dialog) —
    // pollUntilTerminal's APPROVED case only flips the phase, it doesn't
    // carry the masked number/name itself.
    if (result.aadhaarApproved) {
      ref.read(aadhaarProvider.notifier).updateVerifiedDetails(
            maskedNumber: result.aadhaarMaskedNumber,
            name: result.aadhaarName,
            dob: result.aadhaarDob,
          );
    }

    final bothComplete =
        result.documents.every((d) => d.alreadyUploaded) && result.aadhaarApproved;
    // Skip if KYC is already confirmed — e.g. resolving the Aadhaar/PAN
    // name-mismatch dialog just ran confirm_and_sync() on the backend
    // (same call the popup below itself triggers on Save), so re-showing
    // it here would ask the customer to confirm a name they just entered.
    // Mirrors the identical guard in _checkCompletionRecoveryOnLoad.
    if (!bothComplete || result.kycConfirmed) return;

    final panDoc = result.documents.isEmpty
        ? null
        : result.documents.firstWhere(
            (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
            orElse: () => result.documents.first,
          );

    await _runCompletionSequence(
      panName: panDoc?.verifiedName,
      panDob: panDoc?.verifiedDob,
      aadhaarName: result.aadhaarName,
      aadhaarDob: result.aadhaarDob,
    );
  }

  /// Success animation, then the MANDATORY verified-details confirmation —
  /// one dialog per document (Aadhaar first, then PAN — see
  /// _showVerifiedDetailsDialog), each saving straight from its own dialog
  /// rather than a single "pick one source" choice. Every caller
  /// (SIP/Withdrawal/Investment/Profile) awaits this screen and decides
  /// what to do next itself (typically retrying the original blocked
  /// action via KycVerificationFlow) — no requestFrom-specific navigation
  /// lives here.
  Future<void> _runCompletionSequence({
    String? panName,
    String? panDob,
    String? aadhaarName,
    String? aadhaarDob,
  }) async {
    await _showSuccessAnimation();
    if (!mounted) return;

    await _showVerifiedDetailsDialog(
      source: 'AADHAAR', verifiedName: aadhaarName, verifiedDob: aadhaarDob,
    );
    if (!mounted) return;

    await _showVerifiedDetailsDialog(
      source: 'PAN', verifiedName: panName, verifiedDob: panDob,
    );
    if (!mounted) return;

    Navigator.pop(context, true);
  }

  /// Brief, auto-dismissing checkmark — purely celebratory, does not itself
  /// close this screen (see _runCompletionSequence).
  Future<void> _showSuccessAnimation() async {
    if (!mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: Padding(
          padding: EdgeInsets.all(32.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'KYC Verification',
                style: AppTextStyles.titleMedium(isDark)
                    .copyWith(color: const Color(0xFF643D41)),
              ),
              SizedBox(height: 24.h),
              Container(
                width: 72.r,
                height: 72.r,
                decoration: const BoxDecoration(
                  color: Color(0xFF52B76E),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check, color: Colors.white, size: 40.sp),
              ),
              SizedBox(height: 24.h),
              Text(
                'PAN & Aadhaar Verified\nKYC Completed Successfully',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleLarge(isDark)
                    .copyWith(height: 1.4, color: Colors.black),
              ),
            ],
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context); // Close the checkmark dialog only.
  }

  /// MANDATORY confirmation shown once per document after every PAN +
  /// Aadhaar completion — first-time verification AND every re-verification
  /// via Edit — with no exceptions. Not dismissible via the barrier or the
  /// back button (PopScope canPop:false inside _VerifiedDetailsDialog) —
  /// the user must tap Save. Resolves only after the save actually
  /// succeeds (see _VerifiedDetailsDialogState._save).
  Future<void> _showVerifiedDetailsDialog({
    required String source,
    String? verifiedName,
    String? verifiedDob,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerifiedDetailsDialog(
        source: source,
        verifiedName: verifiedName,
        verifiedDob: verifiedDob,
        repository: ref.read(kycRepositoryProvider),
      ),
    );
  }

  /// Shown for EITHER mismatch prompt — AADHAAR's own (CONFIRM_NAME_UPDATE
  /// from the poll response, resolved via AadhaarNotifier.confirmNameMismatch)
  /// or PAN's piggybacked one (resolved via KycRepository.confirmPanNameMismatch
  /// — see NameMismatchPrompt's doc comment for why these are two entirely
  /// separate requests despite sharing this one dialog). Dismissible, unlike
  /// _VerifiedDetailsDialog — a genuine identity mismatch may not be
  /// resolvable by re-typing, so the customer can back out rather than
  /// being stuck. Returns true only once the submit actually resolves it.
  Future<bool> _showMismatchDialog(NameMismatchPrompt prompt) async {
    final resolved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NameMismatchDialog(
        prompt: prompt,
        onSubmit: (name, dob) => prompt.document == 'PAN'
            ? _confirmPanMismatch(prompt.verificationId, name, dob)
            : ref.read(aadhaarProvider.notifier).confirmNameMismatch(
                  widget.requestFrom, name: name, dob: dob,
                ),
      ),
    );
    return resolved ?? false;
  }

  /// PAN-side submit handler for _showMismatchDialog — mirrors
  /// AadhaarNotifier.confirmNameMismatch's outcome contract but has no
  /// AadhaarState to update (PAN's mismatch resolution doesn't touch
  /// Aadhaar's own phase; see KycRepository.confirmPanNameMismatch's doc
  /// comment for the request shape).
  Future<(NameMismatchOutcome, String?)> _confirmPanMismatch(
    String panKycId,
    String name,
    String dob,
  ) async {
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
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring('Exception: '.length);
      return (NameMismatchOutcome.stillMismatched, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(kycDocumentsProvider(widget.requestFrom));
    final aadhaarState = ref.watch(aadhaarProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Verification'),
          Expanded(
            child: docsAsync.when(
              data: (result) {
                _initControllers(result.documents);
                _seedAadhaarIfApproved(
                  result.aadhaarApproved,
                  maskedNumber: result.aadhaarMaskedNumber,
                  name: result.aadhaarName,
                  dob: result.aadhaarDob,
                );
                _checkCompletionRecoveryOnLoad(result);
                return SingleChildScrollView(
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Complete your KYC',
                          style: AppTextStyles.titleLarge(isDark)),
                      SizedBox(height: 8.h),
                      Text(
                        'Aadhaar and PAN are verified together via DigiLocker.',
                        style: AppTextStyles.fieldHelper(isDark),
                      ),
                      SizedBox(height: 32.h),
                      ...result.documents
                          .map((doc) => _buildDocumentCard(doc, isDark, aadhaarState)),
                      _buildAadhaarCard(isDark, aadhaarState),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
    );
  }

  /// PAN is verified automatically from the same DigiLocker consent used
  /// for Aadhaar (see backend `KYCService._try_persist_digilocker_pan`,
  /// which fetches the PAN from DigiLocker then cross-verifies it via
  /// SurePass's /pan/pan-comprehensive) — there is deliberately no manual
  /// PAN entry form anymore. Any OTHER future document type still gets the
  /// generic field-form path below.
  Widget _buildDocumentCard(KycDocumentType doc, bool isDark, AadhaarState aadhaarState) {
    final isPan = doc.name.toUpperCase().contains('PAN') ||
        doc.code.toUpperCase().contains('PAN');
    final isDone = _completedDocIds.contains(doc.id);
    // PAN rides on the same DigiLocker session as Aadhaar (see
    // _buildPanAutoVerifyNotice). If Aadhaar already came back APPROVED but
    // PAN's card is still pending, the user skipped/unchecked PAN in
    // DigiLocker's document picker — show that explicitly instead of the
    // generic "complete Aadhaar below" notice, which would be actively wrong
    // once Aadhaar is done.
    final panSkippedInConsent =
        isPan && !isDone && aadhaarState.phase == AadhaarPhase.approved;
    final aadhaarRetryBusy = aadhaarState.phase == AadhaarPhase.initiating ||
        aadhaarState.phase == AadhaarPhase.polling;

    return Padding(
      padding: EdgeInsets.only(bottom: 32.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusHeader(doc.name, isDark, isDone),
          SizedBox(height: 16.h),
          if (isDone)
            _buildVerifiedBanner(
              isDark,
              numberLabel: isPan ? 'PAN Number' : null,
              maskedValue: doc.maskedValue,
              nameLabel: isPan ? 'Name as on PAN' : null,
              verifiedName: doc.verifiedName,
              // PAN has no manual re-entry path — redo Aadhaar (its own
              // Edit) to trigger a fresh DigiLocker consent + PAN re-check.
              onEdit: isPan ? null : () => _editDocument(doc),
            )
          else if (panSkippedInConsent)
            _buildPanSkippedNotice(isDark, isBusy: aadhaarRetryBusy)
          else if (isPan)
            _buildPanAutoVerifyNotice(isDark)
          else ...[
            Form(
              key: _docFormKeys[doc.id],
              child: _buildGenericCard(doc, isDark, false),
            ),
            SizedBox(height: 12.h),
            CustomButton(
              text: 'Verify ${doc.name}',
              svgIconPath: 'assets/buttons/tick.svg',
              isLoading: _submittingDocIds.contains(doc.id),
              onPressed: () => _submitDoc(doc),
              gradient: AppTheme.greenGradient,
            ),
          ],
        ],
      ),
    );
  }

  /// Shown in place of the (removed) manual PAN entry form while PAN is
  /// still pending — PAN verification is entirely driven by the Aadhaar
  /// DigiLocker consent below, not by anything entered on this card.
  Widget _buildPanAutoVerifyNotice(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20.r)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18.sp, color: isDark ? Colors.white54 : Colors.black45),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'PAN is verified automatically via DigiLocker — complete '
              'Aadhaar verification below and PAN will be checked at the '
              'same time.',
              style: AppTextStyles.fieldHelper(isDark),
            ),
          ),
        ],
      ),
    );
  }

  /// Shown instead of [_buildPanAutoVerifyNotice] once Aadhaar has already
  /// come back APPROVED but this PAN card is still pending — i.e. the user
  /// completed DigiLocker consent without "PAN Verification Record" checked.
  /// Uses the app's existing amber "warning" palette (see `app_toast.dart`'s
  /// `ToastType.warning` style) so this reads as "needs your attention", not
  /// a hard failure, since re-running consent with PAN checked resolves it.
  Widget _buildPanSkippedNotice(bool isDark, {required bool isBusy}) {
    const warningColor = Color(0xFFD97706);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, size: 18.sp, color: warningColor),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  "Aadhaar is verified, but PAN wasn't shared during "
                  "DigiLocker consent, so it couldn't be verified.",
                  style: AppTextStyles.fieldHelper(isDark).copyWith(color: const Color(0xFF78350F)),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          CustomButton(
            text: 'Retry PAN Verification',
            svgIconPath: 'assets/buttons/tick.svg',
            isLoading: isBusy,
            onPressed: isBusy ? null : _onRetryPan,
            gradient: AppTheme.greenGradient,
          ),
          SizedBox(height: 8.h),
          Text(
            "On the next DigiLocker screen, select 'PAN Verification "
            "Record' before tapping Allow.",
            style: AppTextStyles.fieldHelper(isDark)
                .copyWith(color: const Color(0xFF78350F), fontStyle: FontStyle.italic),
          ),
        ],
      ),
    );
  }

  Widget _buildAadhaarCard(bool isDark, AadhaarState state) {
    final isDone = state.phase == AadhaarPhase.approved;
    final isBusy = state.phase == AadhaarPhase.initiating ||
        state.phase == AadhaarPhase.polling;
    // Error/failure text is surfaced only via AppToast (see
    // _onVerifyAadhaar) — never rendered inline on the card, so no backend
    // exception, provider error, or technical message can ever appear here.
    final isErrorPhase = state.phase == AadhaarPhase.failed ||
        state.phase == AadhaarPhase.expired ||
        state.phase == AadhaarPhase.rejected;
    const defaultHelperText =
        'Enter your Aadhaar number, then verify via DigiLocker to complete KYC.';
    final helperText = isErrorPhase ? defaultHelperText : (state.message ?? defaultHelperText);

    return Padding(
      padding: EdgeInsets.only(bottom: 32.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusHeader('Aadhaar', isDark, isDone),
          SizedBox(height: 16.h),
          if (isDone)
            _buildVerifiedBanner(
              isDark,
              numberLabel: 'Aadhaar Number',
              maskedValue: state.maskedNumber,
              nameLabel: 'Name as on Aadhaar',
              verifiedName: state.verifiedName,
              onEdit: _editAadhaar,
            )
          else ...[
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20.r),
              decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.03)
                      : Colors.black.withOpacity(0.02),
                  borderRadius: BorderRadius.circular(20.r)),
              child: Form(
                key: _aadhaarFormKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      helperText,
                      style: AppTextStyles.fieldHelper(isDark),
                    ),
                    SizedBox(height: 16.h),
                    Text('Full Name (as per Aadhaar)',
                        style: AppTextStyles.fieldLabel(isDark)),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _aadhaarNameController,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                        _UpperCaseNameFormatter(),
                        LengthLimitingTextInputFormatter(60),
                      ],
                      contextMenuBuilder: SecureClipboard.none,
                      style: AppTextStyles.kycFieldInput(isDark),
                      decoration: InputDecoration(
                        hintText: 'Full name',
                        hintStyle: AppTextStyles.kycFieldHint(isDark),
                        errorStyle: AppTextStyles.fieldError(isDark),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 14.h),
                      ),
                      validator: _validateAadhaarName,
                    ),
                    SizedBox(height: 16.h),
                    Text('Aadhaar Number',
                        style: AppTextStyles.fieldLabel(isDark)),
                    SizedBox(height: 8.h),
                    TextFormField(
                      controller: _aadhaarNumberController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [AadhaarInputFormatter()],
                      contextMenuBuilder: SecureClipboard.none,
                      style: AppTextStyles.kycFieldInput(isDark),
                      decoration: InputDecoration(
                        hintText: 'XXXX XXXX XXXX',
                        hintStyle: AppTextStyles.kycFieldHint(isDark),
                        errorStyle: AppTextStyles.fieldError(isDark),
                        filled: true,
                        fillColor: isDark
                            ? Colors.white.withOpacity(0.03)
                            : Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide.none),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 14.h),
                      ),
                      validator: _validateAadhaarNumber,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 12.h),
            CustomButton(
              text: 'Verify via DigiLocker',
              svgIconPath: 'assets/buttons/tick.svg',
              isLoading: isBusy,
              onPressed: _onVerifyAadhaar,
              gradient: AppTheme.greenGradient,
            ),
            // Alternate path — only ever succeeds while MEON is the active
            // KYC gateway backend-side; shows a toast otherwise. Not gated
            // behind a feature flag on purpose for now — revisit before
            // wide rollout if this shouldn't be visible to every user.
            Center(
              child: TextButton(
                onPressed: isBusy ? null : _onVerifyAadhaarMeon,
                child: Text(
                  'Verify via Meon (native)',
                  style: AppTextStyles.fieldLabel(isDark),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusHeader(String name, bool isDark, bool isDone) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(4.r),
          decoration: BoxDecoration(
              color: isDone
                  ? const Color(0xFF0E5723).withOpacity(0.15)
                  : (isDark ? Colors.white12 : Colors.black12),
              shape: BoxShape.circle),
          child: Icon(Icons.check,
              color: isDone ? const Color(0xFF0E5723) : Colors.transparent,
              size: 14.sp),
        ),
        SizedBox(width: 8.w),
        Text('$name Required', style: AppTextStyles.fieldLabel(isDark)),
      ],
    );
  }

  /// Same green "Verified" styling used on the Profile screen's KYC menu
  /// item (see profile_screen.dart), extended with the masked document
  /// number + verified name (when available) and an "Edit" action that
  /// re-opens the form to redo verification.
  Widget _buildVerifiedBanner(
    bool isDark, {
    String? numberLabel,
    String? maskedValue,
    String? nameLabel,
    String? verifiedName,
    VoidCallback? onEdit,
  }) {
    final labelColor = const Color(0xFF0E5723).withOpacity(0.65);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF0E5723).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFF0E5723).withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_rounded,
                  color: const Color(0xFF0E5723), size: 16.sp),
              SizedBox(width: 8.w),
              Text(
                'Verified',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF0E5723),
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              if (onEdit != null)
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8.r),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined,
                            size: 14.sp, color: const Color(0xFF0E5723)),
                        SizedBox(width: 4.w),
                        Text(
                          'Edit',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0E5723),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (maskedValue != null && maskedValue.isNotEmpty) ...[
            SizedBox(height: 12.h),
            Text(numberLabel ?? 'Number',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp, color: labelColor, fontWeight: FontWeight.w600)),
            SizedBox(height: 2.h),
            Text(maskedValue,
                style: GoogleFonts.lora(
                    fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.black87)),
          ],
          if (verifiedName != null && verifiedName.isNotEmpty) ...[
            SizedBox(height: 10.h),
            Text(nameLabel ?? 'Name',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 11.sp, color: labelColor, fontWeight: FontWeight.w600)),
            SizedBox(height: 2.h),
            Text(verifiedName,
                style: GoogleFonts.playfairDisplay(
                    fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.black87)),
          ],
        ],
      ),
    );
  }

  Widget _buildGenericCard(KycDocumentType doc, bool isDark, bool isPan) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.03)
              : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(20.r)),
      child: _buildDocInputs(doc, isDark, false, isPan),
    );
  }

  Widget _buildDocInputs(
      KycDocumentType doc, bool isDark, bool stylized, bool isPan) {
    final List<KycField> allFields = List.from(doc.fields);
    if (isPan && !allFields.any((f) => f.name.contains('name'))) {
      allFields
          .add(KycField(name: 'full_name', label: 'Full Name', type: 'text'));
    }

    return Column(
      children: allFields.map((field) {
        final bool isNumeric = field.type == 'number' ||
            (field.regex?.startsWith('^\\d') ?? false);
        // Identify field roles
        final bool isPanNumber = isPan &&
            field.name != 'full_name' &&
            !field.name.contains('name');
        final bool isNameField =
            field.name.contains('name') || field.name == 'full_name';

        // Build input formatters based on field role
        final List<TextInputFormatter> formatters = () {
          if (isPanNumber) {
            // PAN number: only A-Z and 0-9, max 10 characters, uppercase
            return <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
              UpperCaseFormatter(),
              LengthLimitingTextInputFormatter(10),
            ];
          } else if (isNameField) {
            // Name as on PAN: ALL UPPERCASE, letters and spaces only
            return <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
              _UpperCaseNameFormatter(),
              LengthLimitingTextInputFormatter(60),
            ];
          } else if (!isNumeric) {
            return <TextInputFormatter>[UpperCaseFormatter()];
          }
          return <TextInputFormatter>[];
        }();

        return Padding(
          padding: EdgeInsets.only(bottom: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!stylized)
                Text(field.label, style: AppTextStyles.fieldLabel(isDark)),
              if (!stylized) SizedBox(height: 8.h),
              TextFormField(
                controller: _docControllers[doc.id]?[field.name],
                keyboardType:
                    isNumeric ? TextInputType.number : TextInputType.text,
                textCapitalization: isNameField || isPanNumber
                    ? TextCapitalization.characters
                    : TextCapitalization.none,
                inputFormatters: formatters,
                contextMenuBuilder: SecureClipboard.none,
                style: AppTextStyles.kycFieldInput(isDark),
                decoration: InputDecoration(
                  hintText: field.label,
                  hintStyle: AppTextStyles.kycFieldHint(isDark),
                  errorStyle: AppTextStyles.fieldError(isDark),
                  filled: true,
                  fillColor: stylized
                      ? Colors.white
                      : (isDark
                          ? Colors.white.withOpacity(0.03)
                          : Colors.white),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.r),
                      borderSide: stylized
                          ? const BorderSide(color: Colors.black12)
                          : BorderSide.none),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (isPanNumber) {
                    // PAN format: AAAAA9999A (5 letters, 4 digits, 1 letter)
                    if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$')
                        .hasMatch(v.toUpperCase())) {
                      return 'Enter a valid PAN (e.g. ABCDE1234F)';
                    }
                  } else if (isNameField) {
                    if (v.trim().length < 2) return 'Enter a valid name';
                  } else if (field.regex != null && field.regex!.isNotEmpty) {
                    if (!RegExp(field.regex!).hasMatch(v)) {
                      return 'Invalid ${field.label} format';
                    }
                  }
                  return null;
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

}

// Shared by both _VerifiedDetailsDialog and _NameMismatchDialog below — DOB
// display/entry always goes through these two so the format stays paired
// with the backend's KYCService._parse_flexible_date.
DateTime? _parseKycDob(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final ddmmyyyy = RegExp(r'^(\d{2})-(\d{2})-(\d{4})$').firstMatch(raw);
  if (ddmmyyyy != null) {
    return DateTime(
      int.parse(ddmmyyyy.group(3)!),
      int.parse(ddmmyyyy.group(2)!),
      int.parse(ddmmyyyy.group(1)!),
    );
  }
  return DateTime.tryParse(raw);
}

// DD-MM-YYYY, not ISO — this is the one format KYCService._parse_flexible_date
// (backend) tries first. Every DOB payload/display string in this file must
// stay in that format; switching to ISO breaks the pairing with the
// server-side parser.
String _formatKycDob(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

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

/// Shown once per document by _KycScreenState._showVerifiedDetailsDialog —
/// displays the read-only verified Name/DOB fetched from PAN/Aadhaar
/// alongside editable Profile Name (text) and Date of Birth (date picker)
/// fields, pre-filled from those verified values. Saving the name is a real,
/// live call (KycRepository.updateProfileName) — the backend re-validates
/// whatever the customer typed against the verified [source] name and
/// rejects a mismatch (PROFILE_NAME_MISMATCH), surfaced here as [_errorText]
/// rather than closing the dialog. Saving the DOB (KycRepository.updateProfileDob)
/// is best-effort — see that method's doc comment for why: no backend
/// endpoint exists for it yet, so it silently no-ops on failure without
/// blocking the name save or the dialog from closing.
class _VerifiedDetailsDialog extends StatefulWidget {
  final String source; // 'PAN' | 'AADHAAR'
  final String? verifiedName;
  final String? verifiedDob;
  final KycRepository repository;

  const _VerifiedDetailsDialog({
    required this.source,
    required this.verifiedName,
    required this.verifiedDob,
    required this.repository,
  });

  @override
  State<_VerifiedDetailsDialog> createState() => _VerifiedDetailsDialogState();
}

class _VerifiedDetailsDialogState extends State<_VerifiedDetailsDialog> {
  late final TextEditingController _nameController;
  DateTime? _selectedDob;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.verifiedName ?? '');
    _selectedDob = _parseKycDob(widget.verifiedDob);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => _selectedDob = picked);
  }

  Future<void> _save() async {
    final typedName = _nameController.text.trim();
    if (typedName.isEmpty) {
      setState(() => _errorText = 'Name cannot be empty.');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    try {
      await widget.repository.updateProfileName(source: widget.source, name: typedName);
      if (_selectedDob != null) {
        try {
          await widget.repository.updateProfileDob(
            source: widget.source,
            dob: _formatKycDob(_selectedDob!),
          );
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring('Exception: '.length);
      setState(() {
        _saving = false;
        _errorText = msg;
      });
    }
  }

  Widget _buildVerifiedRow(String label, String? value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label:', style: AppTextStyles.fieldLabel(isDark)),
        SizedBox(height: 2.h),
        Text(
          (value == null || value.isEmpty) ? '—' : value,
          style: AppTextStyles.kycFieldInput(isDark).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sourceLabel = widget.source == 'PAN' ? 'PAN' : 'Aadhaar';
    final borderColor = isDark ? Colors.white24 : Colors.black12;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(24.r),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$sourceLabel Verified',
                style: AppTextStyles.titleMedium(isDark).copyWith(color: const Color(0xFF643D41)),
              ),
              SizedBox(height: 16.h),
              _buildVerifiedRow('Verified $sourceLabel Name', widget.verifiedName, isDark),
              SizedBox(height: 12.h),
              _buildVerifiedRow('Verified $sourceLabel Date of Birth', widget.verifiedDob, isDark),
              SizedBox(height: 20.h),
              Text('Profile Name', style: AppTextStyles.fieldLabel(isDark)),
              SizedBox(height: 6.h),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                inputFormatters: [UpperCaseWordsFormatter(), LengthLimitingTextInputFormatter(60)],
                style: AppTextStyles.kycFieldInput(isDark),
                decoration: _kycInputBoxDecoration(isDark),
              ),
              SizedBox(height: 16.h),
              Text('Date of Birth', style: AppTextStyles.fieldLabel(isDark)),
              SizedBox(height: 6.h),
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedDob == null ? 'Select date of birth' : _formatKycDob(_selectedDob!),
                        style: AppTextStyles.kycFieldInput(isDark).copyWith(
                          color: _selectedDob == null ? (isDark ? Colors.white38 : Colors.black38) : null,
                        ),
                      ),
                      Icon(Icons.calendar_today, size: 18.sp, color: isDark ? Colors.white54 : Colors.black45),
                    ],
                  ),
                ),
              ),
              if (_errorText != null) ...[
                SizedBox(height: 10.h),
                Text(_errorText!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
              ],
              SizedBox(height: 20.h),
              CustomButton(
                text: 'Save',
                isLoading: _saving,
                onPressed: _saving ? null : _save,
                gradient: AppTheme.greenGradient,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown by _KycScreenState._showMismatchDialog for either mismatch
/// prompt — AADHAAR's own or PAN's piggybacked one (see
/// NameMismatchPrompt's doc comment in kyc_controller.dart; [prompt]
/// carries which via [prompt.document]). Unlike _VerifiedDetailsDialog this
/// is dismissible (Cancel / back button) — a genuine identity mismatch may
/// not be resolvable by re-typing, so the customer isn't forced to stay
/// stuck here. [onSubmit] does the actual resolution — AADHAAR resubmits
/// the same verification_id (AadhaarNotifier.confirmNameMismatch), PAN
/// targets its own dedicated KYC row (KycRepository.confirmPanNameMismatch)
/// — and returns the same outcome contract either way; a continued
/// mismatch re-shows this same dialog with an inline error instead of
/// closing.
class _NameMismatchDialog extends StatefulWidget {
  final NameMismatchPrompt prompt;
  final Future<(NameMismatchOutcome, String?)> Function(String name, String dob) onSubmit;

  const _NameMismatchDialog({
    required this.prompt,
    required this.onSubmit,
  });

  @override
  State<_NameMismatchDialog> createState() => _NameMismatchDialogState();
}

class _NameMismatchDialogState extends State<_NameMismatchDialog> {
  late final TextEditingController _nameController;
  DateTime? _selectedDob;
  bool _saving = false;
  String? _errorText;

  // Backend only ever asks for DOB confirmation when the document itself
  // carried one (KYCService._validate_mismatch_resubmission's dob_ok
  // short-circuits otherwise) — mirror that here instead of demanding a
  // value the customer was never shown.
  bool get _needsDob => widget.prompt.verifiedDob != null && widget.prompt.verifiedDob!.isNotEmpty;
  String get _documentLabel => widget.prompt.document == 'PAN' ? 'PAN' : 'Aadhaar';

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prompt.verifiedName ?? '');
    _selectedDob = _parseKycDob(widget.prompt.verifiedDob);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 25, now.month, now.day),
      firstDate: DateTime(now.year - 100),
      lastDate: DateTime(now.year - 18, now.month, now.day),
    );
    if (picked != null) setState(() => _selectedDob = picked);
  }

  Future<void> _submit() async {
    final typedName = _nameController.text.trim();
    if (typedName.isEmpty) {
      setState(() => _errorText = 'Name cannot be empty.');
      return;
    }
    if (_needsDob && _selectedDob == null) {
      setState(() => _errorText = 'Please select your date of birth.');
      return;
    }
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final (outcome, msg) = await widget.onSubmit(
      typedName,
      _selectedDob != null ? _formatKycDob(_selectedDob!) : '',
    );
    if (!mounted) return;
    if (outcome == NameMismatchOutcome.resolved) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _errorText = msg ??
          "The name/DOB you entered still doesn't match your $_documentLabel record. "
              'Please re-enter them exactly as on your $_documentLabel.';
    });
  }

  Widget _buildVerifiedRow(String label, String? value, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label:', style: AppTextStyles.fieldLabel(isDark)),
        SizedBox(height: 2.h),
        Text(
          (value == null || value.isEmpty) ? '—' : value,
          style: AppTextStyles.kycFieldInput(isDark).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white24 : Colors.black12;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
      child: SingleChildScrollView(
        padding: EdgeInsets.all(24.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Name / DOB Mismatch',
              style: AppTextStyles.titleMedium(isDark).copyWith(color: const Color(0xFF643D41)),
            ),
            SizedBox(height: 8.h),
            Text(
              widget.prompt.message ??
                  "The name on your $_documentLabel record doesn't match your profile name. "
                      'Please re-enter your name and date of birth exactly as on your $_documentLabel record.',
              style: AppTextStyles.fieldHelper(isDark),
            ),
            SizedBox(height: 16.h),
            _buildVerifiedRow('Verified $_documentLabel Name', widget.prompt.verifiedName, isDark),
            if (_needsDob) ...[
              SizedBox(height: 12.h),
              _buildVerifiedRow('Verified $_documentLabel Date of Birth', widget.prompt.verifiedDob, isDark),
            ],
            SizedBox(height: 12.h),
            _buildVerifiedRow('Current Profile Name', widget.prompt.profileName, isDark),
            if (widget.prompt.profileDob != null && widget.prompt.profileDob!.isNotEmpty) ...[
              SizedBox(height: 12.h),
              _buildVerifiedRow('Current Profile Date of Birth', widget.prompt.profileDob, isDark),
            ],
            SizedBox(height: 20.h),
            Text('Your Name', style: AppTextStyles.fieldLabel(isDark)),
            SizedBox(height: 6.h),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                _UpperCaseNameFormatter(),
                LengthLimitingTextInputFormatter(60),
              ],
              style: AppTextStyles.kycFieldInput(isDark),
              decoration: _kycInputBoxDecoration(isDark),
            ),
            if (_needsDob) ...[
              SizedBox(height: 16.h),
              Text('Date of Birth', style: AppTextStyles.fieldLabel(isDark)),
              SizedBox(height: 6.h),
              InkWell(
                onTap: _pickDob,
                borderRadius: BorderRadius.circular(12.r),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: borderColor),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _selectedDob == null ? 'Select date of birth' : _formatKycDob(_selectedDob!),
                        style: AppTextStyles.kycFieldInput(isDark).copyWith(
                          color: _selectedDob == null ? (isDark ? Colors.white38 : Colors.black38) : null,
                        ),
                      ),
                      Icon(Icons.calendar_today, size: 18.sp, color: isDark ? Colors.white54 : Colors.black45),
                    ],
                  ),
                ),
              ),
            ],
            if (_errorText != null) ...[
              SizedBox(height: 10.h),
              Text(_errorText!, style: TextStyle(color: Colors.red, fontSize: 12.sp)),
            ],
            SizedBox(height: 20.h),
            CustomButton(
              text: 'Submit',
              isLoading: _saving,
              onPressed: _saving ? null : _submit,
              gradient: AppTheme.greenGradient,
            ),
            SizedBox(height: 8.h),
            Center(
              child: TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Converts input to UPPER CASE (used for PAN number).
class UpperCaseFormatter extends TextInputFormatter {
  // Allow only alphanumeric characters for PAN number
  static final _allowed = RegExp(r'[a-zA-Z0-9]');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned =
        newValue.text.split('').where((c) => _allowed.hasMatch(c)).join();
    final upper = cleaned.toUpperCase();
    final offset = upper.length.clamp(0, upper.length);
    return newValue.copyWith(
      text: upper,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

/// Converts name input to ALL UPPERCASE — matches PAN card format.
/// Only letters and spaces are allowed.
class _UpperCaseNameFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r'[a-zA-Z ]');

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned =
        newValue.text.split('').where((c) => _allowed.hasMatch(c)).join();
    final upper = cleaned.toUpperCase();
    final offset = upper.length.clamp(0, upper.length);
    return newValue.copyWith(
      text: upper,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
