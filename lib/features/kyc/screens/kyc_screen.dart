import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/custom_button.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/shared/widgets/secure_clipboard.dart';

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
  final _formKey = GlobalKey<FormState>();
  final Map<String, Map<String, TextEditingController>> _docControllers = {};
  bool _initialized = false;

  @override
  void dispose() {
    for (var controllers in _docControllers.values) {
      for (var controller in controllers.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  void _initControllers(List<KycDocumentType> docs) {
    if (_initialized) return;
    for (var doc in docs) {
      _docControllers[doc.id] = {};
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
    }
    _initialized = true;
  }

  Future<void> _submit(List<KycDocumentType> docs) async {
    if (!_formKey.currentState!.validate()) return;

    // Pick the docs that need submission
    final List<KycDocumentType> docsToSubmit = docs;
    if (docsToSubmit.isEmpty) {
      _handleSuccess();
      return;
    }

    try {
      // For now, we submit them sequentially as per the current kycSubmitProvider design.
      // In a real production app, you might want to call them in parallel or have a single "save-all" API.
      for (var doc in docsToSubmit) {
        final Map<String, dynamic> fields = {};
        final controllers = _docControllers[doc.id];
        controllers?.forEach((key, controller) {
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
            // Extract the real server message from the exception
            String errorMsg = result.error.toString();
            // Strip Dart's 'Exception: ' prefix if present
            if (errorMsg.startsWith('Exception: ')) {
              errorMsg = errorMsg.substring('Exception: '.length);
            }
            AppToast.show(context, errorMsg, type: ToastType.error);
            // Stay on the page so the user can correct their input
          }
          return;
        }
      }

      _handleSuccess();
    } catch (e) {
      if (mounted) {
        String msg = e.toString();
        if (msg.startsWith('Exception: ')) {
          msg = msg.substring('Exception: '.length);
        }
        AppToast.show(context, msg, type: ToastType.error);
      }
    }
  }

  void _handleSuccess() {
    if (mounted) {
      _showSuccessDialog();
    }
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
                'PAN Verification',
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
                'PAN Verification\nCompleted Successfully',
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
        if (widget.requestFrom == 'instant') {
          // [LEGACY — kept for reference]
          // Navigator.pushReplacementNamed(context, '/payment-methods',
          //     arguments: widget.extraData);
          //
          // NEW: Return true to InvestScreen so it can continue payment
          // directly via PaymentHandler.startPayment() without an extra screen.
          Navigator.pop(context, true);
        } else if (widget.requestFrom == 'withdraw') {
          Navigator.pushReplacementNamed(context, '/upi-selection');
        } else {
          Navigator.pop(context, true);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final docsAsync = ref.watch(kycDocumentsProvider(widget.requestFrom));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Verification'),
          Expanded(
            child: docsAsync.when(
              data: (docs) {
                _initControllers(docs);
                return SingleChildScrollView(
            padding: EdgeInsets.all(24.w),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Complete your KYC',
                      style: GoogleFonts.playfairDisplay(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black)),
                  SizedBox(height: 32.h),
                  ...docs.map((doc) => _buildDocumentCard(doc, isDark)),
                ],
              ),
            ),
          );
        },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          docsAsync.hasValue ? _buildFooter(isDark, docsAsync.value!) : null,
    );
  }

  Widget _buildDocumentCard(KycDocumentType doc, bool isDark) {
    final isPan = doc.name.toUpperCase().contains('PAN') ||
        doc.code.toUpperCase().contains('PAN');

    return Padding(
      padding: EdgeInsets.only(bottom: 32.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatusHeader(doc, isDark),
          SizedBox(height: 16.h),
          if (isPan)
            _buildPanCard(doc, isDark)
          else
            _buildGenericCard(doc, isDark, false),
        ],
      ),
    );
  }

  Widget _buildStatusHeader(KycDocumentType doc, bool isDark) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(4.r),
          decoration: BoxDecoration(
              color: isDark ? Colors.white12 : Colors.black12,
              shape: BoxShape.circle),
          child: Icon(Icons.check, color: Colors.transparent, size: 14.sp),
        ),
        SizedBox(width: 8.w),
        Text('${doc.name} Required',
            style: GoogleFonts.playfairDisplay(
                fontSize: 15.sp,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black)),
      ],
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
                Text(field.label,
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white60 : Colors.black54)),
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
                style: GoogleFonts.playfairDisplay(
                    color: stylized
                        ? Colors.black87
                        : (isDark ? Colors.white : Colors.black),
                    fontWeight:
                        stylized ? FontWeight.w600 : FontWeight.normal),
                decoration: InputDecoration(
                  hintText: field.label,
                  hintStyle: GoogleFonts.playfairDisplay(
                      fontSize: 16.sp,
                      color: isDark ? Colors.white38 : Colors.black38),
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

  Widget _buildFooter(bool isDark, List<KycDocumentType> docs) {
    final submitState = ref.watch(kycSubmitProvider);
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: CustomButton(
          text: 'Continue',
          svgIconPath: 'assets/buttons/tick.svg',
          isLoading: submitState.isLoading,
          onPressed: () => _submit(docs),
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

