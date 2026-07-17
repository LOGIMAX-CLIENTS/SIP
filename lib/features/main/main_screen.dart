import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../home/home_screen.dart';
import '../instant_saving/instant_saving_screen.dart';
import '../history/screens/transaction_history_screen.dart';
import '../profile/profile_screen.dart';
import '../../core/providers/home_dashboard_provider.dart';
import '../../core/providers/portfolio_provider.dart';
import '../../features/profile/profile_controller.dart';
import '../../features/instant_saving/controller/saving_controller.dart';
import '../../features/history/controller/history_controller.dart';
import '../../shared/theme/app_theme.dart';
import '../../shared/widgets/app_toast.dart';
import '../../features/auth/controller/auth_controller.dart';
import '../../core/services/notification_service.dart';

/// Shared provider so any child screen can switch tabs
final selectedTabProvider = StateProvider<int>((ref) => 0);

class MainScreen extends ConsumerStatefulWidget {
  const MainScreen({super.key});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  final Set<int> _visitedTabs = {0};
  DateTime? _lastBackPressTime; // tracks double-tap-to-exit timing

  @override
  void initState() {
    super.initState();
    // Reset to Home tab after mount when navigating from payment success.
    // Deferred via addPostFrameCallback to avoid !_doingMountOrUpdate crash.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null && args['resetTab'] == true) {
        // Direct state set — no provider invalidation here.
        // Each screen manages its own data refresh.
        ref.read(selectedTabProvider.notifier).state = 0;
      }

      // Rehydrate auth state from SecureStorage first.
      // The forgot PIN flow's OTP verify may overwrite sessionData with
      // temp_token (no user.id_customer), causing userProvider to return null
      // and dashboard/portfolio APIs to not fire.
      await ref.read(authControllerProvider.notifier).rehydrateFromStorage();

      // Force fresh API calls on MainScreen mount (e.g. after MPIN verify).
      ref.invalidate(homeDashboardProvider);
      ref.invalidate(portfolioProvider);
      ref.invalidate(profileProvider);

      // Fetch notification badge count AFTER auth is ready so the API
      // has a valid token. HomeScreen.initState fires in parallel and
      // may race ahead of rehydration, so this is the authoritative call.
      ref.read(notificationProvider.notifier).refreshUnreadCount();
    });
  }

  /// Called ONLY from user-initiated tab taps — never during navigation.
  /// This is the safe place to refresh providers without causing
  /// !_doingMountOrUpdate assertion errors.
  void _onTabTapped(int index) {
    final current = ref.read(selectedTabProvider);
    if (current == index) return; // same tab — no refresh needed

    // Jewellery is a separate route, not in IndexedStack — navigate without changing tab index
    if (index == 4) {
      Navigator.of(context).pushNamed('/jewellery');
      return;
    }

    ref.read(selectedTabProvider.notifier).state = index;
    switch (index) {
      case 0:
        ref.invalidate(homeDashboardProvider);
        ref.invalidate(profileProvider);
        ref.read(notificationProvider.notifier).refreshUnreadCount();
        break;
      case 1:
        // InstantSavingScreen auto-refreshes its own providers
        ref.invalidate(savingConfigProvider);
        break;
      case 2:
        // historyProvider is intentionally NOT invalidated here — Transaction
        // History lazy-loads in pages and must preserve already-loaded pages
        // (and effective scroll position, since the tab widget stays mounted
        // via IndexedStack) across tab switches instead of refetching page 1
        // every time the user returns to this tab.
        ref.invalidate(portfolioProvider);
        break;
      case 3:
        ref.invalidate(profileProvider);
        break;
    }
  }

  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedTabProvider);
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // Mark current tab as visited
    if (!_visitedTabs.contains(selectedIndex)) {
      _visitedTabs.add(selectedIndex);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      // Never let Flutter pop the route — we handle it ourselves.
      // If canPop=true on home tab, popping navigates to the unknown
      // route (null name) which shows the "Page Not Found" screen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (selectedIndex != 0) {
          // Not on Home tab → go to Home instead of exiting
          ref.read(selectedTabProvider.notifier).state = 0;
        } else {
          // On Home tab → double-tap to exit
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
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            IndexedStack(
              index: selectedIndex,
              children: [
                const HomeScreen(),
                _visitedTabs.contains(1)
                    ? const InstantSavingScreen()
                    : const SizedBox.shrink(),
                _visitedTabs.contains(2)
                    ? const TransactionHistoryScreen()
                    : const SizedBox.shrink(),
                _visitedTabs.contains(3)
                    ? const ProfileScreen()
                    : const SizedBox.shrink(),
              ],
            ),
            _buildBottomNav(ref, selectedIndex, isDark, keyboardOpen),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav(WidgetRef ref, int selectedIndex, bool isDark, bool keyboardOpen) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    // Hide navbar completely when the soft keyboard is visible
    // or when the user is on the Invest tab (Wise-style footer replaces it)
    if (keyboardOpen || selectedIndex == 1) return const SizedBox.shrink();

    return Positioned(
      bottom: bottomPadding + 16.h,
      left: 16.w,
      right: 16.w,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(100.r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withOpacity(0.6)
                  : Colors.white.withOpacity(0.6),
              borderRadius: BorderRadius.circular(100.r),
              border: Border.all(
                color: isDark ? Colors.white12 : Colors.black.withOpacity(0.05),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(ref, 'Home',      selectedIndex == 0, isDark, 0, 'assets/footer/home'),
                _buildNavItem(ref, 'Invest',    selectedIndex == 1, isDark, 1, 'assets/footer/invest'),
                _buildNavItem(ref, 'History',   selectedIndex == 2, isDark, 2, 'assets/footer/history'),
                _buildNavItem(ref, 'Profile',   selectedIndex == 3, isDark, 3, 'assets/footer/profile'),
                _buildNavItem(ref, 'Jewellery', selectedIndex == 4, isDark, 4, 'assets/footer/jewelley'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    WidgetRef ref,
    String label,
    bool isActive,
    bool isDark,
    int index,
    String svgBase, // e.g. 'assets/footer/home'
  ) {
    final inactiveColor = isDark ? Colors.white54 : const Color(0xFF666666);
    // Pick the correct pre-coloured SVG variant
    final svgPath = isActive ? '$svgBase-green.svg' : '$svgBase-grey.svg';

    return InkWell(
      onTap: () => _onTabTapped(index),
      borderRadius: BorderRadius.circular(20.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(4.w),
            child: SvgPicture.asset(
              svgPath,
              width: 22.sp,
              height: 22.sp,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.sp,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? AppTheme.primaryGreen : inactiveColor,
            ),
          ),
        ],
      ),
    );
  }
}
