import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/svg.dart';
import 'dart:async';

import '../controller/auth_controller.dart';
import '../../../core/utils/validators.dart';
import '../../../routes/app_router.dart';
import '../../../main.dart' show navigatorKey;
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/shared_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../core/services/environment_service.dart';
import '../../../core/providers/environment_provider.dart';
import '../../../core/providers/app_control_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final TextEditingController _mobileController = TextEditingController();
  String _countryCode = '+91';
  String _selectedCountryId = '101';
  final TapGestureRecognizer _termsRecognizer = TapGestureRecognizer();
  final TapGestureRecognizer _privacyRecognizer = TapGestureRecognizer();
  DateTime? _lastBackPressTime; // tracks double-tap-to-exit timing
  bool _navigating = false; // guards against double-tap navigation
  Timer? _longPressTimer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer.onTap = () {
      Navigator.pushNamed(context, AppRouter.terms);
    };
    _privacyRecognizer.onTap = () {
      Navigator.pushNamed(context, AppRouter.privacy);
    };
    Future.microtask(() {
      if (mounted) ref.read(authControllerProvider.notifier).clearError();
    });
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    _mobileController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<CountryCode>>>(countryCodesProvider,
        (previous, next) {
      next.whenData((codes) {
        if (codes.isNotEmpty && !codes.any((c) => c.prefix == _countryCode)) {
          setState(() {
            _countryCode = codes.first.prefix;
            _selectedCountryId = codes.first.id;
          });
        }
      });
    });

    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        AppToast.show(context, next.error!, type: ToastType.error);
      }
    });

    final authState = ref.watch(authControllerProvider);
    final countryCodesAsync = ref.watch(countryCodesProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool isValid =
        Validators.validateMobile(_mobileController.text) == null;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);
    final secondaryTextColor =
        isDark ? Colors.white70 : const Color(0xFF666666);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        final now = DateTime.now();
        final isSecondPress = _lastBackPressTime != null &&
            now.difference(_lastBackPressTime!) < const Duration(seconds: 2);
        if (isSecondPress) {
          SystemNavigator.pop();
        } else {
          _lastBackPressTime = now;
          if (mounted) {
            AppToast.show(
              context,
              'Press back again to exit',
              type: ToastType.info,
            );
          }
        }
      },
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
          ),
          child: SafeArea(
          child: Column(
            children: [
              // ── Scrollable Content ──────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.h),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            SvgPicture.asset(
                              'assets/images/startGold.svg',
                              height: 85.h,
                              fit: BoxFit.contain,
                            ),
                          ],
                        ),
                        SizedBox(height: 24.h),
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 100),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome to',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 30.sp,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  // "Start" — green gradient
                                  ShaderMask(
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFF49B44B),
                                        Color(0xFF1A6F2D),
                                      ],
                                    ).createShader(bounds),
                                    blendMode: BlendMode.srcIn,
                                    child: Text(
                                      'start',
                                      style: GoogleFonts.playfairDisplay(
                                        fontSize: 30.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  // "GOLD" — orange gradient
                                  ShaderMask(
                                    shaderCallback: (bounds) =>
                                        const LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Color(0xFFFFB941),
                                        Color(0xFFE27903),
                                      ],
                                    ).createShader(bounds),
                                    blendMode: BlendMode.srcIn,
                                    child: Text(
                                      'GOLD',
                                      style: GoogleFonts.playfairDisplay(
                                        fontSize: 30.sp,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  // " Family" — plain color
                                  Text(
                                    ' Family',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 30.sp,
                                      fontWeight: FontWeight.bold,
                                      color: primaryTextColor,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 12.h),
                              Text(
                                'Your Gold Journey Starts the Best Way!',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 16.sp,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 80.h),
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 200),
                          child: GestureDetector(
                            onTapDown: (_) {
                              final appControl = ref.read(appControlProvider).data;
                              if (appControl?.dynamicSwitching == true) {
                                _longPressTimer?.cancel();
                                _longPressTimer = Timer(const Duration(seconds: 5), () {
                                  final pw = appControl?.dynamicSwitchingPassword?.toString() ?? '0998';
                                  _showSecretCodeDialog(pw);
                                });
                              }
                            },
                            onTapUp: (_) => _longPressTimer?.cancel(),
                            onTapCancel: () => _longPressTimer?.cancel(),
                            behavior: HitTestBehavior.opaque,
                            child: Text(
                              'Phone Number*',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 20.sp,
                                fontWeight: FontWeight.bold,
                                color: primaryTextColor,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 16.h),
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 300),
                          child: Container(
                            height: 64.h,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(16.r),
                              border: Border.all(
                                color: primaryTextColor.withOpacity(0.1),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.03),
                                  blurRadius: 20,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            child: Row(
                              children: [
                                countryCodesAsync.when(
                                  data: (codes) => _buildCountryPicker(
                                      codes, isDark, primaryTextColor),
                                  loading: () => const SizedBox(
                                      width: 40,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2)),
                                  error: (_, __) => Text(_countryCode,
                                      style: GoogleFonts.lora(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16.sp,
                                          color: primaryTextColor)),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 8.w, vertical: 16.h),
                                  child: Container(
                                      width: 1,
                                      color: primaryTextColor.withOpacity(0.1)),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _mobileController,
                                    keyboardType: TextInputType.phone,
                                    enableInteractiveSelection: false,
                                    contextMenuBuilder: SecureClipboard.none,
                                    enableSuggestions: false,
                                    autocorrect: false,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly
                                    ],
                                    maxLength: 10,
                                    style: GoogleFonts.lora(
                                      fontSize: 18.sp,
                                      fontWeight: FontWeight.w500,
                                      color: primaryTextColor,
                                    ),
                                    onChanged: (v) {
                                      if (authState.error != null) {
                                        ref
                                            .read(
                                                authControllerProvider.notifier)
                                            .clearError();
                                      }
                                      setState(() {});
                                    },
                                    decoration: InputDecoration(
                                      hintText: 'Enter Your Phone Number',
                                      hintStyle: AppTextStyles.inputHint(isDark)
                                          .copyWith(
                                        fontSize: 16.sp,
                                        color:
                                            primaryTextColor.withOpacity(0.3),
                                      ),
                                      border: InputBorder.none,
                                      counterText: '',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Pinned Footer ───────────────────────────────────────
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 24.h),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 400),
                      child: CustomButton(
                        text: 'Initiate Secure Login',
                        svgIconPath: 'assets/buttons/login.svg',
                        isLoading: authState.isLoading,
                        onPressed: authState.isLoading
                            ? null
                            : (isValid ? _handleLogin : _showInvalidMobileError),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: isValid
                              ? const [Color(0xFF1B882C), Color(0xFF003716)]
                              : [
                                  const Color(0xFF1B882C).withOpacity(0.5),
                                  const Color(0xFF003716).withOpacity(0.5),
                                ],
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
                    SizedBox(height: 20.h),
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 500),
                      child: Center(
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 12.sp,
                              color: secondaryTextColor,
                              height: 1.6,
                            ),
                            children: [
                              const TextSpan(
                                  text: 'By Proceeding, You Accept Our '),
                              TextSpan(
                                text: 'Terms and Conditions.',
                                style: GoogleFonts.playfairDisplay(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: _termsRecognizer,
                              ),
                              const TextSpan(text: '\nand '),
                              TextSpan(
                                text: 'Privacy Policy.',
                                style: GoogleFonts.playfairDisplay(
                                  color: Colors.orangeAccent,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: _privacyRecognizer,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );    // closes PopScope
  }

  Widget _buildCountryPicker(
      List<CountryCode> codes, bool isDark, Color textColor) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        final selected = codes.firstWhere((c) => c.prefix == val);
        setState(() {
          _countryCode = val;
          _selectedCountryId = selected.id;
        });
      },
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(color: textColor.withOpacity(0.08)),
      ),
      offset: Offset(0, 48.h),
      constraints: BoxConstraints(minWidth: 160.w, maxWidth: 200.w),
      itemBuilder: (_) => codes
          .map(
            (c) => PopupMenuItem<String>(
              value: c.prefix,
              height: 44.h,
              child: Row(
                children: [
                  Text(c.flag, style: TextStyle(fontSize: 20.sp)),
                  SizedBox(width: 10.w),
                  Text(
                    c.prefix,
                    style: GoogleFonts.lora(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  if (c.prefix == _countryCode) ...[
                    const Spacer(),
                    Icon(Icons.check_rounded,
                        size: 16.sp, color: const Color(0xFF1B882C)),
                  ],
                ],
              ),
            ),
          )
          .toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // find current flag
          Builder(builder: (_) {
            final current =
                codes.firstWhere((c) => c.prefix == _countryCode,
                    orElse: () => codes.first);
            return Text(current.flag, style: TextStyle(fontSize: 20.sp));
          }),
          SizedBox(width: 6.w),
          Text(
            _countryCode,
            style: GoogleFonts.lora(
              fontWeight: FontWeight.w700,
              fontSize: 16.sp,
              color: textColor,
            ),
          ),
          SizedBox(width: 2.w),
          Icon(Icons.keyboard_arrow_down_rounded,
              size: 18.sp, color: textColor.withOpacity(0.4)),
        ],
      ),
    );
  }

  void _showInvalidMobileError() {
    final error = Validators.validateMobile(_mobileController.text) ??
        'Invalid mobile number';
    AppToast.show(context, error, type: ToastType.error);
  }

  Future<void> _handleLogin() async {
    if (_navigating) return; // prevent double-tap
    ref.read(authControllerProvider.notifier).clearError();
    final success = await ref.read(authControllerProvider.notifier).sendOtp(
          _mobileController.text,
          _countryCode,
          _selectedCountryId,
        );
    if (success && mounted && !_navigating) {
      _navigating = true;
      final authData = ref.read(authControllerProvider).data;
      // Short delay to let AppControlWrapper state updates settle and
      // release any navigator locks before we push.
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        await navigatorKey.currentState?.pushNamed(
          AppRouter.otp,
          arguments: {
            'mobile': _mobileController.text,
            'countryCode': _countryCode,
            'idCountry': _selectedCountryId,
            'otpReferenceId': authData?['otp_reference_id'] ?? '',
          },
        );
        // User navigated back from OTP screen — allow login again
        _navigating = false;
      } else {
        _navigating = false;
      }
    }
  }

  void _showSecretCodeDialog(String requiredPassword) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF666666);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        final codeController = TextEditingController();
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
            side: BorderSide(color: primaryTextColor.withOpacity(0.08)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Developer Access',
                  style: AppTextStyles.titleMedium(isDark)
                      .copyWith(color: primaryTextColor),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8.h),
                Text(
                  'Enter environment code to proceed.',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 14.sp,
                    color: secondaryTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 20.h),
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: primaryTextColor.withOpacity(0.1)),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.lora(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: primaryTextColor,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    onChanged: (val) {
                      if (val.trim() == requiredPassword) {
                        Navigator.of(context).pop();
                        _showEnvironmentSelectionDialog();
                      }
                    },
                    decoration: const InputDecoration(
                      hintText: '••••',
                      border: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
                SizedBox(height: 20.h),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.playfairDisplay(
                      color: secondaryTextColor,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEnvironmentSelectionDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);
    final secondaryTextColor = isDark ? Colors.white70 : const Color(0xFF666666);
    final currentEnv = ref.read(environmentProvider);

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          backgroundColor: bg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.r),
            side: BorderSide(color: primaryTextColor.withOpacity(0.08)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Select Environment',
                  style: AppTextStyles.titleMedium(isDark)
                      .copyWith(color: primaryTextColor),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 8.h),
                Text(
                  'Choose the target API and WebSocket server.',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 14.sp,
                    color: secondaryTextColor,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24.h),

                // Staging Button
                _buildEnvOption(
                  label: 'Staging',
                  envValue: EnvironmentService.envStaging,
                  isActive: currentEnv == EnvironmentService.envStaging,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await EnvironmentService.setEnvironment(EnvironmentService.envStaging);
                    ref.read(environmentProvider.notifier).state = EnvironmentService.envStaging;
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'Switched to Staging environment',
                        type: ToastType.success,
                      );
                    }
                  },
                ),
                SizedBox(height: 12.h),

                // Production Button
                _buildEnvOption(
                  label: 'Production',
                  envValue: EnvironmentService.envProduction,
                  isActive: currentEnv == EnvironmentService.envProduction,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await EnvironmentService.setEnvironment(EnvironmentService.envProduction);
                    ref.read(environmentProvider.notifier).state = EnvironmentService.envProduction;
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'Switched to Production environment',
                        type: ToastType.success,
                      );
                    }
                  },
                ),
                SizedBox(height: 12.h),

                // VAPT Button
                _buildEnvOption(
                  label: 'VAPT',
                  envValue: EnvironmentService.envVapt,
                  isActive: currentEnv == EnvironmentService.envVapt,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await EnvironmentService.setEnvironment(EnvironmentService.envVapt);
                    ref.read(environmentProvider.notifier).state = EnvironmentService.envVapt;
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'Switched to VAPT environment',
                        type: ToastType.success,
                      );
                    }
                  },
                ),
                SizedBox(height: 16.h),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.playfairDisplay(
                      color: secondaryTextColor,
                      fontSize: 14.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEnvOption({
    required String label,
    required String envValue,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryTextColor = isDark ? Colors.white : const Color(0xFF333333);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54.h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isActive
                ? const Color(0xFF1B882C)
                : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1)),
            width: isActive ? 2 : 1,
          ),
          color: isActive
              ? const Color(0xFF1B882C).withOpacity(0.08)
              : (isDark ? Colors.white.withOpacity(0.02) : Colors.transparent),
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          children: [
            Icon(
              isActive ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isActive ? const Color(0xFF1B882C) : Colors.grey,
              size: 20.sp,
            ),
            SizedBox(width: 12.w),
            Text(
              label,
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                color: primaryTextColor,
              ),
            ),
            if (isActive) ...[
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B882C),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                child: Text(
                  'Active',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white,
                    fontSize: 10.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
