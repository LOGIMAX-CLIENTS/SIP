import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../auth/controller/auth_controller.dart';
import '../../core/security/secure_storage_service.dart';
import '../../routes/app_router.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/theme/app_text_styles.dart';
import '../../core/localization/language_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isMpinEnabled = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMpinStatus();
  }

  Future<void> _loadMpinStatus() async {
    final enabled = await SecureStorageService.isMpinEnabled();
    if (mounted) {
      setState(() {
        _isMpinEnabled = enabled;
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleMpin(bool value) async {
    if (value) {
      // Get mobile from auth state
      final authState = ref.read(authControllerProvider);
      final mobile = authState.data?['mobile'] ?? '';

      // Navigate to MPIN screen (it handles both setup and unlock based on isMpinEnabled flag)
      // Since it's currently false, it will be in Setup mode.
      final result = await Navigator.pushNamed(
        context,
        AppRouter.mpin,
        arguments: {'mobile': mobile},
      );
      if (result == true) {
        setState(() => _isMpinEnabled = true);
      }
    } else {
      // Disable MPIN
      await SecureStorageService.setMpinEnabled(false);
      setState(() => _isMpinEnabled = false);
    }
  }

  void _showLanguageSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Consumer(builder: (context, ref, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30.r)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ref.tr('languageSelector', fallback: 'Change Language'),
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  )),
              SizedBox(height: 8.h),
              Text(
                ref.tr('chooseLanguagePref',
                    fallback: 'Choose your preferred language'),
                style: GoogleFonts.playfairDisplay(
                  fontSize: 14.sp,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 24.h),
              _buildLangOption(context, 'English', 'en', isDark),
              _buildLangOption(context, '????? (Tamil)', 'ta', isDark),
              _buildLangOption(context, '?????? (Telugu)', 'te', isDark),
              SizedBox(height: 16.h),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildLangOption(
      BuildContext context, String title, String code, bool isDark) {
    final currentCode = ref.watch(languageProvider).currentLocale;
    final isSelected = currentCode == code;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title,
          style: GoogleFonts.playfairDisplay(
            fontSize: 16.sp,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected
                ? AppTheme.arcticBlue
                : (isDark ? Colors.white70 : Colors.black87),
          )),
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded, color: AppTheme.arcticBlue)
          : null,
      onTap: () {
        ref.read(languageProvider.notifier).setLanguage(code);
        Navigator.pop(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF020617) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : Colors.black, size: 20.sp),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings',
            style: AppTextStyles.titleLarge(isDark)
                .copyWith(color: isDark ? Colors.white : Colors.black)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: 24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 24.h),
                  _buildSectionTitle('Security', isDark),
                  SizedBox(height: 16.h),
                  _buildSettingTile(
                    icon: Icons.lock_outline,
                    title: 'Enable MPIN',
                    subtitle: 'Secure App Access With A 4-Digit PIN',
                    trailing: Switch.adaptive(
                      value: _isMpinEnabled,
                      onChanged: _toggleMpin,
                      activeColor: AppTheme.arcticBlue,
                    ),
                    isDark: isDark,
                  ),
                  SizedBox(height: 32.h),
                  _buildSectionTitle('App Preferences', isDark),
                  SizedBox(height: 16.h),
                  _buildSettingTile(
                    icon: Icons.notifications_none_rounded,
                    title: 'Push Notifications',
                    subtitle: 'Alerts For Investments & Rewards',
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400),
                    isDark: isDark,
                  ),
                  GestureDetector(
                    onTap: () => _showLanguageSelector(context),
                    child: _buildSettingTile(
                      icon: Icons.language_rounded,
                      title: ref.tr('languageTitle', fallback: 'Language'),
                      subtitle: ref.tr('languageSubtitle',
                          fallback: 'English / ????? / ??????'),
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      isDark: isDark,
                    ),
                  ),
                  _buildSettingTile(
                    icon: Icons.dark_mode_outlined,
                    title: 'Dark Mode',
                    subtitle: 'Toggle App Theme Appearance',
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: Colors.grey.shade400),
                    isDark: isDark,
                  ),
                  SizedBox(height: 40.h),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.playfairDisplay(
          fontSize: 12.sp,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: AppTheme.arcticBlue),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
    required bool isDark,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: AppTheme.arcticBlue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.arcticBlue, size: 22.sp),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87)),
                Text(subtitle,
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp, color: Colors.grey, height: 1.2)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

