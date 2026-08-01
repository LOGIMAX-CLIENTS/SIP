import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/theme/app_text_styles.dart';
import 'package:pinput/pinput.dart';
import '../controller/auth_controller.dart';

import '../../../routes/app_router.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/animations.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/secure_clipboard.dart';
import '../../../core/services/auth_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../core/localization/language_provider.dart';

class PinScreen extends ConsumerStatefulWidget {
  final String mobile;
  const PinScreen({super.key, required this.mobile});

  @override
  ConsumerState<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends ConsumerState<PinScreen> {
  final _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
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

    final defaultPinTheme = PinTheme(
      width: 64.w,
      height: 72.h,
      textStyle: GoogleFonts.lora(
        fontSize: 32.sp,
        fontWeight: FontWeight.w800,
        color: isDark ? Colors.white : const Color(0xFF0F172A),
      ),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.04),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
            color: isDark ? Colors.white12 : Colors.black12, width: 1),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24.w),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top -
                        MediaQuery.of(context).padding.bottom,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.h),
                        IconButton(
                          icon: Icon(Icons.arrow_back_ios_new_rounded,
                              size: 22.sp),
                          onPressed: () => NavigationUtils.safePop(context),
                        ),
                        SizedBox(height: 32.h),
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 100),
                          child: Text(
                            ref.tr('welcomeBack'),
                            style: AppTextStyles.displayLarge(isDark).copyWith(
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                              height: 1.15,
                            ),
                          ),
                        ),
                        SizedBox(height: 16.h),
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 200),
                          child: Text(
                            ref.tr('pinSubtitle'),
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 17.sp,
                              color: isDark ? Colors.white54 : Colors.black45,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),
                        SizedBox(height: 80.h),
                        Center(
                          child: FadeInAnimation(
                            delay: const Duration(milliseconds: 300),
                            child: Pinput(
                              length: 4,
                              controller: _pinController,
                              keyboardType: TextInputType.number,
                              contextMenuBuilder: SecureClipboard.none,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              obscureText: true,
                              defaultPinTheme: defaultPinTheme,
                              focusedPinTheme: defaultPinTheme.copyWith(
                                decoration:
                                    defaultPinTheme.decoration!.copyWith(
                                  color: isDark
                                      ? AppTheme.primaryGreen.withOpacity(0.08)
                                      : Colors.white,
                                  border: Border.all(
                                      color: AppTheme.primaryGreen, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          AppTheme.primaryGreen.withOpacity(0.12),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                              ),
                              onCompleted: _handleVerifyPin,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FadeInAnimation(
                          delay: const Duration(milliseconds: 400),
                          child: CustomButton(
                            text: ref.tr('secureAccess'),
                            svgIconPath: 'assets/buttons/login.svg',
                            isLoading: authState.isLoading,
                            loadingText: 'Verifying...',
                            onPressed: _pinController.text.length == 4
                                ? () => _handleVerifyPin(_pinController.text)
                                : null,
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: _pinController.text.length == 4
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
                        SizedBox(height: 24.h),
                      ],
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleVerifyPin(String pin) async {
    try {
      final success = await ref
          .read(authControllerProvider.notifier)
          .verifyPin(widget.mobile, pin);

      if (success && mounted) {
        Navigator.pushNamedAndRemoveUntil(
            context, AppRouter.home, (route) => false);
      } else {
        _pinController.clear();
      }
    } catch (e) {
      if (mounted) _pinController.clear();
    }
  }
}

