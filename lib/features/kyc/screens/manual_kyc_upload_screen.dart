import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';

import '../repositories/kyc_repository.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/utils/aadhaar_input_formatter.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import 'kyc_screen.dart' show UpperCaseFormatter;

/// "Upload manually instead" — the alternative to DigiLocker offered on the
/// PAN and Aadhaar cards (see kyc_screen.dart's `_buildPanAutoVerifyNotice`
/// and `_buildAadhaarCard`). The customer submits a photo of their document
/// plus the typed number/name; the backend puts it UNDER_REVIEW rather than
/// verifying instantly (KycRepository.submitManualKyc — see its docstring),
/// and an admin reviews it later from the admin panel. Pops `true` on a
/// successful submit so KycScreen refreshes and shows the "under review"
/// banner instead of the DigiLocker form.
///
/// A dedicated pushed route, not a modal bottom sheet — this app has hit
/// Overlay/Navigator races (duplicate GlobalKeys / `_dependents.isEmpty`)
/// from bottom sheets racing route transitions before; a plain route avoids
/// that class of bug entirely.
class ManualKycUploadScreen extends ConsumerStatefulWidget {
  /// "1" (PAN) or "2" (AADHAAR) — same id_document convention as the rest
  /// of the KYC flow.
  final String docType;
  final String requestFrom;

  const ManualKycUploadScreen({
    super.key,
    required this.docType,
    required this.requestFrom,
  });

  @override
  ConsumerState<ManualKycUploadScreen> createState() =>
      _ManualKycUploadScreenState();
}

