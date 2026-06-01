import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/security/session_manager.dart';
import '../../core/security/secure_storage_service.dart';
import '../../core/services/app_control_service.dart';
import '../../core/models/app_control_model.dart';
import '../../routes/app_router.dart';
import '../../main.dart' show navigatorKey;
import '../../shared/widgets/app_update_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  AppVersionInfo? _versionInfo;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeIn,
      ),
    );

    _animationController.forward();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    final minSplashDuration =
        Future.delayed(const Duration(milliseconds: 2000));

    bool loggedIn = false;
    bool mpinEnabled = false;

    try {
      loggedIn = await SessionManager.isAuthenticated();
      mpinEnabled = await SecureStorageService.isMpinEnabled();
    } catch (e) {
      if (kDebugMode) debugPrint('Splash init error: $e');
    }

    // Determine normal route
    // SECURITY: If logged in but PIN was never set (mpin_enabled=false),
    // force re-authentication via login → OTP → PIN setup.
    // This covers the edge case where register succeeded but app was
    // killed before PIN creation completed.
    String nextRoute = AppRouter.login;
    if (loggedIn && mpinEnabled) {
      nextRoute = AppRouter.mpin;
    }

    // Fetch app control data (maintenance + version check)
    Map<String, dynamic>? maintenanceArgs;
    bool updateNeeded = false;
    try {
      final controlService = AppControlService();
      final raw = await controlService.fetchAppControl();
      if (kDebugMode) debugPrint('[Splash] app/control raw response received');
      if (raw != null) {
        final controlData = AppControlData.fromJson(raw);

        // Maintenance gate
        if (controlData.maintenance.isEnabled) {
          maintenanceArgs = {'resumeRoute': nextRoute};
          nextRoute = AppRouter.maintenance;
        }

        // Version update gate — stay on splash so the update dialog
        // appears on top of the splash background (not login/mpin)
        final versionInfo = controlData.versionInfo;
        if (kDebugMode) debugPrint('[Splash] versionInfo parsed: ${versionInfo != null}');
        if (versionInfo != null && !controlData.maintenance.isEnabled) {
          final packageInfo = await PackageInfo.fromPlatform();
          final currentVersion = packageInfo.version;
          final platform = versionInfo.current;
          if (kDebugMode) debugPrint('[Splash] currentVersion=$currentVersion, latestVersion=${platform.latestVersion}');
          if (_isLower(currentVersion, platform.latestVersion)) {
            updateNeeded = true;
            _versionInfo = versionInfo;
            // Cache version info so subsequent launches show dialog
            // even if the API fails (network issues, Android doze, etc.)
            await _cacheVersionInfo(raw);
          } else {
            // User has updated — clear the cache
            await _clearVersionCache();
          }
        }
      } else {
        if (kDebugMode) debugPrint('[Splash] app/control returned NULL — trying cache');
        updateNeeded = await _tryLoadCachedVersionInfo();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] App control fetch failed — trying cache');
      updateNeeded = await _tryLoadCachedVersionInfo();
    }

    await minSplashDuration;

    if (!mounted) return;

    // If update is required, stay on splash and show the blocking
    // update dialog directly. The wrapper does NOT handle version updates.
    if (updateNeeded && _versionInfo != null) {
      _showUpdateDialog();
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      nextRoute,
      arguments: maintenanceArgs,
    );
  }

  /// Semantic version comparison: returns true if [a] < [b]
  bool _isLower(String a, String b) {
    try {
      final av = a.split('.').map(int.parse).toList();
      final bv = b.split('.').map(int.parse).toList();
      for (int i = 0; i < 3; i++) {
        final ai = i < av.length ? av[i] : 0;
        final bi = i < bv.length ? bv[i] : 0;
        if (ai < bi) return true;
        if (ai > bi) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Version Cache (survives app restarts) ──────────────────────────────
  static const _kVersionCacheKey = 'cached_version_control';

  /// Saves the raw app/control response so we can show the update
  /// dialog even if the API fails on next launch.
  Future<void> _cacheVersionInfo(Map<String, dynamic> raw) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kVersionCacheKey, jsonEncode(raw));
      if (kDebugMode) debugPrint('[Splash] Version info cached for offline use.');
    } catch (_) {}
  }

  Future<void> _clearVersionCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kVersionCacheKey);
    } catch (_) {}
  }

  /// Loads cached version info and runs the same version check.
  /// Returns true if an update is still needed.
  Future<bool> _tryLoadCachedVersionInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_kVersionCacheKey);
      if (cached == null) return false;

      final raw = jsonDecode(cached) as Map<String, dynamic>;
      final controlData = AppControlData.fromJson(raw);
      final versionInfo = controlData.versionInfo;
      if (versionInfo == null) return false;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final platform = versionInfo.current;

      if (kDebugMode) debugPrint('[Splash] CACHE: checking versions');

      if (_isLower(currentVersion, platform.latestVersion)) {
        _versionInfo = versionInfo;
        if (kDebugMode) debugPrint('[Splash] CACHE: Update still needed — showing dialog.');
        return true;
      } else {
        // User updated — clear stale cache
        await _clearVersionCache();
        return false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Splash] CACHE: Failed to load');
      return false;
    }
  }

  /// Show the blocking update dialog on top of the splash screen.
  void _showUpdateDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navContext = navigatorKey.currentContext;
      if (mounted && navContext != null && _versionInfo != null) {
        AppUpdateDialog.show(
          navContext,
          versionInfo: _versionInfo!,
          forceUpdate: true,
        );
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Block all back presses during splash — popping the splash leaves
    // nothing in the navigator stack and triggers the "Page Not Found" route.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        // First back: warn; second back: exit
        // (Keep simple — splash is transient so just exit cleanly.)
        SystemNavigator.pop();
      },
      child: Scaffold(
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Stack(
              children: [
                // ── Layer 1: Full background image ──
                Positioned.fill(
                  child: Image.asset(
                    'assets/resources/splash_bg.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFFFEF7E6), Color(0xFFF8D89C)],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Layer 2: Center animated GIF ──
                Center(
                  child: Image.asset(
                    'assets/resources/Splashscreen.gif',
                    width: 100.w,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Image.asset(
                      'assets/resources/splash.png',
                      width: 220.w,
                    ),
                  ),
                ),

                // ── Layer 3: Footer SVG fixed at bottom ──
                Positioned(
                  left: 32.w,
                  right: 32.w,
                  bottom: MediaQuery.of(context).padding.bottom + 20.h,
                  child: SvgPicture.asset(
                    'assets/resources/splash_footer.svg',
                    height: 28.h,
                    fit: BoxFit.contain,
                    // ignore: deprecated_member_use
                    placeholderBuilder: (_) => const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
