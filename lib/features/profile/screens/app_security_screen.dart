import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/security/secure_storage_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/mpin_service.dart';
import '../../../core/utils/navigation_utils.dart';
import '../../../routes/app_router.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/widgets/app_toast.dart';
import '../services/profile_service.dart';

/// Profile > "App Security" — every app-lock setting in one place.
///
///   1. Configure MPIN — expands to Change MPIN.
///   2. Biometric Login — a per-device local toggle, shown disabled with a
///      reason when the server kill-switch (AppConfig.biometricLoginEnabled,
///      from APP_CONTROL_MPIN_LOCK) is off.
///   3. Auto-Lock — how long the app must sit in the background
///      before AppLifecycleObserver shows the MPIN/biometric lock screen on
///      resume. Options come from APP_CONTROL_MPIN_LOCK (see
///      AppControlProvider). The choice is persisted server-side
///      (Customer.cus_mpin_lock_timeout_seconds via
///      ProfileService.setMpinLockTimeout — profile/mpin-lock-timing) so it
///      syncs across the customer's devices, with the local
///      SecureStorageService copy kept in sync as an instant-read cache for
///      AppLifecycleObserver.
class AppSecurityScreen extends ConsumerStatefulWidget {
  const AppSecurityScreen({super.key});

  @override
  ConsumerState<AppSecurityScreen> createState() => _AppSecurityScreenState();
}

class _AppSecurityScreenState extends ConsumerState<AppSecurityScreen> {
  static const _iconGreen = Color(0xFF0E5723);
  static const _ink = Color(0xFF1E293B);

