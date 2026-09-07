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
import 'package:startgold/shared/utils/dob_input_formatter.dart';

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
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
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
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _referralController.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  /// Customers must be at least 18 — leap-year-accurate (unlike a fixed
  /// day-count offset) since it's computed from calendar year/month/day.
  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    // The most recent date that still makes the customer 18 today.
    final DateTime maxDob = DateTime(now.year - 18, now.month, now.day);

    // Seed from whatever is already typed so the picker opens on that date
    // rather than jumping back to the 18-year cutoff.
    final DateTime? typed = DobInputFormatter.parse(_dobController.text);
    final DateTime initial =
        (typed != null && !typed.isAfter(maxDob)) ? typed : maxDob;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: maxDob,
      // calendarOnly removes the picker's own keyboard-entry mode. That mode
      // parses by locale (en_US => MM/DD/YYYY) and is what rejected
      // "19061992" with "Invalid format." — typing is handled by the field
      // itself now, so this path should not be reachable at all.
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      // Day grid first; the header still switches to the year list.
      initialDatePickerMode: DatePickerMode.day,
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
      setState(() {
        _dobController.text = DobInputFormatter.formatDate(picked);
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

                        // First Name Field
                        _buildInputLabel('First Name *', primaryTextColor),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _firstNameController,
                          hint: 'Enter Your First Name',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 30,
                          inputFormatters: _nameInputFormatters(),
                          validator: (v) => v == null || v.trim().length < 2
                              ? 'Enter a valid first name'
                              : null,
                        ),
                        SizedBox(height: 16.h),

                        // Last Name Field
                        _buildInputLabel(
                            'Last Name (Optional)', primaryTextColor),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _lastNameController,
                          hint: 'Enter Your Last Name',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          textCapitalization: TextCapitalization.words,
                          maxLength: 30,
                          inputFormatters: _nameInputFormatters(),
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
                                'Note: Enter your name exactly as on your PAN Card.',
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
                          // Typeable now — DobInputFormatter inserts the
                          // slashes, so "19061992" becomes 19/06/1992 as the
                          // customer types instead of being rejected.
                          keyboardType: TextInputType.number,
                          inputFormatters: [DobInputFormatter()],
                          isNumeric: true,
                          // The calendar is opened from the icon rather than
                          // by tapping the field, so tapping to edit no longer
                          // fights the picker.
                          // Padded off the border — suffixIconConstraints
                          // removes Flutter's default 48x48 box, so without
                          // this the glyph sits flush against the edge. The
                          // padding doubles as the tap target (opaque), so the
                          // area around the icon opens the picker too.
                          suffixIcon: GestureDetector(
                            onTap: () => _selectDate(context),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: EdgeInsets.only(
                                  right: 16.w, left: 12.w, top: 14.h, bottom: 14.h),
                              child: Icon(Icons.calendar_today_rounded,
                                  size: 20.sp,
                                  color: primaryTextColor.withOpacity(0.5)),
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            // parse() rejects both an incomplete value and an
                            // impossible one (31/02/1990 — DateTime would
                            // silently roll that to 3 March).
                            final dob = DobInputFormatter.parse(v);
                            if (dob == null) {
                              return 'Enter a valid date as DD/MM/YYYY';
                            }
                            if (_calculateAge(dob) < 18) {
                              return 'You must be at least 18 years old';
                            }
                            return null;
                          },
                        ),

                        SizedBox(height: 24.h),

                        // Email Field — the Verify action / Verified badge sits
                        // INSIDE the field (suffixIcon), matching DOB's calendar
                        // and Account Details' own e-mail field, rather than
                        // floating beside the label.
                        _buildInputLabel('E-Mail *', primaryTextColor),
                        SizedBox(height: 8.h),
                        _buildClassicTextField(
                          controller: _emailController,
                          hint: 'Enter Your E-Mail',
                          bgColor: inputBgColor,
                          textColor: primaryTextColor,
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.validateEmail,
                          suffixIcon: _buildEmailVerifyAction(),
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

  List<TextInputFormatter> _nameInputFormatters() {
    return [
      // Allow only letters and spaces — no special characters
      FilteringTextInputFormatter.allow(RegExp(r"[a-zA-Z ]")),
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
    ];
  }

  Widget _buildInputLabel(String label, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      label,
      style: AppTextStyles.fieldLabel(isDark).copyWith(color: color),
    );
  }

  /// E-mail Verify link / Verified badge, rendered inside the e-mail field.
  ///
  /// Wrapped so the suffix hugs its content — a bare Row inside `suffixIcon`
  /// stretches to the field's full height and pushes the text off-centre.
  Widget _buildEmailVerifyAction() {
    final Widget child;
    if (_emailVerified) {
      child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 15.sp, color: const Color(0xFF1B882C)),
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
      );
    } else if (_isVerifyingEmail) {
      child = SizedBox(
        width: 14.w,
        height: 14.w,
        child: const CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
        ),
      );
    } else {
      child = Text(
        'Verify',
        style: GoogleFonts.playfairDisplay(
          fontSize: 13.sp,
          fontWeight: FontWeight.w600,
          color: Colors.orangeAccent,
          decoration: TextDecoration.underline,
          decorationColor: Colors.orangeAccent,
        ),
      );
    }

    // The GestureDetector wraps the whole padded region, not just the glyph,
    // so the entire right-hand area behaves like a button — tapping the space
    // around the word triggers it too. HitTestBehavior.opaque is what makes
    // the transparent padding count as part of the hit target.
    final tappable = _emailVerified || _isVerifyingEmail ? null : _verifyEmail;
    // Sized to its content — no fixed or minimum width. An earlier version pinned
    // `width: 0` with a `minWidth` floor, which reserved space the long
    // "Verified" row then overran, producing Flutter's RIGHT OVERFLOWED stripe
    // beside a long address. Paired with `suffixIconConstraints` on the field
    // (defaults to a 48x48 minimum, which would re-introduce the same fight).
    return GestureDetector(
      onTap: tappable,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Horizontal padding keeps it off the border; the vertical padding is
        // what gives the tap target real height rather than just the text's
        // line box.
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        child: child,
      ),
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
        // Without this the suffix is forced to at least 48x48, which steals
        // width from the value text and overflows on a long e-mail address.
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
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
          firstName: _firstNameController.text.trim().isNotEmpty
              ? _firstNameController.text.trim()
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
      firstName: _firstNameController.text.trim(),
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
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
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
            'firstName': _firstNameController.text.trim(),
            'lastName': _lastNameController.text.trim(),
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
