import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../controller/auth_controller.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/fcm_service.dart';

class PinCreationScreen extends ConsumerStatefulWidget {
  final String mobile;
  final String fullName;
  final String email;
  final String dob;
  final String referralCode;
  final String tempToken;
  const PinCreationScreen({
    super.key,
    required this.mobile,
    this.fullName = '',
    this.email = '',
    this.dob = '',
    this.referralCode = '',
    this.tempToken = '',
  });

  @override
  ConsumerState<PinCreationScreen> createState() => _PinCreationScreenState();
}

class _PinCreationScreenState extends ConsumerState<PinCreationScreen> {
  bool _isConfirming = false;
  bool _registerComplete = false; // Prevents re-calling register on PIN retry
  String _pin = '';
  String _confirmPin = '';

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
    _shuffleKeypad();
  }

  void _shuffleKeypad() {
    final digits = List<String>.generate(10, (i) => '$i');
    final random = Random.secure();
    for (var i = digits.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = digits[i];
      digits[i] = digits[j];
      digits[j] = temp;
    }
    if (mounted) setState(() => _shuffledNumbers = digits);
  }

  String get _currentPin => _isConfirming ? _confirmPin : _pin;

  void _onKeyPressed(String key) {
    if (_currentPin.length < 4) {
      setState(() {
        if (_isConfirming) {
          _confirmPin += key;
        } else {
          _pin += key;
        }
      });
      // Auto-advance to confirm step when first PIN is complete
      // Auto-fire API call when confirm PIN is complete
      if (_currentPin.length == 4) {
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          if (!_isConfirming) {
            setState(() {
              _isConfirming = true;
              _confirmPin = '';
            });
            _shuffleKeypad();
          } else {
            _handleSetPin();
          }
        });
      }
    }
  }

  void _onBackspace() {
    if (_currentPin.isNotEmpty) {
      HapticFeedback.selectionClick();
      setState(() {
        if (_isConfirming) {
          _confirmPin = _confirmPin.substring(0, _confirmPin.length - 1);
        } else {
          _pin = _pin.substring(0, _pin.length - 1);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error && mounted) {
        AppToast.show(context, next.error!, type: ToastType.error);
      }
    });

    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subtitleColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable Content ──────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 16.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 22.sp, color: textColor),
                          onPressed: () {
                            if (_isConfirming) {
                              setState(() {
                                _isConfirming = false;
                                _confirmPin = '';
                              });
                              _shuffleKeypad();
                            } else {
                              NavigationUtils.safePop(context);
                            }
                          },
                        ),
                        SvgPicture.asset(
                          'assets/images/startGold.svg',
                          height: 85.h,
                          fit: BoxFit.contain,
                        ),
                      ],
                    ),
                    SizedBox(height: 24.h),

                    // Title
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        _isConfirming
                            ? 'Confirm\nYour PIN'
                            : 'Set Your\nSecurity PIN',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 28.sp,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                          height: 1.15,
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 150),
                      child: NumericStyledText(
                        _isConfirming
                            ? 'Re-enter the 4-digit PIN to confirm.'
                            : 'Create a 4-digit PIN for quick & secure access.',
                        fontSize: 14.sp,
                        color: subtitleColor,
                        fontWeight: FontWeight.w400,
                      ),
                    ),

                    SizedBox(height: 40.h),

                    // PIN Dots
                    Center(
                      child: FadeInAnimation(
                        delay: const Duration(milliseconds: 200),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(4, (index) {
                            final filled = index < _currentPin.length;
                            return TweenAnimationBuilder<double>(
                              tween: Tween(begin: 1.0, end: filled ? 1.2 : 1.0),
                              duration: const Duration(milliseconds: 200),
                              builder: (context, scale, _) => Transform.scale(
                                scale: scale,
                                child: Container(
                                  margin:
                                      EdgeInsets.symmetric(horizontal: 14.w),
                                  height: 16.w,
                                  width: 16.w,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: filled
                                        ? const Color(0xFF1B882C)
                                        : (isDark
                                            ? Colors.white.withOpacity(0.12)
                                            : Colors.black.withOpacity(0.08)),
                                    boxShadow: filled
                                        ? [
                                            BoxShadow(
                                              color: const Color(0xFF1B882C)
                                                  .withOpacity(0.5),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            )
                                          ]
                                        : [],
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ),

                    SizedBox(height: 36.h),

                    // Custom Keypad
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 300),
                      child: _buildKeypad(isDark),
                    ),

                    SizedBox(height: 24.h),
                  ],
                ),
              ),
            ),

            // ── Pinned Footer ──────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 28.h),
              child: FadeInAnimation(
                delay: const Duration(milliseconds: 400),
                child: CustomButton(
                  text: _isConfirming ? 'Complete Setup' : 'Next Step',
                  svgIconPath: 'assets/buttons/getstart.svg',
                  isLoading: authState.isLoading,
                  onPressed: () {
                    if (!_isConfirming && _pin.length == 4) {
                      setState(() {
                        _isConfirming = true;
                        _confirmPin = '';
                      });
                      _shuffleKeypad();
                    } else if (_isConfirming && _confirmPin.length == 4) {
                      _handleSetPin();
                    }
                  },
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: _currentPin.length == 4
                        ? const [Color(0xFF1B882C), Color(0xFF003716)]
                        : [
                            const Color(0xFF1B882C).withOpacity(0.45),
                            const Color(0xFF003716).withOpacity(0.45),
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypad(bool isDark) {
    return Column(
      children: [
        _buildNumRow(_shuffledNumbers.sublist(0, 3), isDark),
        SizedBox(height: 16.h),
        _buildNumRow(_shuffledNumbers.sublist(3, 6), isDark),
        SizedBox(height: 16.h),
        _buildNumRow(_shuffledNumbers.sublist(6, 9), isDark),
        SizedBox(height: 16.h),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            SizedBox(width: 68.w, height: 68.w), // spacer
            _buildKey(_shuffledNumbers[9], isDark),
            _buildBackspaceKey(isDark),
          ],
        ),
      ],
    );
  }

  Widget _buildNumRow(List<String> nums, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: nums.map((n) => _buildKey(n, isDark)).toList(),
    );
  }

  Widget _buildKey(String number, bool isDark) {
    return GestureDetector(
      onTapDown: (_) => HapticFeedback.lightImpact(),
      onTap: () => _onKeyPressed(number),
      child: Container(
        height: 68.w,
        width: 68.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withOpacity(0.06) : Colors.white,
          border: Border.all(
            color: isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            number,
            style: GoogleFonts.lora(
              fontSize: 24.sp,
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

  Widget _buildBackspaceKey(bool isDark) {
    return GestureDetector(
      onTap: _onBackspace,
      child: SizedBox(
        height: 68.w,
        width: 68.w,
        child: Center(
          child: Icon(
            Icons.backspace_outlined,
            size: 26.sp,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ),
    );
  }

  Future<void> _handleSetPin() async {
    if (_pin != _confirmPin) {
      AppToast.show(context, 'PINs do not match. Please try again.',
          type: ToastType.error);
      setState(() {
        _confirmPin = '';
        _isConfirming = true;
      });
      _shuffleKeypad();
      return;
    }

    // Step 1: Call Register API (skip if already completed on a previous attempt)
    if (!_registerComplete) {
      final registerSuccess =
          await ref.read(authControllerProvider.notifier).register(
                mobile: widget.mobile,
                fullName: widget.fullName,
                email: widget.email,
                tempToken: widget.tempToken,
                dob: widget.dob,
                referralCode: widget.referralCode,
              );

      if (!registerSuccess) {
        if (mounted) {
          AppToast.show(
              context,
              ref.read(authControllerProvider).error ??
                  'Registration failed. Please try again.',
              type: ToastType.error);
        }
        return;
      }
      _registerComplete = true;
    }

    // Step 2: Register succeeded → now create PIN
    final pinSuccess = await ref
        .read(authControllerProvider.notifier)
        .setPin(widget.mobile, _pin);

    if (pinSuccess && mounted) {
      // Persist MPIN flag so splash/OTP routes know PIN is set
      await SecureStorageService.setMpinEnabled(true);

      // Register FCM token with server after successful new-user registration.
      // Fire-and-forget — never blocks navigation.
      _registerFcmToken();

      if (widget.fullName.isNotEmpty) {
        Navigator.pushReplacementNamed(
          context,
          AppRouter.registrationSuccess,
          arguments: {'fullName': widget.fullName},
        );
      } else {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRouter.home, (route) => false);
      }
    } else if (mounted) {
      // PIN creation failed → reset to first step so user can retry
      AppToast.show(
          context, 'Failed to set PIN. Please try again.',
          type: ToastType.error);
      setState(() {
        _pin = '';
        _confirmPin = '';
        _isConfirming = false;
      });
      _shuffleKeypad();
    }
  }
  /// Registers FCM device token with the server after new-user registration.
  /// Fire-and-forget — errors are swallowed so registration is never blocked.
  void _registerFcmToken() {
    final notifService = NotificationService();
    Future(() async {
      try {
        final token = await FcmService.getToken();
        if (token != null) {
          await notifService.registerFcmToken(token);
          if (kDebugMode) debugPrint('[FCM] Token registered after new-user registration.');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[FCM] Token registration skipped during registration: $e');
      }
    });
  }
}
