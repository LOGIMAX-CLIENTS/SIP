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
import '../../routes/app_router.dart';
import '../../core/security/secure_logger.dart';
import '../kyc/controllers/kyc_controller.dart';

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
  // Dedupe guards for MainScreen's OWN navigation decision only — kept
  // PRIVATE, deliberately NOT the same Set that KycScreen claims into
  // (AadhaarNotifier.handledMismatchIds/etc.). These two concerns looked
  // identical but aren't: when no KycScreen is mounted, MainScreen must
  // navigate to KycScreen SO THAT it can then claim the shared Set and show
  // its dialog — if MainScreen itself claimed the shared Set first (a prior
  // version of this fix did exactly that), the freshly-navigated-to
  // KycScreen's own claim attempt would find it already taken and silently
  // skip showing anything at all, confirmed live via [KYC DEBUG] logs
  // (MainScreen navigated, then dead silence — no _showMismatchDialog
  // entered ever logged). MainScreen only ever READS the shared Set (via
  // AadhaarNotifier.handledMismatchIds.contains(...)) to check "has someone
  // already claimed this," and uses its own private Set purely to avoid
  // scheduling more than one navigation for the same outcome.
  final Set<String> _navigatedMismatchIds = {};
  final Set<String> _navigatedFailureKeys = {};
  final Set<String> _navigatedApprovedKeys = {};

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

  /// App-shell-level fallback for the Aadhaar/PAN mismatch dialogs AND the
  /// terminal expired/rejected/failed dialog: rather than showing anything
  /// itself on whatever tab the user happens to be on (Profile, Home,
  /// wherever the SDK bounce landed them — confusing, since that's not
  /// where they were verifying), this navigates back to the KYC
  /// Verification screen and lets IT show the result. KycScreen's own
  /// initState (_checkAadhaarOutcomeRecoveryOnLoad) reads aadhaarProvider's
  /// current state on mount and shows whichever dialog applies — the state
  /// itself is still there because aadhaarProvider is kept alive across
  /// this whole span (AadhaarNotifier.pauseAutoDispose/resumeAutoDispose).
  /// A plain push (not pushNamedAndRemoveUntil) — if the user is already
  /// mid-navigation elsewhere, this just adds KYC on top, same as if they'd
  /// tapped into it from Profile themselves.
  void _navigateToKycAndLetItHandle() {
    if (!mounted) return;
    Navigator.of(context).pushNamed(AppRouter.kyc, arguments: {'request_from': 'profile'});
  }

  /// Grace period before MainScreen's own fallback claims a given outcome.
  /// [_shownAadhaarMismatchIds] etc. are now SHARED with KycScreen's own
  /// dedupe (AadhaarNotifier.handledMismatchIds/etc.) — whoever calls
  /// .add() FIRST wins and is the only one that acts. KycScreen's own
  /// ref.listen reacts synchronously the instant the state changes, but
  /// Riverpod doesn't guarantee listener ordering ACROSS separate widgets,
  /// so without a delay MainScreen could occasionally win that race even
  /// while a KycScreen is genuinely mounted and about to show its dialog —
  /// which would silently swallow the claim and the dialog would never
  /// appear at all (confirmed live: this is exactly what a first version of
  /// this fix, with no delay, did). Waiting one frame's worth first gives a
  /// live KycScreen instance's own (near-instant) listener priority; this
  /// fallback only fires when nothing has claimed the outcome after that —
  /// i.e. no KycScreen was actually there to react.
  static const _fallbackGracePeriod = Duration(milliseconds: 150);

  /// [_shownAadhaarMismatchIds] — keyed by verificationId, not a plain bool
  /// — makes this a no-op if KycScreen's own listener already handled this
  /// exact attempt (the normal case where nothing disposes it), and still
  /// allows a genuine reverify (new verification_id) to trigger again.
  void _maybeShowAadhaarMismatchDialog(NameMismatchPrompt prompt) {
    SecureLogger.d('[KYC DEBUG] MainScreen._maybeShowAadhaarMismatchDialog: scheduling fallback for ${prompt.verificationId}');
    Future.delayed(_fallbackGracePeriod, () {
      final alreadyShown = AadhaarNotifier.handledMismatchIds.contains(prompt.verificationId);
      SecureLogger.d('[KYC DEBUG] MainScreen._maybeShowAadhaarMismatchDialog: grace period elapsed, mounted=$mounted, alreadyShownByKycScreen=$alreadyShown');
      if (!mounted || alreadyShown) return;
      if (!_navigatedMismatchIds.add(prompt.verificationId)) return;
      SecureLogger.d('[KYC DEBUG] MainScreen._maybeShowAadhaarMismatchDialog: navigating');
      _navigateToKycAndLetItHandle();
    });
  }

  /// PAN counterpart — same reasoning. [prompt.verificationId] for PAN
  /// actually holds the dedicated PAN KYC row id (see NameMismatchPrompt's
  /// doc comment in kyc_controller.dart for why PAN reuses this field name).
  void _maybeShowPanMismatchDialog(NameMismatchPrompt prompt) {
    Future.delayed(_fallbackGracePeriod, () {
      if (!mounted || AadhaarNotifier.handledMismatchIds.contains(prompt.verificationId)) return;
      if (!_navigatedMismatchIds.add(prompt.verificationId)) return;
      _navigateToKycAndLetItHandle();
    });
  }

  /// Terminal expired/rejected/failed counterpart — same reasoning. Keyed
  /// the same way as KycScreen's own _shownFailureKeys (verificationId+
  /// phase, falling back to message+phase) so this and KycScreen's copy
  /// don't both navigate when nothing actually disposes the screen.
  void _maybeShowAadhaarFailureDialog(AadhaarState state) {
    final key = '${state.verificationId ?? state.message}-${state.phase}';
    Future.delayed(_fallbackGracePeriod, () {
      if (!mounted || AadhaarNotifier.handledFailureKeys.contains(key)) return;
      if (!_navigatedFailureKeys.add(key)) return;
      _navigateToKycAndLetItHandle();
    });
  }

  /// Success counterpart — same reasoning applies to a clean APPROVED
  /// outcome too: if the SDK bounce leaves no KycScreen mounted to run its
  /// own _checkAndHandleCompletion() (the Profile Name Selection dialog /
  /// verified confirmation), the customer never sees any success feedback
  /// at all, silently — indistinguishable from nothing having happened.
  /// Keyed by verificationId so this fires once per genuine approval, not
  /// on every rebuild that still reports the same already-approved state
  /// (e.g. the ordinary case where KycScreen is mounted and handling this
  /// itself — this dedupe guard, not a `mounted` check on MainScreen's
  /// side, is what keeps that from also triggering a redundant navigation).
  void _maybeHandleAadhaarApproved(AadhaarState state) {
    final key = state.verificationId ?? 'approved-${state.maskedNumber}';
    SecureLogger.d('[KYC DEBUG] MainScreen._maybeHandleAadhaarApproved: scheduling fallback for $key');
    Future.delayed(_fallbackGracePeriod, () {
      final alreadyClaimed = AadhaarNotifier.handledApprovedKeys.contains(key);
      SecureLogger.d('[KYC DEBUG] MainScreen._maybeHandleAadhaarApproved: grace elapsed, mounted=$mounted, alreadyClaimedByKycScreen=$alreadyClaimed');
      if (!mounted || alreadyClaimed) return;
      if (!_navigatedApprovedKeys.add(key)) return;
      SecureLogger.d('[KYC DEBUG] MainScreen._maybeHandleAadhaarApproved: navigating');
      _navigateToKycAndLetItHandle();
    });
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
      SecureLogger.d('[KYC DEBUG] MainScreen.ref.listen fired: previous=${previous?.phase} next=${next.phase} mounted=$mounted');
      if (next.phase == AadhaarPhase.awaitingNameMismatchConfirm &&
          next.aadhaarMismatchPrompt != null) {
        _maybeShowAadhaarMismatchDialog(next.aadhaarMismatchPrompt!);
      }
      if (next.panMismatchPrompt != null) {
        _maybeShowPanMismatchDialog(next.panMismatchPrompt!);
      }
      if (next.phase == AadhaarPhase.expired ||
          next.phase == AadhaarPhase.rejected ||
          next.phase == AadhaarPhase.failed) {
        _maybeShowAadhaarFailureDialog(next);
      }
      if (next.phase == AadhaarPhase.approved) {
        _maybeHandleAadhaarApproved(next);
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
