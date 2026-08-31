import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
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
import '../kyc/controllers/kyc_controller.dart';
import '../kyc/repositories/kyc_repository.dart';
import '../kyc/screens/kyc_screen.dart' show NameMismatchDialog;

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
  // Dedupe guards for _maybeShowAadhaarMismatchDialog / _maybeShowPanMismatchDialog
  // — see their doc comments.
  final Set<String> _shownAadhaarMismatchIds = {};
  final Set<String> _shownPanMismatchIds = {};

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
        // Fetch page 1 fresh every time the customer taps into this tab, so
        // a transaction made elsewhere (e.g. Instant Saving, on another
        // device) shows up immediately instead of only after a manual pull-
        // to-refresh. Uses the notifier's refresh() rather than
        // ref.invalidate(historyProvider) — invalidate would recreate the
        // notifier from scratch and silently drop any currently-applied
        // filter; refresh() re-fetches page 1 with whatever filter (if any)
        // is already active, same as the header/pull-to-refresh triggers.
        // Skipped on the very first-ever visit — TransactionHistoryScreen's
        // own build() is about to create the notifier for the first time via
        // ref.watch(historyProvider), and that creation already triggers its
        // own initial fetch; calling refresh() here too would just fire a
        // redundant duplicate request.
        if (_visitedTabs.contains(2)) {
          ref.read(historyProvider.notifier).refresh();
        }
        ref.invalidate(portfolioProvider);
        break;
      case 3:
        ref.invalidate(profileProvider);
        break;
    }
  }

  /// Shows the Aadhaar name/DOB mismatch dialog using THIS (always-alive)
  /// context, regardless of which tab/screen the user is actually looking
  /// at. [_shownAadhaarMismatchIds] — keyed by verificationId, not a plain
  /// bool — makes this a no-op if KycScreen's own listener already handled
  /// this exact attempt (the normal case where nothing disposes it), and
  /// still allows a genuine reverify (new verification_id) to show again.
  Future<void> _maybeShowAadhaarMismatchDialog(NameMismatchPrompt prompt) async {
    if (!_shownAadhaarMismatchIds.add(prompt.verificationId)) return;
    if (!mounted) return;
    final resolved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NameMismatchDialog(
        prompt: prompt,
        onSubmit: (name, dob) => ref.read(aadhaarProvider.notifier).confirmNameMismatch(
              'profile',
              name: name,
              dob: dob,
            ),
      ),
    );
    if (resolved == true) {
      ref.invalidate(profileProvider);
    }
  }

  /// PAN counterpart to _maybeShowAadhaarMismatchDialog — same app-shell
  /// fallback role, same dedupe reasoning. [prompt.verificationId] for PAN
  /// actually holds the dedicated PAN KYC row id (KycRepository.
  /// confirmPanNameMismatch's [panKycId] — see NameMismatchPrompt's doc
  /// comment in kyc_controller.dart for why PAN reuses this field name).
  Future<void> _maybeShowPanMismatchDialog(NameMismatchPrompt prompt) async {
    if (!_shownPanMismatchIds.add(prompt.verificationId)) return;
    if (!mounted) return;
    final resolved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => NameMismatchDialog(
        prompt: prompt,
        onSubmit: (name, dob) async {
          try {
            final data = await ref.read(kycRepositoryProvider).confirmPanNameMismatch(
                  panKycId: prompt.verificationId,
                  confirm: true,
                  name: name,
                  dob: dob,
                );
            final status = (data['status'] ?? '').toString();
            if (status == 'APPROVED') return (NameMismatchOutcome.resolved, null);
            return (NameMismatchOutcome.stillMismatched, data['message']?.toString());
          } catch (e) {
            String msg = e.toString();
            if (msg.startsWith('Exception: ')) msg = msg.substring('Exception: '.length);
            return (NameMismatchOutcome.stillMismatched, msg);
          }
        },
      ),
    );
    if (resolved == true) {
      ref.invalidate(profileProvider);
    }
  }

  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedTabProvider);
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // App-shell-level fallback for the Aadhaar CONFIRM_NAME_UPDATE mismatch
    // dialog. KycScreen has its own ref.listen for this, but SurePass's
    // native DigiLocker SDK Activity can leave the app on a COMPLETELY
    // different screen by the time the poll result comes back — confirmed
    // by testing: the user lands back on this Profile tab, with KycScreen
    // popped off the stack entirely, not merely unmounted underneath
    // something else. No screen-local listener can catch that. MainScreen
    // is the one widget that's guaranteed to stay alive for as long as the
    // user is in the logged-in app shell, so it's the only reliable place
    // for a listener that must survive arbitrary navigation churn.
    // aadhaarProvider itself is kept alive across that churn by
    // AadhaarNotifier.pauseAutoDispose()/resumeAutoDispose() (see
    // kyc_screen.dart's _runVerifyAadhaar) — without that, the provider
    // would already be disposed by the time this fires.
    ref.listen<AadhaarState>(aadhaarProvider, (previous, next) {
      if (next.phase == AadhaarPhase.awaitingNameMismatchConfirm &&
          next.aadhaarMismatchPrompt != null) {
        _maybeShowAadhaarMismatchDialog(next.aadhaarMismatchPrompt!);
      }
      if (next.panMismatchPrompt != null) {
        _maybeShowPanMismatchDialog(next.panMismatchPrompt!);
      }
    });

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
            style: GoogleFonts.playfairDisplay(
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
