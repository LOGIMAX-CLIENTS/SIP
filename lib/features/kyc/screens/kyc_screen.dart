import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/core/security/secure_logger.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/core/security/app_lifecycle_observer.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';
import 'package:startgold/features/kyc/screens/manual_kyc_upload_screen.dart';
import 'package:startgold/features/profile/profile_controller.dart' as pc;
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
  // Guards the stale-approved reconciliation below — fires at most once per
  // screen instance, same pattern as _aadhaarSeeded.
  bool _aadhaarReconciled = false;
  // Guards the on-load completion-recovery check below — fires at most
  // once per screen instance, same pattern as _aadhaarSeeded.
  bool _completionCheckedOnLoad = false;
  // Guards _checkAadhaarOutcomeRecoveryOnLoad — fires at most once per
  // screen instance. Covers the case where MainScreen's app-shell fallback
  // navigated back to THIS (freshly (re)pushed) KycScreen instance because
  // its own listener caught a pending mismatch/failure that happened while
  // no KycScreen was mounted to show it — see main_screen.dart's
  // _navigateToKycAndLetItHandle doc comment for the full chain.
  bool _aadhaarOutcomeCheckedOnLoad = false;
  // Set when the user taps "Edit" on an already-verified Aadhaar card, so
  // the next _onVerifyAadhaar() call tells the backend to bypass its
  // already-approved idempotency short-circuit (see KYCRepository.initiateAadhaar).
  bool _aadhaarEditing = false;
  // Set specifically by _onRetryPan (never by the plain "Edit" button) —
  // distinguishes "redoing DigiLocker only to fetch PAN, Aadhaar itself is
  // fine" from "the customer is actually correcting their Aadhaar details".
  // ref.read(aadhaarProvider.notifier).reset() (inside _editAadhaar) drops
  // the local phase back to idle either way, which would otherwise make the
  // Aadhaar card render as if it needed verifying from scratch — misleading
  // when it's already approved server-side and this is purely a PAN retry.
  bool _retryingPanOnly = false;
  // Dedupe guards for the mismatch dialog / failure dialog — now backed by
  // AadhaarNotifier.handledMismatchIds/handledFailureKeys, SHARED with
  // MainScreen's own fallback listener. A KycScreen-local (even if static)
  // Set only stopped duplicate handling within this screen's own code
  // paths; it couldn't stop MainScreen's independent ref.listen from ALSO
  // pushing a new KycScreen route over an already-open dialog for the same
  // event, which raced with the dialog's own Navigator.pop() (see
  // AadhaarNotifier's doc comment on handledMismatchIds for the full story
  // of how that left the dialog stuck on "Processing..." forever).
  Set<String> get _shownMismatchIds => AadhaarNotifier.handledMismatchIds;
  Set<String> get _shownFailureKeys => AadhaarNotifier.handledFailureKeys;
  // Re-entrancy guard AND loading indicator for the Aadhaar verification
  // attempt in flight — true for the whole duration of _onVerifyAadhaar()
  // (initiate -> consent/SDK sub-screen -> poll), not just the initiating/
  // polling AadhaarState phases. Without this, awaitingSdk/awaitingConsent
  // leave the button tappable while the previous call is still awaiting its
  // pushed route, so a second tap fires an overlapping attempt that
  // re-initiates and pushes a duplicate sub-screen.
  bool _verifyingAadhaar = false;
  // Full-page "updating your verification status" overlay — see
  // _checkAndHandleCompletion's doc comment for why this exists: the gap
  // between a verify action finishing and this screen settling into its
  // final state previously had no on-screen feedback at all.
  bool _completingKyc = false;

  final _aadhaarNumberController = TextEditingController();
  final _aadhaarNameController = TextEditingController();
  final _aadhaarFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // aadhaarProvider is kept alive (see AadhaarNotifier.pauseAutoDispose)
    // across the SDK-bounce navigation that can land the user somewhere
    // other than this screen mid-verify — so if MainScreen's app-shell
    // fallback just navigated the user back HERE because it caught a
    // pending outcome no KycScreen was mounted to show, that outcome is
    // still sitting in aadhaarProvider's current state, unconsumed. Check
    // once, post-frame (dialogs need a laid-out context).
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAadhaarOutcomeRecoveryOnLoad());
  }

  /// See initState's doc comment. Reads aadhaarProvider's CURRENT state
  /// directly rather than relying on ref.listen — a listener registered in
  /// build() only fires on FUTURE transitions, not the one that already
  /// happened before this (possibly freshly-pushed) screen existed.
  void _checkAadhaarOutcomeRecoveryOnLoad() {
    if (_aadhaarOutcomeCheckedOnLoad) return;
    _aadhaarOutcomeCheckedOnLoad = true;
    if (!mounted) return;
    final state = ref.read(aadhaarProvider);
    if (state.phase == AadhaarPhase.awaitingNameMismatchConfirm &&
        state.aadhaarMismatchPrompt != null) {
      _maybeShowAadhaarMismatchDialog(state.aadhaarMismatchPrompt!);
    }
    if (state.panMismatchPrompt != null) {
      _maybeShowPanMismatchDialog(state.panMismatchPrompt!);
    }
    if (state.phase == AadhaarPhase.expired ||
        state.phase == AadhaarPhase.rejected ||
        state.phase == AadhaarPhase.failed) {
      _maybeShowAadhaarFailureDialog(state);
    }
    // APPROVED counterpart — confirmed via [KYC DEBUG] logs that the
    // ORIGINAL screen can be disposed by the SDK bounce before its own
    // linear _runVerifyAadhaar() chain ever reaches its approved branch
    // (the "widget mounted=false" log fires right there), so nothing ever
    // claims AadhaarNotifier.handledApprovedKeys and MainScreen's fallback
    // navigates here — but until this branch existed, THIS freshly-pushed
    // screen never re-ran the completion sequence either: it just showed
    // "Verified" cards from its own normal doc-types fetch and stopped,
    // with no success animation, no auto Navigator.pop(context, true), and
    // therefore no refreshed "Verified" badge back on the Profile screen
    // (that badge only refreshes when THIS route pops with `true`).
    //
    // Guarded on verificationId != null specifically to NOT fire for a
    // customer who casually reopens an already-long-verified KYC screen
    // (AadhaarNotifier.seedApproved() also sets phase=approved, purely for
    // display, whenever the backend reports Aadhaar approved on ANY fresh
    // load — but it never sets verificationId, so that case is excluded
    // here). AadhaarNotifier.handledApprovedKeys.add() below is the second,
    // durable guard — even a genuine verificationId only ever runs this
    // once, matching _checkAndHandleCompletion's own claim for the case
    // where the original screen DOES survive to run it itself.
    if (state.phase == AadhaarPhase.approved && state.verificationId != null) {
      if (AadhaarNotifier.handledApprovedKeys.add(state.verificationId!)) {
        _checkAndHandleCompletion();
      }
    }
    // NOT_SHARED counterpart — same disposal race as approved above
    // (confirmed live: "widget mounted=false" logged right where the
    // linear chain would have handled this phase), but this one was
    // missing recovery entirely: no on-load claim here, and no MainScreen
    // fallback either (see main_screen.dart), so a freshly-pushed screen
    // just silently re-fetched document-types on its own normal load —
    // no loader, no success/failure toast, nothing telling the customer
    // anything happened. Same verificationId != null guard and
    // handledApprovedKeys claim as the approved case (aadhaarNotShared can
    // still mean "PAN got verified this round", so it deserves the same
    // one-time completion check).
    if (state.phase == AadhaarPhase.aadhaarNotShared && state.verificationId != null) {
      if (AadhaarNotifier.handledApprovedKeys.add(state.verificationId!)) {
        _checkAndHandleCompletion();
      }
    }
  }

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

  /// Inverse of `_seedAadhaarIfApproved` — aadhaarProvider is kept alive for
  /// the app's whole lifetime (MainScreen permanently watches it via
  /// ref.listen for the mismatch/failure/approved fallback routing), so a
  /// phase of APPROVED set by an earlier verify can still be sitting in the
  /// provider when this screen is freshly reopened for a customer whose
  /// current backend status is no longer APPROVED (re-verification was
  /// invalidated, a different account, etc). Without this, the Verified
  /// banner keeps showing purely from that stale local phase even though
  /// aadhaar_status from /kyc/document-types now reports PENDING. Fires at
  /// most once per screen instance so it never fights a live verify that's
  /// genuinely in flight in this same instance (see _aadhaarReconciled).
  void _reconcileAadhaarWithBackend(bool aadhaarApproved) {
    if (_aadhaarReconciled) return;
    _aadhaarReconciled = true;
    if (aadhaarApproved) return;
    if (ref.read(aadhaarProvider).phase != AadhaarPhase.approved) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(aadhaarProvider.notifier).reset();
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
    if (!bothComplete) return;
    if (result.kycConfirmed) {
      // Both documents are verified AND already confirmed in a past
      // session — there is nothing left to show or ask, but this screen
      // has no "Continue" button of its own; the only way forward is the
      // Navigator.pop(context, true) that _runCompletionSequence() does
      // at the end of the dialog sequence. Skipping straight past that
      // sequence (correct — there's nothing to (re)confirm) previously
      // skipped the pop too, so a caller awaiting KycVerificationFlow's
      // result (e.g. Withdraw's KYC_REQUIRED gate) never got its `true`
      // and the customer was stuck looking at two "Verified" cards with
      // no way to proceed.
      _completionCheckedOnLoad = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context, true);
      });
      return;
    }
    // Second, durable guard alongside result.kycConfirmed — kycConfirmed
    // can read false on a fetch shortly after a genuine completion (a
    // backend read-timing gap, confirmed live via [KYC DEBUG] logs: the
    // mirror rows were already correctly APPROVED in the DB at the exact
    // moment this returned false), which without this would re-show the
    // WHOLE success-dialogs sequence on every subsequent reopen of this
    // screen for the rest of the session, not just once — this function's
    // own _completionCheckedOnLoad only guards ONE instance, and a fresh
    // instance is exactly what Profile's "KYC Verification" tap-in creates
    // every time. Falls back to a purely local key when there's no live
    // verificationId (e.g. a customer recovering from an earlier app
    // session, where aadhaarProvider has reset to its pristine state) so
    // that case's original recovery behavior is unaffected.
    final key = ref.read(aadhaarProvider).verificationId ?? 'recovery-${result.aadhaarMaskedNumber}';
    if (!AadhaarNotifier.handledApprovedKeys.add(key)) return;
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
  void _editAadhaar({bool panOnly = false}) {
    setState(() {
      _aadhaarEditing = true;
      _retryingPanOnly = panOnly;
    });
    ref.read(aadhaarProvider.notifier).reset();
  }

  /// PAN has no consent of its own — it's fetched from the SAME DigiLocker
  /// session as Aadhaar (see `_buildPanVerifyNotice`'s doc comment and
  /// `MODULE_BRAIN.md` §2). If the user unchecks "PAN Verification Record" on
  /// DigiLocker's document-selection screen, Aadhaar comes back APPROVED but
  /// PAN never does — the only way to retry PAN is a fresh DigiLocker consent.
  /// This re-runs that consent (reusing `_editAadhaar`'s reverify plumbing)
  /// instead of leaving the user staring at a PAN card whose old copy still
  /// said "complete Aadhaar verification below" even though Aadhaar was
  /// already done.
  Future<void> _onRetryPan() async {
    _editAadhaar(panOnly: true);
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
    if (_verifyingAadhaar) return;
    if (_aadhaarFormKey.currentState?.validate() == false) return;

    setState(() => _verifyingAadhaar = true);
    try {
      await _runVerifyAadhaar();
    } finally {
      // Unconditional — not gated behind `mounted`. If the SDK-bounce
      // navigation left this screen unmounted right when _runVerifyAadhaar
      // finished, the OLD (mounted) reset would never run, and this flag
      // would stay stuck `true` on this State instance forever. That
      // wouldn't matter for a genuinely disposed instance — except
      // Navigator can keep a popped-then-reused KycScreen route's State
      // alive in some cases, and a stuck guard here means EVERY future tap
      // on that instance silently no-ops (`if (_verifyingAadhaar) return;`
      // above), which is exactly the "first tap does nothing" symptom this
      // fixes. setState still needs `mounted` (calling it on a disposed
      // State throws) — the field write does not.
      _verifyingAadhaar = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _runVerifyAadhaar() async {
    final notifier = ref.read(aadhaarProvider.notifier);
    // DigiLocker (webview or native SDK) can run long enough for the screen
    // to auto-lock mid-flow — without this, AppLifecycleObserver's resume
    // handler pushes the MPIN re-lock screen on top the instant the app
    // regains focus, burying whatever this flow was about to show (most
    // visibly the CONFIRM_NAME_UPDATE mismatch dialog below). Same pattern
    // as the payment handlers (see hdfc_payment_handler.dart etc.).
    AppLifecycleObserver.suppressAppLock = true;
    // Separately from the app-lock suppression above: SurePass's native SDK
    // Activity still triggers a genuine onPause/onResume on the host
    // Activity even with the lock suppressed, and that's enough for
    // aadhaarProvider (.autoDispose) to lose its listener and be torn down
    // mid-flow — confirmed via [KYC DEBUG] logging showing mounted=false on
    // a poll response that otherwise arrived with the correct
    // CONFIRM_NAME_UPDATE payload. Pausing autoDispose for this same
    // initiate -> sub-screen -> poll span keeps the notifier alive so the
    // result actually reaches the UI.
    notifier.pauseAutoDispose();
    try {
      SecureLogger.d(
        '[KYC DEBUG] initiate() call: _aadhaarEditing=$_aadhaarEditing '
        '_retryingPanOnly=$_retryingPanOnly '
        'aadhaarNumberEmpty=${_aadhaarNumberController.text.isEmpty} '
        'nameEmpty=${_aadhaarNameController.text.isEmpty}',
      );
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
          // Re-read rather than reuse the `notifier` captured above: aadhaarProvider
          // is .autoDispose, and the pushed sub-screen can outlive its last
          // listener long enough for Riverpod to tear it down and recreate it —
          // calling pollUntilTerminal on the stale instance would silently no-op
          // via its own `mounted` guard, dropping a real CONFIRM_NAME_UPDATE/
          // APPROVED/etc. result on the floor with no error shown.
          await ref.read(aadhaarProvider.notifier).pollUntilTerminal(widget.requestFrom);
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
          // Re-read — see the webview branch's comment above. Especially
          // relevant here: the native SDK renders via a platform view
          // (PlatformViewsController), which is more likely than a plain
          // Flutter WebView route to suspend the underlying widget tree long
          // enough for the autoDispose provider to be torn down.
          await ref.read(aadhaarProvider.notifier).pollUntilTerminal(widget.requestFrom);
        }
      }

      SecureLogger.d('[KYC DEBUG] after poll branches, widget mounted=$mounted');
      if (!mounted) return;
      var finalState = ref.read(aadhaarProvider);
      SecureLogger.d(
        '[KYC DEBUG] post-poll finalState.phase=${finalState.phase} '
        'aadhaarMismatchPrompt=${finalState.aadhaarMismatchPrompt != null} '
        'panMismatchPrompt=${finalState.panMismatchPrompt != null}',
      );

      // PAN's mismatch prompt (if any) is independent of Aadhaar's own
      // phase below — it can be set alongside APPROVED, already-approved, or
      // even REJECTED (see AadhaarState.panMismatchPrompt's doc comment) — so
      // it's handled first, unconditionally, before branching on phase.
      if (finalState.panMismatchPrompt != null) {
        await _maybeShowPanMismatchDialog(finalState.panMismatchPrompt!);
        if (!mounted) return;
        finalState = ref.read(aadhaarProvider);
      }

      if (finalState.phase == AadhaarPhase.expired ||
          finalState.phase == AadhaarPhase.rejected ||
          finalState.phase == AadhaarPhase.failed) {
        _maybeShowAadhaarFailureDialog(finalState);
        return;
      }

      // Aadhaar wasn't shared this round, but PAN may have been (backend's
      // own framing: "not a failure ... report this as a genuine success").
      // Must refresh document-types here — this is the only phase-branch
      // that can carry a fresh PAN approval without Aadhaar's own phase
      // also being `approved`, so it needed its own call to
      // _checkAndHandleCompletion() rather than falling through to the
      // generic message-only toast below (which never re-fetches anything).
      if (finalState.phase == AadhaarPhase.aadhaarNotShared) {
        if (mounted && finalState.message != null) {
          AppToast.show(context, finalState.message!, type: ToastType.info);
        }
        if (!mounted) return;
        await _checkAndHandleCompletion();
        return;
      }

      if (finalState.phase == AadhaarPhase.approved) {
        // Claim the SAME shared key MainScreen's own approved-fallback
        // checks (see AadhaarNotifier.handledApprovedKeys / MainScreen's
        // _maybeHandleAadhaarApproved) — this branch only runs when THIS
        // widget is still mounted and is about to handle the approval
        // itself; without claiming here, nothing ever marks the outcome as
        // handled (KycScreen never used to claim this key at all), so
        // MainScreen's listener — reacting to the very same state
        // transition — always finds it unclaimed after its grace period
        // and pushes a REDUNDANT fresh KycScreen route on top of this one,
        // which is why leaving the screen needed two back-presses and the
        // customer landed on a second, differently-timed fetch of the KYC
        // status instead of this instance's own freshly-refreshed one.
        final claimed = AadhaarNotifier.handledApprovedKeys
            .add(finalState.verificationId ?? 'approved-${finalState.maskedNumber}');
        SecureLogger.d('[KYC DEBUG] linear chain approved branch: claimed=$claimed, calling _checkAndHandleCompletion');
        await _checkAndHandleCompletion();
        return;
      }

      if (finalState.phase == AadhaarPhase.awaitingNameMismatchConfirm) {
        await _maybeShowAadhaarMismatchDialog(finalState.aadhaarMismatchPrompt!);
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
    } finally {
      AppLifecycleObserver.suppressAppLock = false;
      notifier.resumeAutoDispose();
    }
  }

  /// Fires after EVERY successful PAN submit and EVERY successful Aadhaar
  /// approval (first-time or via Edit/reverify — see _submitDoc and
  /// _onVerifyAadhaar). Re-fetches document-types so the completion check —
  /// and the names shown in the mandatory popup below — always reflect the
  /// verification that JUST happened, never stale pre-edit data. Only forms
  /// call this, so it can never fire from merely viewing an already-verified
  /// screen (e.g. opened from Profile).
  /// Thin serializing wrapper — see AadhaarNotifier.completionInFlight's doc
  /// comment for why this can't just be a plain reentrancy-guard bool: the
  /// duplicate calls come from DIFFERENT KycScreen instances, so the lock
  /// has to be shared (static), not per-instance.
  Future<void> _checkAndHandleCompletion() async {
    // Visible "updating..." overlay (see build()'s _completingKyc check) —
    // without this, the gap between a verify action finishing and this
    // screen settling into its final state (re-fetch document-types,
    // decide whether to run the completion sequence) had no on-screen
    // feedback at all: the customer had no way to tell whether anything
    // was happening. mounted-guarded since this can be reached after the
    // widget that started the call is already gone (another instance
    // handling the same in-flight completion).
    if (mounted) setState(() => _completingKyc = true);
    try {
      if (AadhaarNotifier.completionInFlight != null) {
        SecureLogger.d('[KYC DEBUG] _checkAndHandleCompletion: another check already in flight, awaiting it instead');
        await AadhaarNotifier.completionInFlight;
        return;
      }
      final future = _doCheckAndHandleCompletion();
      AadhaarNotifier.completionInFlight = future;
      try {
        await future;
      } finally {
        AadhaarNotifier.completionInFlight = null;
      }
    } finally {
      if (mounted) setState(() => _completingKyc = false);
    }
  }

  Future<void> _doCheckAndHandleCompletion() async {
    SecureLogger.d('[KYC DEBUG] _checkAndHandleCompletion: entered, mounted=$mounted');
    if (!mounted) return;
    // Captured BEFORE refreshing — see the kycConfirmed guard below for why
    // the post-refresh value can no longer be used here.
    final wasAlreadyConfirmed =
        ref.read(kycDocumentsProvider(widget.requestFrom)).valueOrNull?.kycConfirmed ?? false;
    final KycDocumentsResult result;
    try {
      result = await ref.refresh(kycDocumentsProvider(widget.requestFrom).future);
    } catch (e) {
      SecureLogger.d('[KYC DEBUG] _checkAndHandleCompletion: refresh threw $e');
      // Explicit failure feedback — previously this failed completely
      // silently (just a debug log), leaving the customer no way to tell
      // whether their verification went through or not.
      if (mounted) {
        AppToast.show(
          context,
          "Couldn't refresh your verification status. Please check your connection and try again.",
          type: ToastType.error,
        );
      }
      return; // Couldn't refresh — nothing reliable to show, don't block on it.
    }
    if (!mounted) return;
    SecureLogger.d('[KYC DEBUG] _checkAndHandleCompletion: wasAlreadyConfirmed=$wasAlreadyConfirmed aadhaarApproved=${result.aadhaarApproved} kycConfirmedNow=${result.kycConfirmed} allDocsUploaded=${result.documents.every((d) => d.alreadyUploaded)}');

    // _initControllers only ever populates _completedDocIds from the VERY
    // FIRST docs fetch (it's a one-shot init, guarded by _initialized) — so
    // a document that gets approved DURING this screen's lifetime (exactly
    // what just happened) never gets added to it by that path. Without this
    // resync, its card keeps rendering from the stale pre-completion data
    // forever, e.g. still showing "Retry PAN Verification" right after PAN
    // was actually just approved. Also clears the Edit/Retry-PAN flags —
    // they exist only to reopen a form for a redo in progress; once that
    // redo has genuinely completed, leaving them set forces
    // _buildDocumentCard's !_aadhaarEditing guards to keep suppressing the
    // now-correct Verified state for the SAME reason.
    for (final doc in result.documents) {
      if (doc.alreadyUploaded) _completedDocIds.add(doc.id);
    }
    setState(() {
      _aadhaarEditing = false;
      _retryingPanOnly = false;
    });

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
    // Mirrors _checkCompletionRecoveryOnLoad's guard — without this, editing
    // Aadhaar (e.g. resolving a name mismatch) after KYC was already fully
    // confirmed re-triggers the ENTIRE mandatory sequence again, including
    // PAN's "verified details" dialog, even though PAN wasn't touched.
    //
    // Uses wasAlreadyConfirmed (the state BEFORE this refresh), not
    // result.kycConfirmed (the state AFTER it) — the backend now flips
    // kyc_confirmed the moment a verify call itself succeeds (mirror
    // synced at verify time, not deferred to the Profile Name Save step
    // anymore), so by the time this refresh returns, kyc_confirmed is
    // ALREADY true even for the very first, genuinely-just-completed PAN
    // or Aadhaar verification. Using the post-refresh value here made this
    // guard swallow that first completion too: _runCompletionSequence()
    // (and its trailing Navigator.pop(context, true)) never ran, so the
    // screen never closed itself and the Profile screen — which only
    // refreshes its own "Verified" badge when this route pops with
    // `true` — kept showing stale, unverified status even though the
    // backend had already approved everything.
    if (!bothComplete || wasAlreadyConfirmed) {
      SecureLogger.d('[KYC DEBUG] _checkAndHandleCompletion: skipping sequence, bothComplete=$bothComplete wasAlreadyConfirmed=$wasAlreadyConfirmed');
      // Partial-progress feedback — bothComplete's full success animation
      // covers the "everything just got verified" case below, but a
      // customer who e.g. just verified Aadhaar with PAN still pending
      // previously got NO acknowledgement at all beyond the card quietly
      // changing color. Skipped when wasAlreadyConfirmed — that means
      // nothing new happened this round (a stale/duplicate re-check), so
      // there's nothing genuine to announce.
      if (!wasAlreadyConfirmed && mounted) {
        final pendingDocs = result.documents.where((d) => !d.alreadyUploaded);
        final message = !result.aadhaarApproved
            ? 'PAN verified. Aadhaar verification is still pending.'
            : pendingDocs.isNotEmpty
                ? 'Aadhaar verified. ${pendingDocs.first.name} verification is still pending.'
                : 'Verification status updated.';
        AppToast.show(context, message, type: ToastType.success);
      }
      return;
    }

    final panDoc = result.documents.isEmpty
        ? null
        : result.documents.firstWhere(
            (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
            orElse: () => result.documents.first,
          );

    SecureLogger.d('[KYC DEBUG] _checkAndHandleCompletion: running completion sequence');
    await _runCompletionSequence(
      panName: panDoc?.verifiedName,
      panDob: panDoc?.verifiedDob,
      aadhaarName: result.aadhaarName,
      aadhaarDob: result.aadhaarDob,
    );
  }

  /// True when the customer's profile already carries this exact verified
  /// name — e.g. AADHAAR's name/DOB was just synced to the profile moments
  /// earlier via the CONFIRM_NAME_UPDATE mismatch flow (KYCService's
  /// `_finalize_name_mismatch_confirmation`, `profile_updated: true` in
  /// that response). Asking the customer to "Save" a name that's already
  /// saved is pure redundancy, not a genuine confirmation of anything new.
  Future<bool> _profileAlreadyMatches(String? verifiedName) async {
    if (verifiedName == null || verifiedName.trim().isEmpty) return false;
    // ProfileNotifier starts with an EMPTY name and fetches the real one
    // asynchronously in its constructor (see profile_controller.dart) — a
    // synchronous ref.read() here can race that fetch and see '' instead
    // of the customer's actual (already-matching) name whenever Profile
    // hasn't been visited yet this session, which is exactly the
    // MainScreen-fallback path: it never routes through Profile's own
    // screen first. Awaiting a fresh fetch here guarantees a real
    // comparison regardless of what's cached.
    await ref.read(pc.profileProvider.notifier).fetchProfileDetails();
    if (!mounted) return false;
    final currentName = ref.read(pc.profileProvider).user.name;
    return currentName.trim().toUpperCase() == verifiedName.trim().toUpperCase();
  }

  /// Success animation, then the MANDATORY verified-details confirmation —
  /// one dialog per document (Aadhaar first, then PAN — see
  /// _showVerifiedDetailsDialog), each saving straight from its own dialog
  /// rather than a single "pick one source" choice, UNLESS the profile
  /// already carries that exact name (see _profileAlreadyMatches — nothing
  /// to confirm/save in that case). Every caller (SIP/Withdrawal/
  /// Investment/Profile) awaits this screen and decides what to do next
  /// itself (typically retrying the original blocked action via
  /// KycVerificationFlow) — no requestFrom-specific navigation lives here.
  Future<void> _runCompletionSequence({
    String? panName,
    String? panDob,
    String? aadhaarName,
    String? aadhaarDob,
  }) async {
    SecureLogger.d('[KYC DEBUG] _runCompletionSequence: entered');
    await _showSuccessAnimation();
    if (!mounted) {
      SecureLogger.d('[KYC DEBUG] _runCompletionSequence: unmounted after success animation');
      return;
    }

    if (!await _profileAlreadyMatches(aadhaarName)) {
      if (!mounted) return;
      final savedAadhaar = await _showVerifiedDetailsDialog(
        source: 'AADHAAR', verifiedName: aadhaarName, verifiedDob: aadhaarDob,
      );
      if (!mounted) {
        SecureLogger.d('[KYC DEBUG] _runCompletionSequence: unmounted after AADHAAR dialog');
        return;
      }
      if (!savedAadhaar) {
        // Deferred, not saved — do NOT fall through to the completion pop
        // below. Falling through here would tell the caller (e.g.
        // Withdraw's KYC_REQUIRED gate) that KYC is confirmed when it
        // isn't. Returning normally still lets the outer finally reset
        // _completingKyc, so the screen itself isn't left frozen either.
        SecureLogger.d('[KYC DEBUG] _runCompletionSequence: AADHAAR confirmation deferred');
        return;
      }
    }

    if (!await _profileAlreadyMatches(panName)) {
      if (!mounted) return;
      final savedPan = await _showVerifiedDetailsDialog(
        source: 'PAN', verifiedName: panName, verifiedDob: panDob,
      );
      if (!mounted) {
        SecureLogger.d('[KYC DEBUG] _runCompletionSequence: unmounted after PAN dialog');
        return;
      }
      if (!savedPan) {
        SecureLogger.d('[KYC DEBUG] _runCompletionSequence: PAN confirmation deferred');
        return;
      }
    }

    // Refreshed directly here, not left to the caller's own pop-result
    // handling — Profile's own "KYC Verification" tap-in DOES await this
    // push and refresh on `result == true`, but this screen can just as
    // easily be reached via MainScreen's app-shell fallback navigation
    // (SDK-bounce recovery — see MainScreen's _navigateToKycAndLetItHandle),
    // which pushes this route directly and never awaits a result at all.
    // Without this, that path's customer would see a still-unverified
    // "KYC Verification" badge on Profile despite everything having just
    // succeeded, until they happened to revisit another tab that also
    // invalidates profileProvider.
    ref.read(pc.profileProvider.notifier).fetchProfileDetails();

    SecureLogger.d('[KYC DEBUG] _runCompletionSequence: popping(true)');
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
  /// the user must either Save or explicitly defer. Returns true only once
  /// the save actually succeeds (see _VerifiedDetailsDialogState._save);
  /// false if the user taps "Do this later" instead. Previously this had
  /// no deferral option at all — if the backend kept rejecting Save (e.g. a
  /// false-positive PROFILE_NAME_MISMATCH), the dialog had no way to close
  /// short of force-killing the app, since nothing else in the tree could
  /// pop it. The caller (_runCompletionSequence) must stop, not proceed,
  /// on a false result — this is a UI escape hatch, not a compliance
  /// bypass; the confirmation is still required before KYC counts as done.
  Future<bool> _showVerifiedDetailsDialog({
    required String source,
    String? verifiedName,
    String? verifiedDob,
  }) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _VerifiedDetailsDialog(
        source: source,
        verifiedName: verifiedName,
        verifiedDob: verifiedDob,
        repository: ref.read(kycRepositoryProvider),
      ),
    );
    return saved ?? false;
  }

  /// Aadhaar-mismatch entry point shared by the reactive ref.listen in
  /// build() and the linear await-chain in _runVerifyAadhaar() — see the
  /// listener's doc comment for why both exist. [_shownMismatchIds] ensures
  /// only whichever one runs first actually opens the dialog; the other
  /// becomes a no-op.
  Future<void> _maybeShowAadhaarMismatchDialog(NameMismatchPrompt prompt) async {
    if (!_shownMismatchIds.add(prompt.verificationId)) return;
    final resolved = await _showMismatchDialog(prompt);
    SecureLogger.d('[KYC DEBUG] _maybeShowAadhaarMismatchDialog: _showMismatchDialog returned resolved=$resolved, mounted=$mounted');
    if (!mounted) return;
    if (resolved) await _checkAndHandleCompletion();
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
    SecureLogger.d('[KYC DEBUG] _showMismatchDialog entered, mounted=$mounted, document=${prompt.document}');
    final dialogContext = context;
    final resolved = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => NameMismatchDialog(
        prompt: prompt,
        onSubmit: (name, dob) => prompt.document == 'PAN'
            ? _confirmPanMismatch(prompt.verificationId, name, dob)
            : ref.read(aadhaarProvider.notifier).confirmNameMismatch(
                  widget.requestFrom, name: name, dob: dob,
                ),
      ),
    );
    SecureLogger.d('[KYC DEBUG] _showMismatchDialog: showDialog future resolved=$resolved');
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

  /// PAN counterpart to _maybeShowAadhaarMismatchDialog — same dedupe
  /// reasoning (shared with the reactive ref.listen in build() and
  /// MainScreen's own app-shell-level fallback), keyed by
  /// prompt.verificationId which for PAN actually holds the dedicated PAN
  /// KYC row id (see _confirmPanMismatch's doc comment).
  Future<void> _maybeShowPanMismatchDialog(NameMismatchPrompt prompt) async {
    if (!_shownMismatchIds.add(prompt.verificationId)) return;
    final resolved = await _showMismatchDialog(prompt);
    if (!mounted) return;
    if (resolved) await _checkAndHandleCompletion();
  }

  /// Reactive counterpart to the terminal expired/rejected/failed branch in
  /// _runVerifyAadhaar() — same widget-disposal risk as the mismatch dialogs
  /// above (confirmed: the backend sends a proper, safe-to-show message —
  /// e.g. "Your profile name and/or date of birth doesn't match your
  /// Aadhaar record..." — but the linear chain's `if (!mounted) return;`
  /// silently swallowed it before this ever ran). A dialog, not a toast — a
  /// toast auto-dismisses in ~3s, easy to miss entirely if the user's
  /// attention is elsewhere right after the SDK-bounce navigation this is
  /// usually paired with; this stays up until the user explicitly closes it.
  /// [_shownFailureKeys] is keyed by verificationId+phase (falling back to
  /// message+phase when verificationId is unset) since a failure has no
  /// per-attempt id the way a mismatch prompt's own verificationId provides.
  Future<void> _maybeShowAadhaarFailureDialog(AadhaarState state) async {
    final key = '${state.verificationId ?? state.message}-${state.phase}';
    if (!_shownFailureKeys.add(key)) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Aadhaar Verification'),
        content: Text(state.message ?? 'Aadhaar verification failed. Please try again.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Silent, in-place refresh — no navigation. A rejection/expiry is a
    // real state change on the backend (kyc_status flips, which is what
    // aadhaarRejected below reads), but this path previously never
    // re-fetched document-types at all: the customer stayed on this exact
    // screen looking at data from before the failed attempt, so
    // "Upload manually instead" (gated on aadhaarRejected) wouldn't appear
    // until something unrelated happened to refresh the provider.
    ref.invalidate(kycDocumentsProvider(widget.requestFrom));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(kycDocumentsProvider(widget.requestFrom));
    final aadhaarState = ref.watch(aadhaarProvider);

    // Blocks the customer from backing out of this screen mid-verification —
    // previously nothing stopped a back-press while _runVerifyAadhaar()'s
    // Aadhaar+PAN DigiLocker poll was still in flight, so they'd land back
    // on MainScreen (or wherever) while the request was still pending, then
    // return to a freshly-built KycScreen showing stale/contradictory state
    // (the entry form again, or a leftover message) instead of the actual
    // in-progress verification. Same condition as _buildAadhaarCard's own
    // `isBusy`, plus any generic doc submit in flight.
    final verificationInFlight = _verifyingAadhaar ||
        _completingKyc ||
        _submittingDocIds.isNotEmpty ||
        aadhaarState.phase == AadhaarPhase.initiating ||
        aadhaarState.phase == AadhaarPhase.polling;

    // Reactive fallback for the CONFIRM_NAME_UPDATE mismatch dialog —
    // primary path when the linear await-chain in _runVerifyAadhaar() can't
    // deliver it itself: SurePass's native DigiLocker SDK Activity can leave
    // THIS specific KycScreen State instance unmounted by the time
    // pollUntilTerminal()'s result comes back (confirmed via [KYC DEBUG]
    // logging — the aadhaarProvider notifier itself stays alive thanks to
    // pauseAutoDispose/resumeAutoDispose, but widget.mounted was still false
    // afterward), silently dropping the dialog via that chain's `if
    // (!mounted) return;` guards. ref.listen ties its callback to whichever
    // KycScreen instance is CURRENTLY built and watching aadhaarProvider, so
    // it fires regardless of which instance's async chain the state change
    // actually happened under.
    ref.listen<AadhaarState>(aadhaarProvider, (previous, next) {
      if (next.phase == AadhaarPhase.awaitingNameMismatchConfirm &&
          next.aadhaarMismatchPrompt != null) {
        _maybeShowAadhaarMismatchDialog(next.aadhaarMismatchPrompt!);
      }
      // Same rationale, PAN side — panMismatchPrompt can be set alongside
      // APPROVED/already-approved/REJECTED (see AadhaarState.panMismatchPrompt's
      // doc comment), independent of [phase], so it's checked unconditionally.
      if (next.panMismatchPrompt != null) {
        _maybeShowPanMismatchDialog(next.panMismatchPrompt!);
      }
      if (next.phase == AadhaarPhase.expired ||
          next.phase == AadhaarPhase.rejected ||
          next.phase == AadhaarPhase.failed) {
        _maybeShowAadhaarFailureDialog(next);
      }
      // Same reactive-fallback rationale as above, for the case
      // _runVerifyAadhaar's own linear chain documents (SurePass SDK
      // Activity onPause/onResume tearing down this instance before the
      // poll result lands) — without this, a PAN approval piggybacked on
      // an aadhaarNotShared outcome is silently dropped exactly like the
      // mismatch dialog used to be. _checkAndHandleCompletion() is
      // idempotent (AadhaarNotifier.completionInFlight dedupes concurrent
      // calls), so this is safe even if the linear chain also reaches it.
      if (next.phase == AadhaarPhase.aadhaarNotShared) {
        if (next.message != null) {
          AppToast.show(context, next.message!, type: ToastType.info);
        }
        _checkAndHandleCompletion();
      }
    });

    return PopScope(
      canPop: !verificationInFlight,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        AppToast.show(
          context,
          'Please wait — verification is in progress.',
          type: ToastType.info,
        );
      },
      // Opaque background on this screen itself (same fix as
      // withdrawal_screen.dart/bank_account_picker_screen.dart) — a
      // transparent Scaffold here let Home (kept alive underneath by
      // MainScreen's IndexedStack) bleed through during the pop transition
      // back to this screen.
      child: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            Column(
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
                _reconcileAadhaarWithBackend(result.aadhaarApproved);
                _checkCompletionRecoveryOnLoad(result);
                // "Upload manually instead" is offered for a NOT-YET-verified
                // document once ANY of:
                //   (a) DigiLocker has genuinely been tried at least once
                //       (result.digilockerAttempted — the original "not on
                //       the very first visit" gate).
                //   (b) the OTHER document is already verified (by any means
                //       — DigiLocker or a prior manual-upload approval) — an
                //       already-verified PAN/Aadhaar is itself proof the
                //       customer has been through this screen's verification
                //       flow before, so the remaining side shouldn't be
                //       gated behind a SEPARATE DigiLocker attempt of its own.
                //   (c) THIS document's own latest attempt was REJECTED —
                //       most relevant for a manual upload that was refused
                //       without DigiLocker ever having been tried, which (a)
                //       alone would never unlock; the customer needs both
                //       retry paths offered right when a rejection happens.
                // A verified document's OWN card never reaches this — isDone
                // always shows the Verified banner instead, on both cards,
                // regardless of these flags.
                final panDoc = result.documents.where((d) =>
                    d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'));
                final panApproved = panDoc.any((d) => d.alreadyUploaded);
                final panRejected = panDoc.any((d) => d.status.toUpperCase() == 'REJECTED');
                final panAllowManualUpload =
                    result.digilockerAttempted || result.aadhaarApproved || panRejected;
                final aadhaarAllowManualUpload =
                    result.digilockerAttempted || panApproved || result.aadhaarRejected;
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
                      if (verificationInFlight) ...[
                        SizedBox(height: 16.h),
                        _buildVerificationInProgressBanner(isDark),
                      ],
                      SizedBox(height: 32.h),
                      ...result.documents.map((doc) => _buildDocumentCard(
                            doc, isDark, aadhaarState,
                            backendAadhaarApproved: result.aadhaarApproved,
                            allowManualUpload: panAllowManualUpload,
                          )),
                      _buildAadhaarCard(
                        isDark, aadhaarState,
                        backendApproved: result.aadhaarApproved,
                        backendMaskedNumber: result.aadhaarMaskedNumber,
                        backendVerifiedName: result.aadhaarName,
                        backendUnderReview: result.aadhaarUnderReview,
                        allowManualUpload: aadhaarAllowManualUpload,
                      ),
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
            if (_completingKyc) _buildCompletingOverlay(isDark),
          ],
        ),
      ),
      ),
    );
  }

  /// Full-page "updating your verification status" overlay shown while
  /// _checkAndHandleCompletion() is refreshing/deciding what to show next —
  /// see _completingKyc's doc comment for why this exists.
  Widget _buildCompletingOverlay(bool isDark) {
    return Positioned.fill(
      child: Container(
        color: (isDark ? Colors.black : Colors.white).withOpacity(0.75),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: 16.h),
            Text(
              'Updating your verification status…',
              style: AppTextStyles.fieldHelper(isDark),
            ),
          ],
        ),
      ),
    );
  }

  /// PAN is verified automatically from the same DigiLocker consent used
  /// for Aadhaar (see backend `KYCService._try_persist_digilocker_pan`,
  /// which fetches the PAN from DigiLocker then cross-verifies it via
  /// SurePass's /pan/pan-comprehensive) — there is deliberately no manual
  /// PAN entry form anymore. Any OTHER future document type still gets the
  /// generic field-form path below.
  Widget _buildDocumentCard(
    KycDocumentType doc,
    bool isDark,
    AadhaarState aadhaarState, {
    required bool backendAadhaarApproved,
    required bool allowManualUpload,
  }) {
    final isPan = doc.name.toUpperCase().contains('PAN') ||
        doc.code.toUpperCase().contains('PAN');
    final isDone = _completedDocIds.contains(doc.id);
    // PAN rides on the same DigiLocker session as Aadhaar (see
    // _buildPanVerifyNotice). If Aadhaar already came back APPROVED but
    // PAN's card is still pending, the user skipped/unchecked PAN in
    // DigiLocker's document picker — show that explicitly instead of the
    // generic "complete Aadhaar below" notice, which would be actively wrong
    // once Aadhaar is done. Checks the backend's own aadhaar_status too, not
    // just the local aadhaarProvider phase — _seedAadhaarIfApproved seeds
    // that provider a frame late (see its doc comment), so on first load
    // this card would otherwise show the generic notice for one frame even
    // though the backend already confirms Aadhaar is done. Suppressed while
    // _aadhaarEditing is true — that's the user actively mid-Edit/Retry-PAN
    // (the Aadhaar card below is showing an input form for it, see
    // _buildAadhaarCard's matching guard) — showing this "Retry PAN
    // Verification" card at the same time would be redundant with the form
    // already open for exactly that.
    final panSkippedInConsent = isPan &&
        !isDone &&
        !_aadhaarEditing &&
        (aadhaarState.phase == AadhaarPhase.approved || backendAadhaarApproved);
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
              // Live-session only (see AadhaarState.aadhaarPanLinked) — shows
              // on the PAN card right after a verification completes this
              // session; reads as unset again on a fresh screen load, same
              // as every other field the backend doesn't persist for replay.
              linkedToAadhaar: isPan ? aadhaarState.aadhaarPanLinked : null,
            )
          else if (doc.isUnderReview)
            _buildUnderReviewNotice(isDark, label: doc.name)
          else if (panSkippedInConsent)
            _buildPanSkippedNotice(isDark, isBusy: aadhaarRetryBusy, showManualUpload: allowManualUpload)
          else if (isPan)
            _buildPanVerifyNotice(isDark, isBusy: aadhaarRetryBusy, showManualUpload: allowManualUpload)
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

  /// Screen-level "something is happening, stay here" indicator for the
  /// whole span _runVerifyAadhaar()/_submitDoc() are
  /// awaiting a response — the per-button spinner (CustomButton.isLoading)
  /// only reads as "this one button is busy", not "don't leave this
  /// screen". Paired with the PopScope guard in build() that blocks the
  /// back-press this banner is telling the customer not to use.
  Widget _buildVerificationInProgressBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18.w,
            height: 18.w,
            child: const CircularProgressIndicator(strokeWidth: 2.2),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              'Verifying your details — please stay on this screen until it finishes.',
              style: AppTextStyles.fieldHelper(isDark),
            ),
          ),
        ],
      ),
    );
  }

  /// Pushes manual_kyc_upload_screen.dart for [docType] ("1"=PAN,
  /// "2"=AADHAAR) — the "Upload manually instead" alternative to DigiLocker.
  /// A plain pushed route, not a named one via app_router.dart — this
  /// screen only ever needs docType/requestFrom, both already in scope here.
  /// On a successful submit (result == true) invalidates kycDocumentsProvider
  /// so this screen's cards immediately reflect the new UNDER_REVIEW status.
  /// Also refreshes profileProvider — previously only _runCompletionSequence
  /// did that, which never runs for a manual upload (it goes to UNDER_REVIEW,
  /// not an immediate approval), so any profile-facing screen stayed on
  /// stale customer data until something else happened to refresh it.
  Future<void> _openManualUpload(String docType) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ManualKycUploadScreen(
          docType: docType, requestFrom: widget.requestFrom,
        ),
      ),
    );
    if (result == true && mounted) {
      ref.invalidate(kycDocumentsProvider(widget.requestFrom));
      ref.read(pc.profileProvider.notifier).fetchProfileDetails();
    }
  }

  /// Same size/shape/prominence as the "Verify via DigiLocker" CustomButton
  /// it sits below — a light-green fill (not the green gradient) keeps it
  /// visually secondary to that primary action while still reading as a
  /// real, full-width button rather than a small text link.
  Widget _buildManualUploadButton(bool isDark, {required String docType}) {
    return CustomButton(
      text: 'Upload Manually',
      svgIconPath: 'assets/buttons/folder-add.svg',
      backgroundColor: const Color(0xFFE3F1E7),
      textColor: const Color(0xFF0E5723),
      onPressed: () => _openManualUpload(docType),
    );
  }

  /// Shown once a manual upload has been submitted and is awaiting admin
  /// review — backend reports this as status "UNDER_REVIEW" (see
  /// KycDocumentType.isUnderReview / KycDocumentsResult.aadhaarUnderReview).
  /// Same blue "info" palette as AppToast's ToastType.info — this is neither
  /// a failure nor (yet) a success.
  Widget _buildUnderReviewNotice(bool isDark, {required String label}) {
    const infoColor = Color(0xFF2563EB);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(20.r),
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

  /// PAN has no consent of its own — it rides on the SAME DigiLocker
  /// session as Aadhaar (see `_onRetryPan`'s doc comment and
  /// `MODULE_BRAIN.md` §2), so this button's onPressed is literally
  /// [_onVerifyAadhaar] — the same handler the Aadhaar card's own "Verify
  /// via DigiLocker" button uses. If the Aadhaar form (below, on the same
  /// screen) isn't filled in yet, `_aadhaarFormKey`'s validation surfaces
  /// its errors there rather than here, which is the correct place to fix
  /// them — PAN has nothing of its own to validate.
  Widget _buildPanVerifyNotice(bool isDark, {required bool isBusy, required bool showManualUpload}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(20.r),
          decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.03)
                  : Colors.black.withOpacity(0.02),
              borderRadius: BorderRadius.circular(20.r)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PAN is verified automatically together with Aadhaar via DigiLocker.',
                style: AppTextStyles.fieldHelper(isDark),
              ),
              SizedBox(height: 16.h),
              CustomButton(
                text: 'Verify via DigiLocker',
                svgIconPath: 'assets/buttons/tick.svg',
                isLoading: isBusy,
                onPressed: isBusy ? null : _onVerifyAadhaar,
                gradient: AppTheme.greenGradient,
              ),
            ],
          ),
        ),
        // Offered once EITHER DigiLocker has genuinely been tried at least
        // once (win, lose, or abandoned mid-consent), OR Aadhaar is already
        // verified by any means — see build()'s panAllowManualUpload
        // comment for the full reasoning. Never on the very first visit
        // with nothing yet attempted or verified.
        if (showManualUpload) ...[
          SizedBox(height: 8.h),
          _buildManualUploadButton(isDark, docType: '1'),
        ],
      ],
    );
  }

  /// Shown instead of [_buildPanVerifyNotice] once Aadhaar has already
  /// come back APPROVED but this PAN card is still pending — i.e. the user
  /// completed DigiLocker consent without "PAN Verification Record" checked.
  /// Uses the app's existing amber "warning" palette (see `app_toast.dart`'s
  /// `ToastType.warning` style) so this reads as "needs your attention", not
  /// a hard failure, since re-running consent with PAN checked resolves it.
  Widget _buildPanSkippedNotice(bool isDark, {required bool isBusy, required bool showManualUpload}) {
    const warningColor = Color(0xFFD97706);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
              // Same label as _buildPanVerifyNotice's button for consistency
              // — the handler is _onRetryPan (not _onVerifyAadhaar) because
              // Aadhaar is already approved here, so the plain verify path
              // would short-circuit as "already approved" without ever
              // re-fetching PAN. _onRetryPan reopens the Aadhaar form with
              // allow_reverify set, specifically to redo DigiLocker for PAN.
              CustomButton(
                text: 'Verify via DigiLocker',
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
        ),
        // Always true in practice here (this state only shows once Aadhaar
        // is APPROVED, which itself proves DigiLocker was attempted) — the
        // param is still threaded through rather than hardcoded so this
        // stays correct if that invariant ever changes.
        if (showManualUpload) ...[
          SizedBox(height: 8.h),
          _buildManualUploadButton(isDark, docType: '1'),
        ],
      ],
    );
  }

  Widget _buildAadhaarCard(
    bool isDark,
    AadhaarState state, {
    required bool backendApproved,
    String? backendMaskedNumber,
    String? backendVerifiedName,
    bool backendUnderReview = false,
    bool allowManualUpload = false,
  }) {
    // Falls back to the backend's own aadhaar_status (from get_document_types
    // / kyc/document-types, always current) when the local provider hasn't
    // caught up yet — _seedAadhaarIfApproved seeds it a frame late (see its
    // doc comment). Without this, a customer whose Aadhaar the backend
    // already reports as approved briefly sees the fresh "enter your
    // Aadhaar number" form instead of the Verified banner — and if they
    // type into it and submit during that window, the backend's own
    // idempotency short-circuit rejects it as a no-op (`allow_reverify`
    // wasn't set, since this wasn't reached through the Edit/Retry-PAN
    // flow that sets it), which reads as "my first tap did nothing."
    // Restricted to phase == idle specifically — never overrides a
    // genuinely in-progress or failed local phase with a stale backend flag
    // from before a fresh reverify attempt started. Also suppressed while
    // _aadhaarEditing is true: that flag means the user deliberately
    // triggered Edit or Retry PAN Verification, which ALSO resets the local
    // phase to idle (see _editAadhaar) specifically to reopen the input
    // form — without this guard, the stale backendApproved flag (from
    // before this reverify attempt) would immediately re-collapse that
    // freshly-reopened form back into the Verified banner.
    final isDone = state.phase == AadhaarPhase.approved ||
        (backendApproved && state.phase == AadhaarPhase.idle && !_aadhaarEditing);
    final isBusy = _verifyingAadhaar ||
        state.phase == AadhaarPhase.initiating ||
        state.phase == AadhaarPhase.polling;
    // Error/failure text is surfaced only via AppToast (see
    // _onVerifyAadhaar) — never rendered inline on the card, so no backend
    // exception, provider error, or technical message can ever appear here.
    final isErrorPhase = state.phase == AadhaarPhase.failed ||
        state.phase == AadhaarPhase.expired ||
        state.phase == AadhaarPhase.rejected;
    const defaultHelperText =
        'Enter your Aadhaar number, then verify via DigiLocker to complete KYC.';
    // Shown instead of the generic helper (and instead of any backend
    // message) whenever this form reopened via "Retry PAN Verification" —
    // Aadhaar itself doesn't need re-entry, this round trip through
    // DigiLocker exists only to fetch PAN. Takes priority over isErrorPhase
    // too: a stale REJECTED/EXPIRED message from a much earlier Aadhaar
    // attempt has no bearing on this PAN-only retry.
    const panRetryHelperText =
        "Your Aadhaar is already verified — this step only redoes DigiLocker "
        "consent so PAN can be fetched. Select 'PAN Verification Record' "
        "this time before tapping Allow.";
    // Broader than just `_retryingPanOnly` (the dedicated "Retry PAN
    // Verification" button) — ANY path that reopens this form while the
    // backend already reports Aadhaar approved (e.g. re-verifying PAN from
    // its plain "not yet uploaded" state, which reopens the SAME shared
    // Aadhaar+PAN form via _aadhaarEditing without going through the
    // retry-PAN button) should reassure the customer their Aadhaar isn't
    // actually being un-verified, not just the one specific entry point.
    final showAadhaarAlreadyVerifiedHint = backendApproved && _aadhaarEditing;
    final helperText = showAadhaarAlreadyVerifiedHint
        ? panRetryHelperText
        : (isErrorPhase ? defaultHelperText : (state.message ?? defaultHelperText));

    return Padding(
      padding: EdgeInsets.only(bottom: 32.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header icon reflects the BACKEND's verified status specifically
          // (not `isDone`, which the !_aadhaarEditing guard above forces
          // false while this card is reopened for a PAN-only DigiLocker
          // retry) — otherwise a customer whose Aadhaar is genuinely already
          // approved sees a "not verified" grey icon the instant PAN retry
          // starts, which reads as Aadhaar having been un-verified. Which
          // body renders below (banner vs form) still uses `isDone` as
          // before; only this status icon is decoupled from it.
          _buildStatusHeader('Aadhaar', isDark, isDone || backendApproved),
          SizedBox(height: 16.h),
          if (isDone)
            _buildVerifiedBanner(
              isDark,
              numberLabel: 'Aadhaar Number',
              maskedValue: state.maskedNumber ?? backendMaskedNumber,
              nameLabel: 'Name as on Aadhaar',
              verifiedName: state.verifiedName ?? backendVerifiedName,
              onEdit: _editAadhaar,
            )
          else if (backendUnderReview && !_aadhaarEditing)
            _buildUnderReviewNotice(isDark, label: 'Aadhaar')
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
                    if (showAadhaarAlreadyVerifiedHint) ...[
                      Row(
                        children: [
                          Icon(Icons.check_circle, size: 16.sp, color: const Color(0xFF16A34A)),
                          SizedBox(width: 6.w),
                          Text(
                            'Aadhaar Verified',
                            style: AppTextStyles.fieldLabel(isDark).copyWith(color: const Color(0xFF16A34A)),
                          ),
                        ],
                      ),
                      SizedBox(height: 8.h),
                    ],
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
            if (!showAadhaarAlreadyVerifiedHint && allowManualUpload) ...[
              SizedBox(height: 8.h),
              _buildManualUploadButton(isDark, docType: '2'),
            ],
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
    // PAN–Aadhaar link result for this session (see AadhaarState.aadhaarPanLinked's
    // doc comment) — null (not shown) whenever it isn't known yet, true/false
    // once the backend's PAN check has resolved it.
    bool? linkedToAadhaar,
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
          if (linkedToAadhaar != null) ...[
            SizedBox(height: 10.h),
            Row(
              children: [
                Icon(
                  linkedToAadhaar ? Icons.link_rounded : Icons.link_off_rounded,
                  size: 14.sp,
                  color: linkedToAadhaar ? const Color(0xFF0E5723) : Colors.orange[800],
                ),
                SizedBox(width: 6.w),
                Text(
                  linkedToAadhaar ? 'Linked to your Aadhaar' : 'Not linked to your Aadhaar',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: linkedToAadhaar ? const Color(0xFF0E5723) : Colors.orange[800],
                  ),
                ),
              ],
            ),
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

// Shared by both _VerifiedDetailsDialog and NameMismatchDialog below — DOB
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
      if (mounted) Navigator.pop(context, true);
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
              // Deliberate escape hatch: confirming this name is still
              // mandatory before KYC counts as complete (see
              // _runCompletionSequence, which stops rather than proceeding
              // when this dialog is deferred) — but Save has no way to
              // succeed if the backend keeps rejecting it (e.g. a
              // false-positive name-mismatch), and until now nothing else
              // in this dialog could close it, trapping the customer until
              // they force-killed the app. This lets them back out and
              // retry later instead.
              if (!_saving) ...[
                SizedBox(height: 8.h),
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(
                    'Do this later',
                    style: AppTextStyles.fieldLabel(isDark),
                  ),
                ),
              ],
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
class NameMismatchDialog extends StatefulWidget {
  final NameMismatchPrompt prompt;
  final Future<(NameMismatchOutcome, String?)> Function(String name, String dob) onSubmit;

  const NameMismatchDialog({
    required this.prompt,
    required this.onSubmit,
  });

  @override
  State<NameMismatchDialog> createState() => NameMismatchDialogState();
}

class NameMismatchDialogState extends State<NameMismatchDialog> {
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
    SecureLogger.d('[KYC DEBUG] NameMismatchDialog._submit: calling onSubmit, document=${widget.prompt.document}');
    final (outcome, msg) = await widget.onSubmit(
      typedName,
      _selectedDob != null ? _formatKycDob(_selectedDob!) : '',
    );
    SecureLogger.d('[KYC DEBUG] NameMismatchDialog._submit: onSubmit returned outcome=$outcome, dialog mounted=$mounted');
    if (!mounted) return;
    if (outcome == NameMismatchOutcome.resolved) {
      SecureLogger.d('[KYC DEBUG] NameMismatchDialog._submit: popping dialog(true), canPop=${Navigator.of(context, rootNavigator: true).canPop()}');
      Navigator.of(context, rootNavigator: true).pop(true);
      SecureLogger.d('[KYC DEBUG] NameMismatchDialog._submit: pop() call returned');
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
