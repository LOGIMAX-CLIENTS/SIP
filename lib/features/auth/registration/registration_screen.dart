import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:dio/dio.dart';
import '../controller/auth_controller.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/utils/validators.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'email_otp_sheet.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  final String mobile;
  final String tempToken;
  const RegistrationScreen(
      {super.key, required this.mobile, required this.tempToken});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _dobController = TextEditingController();
  final _referralController = TextEditingController();

  bool _agreedToTerms = false;
  bool _isSubmitting = false;

  // ── Mandatory email OTP verification state ──────────────────────────────
  bool _emailVerified = false;
  bool _isVerifyingEmail = false;
  String? _verifiedEmail;

  late final TapGestureRecognizer _termsRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => Navigator.pushNamed(context, AppRouter.terms);

    // Editing the email after verification invalidates that verification.
    _emailController.addListener(() {
      if (_emailVerified && _emailController.text.trim() != _verifiedEmail) {
        setState(() => _emailVerified = false);
      }
    });

    Future.microtask(() {
      if (mounted) ref.read(authControllerProvider.notifier).clearError();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _referralController.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime yesterday = now.subtract(const Duration(days: 1));

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now.subtract(const Duration(days: 6570)), // Default 18 years
      firstDate: DateTime(1900),
      lastDate: yesterday,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF064E3B),
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedDate =
          "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      setState(() {
        _dobController.text = formattedDate;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        AppToast.show(context, next.error!, type: ToastType.error);
      }
    });

    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);
    final inputBgColor = isDark ? Colors.white.withOpacity(0.05) : Colors.white;

    final bool canSubmit =
        _agreedToTerms && _emailVerified && !_isSubmitting && !authState.isLoading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable Content ─────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.w),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              icon: Icon(Icons.arrow_back, color: primaryTextColor),
                              onPressed: () => NavigationUtils.safePop(context),
                            ),
                            SvgPicture.asset(
                              'assets/images/startGold.svg',
                              height: 85.h,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                        SizedBox(height: 32.h),

                        // Title
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 100),
                          child: Text(
                            'Personal Information',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 30.sp,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                        ),
                        SizedBox(height: 36.h),

                        // Full Name Field
                        _buildInputLabel('Full Name *', primaryTextColor),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _nameController,
                          hint: 'Enter Your Full Name',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          textCapitalization: TextCapitalization.words,
                          inputFormatters: [
                            // Allow only letters and spaces — no special characters
                            FilteringTextInputFormatter.allow(
                                RegExp(r"[a-zA-Z ]")),
                            // Capitalise first letter of every word
                            TextInputFormatter.withFunction((oldValue, newValue) {
                              final text = newValue.text;
                              if (text.isEmpty) return newValue;
                              final capitalized = text.split(' ').map((word) {
                                if (word.isEmpty) return word;
                                return word[0].toUpperCase() + word.substring(1);
                              }).join(' ');
                              return newValue.copyWith(text: capitalized);
                            }),
                          ],
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),
                        SizedBox(height: 6.h),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 14.sp,
                              color: const Color(0xFFD97706),
                            ),
                            SizedBox(width: 6.w),
                            Expanded(
                              child: Text(
                                'Note: Enter full name exactly as on your PAN Card.',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 11.sp,
                                  color: isDark ? Colors.white54 : const Color(0xFF92400E),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: 24.h),

                        // DOB Field
                        _buildInputLabel('Date of Birth *', primaryTextColor),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _dobController,
                          hint: 'DD/MM/YYYY',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          readOnly: true,
                          onTap: () => _selectDate(context),
                          isNumeric: true,
                          suffixIcon: Icon(Icons.calendar_today_rounded,
                              size: 20.sp,
                              color: primaryTextColor.withOpacity(0.5)),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'Required' : null,
                        ),

                        SizedBox(height: 24.h),

                        // Email Field
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildInputLabel('E-Mail *', primaryTextColor),
                            if (_emailVerified)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      size: 15.sp, color: const Color(0xFF1B882C)),
                                  SizedBox(width: 4.w),
                                  Text(
                                    'Verified',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1B882C),
                                    ),
                                  ),
                                ],
                              )
                            else
                              GestureDetector(
                                onTap: _isVerifyingEmail ? null : _verifyEmail,
                                child: _isVerifyingEmail
                                    ? SizedBox(
                                        width: 14.w,
                                        height: 14.w,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                              Colors.orangeAccent),
                                        ),
                                      )
                                    : Text(
                                        'Verify',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 13.sp,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.orangeAccent,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.orangeAccent,
                                        ),
                                      ),
                              ),
                          ],
                        ),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _emailController,
                          hint: 'Enter Your E-Mail',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.validateEmail,
                        ),

                        SizedBox(height: 24.h),

                        // Referral Field
                        _buildInputLabel(
                            'Referral Code (Optional)', primaryTextColor),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _referralController,
                          hint: 'Enter Referral Code',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          textCapitalization: TextCapitalization.characters,
                        ),

                        SizedBox(height: 20.h),

                        // ── Terms & Conditions Checkbox ───────────────────────
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 300),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 24.w,
                                height: 24.w,
                                child: Checkbox(
                                  value: _agreedToTerms,
                                  onChanged: (v) =>
                                      setState(() => _agreedToTerms = v ?? false),
                                  activeColor: const Color(0xFF1B882C),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4.r),
                                  ),
                                  side: BorderSide(
                                    color: primaryTextColor.withOpacity(0.4),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                              SizedBox(width: 10.w),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 13.sp,
                                      color: primaryTextColor.withOpacity(0.7),
                                      height: 1.5,
                                    ),
                                    children: [
                                      const TextSpan(text: 'I Agree to the '),
                                      TextSpan(
                                        text: 'Terms and Conditions',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 13.sp,
                                          color: Colors.orangeAccent,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationColor: Colors.orangeAccent,
                                        ),
                                        recognizer: _termsRecognizer,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Pinned Footer ──────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 28.h),
              child: FadeInAnimation(
                delay: const Duration(milliseconds: 400),
                child: CustomButton(
                  text: 'Confirm',
                  svgIconPath: 'assets/buttons/tick.svg',
                  isLoading: _isSubmitting || authState.isLoading,
                  onPressed: canSubmit ? _handleRegistration : null,
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF1B882C), Color(0xFF003716)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8F4C05).withOpacity(0.06),
                      offset: const Offset(0, 4),
                      blurRadius: 10,
                    ),
                  ],
                  textColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputLabel(String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label,
      style: AppTextStyles.fieldLabel(isDark).copyWith(color: color),
    );
  }

  Widget _buildClassicTextField({
    required TextEditingController controller,
    required String hint,
    required Color bgColor,
    required Color textColor,
    TextInputType? keyboardType,
    int? maxLength,
    TextAlign textAlign = TextAlign.start,
    TextCapitalization textCapitalization = TextCapitalization.none,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    bool isNumeric = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      textAlign: textAlign,
      textCapitalization: textCapitalization,
      readOnly: readOnly,
      onTap: onTap,
      validator: validator,
      inputFormatters: inputFormatters,
      contextMenuBuilder: SecureClipboard.none,
      style: isNumeric
          ? AppTextStyles.input(isDark).copyWith(color: textColor)
          : AppTextStyles.bodyLarge(isDark).copyWith(color: textColor),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: AppTextStyles.inputHint(isDark)
            .copyWith(color: textColor.withOpacity(0.6)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: bgColor,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 20.h),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide(color: textColor.withOpacity(0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide(color: textColor.withOpacity(0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: BorderSide(color: textColor.withOpacity(0.3), width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16.r),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
      ),
    );
  }

  Future<void> _verifyEmail() async {
    final email = _emailController.text.trim();
    final emailError = Validators.validateEmail(email);
    if (emailError != null) {
      AppToast.show(context, emailError, type: ToastType.error);
      return;
    }

    setState(() => _isVerifyingEmail = true);
    final success = await ref.read(authControllerProvider.notifier).sendEmailOtp(
          email,
          fullName: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : null,
        );

    if (!mounted) return;
    setState(() => _isVerifyingEmail = false);
    if (!success) return;

    final otpReferenceId =
        ref.read(authControllerProvider).data?['otp_reference_id'] as String?;
    if (otpReferenceId == null) return;

    final verified = await showEmailOtpSheet(
      context,
      email: email,
      otpReferenceId: otpReferenceId,
      fullName: _nameController.text.trim(),
    );

    if (verified == true && mounted) {
      setState(() {
        _emailVerified = true;
        _verifiedEmail = email;
      });
    }
  }

  Future<void> _handleRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_emailVerified) {
      AppToast.show(context, 'Please verify your email before proceeding.',
          type: ToastType.error);
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      // ── Step 1: Call /register-check to validate fields ──────────
      final authService = ref.read(authServiceProvider);
      final result = await authService.registerCheck(
        mobile: widget.mobile,
        fullName: _nameController.text.trim(),
        email: _emailController.text.trim(),
        tempToken: widget.tempToken,
        dob: _dobController.text,
        referralCode: _referralController.text.trim(),
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // ── Step 2: Validation passed → navigate to PIN creation ───
        Navigator.pushReplacementNamed(
          context,
          AppRouter.mpinCreation,
          arguments: {
            'fullName': _nameController.text.trim(),
            'mobile': widget.mobile,
            'email': _emailController.text.trim(),
            'dob': _dobController.text,
            'referralCode': _referralController.text.trim(),
            'tempToken': widget.tempToken,
          },
        );
      } else {
        // ── Error from API ──────────────────────────────────────────
        String errorMsg = 'Registration check failed. Please try again.';
        if (result['error'] != null && result['error']['message'] != null) {
          final msg = result['error']['message'];
          if (msg is Map) {
            errorMsg = msg.values.first
                .toString()
                .replaceAll('[', '')
                .replaceAll(']', '');
          } else {
            errorMsg = msg.toString();
          }
        } else if (result['message'] != null) {
          errorMsg = result['message'];
        }
        AppToast.show(context, errorMsg, type: ToastType.error);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      String errorMsg = 'Registration check failed. Please try again.';
      if (e.response?.data != null) {
        final respData = e.response?.data;
        if (respData is Map) {
          if (respData['error'] != null &&
              respData['error']['message'] != null) {
            final msg = respData['error']['message'];
            if (msg is Map) {
              errorMsg = msg.values.first
                  .toString()
                  .replaceAll('[', '')
                  .replaceAll(']', '');
            } else {
              errorMsg = msg.toString();
            }
          } else if (respData['message'] != null) {
            errorMsg = respData['message'];
          }
        }
      }
      AppToast.show(context, errorMsg, type: ToastType.error);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      AppToast.show(context, msg, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
