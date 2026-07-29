import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
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
  void _seedAadhaarIfApproved(bool aadhaarApproved) {
    if (_aadhaarSeeded || !aadhaarApproved) return;
    _aadhaarSeeded = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(aadhaarProvider.notifier).seedApproved();
    });
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
    );
    if (!mounted) return;

    final afterInitiate = ref.read(aadhaarProvider);
    if (afterInitiate.phase == AadhaarPhase.awaitingConsent &&
        afterInitiate.consentUrl != null) {
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
    }
  }

  bool _allDocsComplete(List<KycDocumentType> docs) {
    return docs.every((doc) => _completedDocIds.contains(doc.id));
  }

  void _showSuccessDialog() {
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
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF643D41),
                ),
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
                style: GoogleFonts.playfairDisplay(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context); // Close dialog
        // KYC is complete — every caller (SIP/Withdrawal/Investment/Profile)
        // awaits this screen and decides what to do next itself (typically
        // retrying the original blocked action via KycVerificationFlow).
        // No requestFrom-specific navigation lives here anymore.
        Navigator.pop(context, true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(kycDocumentsProvider(widget.requestFrom));
    final aadhaarState = ref.watch(aadhaarProvider);
    final aadhaarApproved = aadhaarState.phase == AadhaarPhase.approved;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Verification'),
          Expanded(
            child: docsAsync.when(
              data: (result) {
                _initControllers(result.documents);
                _seedAadhaarIfApproved(result.aadhaarApproved);
                return SingleChildScrollView(
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Complete your KYC',
                          style: AppTextStyles.titleLarge(isDark)),
                      SizedBox(height: 8.h),
                      Text(
                        'PAN and Aadhaar verification are both required.',
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
      bottomNavigationBar: docsAsync.hasValue
          ? _buildFooter(isDark, docsAsync.value!.documents, aadhaarApproved)
          : null,
    );
  }

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
            _buildVerifiedBanner(isDark)
          else ...[
            Form(
              key: _docFormKeys[doc.id],
              child: isPan
                  ? _buildPanCard(doc, isDark)
                  : _buildGenericCard(doc, isDark, false),
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
            _buildVerifiedBanner(isDark)
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

  /// Same green "Verified" pill used on the Profile screen's KYC menu item
  /// (see profile_screen.dart) — reused here so a completed PAN/Aadhaar
  /// step reads consistently across the app.
  Widget _buildVerifiedBanner(bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: const Color(0xFF0E5723).withOpacity(0.08),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFF0E5723).withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded,
              color: const Color(0xFF0E5723), size: 16.sp),
          SizedBox(width: 8.w),
          Text(
            'Verified',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF0E5723),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanCard(KycDocumentType doc, bool isDark) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24.r),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1E3A8A).withOpacity(0.2)
            : const Color(0xFFE2F1FF),
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('आयकर विभाग',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSans(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black)),
                    Text('INCOME TAX DEPARTMENT',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black54)),
                  ],
                ),
              ),
              Icon(Icons.account_balance_rounded,
                  size: 32.sp, color: isDark ? Colors.white38 : Colors.black45),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('भारत सरकार',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.notoSans(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black)),
                    Text('GOVT OF INDIA',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 9.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : Colors.black54)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 24.h),
          _buildDocInputs(doc, isDark, false, true),
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

  Widget _buildFooter(
      bool isDark, List<KycDocumentType> docs, bool aadhaarApproved) {
    final canFinish = _allDocsComplete(docs) && aadhaarApproved;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: CustomButton(
          text: 'Finish',
          svgIconPath: 'assets/buttons/tick.svg',
          onPressed: canFinish ? _showSuccessDialog : null,
          gradient: AppTheme.greenGradient,
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