  int _selectedTimeoutSeconds = AppConfig.mpinLockDefaultTimeoutSeconds;
  bool _mpinEnabled = false;
  bool _biometricEnabled = false;
  bool _mpinExpanded = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final mpinEnabled = await SecureStorageService.isMpinEnabled();
    final storedTimeout = await SecureStorageService.getMpinLockTimeoutSeconds();
    final hasDevice = await BiometricService.deviceHasBiometric();
    final canUse = hasDevice && await BiometricService.canUseBiometric();
    if (mounted) {
      setState(() {
        _mpinEnabled = mpinEnabled;
        _selectedTimeoutSeconds = storedTimeout;
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
      if (!mounted) return;

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
    if (mounted) {
      setState(() {
        _biometricEnabled = newValue;
        if (newValue) _mpinEnabled = true;
      });
    }

    final msg = newValue
        ? 'Biometric authentication enabled'
        : 'Biometric authentication disabled';
    if (mounted) {
      AppToast.show(context, msg,
          type: newValue ? ToastType.success : ToastType.info);
    }
  }

  Future<void> _showTimeoutSheet(bool isDark) async {
    final options = AppConfig.mpinLockTimeoutOptionsSeconds;
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 12.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(100.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Auto-Lock',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : _ink,
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
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: options.map((seconds) {
                    final isSelected = seconds == _selectedTimeoutSeconds;
                    return InkWell(
                      onTap: () => Navigator.pop(sheetContext, seconds),
                      borderRadius: BorderRadius.circular(12.r),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatDuration(seconds),
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 15.sp,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isDark ? Colors.white : _ink,
                                ),
                              ),
                            ),
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 22.sp,
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : (isDark ? Colors.white38 : Colors.black26),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != _selectedTimeoutSeconds) {
      await _onSelectTimeout(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppTheme.primaryGreen))
                  : SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(20.w, 4.h, 20.w, 24.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSectionLabel('LOGIN CREDENTIALS', isDark),
                          _buildCard(isDark, child: _buildMpinTile(isDark)),
                          SizedBox(height: 24.h),
                          _buildSectionLabel('DEVICE AUTHENTICATION', isDark),
                          _buildCard(
                            isDark,
                            child: Column(
                              children: [
                                _buildBiometricTile(isDark),
                                _buildDivider(isDark),
                                _buildAutoLockTile(isDark),
                              ],
                            ),
                          ),
                          SizedBox(height: 20.h),
                          _buildAdvisory(isDark),
                          SizedBox(height: 16.h),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4.w),
                            child: Text(
                              // Only MPIN change/reset sends an SMS
                              // (MPIN_CHANGE_SUCCESSFUL_SMS) — biometric and
                              // lock-timing changes don't, so don't claim so.
                              'Protected sessions · MPIN changes are confirmed by SMS on your registered mobile number.',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 11.sp,
                                height: 1.4,
                                color: isDark ? Colors.white38 : Colors.black45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 16.h),
      child: Row(
        children: [
          Material(
            color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            child: InkWell(
              onTap: () => NavigationUtils.safePop(context),
              borderRadius: BorderRadius.circular(12.r),
              child: Container(
                width: 40.w,
                height: 40.w,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withOpacity(0.06)),
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 26.sp,
                  color: isDark ? Colors.white : _ink,
                ),
              ),
            ),
          ),
          SizedBox(width: 14.w),
          Text(
            'App Security',
            style: GoogleFonts.playfairDisplay(
              fontSize: 20.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(left: 4.w, bottom: 8.h),
      child: Text(
        text,
        style: GoogleFonts.playfairDisplay(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, {required Widget child}) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      // Transparent Material so the tiles' InkWell splashes paint above the
      // card's white fill instead of underneath it.
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 1,
      indent: 14.w,
      endIndent: 14.w,
      color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
    );
  }

  Widget _buildTile({
    required bool isDark,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
        child: Row(
          children: [
            Container(
              width: 40.w,
              height: 40.w,
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, size: 20.sp, color: _iconGreen),
            ),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : _ink,
                    ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 12.sp,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildMpinTile(bool isDark) {
    final statusColor = _mpinEnabled ? AppTheme.primaryGreen : Colors.black38;
    return Column(
      children: [
        _buildTile(
          isDark: isDark,
          icon: Icons.key_rounded,
          title: 'Configure MPIN',
          subtitle:
              'A ${MpinNotifier.pinLength}-digit PIN for login & transactions',
          onTap: () => setState(() => _mpinExpanded = !_mpinExpanded),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 7.sp, color: statusColor),
              SizedBox(width: 4.w),
              Text(
                _mpinEnabled ? 'Active' : 'Off',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
              SizedBox(width: 4.w),
              AnimatedRotation(
                turns: _mpinExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 22.sp,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: _mpinExpanded
              ? Column(
                  children: [
                    _buildDivider(isDark),
                    _buildTile(
                      isDark: isDark,
                      icon: Icons.lock_reset_rounded,
                      title: 'Change MPIN',
                      subtitle: 'Verify your current MPIN, then set a new one',
                      onTap: () =>
                          Navigator.pushNamed(context, AppRouter.changeMpin),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 22.sp,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildBiometricTile(bool isDark) {
    // Server kill-switch off — show the option as disabled with a reason
    // instead of silently hiding it, so the customer isn't left wondering
    // where it went.
    final allowed = AppConfig.biometricLoginEnabled;
    return _buildTile(
      isDark: isDark,
      icon: Icons.fingerprint_rounded,
      title: 'Biometric Login',
      subtitle: allowed
          ? 'Fingerprint / Face unlock'
          : 'Biometric login is currently unavailable.',
      onTap: allowed ? () => _onBiometricToggle(!_biometricEnabled) : null,
      trailing: Switch(
        value: allowed && _biometricEnabled,
        onChanged: allowed ? _onBiometricToggle : null,
        activeTrackColor: AppTheme.primaryGreen,
        inactiveTrackColor: isDark ? Colors.white24 : Colors.black12,
        thumbColor: WidgetStateProperty.all(Colors.white),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }

  Widget _buildAutoLockTile(bool isDark) {
    return _buildTile(
      isDark: isDark,
      icon: Icons.timer_outlined,
      title: 'Auto-Lock',
      subtitle: 'Re-authenticate after the app is in the background',
      onTap: () => _showTimeoutSheet(isDark),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(100.r),
            ),
            child: Text(
              _formatDuration(_selectedTimeoutSeconds),
              style: GoogleFonts.playfairDisplay(
                fontSize: 11.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFB45309),
              ),
            ),
          ),
          SizedBox(width: 4.w),
          Icon(
            Icons.chevron_right_rounded,
            size: 22.sp,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ],
      ),
    );
  }

  Widget _buildAdvisory(bool isDark) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18.sp, color: _iconGreen),
          SizedBox(width: 10.w),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  height: 1.4,
                  color: isDark ? Colors.white70 : _ink,
                ),
                children: const [
                  TextSpan(
                    text: 'Security advisory: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text:
                        '${AppConstants.companyName} will never ask for your MPIN, OTP or card details over call, SMS, email or WhatsApp.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
