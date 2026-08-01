import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shimmer/shimmer.dart';
import 'package:intl/intl.dart';
import '../../core/services/biometric_service.dart';
import '../../routes/app_router.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/utils/masking_utils.dart';
import '../auth/controller/auth_controller.dart';
import '../main/main_screen.dart';
import 'profile_controller.dart' as pc;
import '../../shared/widgets/loaders.dart';
import '../../shared/widgets/app_toast.dart';

// ── App version provider ───────────────────────────────────────────────────
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return 'Version ${info.version} (${info.buildNumber})';
});

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    // deviceHasBiometric() uses getAvailableBiometrics() internally.
    // canUseBiometric() also auto-disables storage if device biometrics
    // were removed since last launch.
    final hasDevice = await BiometricService.deviceHasBiometric();
    final canUse = hasDevice && await BiometricService.canUseBiometric();
    if (mounted) {
      setState(() {
        _biometricAvailable = hasDevice;
        _biometricEnabled = canUse;
      });
    }
  }

  Future<void> _onBiometricToggle(bool newValue) async {
    if (newValue) {
      // ── Guard 1: confirm device has enrolled biometrics ──────────────
      final check = await BiometricService.checkBeforeEnable();
      if (check == BiometricCheckResult.noneEnrolled) {
        if (mounted) {
          AppToast.show(
            context,
            'No biometric found in device. Please enroll a fingerprint or face in your phone settings.',
            type: ToastType.error,
          );
        }
        return; // Keep toggle OFF
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

      // ── Guard 2: verify identity with existing MPIN ───────────────────
      final verified = await Navigator.pushNamed(
        context,
        AppRouter.mpin,
        arguments: {'type': 'verify_only'},
      );
      if (verified != true) return; // MPIN not verified — abort

      // ── Guard 3: final biometric prompt to confirm enrollment ─────────
      final enrolled = await BiometricService.authenticate(
        reason: 'Confirm biometrics to enable this feature',
      );
      if (!enrolled) return; // User cancelled — abort
    }

    // Persist the new state
    await SecureStorageService.setBiometricEnabled(newValue);
    if (newValue) await SecureStorageService.setMpinEnabled(true);
    if (mounted) setState(() => _biometricEnabled = newValue);

    final msg = newValue
        ? 'Biometric authentication enabled'
        : 'Biometric authentication disabled';
    if (mounted)
      AppToast.show(context, msg,
          type: newValue ? ToastType.success : ToastType.info);
  }

  /// Formats ISO 8601 login timestamp to Indian format.
  /// e.g., "2026-06-13T10:04:09.000000Z" → "13/06/2026, 3:34 PM"
  String _formatLoginDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return DateFormat('dd/MM/yyyy, h:mm a').format(dt);
    } catch (_) {
      return isoDate; // Fallback: show raw value if parsing fails
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileState = ref.watch(pc.profileProvider);

    if (profileState.isLoading && profileState.user.name.isEmpty) {
      return _buildSkeleton(isDark);
    }

    final user = profileState.user;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Pinned gradient header (never scrolls) ──────────────────
          _buildHeader(context, user, isDark),

          // ── Scrollable menu body ─────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                        'Profile Settings',
                        [
                          _buildMenuItem(
                            'Account Details',
                            'assets/sidemenu/account.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.accountDetails),
                          ),
                          _buildMenuItem(
                            'Bank Details',
                            'assets/withdraw/bank.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.bankDetails),
                          ),
                          _buildMenuItem(
                            'Transaction History',
                            'assets/sidemenu/transhistory.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.transactionHistory),
                          ),
                          _buildMenuItem(
                            'KYC Verification',
                            'assets/sidemenu/kyc.svg',
                            onTap: () async {
                              // Always open the KYC screen — even when already
                              // verified, so the user can view their masked
                              // PAN/Aadhaar details and use Edit to redo
                              // verification (see kyc/screens/kyc_screen.dart).
                              final result = await Navigator.pushNamed(
                                  context, AppRouter.kyc,
                                  arguments: {'request_from': 'profile'});
                              // Refresh profile to update the verified badge
                              if (result == true && mounted) {
                                ref
                                    .read(pc.profileProvider.notifier)
                                    .fetchProfileDetails();
                              }
                            },
                            trailing: user.kycStatus == 1
                                ? Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10.w, vertical: 4.h),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0E5723)
                                          .withOpacity(0.08),
                                      borderRadius:
                                          BorderRadius.circular(100.r),
                                      border: Border.all(
                                          color: const Color(0xFF0E5723)
                                              .withOpacity(0.15)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.verified_user_rounded,
                                            color: const Color(0xFF0E5723),
                                            size: 14.sp),
                                        SizedBox(width: 4.w),
                                        Text(
                                          'Verified',
                                          style: GoogleFonts.playfairDisplay(
                                            fontSize: 10.sp,
                                            fontWeight: FontWeight.w900,
                                            color: const Color(0xFF0E5723),
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : null,
                          ),
                          // Nominee Details - Commented as requested

                          _buildMenuItem(
                            'Nominee Details',
                            'assets/sidemenu/nominee.svg',
                            onTap: () =>
                                Navigator.pushNamed(context, AppRouter.nominee),
                          ),

                          // Auto Savings — commented: accessible via other nav paths
                          _buildMenuItem(
                            'Auto Savings',
                            'assets/sidemenu/autosaving.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.sipOverview),
                          ),
                          // SIP Transactions — commented: accessible from Auto Savings Quick Actions
                          // _buildMenuItem(
                          //   'SIP Transactions',
                          //   'assets/sidemenu/autosaving.svg',
                          //   onTap: () => Navigator.pushNamed(
                          //       context, AppRouter.sipTransactions),
                          // ),
                        ],
                        isDark),
                    SizedBox(height: 16.h),
                    _buildSection(
                        'General',
                        [
                          _buildMenuItem(
                            'Refer & Earn',
                            'assets/sidemenu/refer.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.referral),
                          ),
                          _buildMenuItem(
                            'Terms & Conditions',
                            'assets/sidemenu/tc.svg',
                            onTap: () =>
                                Navigator.pushNamed(context, AppRouter.terms),
                          ),
                          _buildMenuItem(
                            'Privacy Policy',
                            'assets/sidemenu/privacy.svg',
                            onTap: () =>
                                Navigator.pushNamed(context, AppRouter.privacy),
                          ),
                          _buildMenuItem(
                            'Refund Policy',
                            'assets/sidemenu/refund.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.refundPolicy),
                          ),
                          _buildMenuItem(
                            'FAQ',
                            'assets/sidemenu/faq.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.faq),
                          ),
                          _buildMenuItem(
                            'Enquiry',
                            'assets/sidemenu/enquiry.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.enquiryList),
                          ),
                          _buildMenuItem(
                            'Contact Us',
                            'assets/sidemenu/help.svg',
                            onTap: () =>
                                Navigator.pushNamed(context, AppRouter.contact),
                          ),
                        ],
                        isDark),
                    SizedBox(height: 16.h),
                    _buildSection(
                        'Account',
                        [
                          // Biometrics Auth
                          if (_biometricAvailable)
                            _buildMenuItem(
                              'Biometric Authentication',
                              'assets/sidemenu/lock.svg',
                              onTap: () =>
                                  _onBiometricToggle(!_biometricEnabled),
                              trailing: Switch(
                                value: _biometricEnabled,
                                onChanged: _onBiometricToggle,
                                activeColor: const Color(0xFF0E5723),
                              ),
                            ),

                          // Change MPIN

                          _buildMenuItem(
                            'Change MPIN',
                            'assets/sidemenu/mpin.svg',
                            onTap: () => Navigator.pushNamed(
                                context, AppRouter.changeMpin),
                          ),

                          _buildMenuItem(
                            'Logout',
                            'assets/sidemenu/logout.svg',
                            onTap: () => _handleLogout(context, ref),
                          ),
                          _buildMenuItem(
                            'Delete Account',
                            'assets/sidemenu/deleteacc.svg',
                            isDestructive: true,
                            onTap: () => _handleDeleteAccount(context),
                          ),
                        ],
                        isDark),
                    SizedBox(height: 32.h),
                    Center(
                      child: Consumer(
                        builder: (context, ref, _) {
                          final versionAsync = ref.watch(appVersionProvider);
                          final label = versionAsync.when(
                            data: (v) => v,
                            loading: () => 'Version ...',
                            error: (_, __) => 'Version 1.0',
                          );
                          return Text(
                            label,
                            style: GoogleFonts.lora(
                              fontSize: 14.sp,
                              color: isDark ? Colors.white38 : Colors.black38,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
                      ),
                    ),
                    // Extra space so last item scrolls above the floating nav bar
                    SizedBox(height: 120.h),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shimmer skeleton — mirrors the real profile layout ────────────────────
  Widget _buildSkeleton(bool isDark) {
    final baseLight = Colors.white.withValues(alpha: 0.15);
    final highlightLight = Colors.white.withValues(alpha: 0.30);
    final baseDark = Colors.black.withValues(alpha: isDark ? 0.12 : 0.06);
    final highlightDark = Colors.black.withValues(alpha: isDark ? 0.22 : 0.12);

    // Helper — shimmering pill on the green header
    Widget headerPill(double w, double h) => Shimmer.fromColors(
          baseColor: baseLight,
          highlightColor: highlightLight,
          child: Container(
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(h / 2),
            ),
          ),
        );

    // Helper — shimmering circle on the green header
    Widget headerCircle(double size) => Shimmer.fromColors(
          baseColor: baseLight,
          highlightColor: highlightLight,
          child: Container(
            width: size,
            height: size,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        );

    // Helper — shimmering menu-item card (matches _buildMenuItem exactly)
    Widget menuCard() => Shimmer.fromColors(
          baseColor: baseDark,
          highlightColor: highlightDark,
          child: Container(
            margin: EdgeInsets.only(bottom: 12.h),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.r),
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                SizedBox(width: 16.w),
                Container(
                  width: 140.w,
                  height: 14.h,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(7.r),
                  ),
                ),
              ],
            ),
          ),
        );

    // Helper — section title pill
    Widget sectionTitle() => Shimmer.fromColors(
          baseColor: baseDark,
          highlightColor: highlightDark,
          child: Container(
            width: 120.w,
            height: 18.h,
            margin: EdgeInsets.only(left: 4.w, bottom: 16.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9.r),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // ── Green header skeleton (same gradient as real header) ────────
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment(-0.87, -0.5),
                end: Alignment(0.87, 0.5),
                colors: [Color(0xFF003716), Color(0xFF167525)],
                stops: [0.0223, 0.9399],
              ),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(32.r),
                bottomRight: Radius.circular(32.r),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 28.h),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Nav row
                    SizedBox(height: 8.h),
                    Row(
                      children: [
                        Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white54, size: 20.sp),
                        SizedBox(width: 8.w),
                        headerPill(60.w, 18.h),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    // Avatar + name/phone row
                    Row(
                      children: [
                        SizedBox(width: 8.w),
                        headerCircle(70.w),
                        SizedBox(width: 20.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            headerPill(130.w, 18.h),
                            SizedBox(height: 8.h),
                            headerPill(90.w, 13.h),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Menu body skeleton ──────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(24.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section 1 — Profile Settings (3 items)
                  sectionTitle(),
                  menuCard(),
                  menuCard(),
                  menuCard(),
                  SizedBox(height: 16.h),
                  // Section 2 — General (5 items)
                  sectionTitle(),
                  menuCard(),
                  menuCard(),
                  menuCard(),
                  menuCard(),
                  menuCard(),
                  SizedBox(height: 16.h),
                  // Section 3 — Account (3 items)
                  sectionTitle(),
                  menuCard(),
                  menuCard(),
                  menuCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, user, bool isDark) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment(-0.87, -0.5),
          end: Alignment(0.87, 0.5),
          colors: [Color(0xFF003716), Color(0xFF167525)],
          stops: [0.0223, 0.9399],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(32.r),
          bottomRight: Radius.circular(32.r),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 28.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Nav row ─────────────────────────────────────────────────
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 20.sp),
                    onPressed: () {
                      final routeName = ModalRoute.of(context)?.settings.name;
                      if (routeName == AppRouter.profile) {
                        Navigator.pop(context);
                      } else {
                        ref.read(selectedTabProvider.notifier).state = 0;
                      }
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Profile',
                      textAlign: TextAlign.left,
                      style: GoogleFonts.playfairDisplay(
                        fontWeight: FontWeight.w800,
                        fontSize: 18.sp,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20.h),
              // ── User info ───────────────────────────────────────────────
              Row(
                children: [
                  SizedBox(width: 8.w),
                  // Circular Progress Avatar
                  Builder(builder: (context) {
                    // Profile completion: 5 fields × 20% each
                    int filled = 0;
                    if (user.name.isNotEmpty) filled++;
                    if (user.phone.isNotEmpty) filled++;
                    if (user.dob.isNotEmpty) filled++;
                    if (user.kycStatus == 1) filled++;
                    if (user.pincode.isNotEmpty) filled++;
                    final completion = filled / 5.0;
                    final pct = (completion * 100).round();

                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 70.w,
                          height: 70.w,
                          child: CircularProgressIndicator(
                            value: completion,
                            strokeWidth: 4,
                            backgroundColor: Colors.white.withOpacity(0.15),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFFFDE047)),
                          ),
                        ),
                        Container(
                          width: 58.w,
                          height: 58.w,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.15),
                            shape: BoxShape.circle,
                            image: user.photoUrl != null &&
                                    user.photoUrl!.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(user.photoUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          alignment: Alignment.center,
                          child: user.photoUrl == null || user.photoUrl!.isEmpty
                              ? Text(
                                  user.name.isNotEmpty
                                      ? user.name
                                          .substring(
                                              0,
                                              user.name.length < 2
                                                  ? user.name.length
                                                  : 2)
                                          .toUpperCase()
                                      : 'AS',
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: EdgeInsets.all(7.w),
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$pct%',
                              style: GoogleFonts.lora(
                                fontSize: 8.sp,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF0E5723),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                  SizedBox(width: 20.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name.isNotEmpty ? user.name : '',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          MaskingUtils.maskMobile(user.phone),
                          style: GoogleFonts.lora(
                            fontSize: 14.sp,
                            color: Colors.white.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // ── VAPT Finding 6: Last Login Info ─────────
                        if (user.lastLoginAt != null &&
                            user.lastLoginAt!.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 6.h),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 12.sp,
                                  color: const Color(0xFF4ADE80),
                                ),
                                SizedBox(width: 4.w),
                                Flexible(
                                  child: Text(
                                    'Last login: ${_formatLoginDate(user.lastLoginAt!)}',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 11.sp,
                                      color: Colors.white.withOpacity(0.6),
                                      fontWeight: FontWeight.w400,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        // ── VAPT Finding 6: Last Failed Login ───────
                        if (user.lastFailedLoginAt != null &&
                            user.lastFailedLoginAt!.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(top: 4.h),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 12.sp,
                                  color: const Color(0xFFFBBF24),
                                ),
                                SizedBox(width: 4.w),
                                Flexible(
                                  child: Text(
                                    'Last failed login: ${_formatLoginDate(user.lastFailedLoginAt!)}',
                                    style: GoogleFonts.playfairDisplay(
                                      fontSize: 11.sp,
                                      color: const Color(0xFFFBBF24).withOpacity(0.8),
                                      fontWeight: FontWeight.w400,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> items, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.w, bottom: 16.h),
          child: Text(
            title,
            style: GoogleFonts.playfairDisplay(
              fontSize: 18.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        ...items,
      ],
    );
  }

  Widget _buildMenuItem(String title, String iconPath,
      {required VoidCallback onTap,
      bool isDestructive = false,
      Widget? trailing}) {
    return Container(
      margin: EdgeInsets.only(bottom: 12.h),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15.r),
              border: Border.all(color: Colors.black.withOpacity(0.05)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  padding: EdgeInsets.all(10.w),
                  child: SvgPicture.asset(
                    iconPath,
                    colorFilter: ColorFilter.mode(
                        isDestructive ? Colors.red : const Color(0xFF0E5723),
                        BlendMode.srcIn),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w500,
                      color:
                          isDestructive ? Colors.red : const Color(0xFF4B5563),
                    ),
                  ),
                ),
                trailing ??
                    Icon(
                      Icons.arrow_forward_rounded,
                      size: 20.sp,
                      color: Colors.black26,
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Logout',
            style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to logout?',
            style: GoogleFonts.playfairDisplay(fontSize: 13.sp)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: GoogleFonts.playfairDisplay())),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(selectedTabProvider.notifier).state = 0;
              ref.read(authControllerProvider.notifier).logout();
              Navigator.pushNamedAndRemoveUntil(
                  context, AppRouter.login, (route) => false);
            },
            child: Text('Logout',
                style: GoogleFonts.playfairDisplay(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleDeleteAccount(BuildContext context) {
    Navigator.pushNamed(context, AppRouter.deleteAccount);
  }
}