class _ManualKycUploadScreenState extends ConsumerState<ManualKycUploadScreen> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _picker = ImagePicker();

  XFile? _panFile;
  XFile? _frontFile;
  XFile? _backFile;
  bool _submitting = false;

  bool get _isPan => widget.docType == '1';
  bool get _filesReady => _isPan ? _panFile != null : (_frontFile != null && _backFile != null);

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pick(void Function(XFile) onPicked) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppTheme.arcticBlue),
              title: const Text('Take Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: AppTheme.arcticBlue),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.cancel, color: Colors.grey),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    try {
      final file = await _picker.pickImage(
        source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 85,
      );
      if (file == null || !mounted) return;

      // Mirrors the backend's 5MB cap (shared/utils/upload_validation.py) —
      // catches an oversized file before the round trip, not instead of the
      // server-side check.
      final sizeBytes = await file.length();
      if (sizeBytes > 5 * 1024 * 1024) {
        if (mounted) {
          AppToast.show(context, 'Image is too large. Maximum allowed size is 5MB.', type: ToastType.error);
        }
        return;
      }

      onPicked(file);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Could not pick the image. Please try again.', type: ToastType.error);
      }
    }
  }

  String? _validateNumber(String? value) {
    if (_isPan) {
      final v = (value ?? '').trim().toUpperCase();
      if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$').hasMatch(v)) {
        return 'Enter a valid PAN (e.g. ABCDE1234F)';
      }
      return null;
    }
    final digits = AadhaarInputFormatter.unformat(value ?? '');
    if (digits.length != 12) return 'Enter a valid 12-digit Aadhaar number';
    if (!RegExp(r'^[2-9]').hasMatch(digits)) return 'Enter a valid 12-digit Aadhaar number';
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.trim().length < 2) return 'Enter a valid name';
    return null;
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    if (!_filesReady) {
      AppToast.show(
        context,
        _isPan
            ? 'Upload a photo of your PAN card.'
            : 'Upload both the front and back of your Aadhaar card.',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final files = _isPan
          ? {'file': _panFile!}
          : {'front': _frontFile!, 'back': _backFile!};

      await ref.read(kycRepositoryProvider).submitManualKyc(
            docType: widget.docType,
            documentNumber: _isPan
                ? _numberController.text.trim().toUpperCase()
                : AadhaarInputFormatter.unformat(_numberController.text),
            nameOnDocument: _nameController.text.trim(),
            files: files,
          );

      if (!mounted) return;
      AppToast.show(
        context,
        "Submitted for manual review — you'll be notified once it's verified.",
        type: ToastType.success,
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) msg = msg.substring('Exception: '.length);
      AppToast.show(context, msg, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _decoration(bool isDark, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTextStyles.kycFieldHint(isDark),
      errorStyle: AppTextStyles.fieldError(isDark),
      filled: true,
      fillColor: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12.r), borderSide: BorderSide.none,
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
    );
  }

  Widget _buildPicker(bool isDark, {
    required String label,
    required XFile? file,
    required VoidCallback onTap,
  }) {
    final done = file != null;
    return GestureDetector(
      onTap: _submitting ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: done ? const Color(0xFF16A34A) : (isDark ? Colors.white24 : Colors.black12),
          ),
        ),
        child: Row(
          children: [
            if (done)
              ClipRRect(
                borderRadius: BorderRadius.circular(8.r),
                child: Image.file(File(file.path), width: 48.w, height: 48.w, fit: BoxFit.cover),
              )
            else
              Container(
                width: 48.w,
                height: 48.w,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Icon(Icons.add_a_photo_outlined,
                    size: 20.sp, color: isDark ? Colors.white54 : Colors.black45),
              ),
            SizedBox(width: 12.w),
            Expanded(
              child: Text(
                done ? '$label — tap to retake' : 'Tap to add $label',
                style: AppTextStyles.fieldHelper(isDark),
              ),
            ),
            Icon(
              done ? Icons.check_circle : Icons.chevron_right,
              color: done ? const Color(0xFF16A34A) : (isDark ? Colors.white38 : Colors.black38),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: !_submitting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        AppToast.show(context, 'Please wait — submitting your document.', type: ToastType.info);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(title: _isPan ? 'Upload PAN Manually' : 'Upload Aadhaar Manually'),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(24.w),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isPan
                            ? 'Upload a clear photo of your PAN card. An admin will '
                              'review and verify it — this takes a little longer than DigiLocker.'
                            : 'Upload clear photos of the front and back of your Aadhaar '
                              'card. An admin will review and verify it — this takes a '
                              'little longer than DigiLocker.',
                        style: AppTextStyles.fieldHelper(isDark),
                      ),
                      SizedBox(height: 24.h),
                      Text(_isPan ? 'Full Name (as on PAN)' : 'Full Name (as on Aadhaar)',
                          style: AppTextStyles.fieldLabel(isDark)),
                      SizedBox(height: 8.h),
                      TextFormField(
                        controller: _nameController,
                        textCapitalization: TextCapitalization.characters,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
                          LengthLimitingTextInputFormatter(60),
                        ],
                        contextMenuBuilder: SecureClipboard.none,
                        style: AppTextStyles.kycFieldInput(isDark),
                        decoration: _decoration(isDark, 'Full name'),
                        validator: _validateName,
                      ),
                      SizedBox(height: 16.h),
                      Text(_isPan ? 'PAN Number' : 'Aadhaar Number', style: AppTextStyles.fieldLabel(isDark)),
                      SizedBox(height: 8.h),
                      TextFormField(
                        controller: _numberController,
                        keyboardType: _isPan ? TextInputType.text : TextInputType.number,
                        textCapitalization:
                            _isPan ? TextCapitalization.characters : TextCapitalization.none,
                        inputFormatters: _isPan
                            ? [UpperCaseFormatter(), LengthLimitingTextInputFormatter(10)]
                            : [AadhaarInputFormatter()],
                        contextMenuBuilder: SecureClipboard.none,
                        style: AppTextStyles.kycFieldInput(isDark),
                        decoration: _decoration(isDark, _isPan ? 'ABCDE1234F' : 'XXXX XXXX XXXX'),
                        validator: _validateNumber,
                      ),
                      SizedBox(height: 24.h),
                      if (_isPan)
                        _buildPicker(
                          isDark, label: 'PAN Card Photo', file: _panFile,
                          onTap: () => _pick((f) => _panFile = f),
                        )
                      else ...[
                        _buildPicker(
                          isDark, label: 'Aadhaar — Front', file: _frontFile,
                          onTap: () => _pick((f) => _frontFile = f),
                        ),
                        SizedBox(height: 16.h),
                        _buildPicker(
                          isDark, label: 'Aadhaar — Back', file: _backFile,
                          onTap: () => _pick((f) => _backFile = f),
                        ),
                      ],
                      SizedBox(height: 32.h),
                      CustomButton(
                        text: 'Submit for Review',
                        svgIconPath: 'assets/buttons/tick.svg',
                        isLoading: _submitting,
                        onPressed: _submitting ? null : _submit,
                        gradient: AppTheme.greenGradient,
                      ),
                    ],
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
