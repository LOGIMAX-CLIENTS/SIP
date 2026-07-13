import 'dart:math';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/numeric_styled_text.dart';
import '../../core/security/screenshot_security_service.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/services/mpin_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/fcm_service.dart';
import '../../core/security/secure_storage_service.dart';
import '../../routes/app_router.dart';
import '../../shared/theme/app_theme.dart';
import 'package:local_auth/local_auth.dart';
import '../../../core/constants/app_constants.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/custom_button.dart';
import '../../shared/widgets/app_toast.dart';

class MpinScreen extends ConsumerStatefulWidget {
  const MpinScreen({super.key});

  @override
  ConsumerState<MpinScreen> createState() => _MpinScreenState();
}

class _MpinScreenState extends ConsumerState<MpinScreen>
    with WidgetsBindingObserver {
  bool _isMpinEnabledCount = false;
  bool _isBiometricEnabled = false;
  bool _isLoadingStatus = true;
  DateTime? _lastBackPressTime; // tracks double-tap-to-exit timing
  final LocalAuthentication _localAuth = LocalAuthentication();
  List<String> _shuffledNumbers = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '0'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      ref.read(mpinProvider.notifier).clear();
    });
    // Defer to post-frame so ModalRoute.of(context) is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadMpinStatus();
    });
    _shuffleKeypad();
    _secureScreen();
  }

  Future<void> _loadMpinStatus() async {
    final enabled = await SecureStorageService.isMpinEnabled();

    // Use BiometricService.canUseBiometric() which:
    //  • checks getAvailableBiometrics() (not just hardware presence)
    //  • auto-disables storage flag if device biometrics were removed
    final canBio = await BiometricService.canUseBiometric();

    if (kDebugMode) {
      debugPrint('── MPIN Screen Status ──');
      debugPrint('  mpinEnabled: $enabled');
      debugPrint('  canUseBiometric: $canBio');
      debugPrint('── End ──');
    }

    if (mounted) {
      setState(() {
        _isMpinEnabledCount  = enabled;
        _isBiometricEnabled  = canBio;
        _isLoadingStatus     = false;
      });

      // Auto-trigger biometric on app open — skip for withdrawal/verify_only
      // Also skip for app_lock since AppLifecycleObserver already attempted
      // biometric before pushing this screen.
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
              {};
      final String? type = args['type'];

      if (_isBiometricEnabled &&
          _isMpinEnabledCount &&
          type != 'withdrawal_pin' &&
          type != 'verify_only' &&
          type != 'app_lock' &&
          type != 'verify_after_reset') {
        _authenticateBiometric();
      }
    }
  }

  Future<void> _authenticateBiometric() async {
    try {
      final didAuthenticate = await BiometricService.authenticate(
        reason: 'Please authenticate to unlock the app',
      );

      if (didAuthenticate && mounted) {
        final args = ModalRoute.of(context)!.settings.arguments
                as Map<String, dynamic>? ??
            {};
        final String? type = args['type'];

        if (type == 'authorize_withdrawal') {
          _showSuccessDialog();
        } else if (type == 'verify_only') {
          Navigator.pop(context, true);
        } else if (type == 'app_lock') {
          // App lock: pop back to the previous screen (preserve nav stack)
          Navigator.pop(context, true);
        } else {
          Navigator.pushNamedAndRemoveUntil(
              context, AppRouter.main, (route) => false);
        }
      }
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('Biometric Auth Error: $e');
      // Fallback: user can use MPIN keypad naturally.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _shuffleKeypad();
    }
  }

  void _shuffleKeypad() {
    final List<String> digits = [
      '0',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9'
    ];
    // Use Random.secure() for banking-grade security
    final random = Random.secure();
    for (var i = digits.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = digits[i];
      digits[i] = digits[j];
      digits[j] = temp;
    }
    if (mounted) {
      setState(() {
        _shuffledNumbers = List.from(digits);
      });
    }
    if (kDebugMode) debugPrint('MPIN Numpad Randomized');
  }

  Future<void> _secureScreen() async {
    await ScreenshotSecurityService.secureScreen();
  }

  Future<void> _releaseScreen() async {
    await ScreenshotSecurityService.releaseScreen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _releaseScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingStatus) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final mpinState = ref.watch(mpinProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<MpinState>(mpinProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        // Session expired (401/403/409) — redirect to login
        if (next.error == 'SESSION_EXPIRED') {
          AppToast.show(
            context,
            'Session expired. Please login again.',
            type: ToastType.error,
          );
          // Clear storage & navigate to login
          SecureStorageService.logout().then((_) {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRouter.login,
                (route) => false,
              );
            }
          });
        } else {
          AppToast.show(context, next.error!, type: ToastType.error);
        }
      }
    });

    // Auto-submit when 4 digits entered for login / reset flows.
    // Withdrawal stays manual (user must consciously tap Confirm).
    // Setup stays manual (user reviews before activating PIN).
    ref.listen<MpinState>(mpinProvider, (prev, next) {
      if (next.isComplete && !(prev?.isComplete ?? false) && !next.isLocked) {
        final args = ModalRoute.of(context)?.settings.arguments
                as Map<String, dynamic>? ??
            {};
        final String? type = args['type'];
        // Auto-submit for all verify modes when 4 digits are entered
        if (type == null || type == 'reset_pin' || type == 'withdrawal_pin' || type == 'app_lock' || type == 'verify_only' || type == 'verify_after_reset') {
          _handleAction();
        }
      }
    });

    // Determine if this is a root/exit-eligible screen:
    // login verify (no type), setup — back should exit the app.
    // Sub-flows (withdrawal_pin, verify_only, reset_pin) — back pops normally.
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
            {};
    final String? screenType = args['type'];
    final bool isFromAppLock = args['from_app_lock'] == true;
    final bool isRootFlow =
        screenType == null || screenType == 'setup' || screenType == 'app_lock'
        || (screenType == 'reset_pin' && isFromAppLock)
        || screenType == 'verify_after_reset';

    return PopScope(
      // Sub-flows: allow normal pop. Root flows: we handle it.
      canPop: !isRootFlow,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !isRootFlow) return; // sub-flow handled by Flutter

        // App lock / reset_pin from app_lock / verify_after_reset:
        // block ALL back navigation — user must authenticate
        if (screenType == 'app_lock' ||
            (screenType == 'reset_pin' && isFromAppLock) ||
            screenType == 'verify_after_reset') {
          if (mounted) {
            AppToast.show(
              context,
              'Please verify your PIN to continue',
              type: ToastType.info,
            );
          }
          return;
        }

        // Login/setup root flow: double-tap to exit app
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
        backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 2. Animated Background Aurora Orbs (Abstract Luxury)
          if (isDark) ...[
            _buildAuroraOrb(
                top: -100.h,
                right: -100.w,
                color: AppTheme.arcticBlue.withOpacity(0.12),
                size: 450.w),
            _buildAuroraOrb(
                bottom: -150.h,
                left: -100.w,
                color: AppTheme.auroraPurple.withOpacity(0.08),
                size: 500.w),
          ],

          SafeArea(
            bottom: true,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.symmetric(horizontal: 24.w),
                    child: Column(
                      key: ValueKey(_shuffledNumbers.join()),
                      children: [
                        SizedBox(height: 32.h),

                        // Center-Aligned Luxury Branding
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 100),
                          child: Center(
                            child: SvgPicture.asset(
                              'assets/images/startGold.svg',
                              height: 85.h,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),

                        SizedBox(height: 24.h),

                        // 3. Luxury Branding Header
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 100),
                          child: Builder(builder: (context) {
                            final args = ModalRoute.of(context)
                                    ?.settings
                                    .arguments as Map<String, dynamic>? ??
                                {};
                            final String? routeType = args['type'];

                            final isWithdrawal =
                                routeType == 'withdrawal_pin' ||
                                    routeType == 'authorize_withdrawal';
                            final isBiometric = routeType == 'verify_only';
                            final isSetup = routeType == 'setup';
                            final isReset = routeType == 'reset_pin';
                            final isVerifyAfterReset = routeType == 'verify_after_reset';

                            final String title = isWithdrawal
                                ? AppConstants.mpinWithdrawalTitle
                                : isBiometric
                                    ? AppConstants.mpinBiometricTitle
                                    : isSetup
                                        ? 'Set Your PIN'
                                        : isReset
                                            ? 'Reset Your PIN'
                                            : isVerifyAfterReset
                                                ? 'Verify New PIN'
                                                : AppConstants.mpinTitle;

                            final String subtitle = isWithdrawal
                                ? AppConstants.mpinWithdrawalSubtitle
                                : isBiometric
                                    ? AppConstants.mpinBiometricSubtitle
                                    : isSetup
                                        ? 'Create a 6-digit PIN for quick & secure access.'
                                        : isReset
                                            ? 'Enter your new 6-digit security PIN.'
                                            : isVerifyAfterReset
                                                ? 'Enter your new PIN to confirm & unlock.'
                                                : AppConstants.mpinSubtitle;

                            return Column(
                              children: [
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 24.sp,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 2,
                                    color: isDark
                                        ? Colors.white
                                        : const Color(0xFF1E293B),
                                  ),
                                ),
                                SizedBox(height: 8.h),
                                NumericStyledText(
                                  subtitle,
                                  textAlign: TextAlign.center,
                                  fontSize: 14.sp,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black45,
                                  fontWeight: FontWeight.w400,
                                ),
                              ],
                            );
                          }),
                        ),

                        SizedBox(height: 16.h),

                        // 4. Premium Glowing PIN Indicators
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 300),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(MpinNotifier.pinLength, (index) {
                              bool filled = index < mpinState.mpin.length;
                              return TweenAnimationBuilder<double>(
                                tween:
                                    Tween(begin: 1.0, end: filled ? 1.2 : 1.0),
                                duration: const Duration(milliseconds: 200),
                                builder: (context, scale, child) {
                                  return Transform.scale(
                                    scale: scale,
                                    child: Container(
                                      margin: EdgeInsets.symmetric(
                                          horizontal: 14.w),
                                      height: 16.w,
                                      width: 16.w,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: filled
                                            ? AppTheme.arcticBlue
                                            : (isDark
                                                ? Colors.white.withOpacity(0.1)
                                                : Colors.black
                                                    .withOpacity(0.05)),
                                        boxShadow: filled
                                            ? [
                                                BoxShadow(
                                                  color: AppTheme.arcticBlue
                                                      .withOpacity(0.6),
                                                  blurRadius: 20,
                                                  spreadRadius: 2,
                                                ),
                                                BoxShadow(
                                                  color: Colors.white
                                                      .withOpacity(0.2),
                                                  blurRadius: 5,
                                                )
                                              ]
                                            : [],
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),
                          ),
                        ),

                        SizedBox(height: 20.h),

                        // 5. Number Keypad
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 400),
                          child: Padding(
                            key: UniqueKey(),
                            padding: EdgeInsets.symmetric(horizontal: 16.w),
                            child: Column(
                              children: [
                                _buildNumRow(_shuffledNumbers.sublist(0, 3)),
                                SizedBox(height: 16.h),
                                _buildNumRow(_shuffledNumbers.sublist(3, 6)),
                                SizedBox(height: 16.h),
                                _buildNumRow(_shuffledNumbers.sublist(6, 9)),
                                SizedBox(height: 16.h),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceEvenly,
                                  children: [
                                    _buildBiometricHint(),
                                    _buildNumberKey(_shuffledNumbers[9]),
                                    _buildBackspaceKey(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(height: 16.h),
                      ],
                    ),
                  ),
                ),

                // 8. CTA Section
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                  child: FadeInAnimation(
                    delay: const Duration(milliseconds: 500),
                    child: Builder(
                      builder: (context) {
                        // Read the route type to know which context we're in
                        final args = ModalRoute.of(context)?.settings.arguments
                                as Map<String, dynamic>? ??
                            {};
                        final String? routeType = args['type'];

                        // "Forgot PIN?" is only relevant during app-unlock.
                        // Hide it when opened from Profile (verify_only) or
                        // from Withdrawal (authorize_withdrawal).
                        // "Forgot PIN?" only in unlock mode (no route type)
                        final bool showForgotPin = routeType == null || routeType == 'app_lock';

                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CustomButton(
                              text: routeType == 'withdrawal_pin' ||
                                      routeType == 'authorize_withdrawal'
                                  ? 'CONFIRM WITHDRAWAL'
                                  : routeType == 'verify_only'
                                      ? 'VERIFY IDENTITY'
                                      : routeType == 'setup'
                                          ? 'ACTIVATE SECURE PIN'
                                          : routeType == 'reset_pin'
                                              ? 'RESET PIN'
                                              : routeType == 'verify_after_reset'
                                                  ? 'VERIFY PIN'
                                                  : 'UNLOCK APP',
                              svgIconPath: 'assets/buttons/security-user.svg',
                              isLoading: mpinState.isLoading,
                              onPressed:
                                  (mpinState.isComplete && !mpinState.isLocked)
                                      ? _handleAction
                                      : null,
                              gradient: LinearGradient(
                                begin: Alignment.centerLeft,
                                end: Alignment.centerRight,
                                colors: routeType == 'withdrawal_pin' ||
                                        routeType == 'authorize_withdrawal'
                                    ? (mpinState.isComplete
                                        ? const [
                                            Color(0xFF1B882C),
                                            Color(0xFF003716)
                                          ]
                                        : [
                                            Color(0xFF1B882C).withOpacity(0.4),
                                            Color(0xFF003716).withOpacity(0.4)
                                          ])
                                    : (mpinState.isComplete
                                        ? const [
                                            Color(0xFF1B882C),
                                            Color(0xFF003716)
                                          ]
                                        : [
                                            Color(0xFF1B882C).withOpacity(0.35),
                                            Color(0xFF003716).withOpacity(0.35)
                                          ]),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      const Color(0xFF8F4C05).withOpacity(0.06),
                                  offset: const Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ],
                              textColor: Colors.white,
                            ),
                            if (showForgotPin) ...[
                              SizedBox(height: 28.h),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.verified_user_outlined,
                                      size: 16.sp,
                                      color: AppTheme.electricCyan),
                                  SizedBox(width: 10.w),
                                  GestureDetector(
                                    onTap: _handleForgotPin,
                                    child: Text(
                                      'Forgot PIN?',
                                      style: GoogleFonts.playfairDisplay(
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),    // closes Scaffold (child of PopScope)
    );      // closes PopScope
  }

  Widget _buildAuroraOrb(
      {double? top,
      double? right,
      double? bottom,
      double? left,
      required Color color,
      required double size}) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }

  Widget _buildBiometricHint() {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
            {};
    final String? type = args['type'];

    // Hide biometric icon for withdrawal (must use MPIN), verify_only, and verify_after_reset
    if (!_isBiometricEnabled ||
        !_isMpinEnabledCount ||
        type == 'withdrawal_pin' ||
        type == 'verify_only' ||
        type == 'verify_after_reset') {
      return SizedBox(height: 60.w, width: 60.w);
    }

    return GestureDetector(
      onTap: _authenticateBiometric,
      child: SizedBox(
        height: 60.w,
        width: 60.w,
        child: Center(
            child: Icon(Icons.fingerprint,
                color: AppTheme.arcticBlue.withOpacity(0.8), size: 32.sp)),
      ),
    );
  }

  Future<void> _handleAction() async {
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>? ??
            {};
    final String? type = args['type'];

    if (type == 'setup') {
      // ── SETUP MODE → POST /mpin/create ──
      // User registered but PIN was never created (interrupted flow)
      final success = await ref.read(mpinProvider.notifier).setMpin();
      if (success && mounted) {
        await SecureStorageService.setMpinEnabled(true);
        Navigator.pushNamedAndRemoveUntil(
            context, AppRouter.main, (route) => false);
      } else {
        _shuffleKeypad();
      }
    } else if (type == 'reset_pin') {
      // ── RESET MODE → POST /mpin/reset ──
      // User verified identity via OTP, now setting a new PIN
      final tempToken = args['temp_token'] ?? '';
      final mobile = args['mobile'] as String?;
      final bool fromAppLock = args['from_app_lock'] == true;
      final success = await ref
          .read(mpinProvider.notifier)
          .resetMpin(tempToken, mobile: mobile);
      if (success && mounted) {
        await SecureStorageService.setMpinEnabled(true);
        if (fromAppLock) {
          // App lock flow: use verify_after_reset (no Forgot PIN, back blocked)
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRouter.mpin,
            (route) => false,
            arguments: {
              'type': 'verify_after_reset',
              'mobile': mobile,
            },
          );
        } else {
          // Normal flow: navigate to MPIN verify
          Navigator.pushReplacementNamed(
            context,
            AppRouter.mpin,
            arguments: {'mobile': mobile},
          );
        }
      } else {
        _shuffleKeypad();
      }
    } else {
      // ── VERIFY MODE → POST /mpin/validate ──
      // App unlock, withdrawal authorization, biometric verification, app lock
      final success = await ref.read(mpinProvider.notifier).verifyMpin();
      if (success && mounted) {
        await SecureStorageService.setMpinEnabled(true);
        if (type == 'authorize_withdrawal') {
          _showSuccessDialog();
        } else if (type == 'withdrawal_pin') {
          final pin = ref.read(mpinProvider).mpin;
          Navigator.pop(context, pin);
        } else if (type == 'verify_only') {
          Navigator.pop(context, true);
        } else if (type == 'app_lock') {
          // App lock: pop back — user resumes where they left off
          Navigator.pop(context, true);
        } else if (type == 'verify_after_reset') {
          // After forgot-PIN reset from app_lock: go to home
          _registerFcmTokenAfterLogin();
          Navigator.pushNamedAndRemoveUntil(
              context, AppRouter.main, (route) => false);
        } else {
          // ── Register FCM token with server on successful login ──────────
          // Fire-and-forget: never blocks navigation.
          _registerFcmTokenAfterLogin();
          Navigator.pushNamedAndRemoveUntil(
              context, AppRouter.main, (route) => false);
        }
      } else {
        _shuffleKeypad();
      }
    }
  }

  /// Called after successful MPIN login before navigating to main.
  /// Gets the FCM device token and registers it with the backend.
  /// Completely fire-and-forget — errors are swallowed so login is never blocked.
  void _registerFcmTokenAfterLogin() {
    final notifService = NotificationService();
    Future(() async {
      try {
        // FcmService.getToken() requires Firebase to be initialized.
        // Once Firebase is set up (Step 1 of FCM guide), this will return the token.
        final token = await FcmService.getToken();
        if (token != null) {
          await notifService.registerFcmToken(token);
        }
      } catch (e) {
        // Non-fatal — Firebase may not be set up yet.
        if (kDebugMode) debugPrint('[FCM] Token registration skipped: $e');
      }
    });
  }

  /// Forgot PIN flow: Send OTP → verify identity → reset PIN
  Future<void> _handleForgotPin() async {
    final mobile = await SecureStorageService.getMobile();
    if (mobile == null || mobile.isEmpty) {
      if (mounted) {
        AppToast.show(context, 'Unable to verify identity. Please login again.',
            type: ToastType.error);
        Navigator.pushReplacementNamed(context, AppRouter.login);
      }
      return;
    }

    // Determine if we're in app_lock mode
    final currentArgs =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
            {};
    final bool isAppLock = currentArgs['type'] == 'app_lock';

    // Show loading
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      final authService = AuthService();
      final result = await authService.sendOtp(
        mobile: mobile,
        countryCode: '+91',
        idCountry: '101',
        type: 'FORGOT_PIN',
      );

      if (mounted) Navigator.pop(context); // dismiss loading

      if (result['success'] == true && mounted) {
        final otpRefId = result['data']?['otp_reference_id'] ?? '';

        if (isAppLock) {
          // App lock: use pushNamedAndRemoveUntil to prevent swiping back to home
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRouter.otp,
            (route) => false,
            arguments: {
              'mobile': mobile,
              'countryCode': '+91',
              'idCountry': '101',
              'otpReferenceId': otpRefId,
              'actionType': 'forgot_pin',
              'from_app_lock': true,
            },
          );
        } else {
          Navigator.pushReplacementNamed(
            context,
            AppRouter.otp,
            arguments: {
              'mobile': mobile,
              'countryCode': '+91',
              'idCountry': '101',
              'otpReferenceId': otpRefId,
              'actionType': 'forgot_pin',
            },
          );
        }
      } else if (mounted) {
        AppToast.show(context, result['message'] ?? 'Failed to send OTP.',
            type: ToastType.error);
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // dismiss loading
      if (mounted) {
        AppToast.show(context, 'Failed to send OTP. Please try again.',
            type: ToastType.error);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 16.h),
            Container(
              padding: EdgeInsets.all(16.r),
              decoration: BoxDecoration(
                  color: Colors.greenAccent.withOpacity(0.1),
                  shape: BoxShape.circle),
              child: Icon(Icons.check_circle_rounded,
                  color: Colors.greenAccent[400], size: 48.sp),
            ),
            SizedBox(height: 24.h),
            Text('Withdrawal Successful',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20.sp, fontWeight: FontWeight.w900)),
            SizedBox(height: 12.h),
            Text(
                'Your funds will be credited to your account within 24-48 hours.',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.playfairDisplay(fontSize: 14.sp, color: Colors.black54)),
            SizedBox(height: 32.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pushNamedAndRemoveUntil(
                    context, AppRouter.main, (route) => false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.arcticBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                ),
                child: const Text('BACK TO HOME',
                    style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNumRow(List<String> numbers) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: numbers.map((n) => _buildNumberKey(n)).toList(),
    );
  }

  Widget _buildNumberKey(String number) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => HapticFeedback.lightImpact(),
      onTap: () {
        ref.read(mpinProvider.notifier).addKey(number);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 64.w,
        width: 64.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.white.withOpacity(0.01)
                  : Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            number,
            style: GoogleFonts.lora(
              fontSize: 28.sp,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? Colors.white.withOpacity(0.9)
                  : const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        ref.read(mpinProvider.notifier).backspace();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 60.w,
        width: 60.w,
        child: Center(
          child: Icon(
            Icons.backspace_outlined,
            size: 26.sp,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
      ),
    );
  }
}
