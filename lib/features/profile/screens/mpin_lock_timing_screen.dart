import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_config.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../routes/app_router.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../services/profile_service.dart';

/// Profile > Security > "MPIN & Biometric Timing".
///
/// Two server-configurable settings live here (APP_CONTROL_MPIN_LOCK, see
/// AppControlProvider):
///   1. How long the app must sit in the background before AppLifecycleObserver
///      shows the MPIN/biometric lock screen on resume. The customer's choice
///      is persisted server-side (Customer.cus_mpin_lock_timeout_seconds via
///      ProfileService.setMpinLockTimeout — profile/mpin-lock-timing) so it
///      syncs across their devices, with the local SecureStorageService copy
///      kept in sync as an instant-read cache for AppLifecycleObserver.
///   2. Biometric unlock — hidden entirely if the server kill-switch
///      (AppConfig.biometricLoginEnabled) is off, regardless of the
///      customer's own local toggle. Stays a per-device local setting.
class MpinLockTimingScreen extends ConsumerStatefulWidget {
  const MpinLockTimingScreen({super.key});

  @override
  ConsumerState<MpinLockTimingScreen> createState() =>
      _MpinLockTimingScreenState();
}

class _MpinLockTimingScreenState extends ConsumerState<MpinLockTimingScreen> {
  int _selectedTimeoutSeconds = AppConfig.mpinLockDefaultTimeoutSeconds;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final storedTimeout = await SecureStorageService.getMpinLockTimeoutSeconds();
    final hasDevice = await BiometricService.deviceHasBiometric();
    final canUse = hasDevice && await BiometricService.canUseBiometric();
    if (mounted) {
      setState(() {
        _selectedTimeoutSeconds = storedTimeout;
        _biometricAvailable = hasDevice;
        _biometricEnabled = canUse;
        _loading = false;
      });
    }
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return 'Immediately';
    if (seconds < 60) return '$seconds sec';
    final minutes = seconds ~/ 60;
    if (minutes < 60) return minutes == 1 ? '1 min' : '$minutes min';
    final hours = minutes ~/ 60;
    return hours == 1 ? '1 hour' : '$hours hours';
  }

  Future<void> _onSelectTimeout(int seconds) async {
    // Local cache updates immediately — AppLifecycleObserver reads this
    // synchronously and must never wait on the network.
    await SecureStorageService.setMpinLockTimeoutSeconds(seconds);
    if (mounted) setState(() => _selectedTimeoutSeconds = seconds);

    final synced = await ref.read(profileServiceProvider).setMpinLockTimeout(seconds);
    if (!synced && mounted) {
      AppToast.show(
        context,
        'Saved on this device, but could not sync to your account. Check your connection.',
        type: ToastType.error,
      );
    }
  }

  Future<void> _onBiometricToggle(bool newValue) async {
    if (newValue) {
      final check = await BiometricService.checkBeforeEnable();
      if (check == BiometricCheckResult.noneEnrolled) {
        if (mounted) {
          AppToast.show(
            context,
            'No biometric found in device. Please enroll a fingerprint or face in your phone settings.',
            type: ToastType.error,
          );
        }
        return;
      }
      if (check == BiometricCheckResult.notSupported) {
        if (mounted) {
          AppToast.show(
            context,
            'Biometric authentication is not supported on this device.',
            type: ToastType.error,
          );
        }
        return;
      }

      final verified = await Navigator.pushNamed(
        context,
        AppRouter.mpin,
        arguments: {'type': 'verify_only'},
      );
      if (verified != true) return;

      final enrolled = await BiometricService.authenticate(
        reason: 'Confirm biometrics to enable this feature',
      );
      if (!enrolled) return;
    }

    await SecureStorageService.setBiometricEnabled(newValue);
    if (newValue) await SecureStorageService.setMpinEnabled(true);
    if (mounted) setState(() => _biometricEnabled = newValue);

    final msg = newValue
        ? 'Biometric authentication enabled'
        : 'Biometric authentication disabled';
    if (mounted) {
      AppToast.show(context, msg,
          type: newValue ? ToastType.success : ToastType.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = AppConfig.mpinLockTimeoutOptionsSeconds;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'MPIN & Biometric Timing'),
          Expanded(
            child: _loading
                ? Center(
                    child: CircularProgressIndicator(color: AppTheme.primaryGreen))
                : SafeArea(
                    top: false,
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(20.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_biometricAvailable) ...[
                            Text(
                              'Biometric Unlock',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white70 : Colors.black54,
                              ),
                            ),
                            SizedBox(height: 8.h),
                            _buildCard(
                              isDark,
                              child: AppConfig.biometricLoginEnabled
                                  ? SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        'Unlock using Biometric',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                                        ),
                                      ),
                                      value: _biometricEnabled,
                                      onChanged: _onBiometricToggle,
                                      activeColor: AppTheme.primaryGreen,
                                    )
                                  // Server kill-switch (APP_CONTROL_MPIN_LOCK.
                                  // biometric_login_enabled) is off — show the
                                  // option as disabled with a reason instead of
                                  // silently hiding it, so the customer isn't
                                  // left wondering where it went.
                                  : ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      enabled: false,
                                      title: Text(
                                        'Unlock using Biometric',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 15.sp,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white38 : Colors.black38,
                                        ),
                                      ),
                                      subtitle: Text(
                                        'Biometric login is currently unavailable.',
                                        style: GoogleFonts.playfairDisplay(
                                          fontSize: 12.sp,
                                          color: isDark ? Colors.white24 : Colors.black38,
                                        ),
                                      ),
                                      trailing: Switch(
                                        value: false,
                                        onChanged: null,
                                        activeColor: AppTheme.primaryGreen,
                                      ),
                                    ),
                            ),
                            SizedBox(height: 24.h),
                          ],
                          Text(
                            'Lock Timing',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                          SizedBox(height: 4.h),
                          Text(
                            'Ask for MPIN only after the app has been in the background this long.',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 12.sp,
                              color: isDark ? Colors.white38 : Colors.black45,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          _buildCard(
                            isDark,
                            child: Column(
                              children: options.map((seconds) {
                                final isSelected = seconds == _selectedTimeoutSeconds;
                                return RadioListTile<int>(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    _formatDuration(seconds),
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 15.sp,
                                      fontWeight:
                                          isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isDark ? Colors.white : const Color(0xFF1E293B),
                                    ),
                                  ),
                                  value: seconds,
                                  groupValue: _selectedTimeoutSeconds,
                                  activeColor: AppTheme.primaryGreen,
                                  onChanged: (value) {
                                    if (value != null) _onSelectTimeout(value);
                                  },
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(bool isDark, {required Widget child}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
      ),
      child: child,
    );
  }
}
