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
  void _seedAadhaarIfApproved(bool aadhaarApproved, {String? maskedNumber, String? name}) {
    if (_aadhaarSeeded || !aadhaarApproved) return;
    _aadhaarSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(aadhaarProvider.notifier).seedApproved(maskedNumber: maskedNumber, name: name);
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
    final finalState = ref.read(aadhaarProvider);
    if (finalState.phase == AadhaarPhase.expired ||
        finalState.phase == AadhaarPhase.rejected ||
        finalState.phase == AadhaarPhase.failed) {
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

    // pollUntilTerminal exhausted its retries while DigiLocker was still
    // processing (e.g. the provider's document-fetch/cross-verify chain
    // outran the client's polling window) — it resets to awaitingConsent
    // with an explanatory message instead of a terminal phase. Without this,
    // the user sees the DigiLocker screen close and nothing else: no
    // success, no error. Surface it so they know to check back / retry.
    if (finalState.message != null) {
      AppToast.show(context, finalState.message!, type: ToastType.info);
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
          );
    }

    final bothComplete =
        result.documents.every((d) => d.alreadyUploaded) && result.aadhaarApproved;
    if (!bothComplete) return;

    final panDoc = result.documents.isEmpty
        ? null
        : result.documents.firstWhere(
            (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
            orElse: () => result.documents.first,
          );

    await _runCompletionSequence(panName: panDoc?.verifiedName, aadhaarName: result.aadhaarName);
  }

  /// Success animation, then the MANDATORY Profile Name Selection popup
  /// (never skipped — see _showProfileNameSelectionDialog), then applies
  /// the user's choice, then finally completes the screen. Every caller
  /// (SIP/Withdrawal/Investment/Profile) awaits this screen and decides
  /// what to do next itself (typically retrying the original blocked
  /// action via KycVerificationFlow) — no requestFrom-specific navigation
  /// lives here.
  Future<void> _runCompletionSequence({String? panName, String? aadhaarName}) async {
    await _showSuccessAnimation();
    if (!mounted) return;

    final choice = await _showProfileNameSelectionDialog(
      panName: panName, aadhaarName: aadhaarName,
    );
    if (!mounted) return;

    if (choice == 'PAN' || choice == 'AADHAAR') {
      try {
        await ref.read(kycRepositoryProvider).updateProfileName(source: choice!);
        if (mounted) {
          AppToast.show(context, 'Profile name updated.', type: ToastType.success);
        }
      } catch (e) {
        if (mounted) {
          String msg = e.toString();
          if (msg.startsWith('Exception: ')) msg = msg.substring('Exception: '.length);
          AppToast.show(context, msg, type: ToastType.error);
        }
      }
    }
    // "Not Now" (choice == null): profile name left unchanged, KYC stays APPROVED.

    if (mounted) Navigator.pop(context, true);
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

  /// MANDATORY confirmation shown after every PAN + Aadhaar completion —
  /// first-time verification AND every re-verification via Edit — with no
  /// exceptions, even when both verified names are identical to each other
  /// or to the current profile name (the point is to make the customer
  /// explicitly aware their profile name CAN change, every single time).
  /// Not dismissible via the barrier or the back button (PopScope
  /// canPop:false) — the user must tap one of the three actions. Returns
  /// 'PAN', 'AADHAAR', or null ("Not Now").
  Future<String?> _showProfileNameSelectionDialog({String? panName, String? aadhaarName}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
          child: Padding(
            padding: EdgeInsets.all(24.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose Your Profile Name',
                  style: AppTextStyles.titleMedium(isDark)
                      .copyWith(color: const Color(0xFF643D41)),
                ),
                SizedBox(height: 16.h),
                _buildVerifiedNameDisplay('Verified PAN Name', panName, isDark),
                SizedBox(height: 12.h),
                _buildVerifiedNameDisplay('Verified Aadhaar Name', aadhaarName, isDark),
                SizedBox(height: 16.h),
                Text(
                  'Which verified name would you like to use as your Profile Name?',
                  style: AppTextStyles.fieldHelper(isDark),
                ),
                SizedBox(height: 20.h),
                CustomButton(
                  text: 'Use PAN Name',
                  onPressed: () => Navigator.pop(dialogContext, 'PAN'),
                  gradient: AppTheme.greenGradient,
                ),
                SizedBox(height: 10.h),
                CustomButton(
                  text: 'Use Aadhaar Name',
                  onPressed: () => Navigator.pop(dialogContext, 'AADHAAR'),
                  gradient: AppTheme.greenGradient,
                ),
                SizedBox(height: 8.h),
                // Center(
                //   child: TextButton(
                //     onPressed: () => Navigator.pop(dialogContext, null),
                //     child: Text(
                //       'Not Now',
                //       style: TextStyle(
                //         fontSize: 14.sp,
                //         fontWeight: FontWeight.w700,
                //         color: isDark ? Colors.white60 : Colors.black54,
                //       ),
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerifiedNameDisplay(String label, String? name, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label:', style: AppTextStyles.fieldLabel(isDark)),
        SizedBox(height: 2.h),
        Text(
          (name == null || name.isEmpty) ? '—' : name,
          style: AppTextStyles.kycFieldInput(isDark).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
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
                );
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
                      ...result.documents.map((doc) => _buildDocumentCard(doc, isDark)),
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
  Widget _buildDocumentCard(KycDocumentType doc, bool isDark) {
    final isPan = doc.name.toUpperCase().contains('PAN') ||
        doc.code.toUpperCase().contains('PAN');
    final isDone = _completedDocIds.contains(doc.id);

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
