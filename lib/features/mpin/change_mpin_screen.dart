import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../shared/widgets/numeric_styled_text.dart';

import '../../core/services/mpin_service.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/animations.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/gradient_header.dart';

enum _ChangePinStep { enterOld, enterNew, confirmNew }

class ChangeMpinScreen extends ConsumerStatefulWidget {
  const ChangeMpinScreen({super.key});

  @override
  ConsumerState<ChangeMpinScreen> createState() => _ChangeMpinScreenState();
}

class _ChangeMpinScreenState extends ConsumerState<ChangeMpinScreen> {
  _ChangePinStep _step = _ChangePinStep.enterOld;
  String _oldPin = '';
  String _newPin = '';
  String _currentInput = '';
  bool _isLoading = false;

  List<String> _shuffledNumbers = ['1','2','3','4','5','6','7','8','9','0'];

  @override
  void initState() {
    super.initState();
    _shuffleKeypad();
  }

  void _shuffleKeypad() {
    final digits = List<String>.generate(10, (i) => '$i');
    digits.shuffle();
    setState(() => _shuffledNumbers = digits);
  }

  String get _stepTitle {
    switch (_step) {
      case _ChangePinStep.enterOld: return 'Enter Current PIN';
      case _ChangePinStep.enterNew: return 'Enter New PIN';
      case _ChangePinStep.confirmNew: return 'Confirm New PIN';
    }
  }

  String get _stepSubtitle {
    switch (_step) {
      case _ChangePinStep.enterOld: return 'Enter your existing 6-digit MPIN.';
      case _ChangePinStep.enterNew: return 'Choose a new 6-digit PIN.';
      case _ChangePinStep.confirmNew: return 'Re-enter your new PIN to confirm.';
    }
  }

  void _onKeyPressed(String key) {
    if (_currentInput.length < MpinNotifier.pinLength) {
      setState(() {
        _currentInput += key;
      });
      if (_currentInput.length == MpinNotifier.pinLength) {
        Future.delayed(const Duration(milliseconds: 200), _processStep);
      }
    }
  }

  void _onBackspace() {
    if (_currentInput.isNotEmpty) {
      setState(() => _currentInput = _currentInput.substring(0, _currentInput.length - 1));
    }
  }

  Future<void> _processStep() async {
    switch (_step) {
      case _ChangePinStep.enterOld:
        setState(() {
          _oldPin = _currentInput;
          _currentInput = '';
          _step = _ChangePinStep.enterNew;
        });
        _shuffleKeypad();
        break;

      case _ChangePinStep.enterNew:
        if (_currentInput == _oldPin) {
          setState(() { _currentInput = ''; });
          _shuffleKeypad();
          AppToast.show(context, 'New PIN must be different from current PIN.', type: ToastType.error);
          return;
        }
        setState(() {
          _newPin = _currentInput;
          _currentInput = '';
          _step = _ChangePinStep.confirmNew;
        });
        _shuffleKeypad();
        break;

      case _ChangePinStep.confirmNew:
        if (_currentInput != _newPin) {
          setState(() {
            _currentInput = '';
            _step = _ChangePinStep.enterNew;
          });
          _shuffleKeypad();
          AppToast.show(context, 'PINs do not match. Try again.', type: ToastType.error);
          return;
        }
        setState(() => _isLoading = true);
        try {
          final service = ref.read(mpinServiceProvider);
          await service.changeMpin(_oldPin, _newPin);
          if (mounted) _showSuccessAndPop();
        } catch (e) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _currentInput = '';
              _oldPin = '';
              _newPin = '';
              _step = _ChangePinStep.enterOld;
            });
            _shuffleKeypad();
            final msg = e.toString().replaceFirst('Exception: ', '');
            AppToast.show(context, msg, type: ToastType.error);
          }
        }
        break;
    }
  }

  void _showSuccessAndPop() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.r)),
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
                  color: AppTheme.primaryGreen, size: 48.sp),
            ),
            SizedBox(height: 20.h),
            Text('PIN Changed!',
                style: GoogleFonts.playfairDisplay(
                    fontSize: 20.sp, fontWeight: FontWeight.w900)),
            SizedBox(height: 8.h),
            Text('Your MPIN has been updated successfully.',
                textAlign: TextAlign.center,
                style: GoogleFonts.playfairDisplay(fontSize: 14.sp, color: Colors.black54)),
            SizedBox(height: 28.h),
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.greenGradient,
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r)),
                  ),
                  child: const Text('Done', style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(title: 'Change MPIN'),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(height: 40.h),
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        _stepTitle,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 24.sp,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    SizedBox(height: 8.h),
                    FadeInAnimation(
                      delay: const Duration(milliseconds: 150),
                      child: NumericStyledText(
                        _stepSubtitle,
                        fontSize: 14.sp,
                        color: isDark ? Colors.white38 : Colors.black45,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: 48.h),
                    // Step indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [1, 2, 3].map((s) {
                        final idx = s - 1;
                        final currentIdx = _ChangePinStep.values.indexOf(_step);
                        final isActive = idx <= currentIdx;
                        return Container(
                          margin: EdgeInsets.symmetric(horizontal: 4.w),
                          width: isActive ? 24.w : 8.w,
                          height: 8.w,
                          decoration: BoxDecoration(
                            color: isActive ? AppTheme.primaryGreen : Colors.grey.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        );
                      }).toList(),
                    ),
                    SizedBox(height: 40.h),
                    // PIN Dots
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(MpinNotifier.pinLength, (index) {
                        final filled = index < _currentInput.length;
                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 1.0, end: filled ? 1.2 : 1.0),
                          duration: const Duration(milliseconds: 200),
                          builder: (context, scale, _) => Transform.scale(
                            scale: scale,
                            child: Container(
                              margin: EdgeInsets.symmetric(horizontal: 12.w),
                              height: 16.w,
                              width: 16.w,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: filled
                                    ? AppTheme.primaryGreen
                                    : (isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.08)),
                                boxShadow: filled
                                    ? [BoxShadow(color: AppTheme.primaryGreen.withOpacity(0.5), blurRadius: 12, spreadRadius: 2)]
                                    : [],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    SizedBox(height: 32.h),
                    // Keypad
                    _buildKeypad(isDark),
                    if (_isLoading) ...[
                      SizedBox(height: 16.h),
                      CircularProgressIndicator(color: AppTheme.primaryGreen),
                    ],
                    SizedBox(height: 32.h),
                  ],
                ),
              ),
            ),
          ),
        ],
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
            SizedBox(width: 72.w, height: 72.w),
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
        height: 72.w,
        width: 72.w,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Center(
          child: Text(
            number,
            style: GoogleFonts.lora(
              fontSize: 26.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white.withOpacity(0.9) : const Color(0xFF0F172A),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackspaceKey(bool isDark) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); _onBackspace(); },
      child: SizedBox(
        height: 72.w,
        width: 72.w,
        child: Center(
          child: Icon(Icons.backspace_outlined,
              size: 26.sp, color: isDark ? Colors.white38 : Colors.black38),
        ),
      ),
    );
  }
}
