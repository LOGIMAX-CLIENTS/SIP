import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../shared/theme/app_theme.dart';
import '../../routes/app_router.dart';
import '../../core/providers/market_provider.dart';
import '../market/models/market_rates.dart';
import '../../core/providers/commodity_provider.dart';
import '../../core/providers/portfolio_provider.dart';
import '../../core/providers/user_provider.dart';
import '../../core/localization/language_provider.dart';
import '../../core/providers/home_dashboard_provider.dart';
import '../../shared/widgets/loaders.dart';
import './models/home_dashboard.dart';
import '../profile/profile_controller.dart';
import '../main/main_screen.dart';
import '../../shared/widgets/numeric_styled_text.dart';
import 'widgets/micro_savings_banner.dart';
import 'widgets/learn_carousel.dart';
import 'widgets/countdown_offer_widget.dart';
import '../../core/providers/countdown_offer_provider.dart';
import '../../core/services/notification_service.dart';
import '../../core/providers/timer_provider.dart';
import '../instant_saving/controller/saving_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    // Fetch fresh notification badge count on home load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(notificationProvider.notifier).refreshUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCommodity = ref.watch(commodityProvider);
    final userProfile = ref.watch(userProvider);
    final profileState =
        ref.watch(profileProvider); // Added to get latest name/profile
    final portfolioState = ref.watch(portfolioProvider);
    final marketRates = ref.watch(marketRatesStreamProvider);
    // Sell rate lock timer — uses sell_rate_lock_seconds from config API.
    // Locks the displayed sell rate for the configured duration (e.g. 120s).
    final timerState = ref.watch(sellRateTimerProvider);
    ref.watch(savingConfigProvider); // keep config subscription alive
    ref.listen(savingConfigProvider, (prev, next) {
      final config = next.valueOrNull;
      if (config != null && !ref.read(sellRateTimerProvider).isActive) {
        ref
            .read(sellRateTimerProvider.notifier)
            .startOrRefresh(config.sellRateLockSeconds);
      }
    });

    // Per-commodity market open/close status from socket
    final marketStatusMap =
        ref.watch(marketStatusProvider).valueOrNull ?? const {};
    final commodityId = selectedCommodity == CommodityType.gold ? '1' : '3';
    final isCurrentMarketClosed = marketStatusMap[commodityId] == false;

    // When market transitions closed \u2192 open: restart timer so the header
    // switches back to LIVE + countdown immediately.
    ref.listen<AsyncValue<Map<String, bool>>>(marketStatusProvider,
        (prev, next) {
      next.whenData((statusMap) {
        final currId = selectedCommodity == CommodityType.gold ? '1' : '3';
        final wasOpen = prev?.valueOrNull?[currId] != false;
        final isNowOpen = statusMap[currId] != false;
        if (!wasOpen && isNowOpen && mounted) {
          ref.read(sellRateTimerProvider.notifier).clear();
          final config = ref.read(savingConfigProvider).valueOrNull;
          if (config != null) {
            ref
                .read(sellRateTimerProvider.notifier)
                .startOrRefresh(config.sellRateLockSeconds);
          }
        }
      });
    });

    // ── Race-condition guard: market-reopen vs first rate frame ─────────
    // When `5|...|1` fires, the timer is restarted but `3|...` rate may not
    // have arrived yet. Lock 0-rate gets replaced as soon as non-zero arrives.
    ref.listen<AsyncValue<MarketRates>>(marketRatesStreamProvider,
        (prev, next) {
      next.whenData((rates) {
        if (!mounted) return;
        final currId = selectedCommodity == CommodityType.gold ? '1' : '3';
        final isMarketOpen =
            (ref.read(marketStatusProvider).valueOrNull ?? {})[currId] != false;
        if (!isMarketOpen) return;
        final liveRate = selectedCommodity == CommodityType.gold
            ? rates.goldSell
            : rates.silverSell;
        if (liveRate <= 0) return;
        final tState = ref.read(sellRateTimerProvider);
        final lockedRate = selectedCommodity == CommodityType.gold
            ? (tState.lockedRates?.goldSell ?? 0.0)
            : (tState.lockedRates?.silverSell ?? 0.0);
        if (tState.isActive && lockedRate <= 0) {
          final config = ref.read(savingConfigProvider).valueOrNull;
          if (config != null) {
            ref
                .read(sellRateTimerProvider.notifier)
                .startOrRefresh(config.sellRateLockSeconds);
          }
        }
      });
    });

    // Auto-refresh ALL Home page APIs whenever Home tab becomes active.
    // Covers: bottom nav tap, returning from payment/withdrawal success.
    // Future.microtask safely defers until after the build frame.
    // Navigation success screens use 350ms delay before switching tab,
    // ensuring animation is fully done before these calls fire.
    ref.listen<int>(selectedTabProvider, (prev, next) {
      if (next == 0 && prev != 0) {
        Future.microtask(() {
          if (mounted) {
            // 1. Portfolio — weight/value updated after purchase/withdrawal
            ref.read(portfolioProvider.notifier).fetchPortfolio();
            // 2. Home dashboard — growth streak, schemes, latest metrics
            ref.invalidate(homeDashboardProvider);
            // 3. Countdown offer — refresh offer state
            ref.invalidate(countdownOfferProvider);
            // 4. Profile — name, photo (in case updated)
            ref.invalidate(profileProvider);
            // 5. Notification badge — refresh unread count
            ref.read(notificationProvider.notifier).refreshUnreadCount();
            // 5. Sell-rate timer — lock freshest live rate for header display
            final homeStatusMap =
                ref.read(marketStatusProvider).valueOrNull ?? const {};
            final homeCommodityId =
                selectedCommodity == CommodityType.gold ? '1' : '3';
            if (homeStatusMap[homeCommodityId] != false) {
              ref.read(sellRateTimerProvider.notifier).clear();
              final homeConfig = ref.read(savingConfigProvider).valueOrNull;
              if (homeConfig != null) {
                ref
                    .read(sellRateTimerProvider.notifier)
                    .startOrRefresh(homeConfig.sellRateLockSeconds);
              }
            }
          }
        });
      }
    });

    // Never block render with full-screen spinner.
    // Header shows immediately; content shimmer-loads below.

    final String customerName = profileState.user.name.isNotEmpty
            ? profileState.user.name
            : (userProfile?.name ?? '');

    final String? photoUrl =
        profileState.user.photoUrl ?? userProfile?.photoUrl;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFFDFBF3),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(portfolioProvider.notifier).fetchPortfolio();
          ref.invalidate(homeDashboardProvider);
          ref.invalidate(countdownOfferProvider);
          ref.invalidate(profileProvider);
          ref.read(notificationProvider.notifier).refreshUnreadCount();
        },
        color: AppTheme.arcticBlue,
        backgroundColor: Colors.transparent,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            _buildPremiumHeader(
                context,
                isDark,
                customerName,
                photoUrl,
                marketRates,
                selectedCommodity,
                timerState,
                isCurrentMarketClosed),
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  // Color visible behind green section's rounded corners
                  // Uses offer card color when offer is active, otherwise rate-history gradient
                  Builder(builder: (context) {
                    final offerAsync = ref.watch(countdownOfferProvider);
                    final isOfferActive =
                        offerAsync.valueOrNull?.enabled ?? false;
                    final hasRateHistory = ref
                            .watch(homeDashboardProvider)
                            .valueOrNull
                            ?.rateHistory !=
                        null;

                    if (!isOfferActive && !hasRateHistory) {
                      return const SizedBox.shrink();
                    }

                    return Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isOfferActive ? const Color(0xFFFFF0CB) : null,
                          gradient: isOfferActive
                              ? null
                              : const LinearGradient(
                                  begin: Alignment(-0.73, -0.68),
                                  end: Alignment(0.73, 0.68),
                                  colors: [
                                    Color(0xFFF9F3E3),
                                    Color(0xFFFFDF90),
                                    Color(0xFFf4bd44),
                                  ],
                                  stops: [0.0, 0.5679, 1.0],
                                ),
                        ),
                      ),
                    );
                  }),
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        // same 120deg gradient as the header
                        begin: Alignment(-0.87, -0.5),
                        end: Alignment(0.87, 0.5),
                        colors: [Color(0xFF003716), Color(0xFF167525)],
                        stops: [0.0223, 0.9399],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24.w),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(height: 8.h),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 350),
                            switchInCurve: Curves.easeOut,
                            child: portfolioState.maybeWhen(
                              data: (data) {
                                if (userProfile?.isNewUser == true ||
                                    data.isNewCustomer) {
                                  return KeyedSubtree(
                                    key: const ValueKey('new_customer_banner'),
                                    child: _buildNewCustomerBanner(context,
                                        selectedCommodity, isCurrentMarketClosed),
                                  );
                                }
                                return KeyedSubtree(
                                  key: const ValueKey('portfolio_overview'),
                                  child: _buildPortfolioOverview(
                                      isDark,
                                      data,
                                      selectedCommodity,
                                      marketRates,
                                      isCurrentMarketClosed),
                                );
                              },
                              // On refresh: if we have previous data keep showing it
                              loading: () {
                                final prev = portfolioState.valueOrNull;
                                if (prev != null) {
                                  if (userProfile?.isNewUser == true ||
                                      prev.isNewCustomer) {
                                    return KeyedSubtree(
                                      key: const ValueKey('new_customer_banner'),
                                      child: _buildNewCustomerBanner(
                                          context,
                                          selectedCommodity,
                                          isCurrentMarketClosed),
                                    );
                                  }
                                  return KeyedSubtree(
                                    key: const ValueKey('portfolio_overview'),
                                    child: _buildPortfolioOverview(
                                        isDark,
                                        prev,
                                        selectedCommodity,
                                        marketRates,
                                        isCurrentMarketClosed),
                                  );
                                }
                                return KeyedSubtree(
                                  key: const ValueKey('portfolio_skeleton'),
                                  child: _buildPortfolioSkeleton(isDark),
                                );
                              },
                              orElse: () => KeyedSubtree(
                                key: const ValueKey('portfolio_error'),
                                child: _buildPortfolioError(isDark),
                              ),
                            ),
                          ),
                          SizedBox(height: 16.h),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── Countdown Offer Widget ──
            SliverToBoxAdapter(
              child: Builder(builder: (context) {
                final offerAsync = ref.watch(countdownOfferProvider);
                final isOfferActive = offerAsync.valueOrNull?.enabled ?? false;

                if (!isOfferActive) {
                  return const CountdownOfferWidget();
                }

                // Stack: fill behind bottom rounded corners with #F3BA3F
                return Stack(
                  children: [
                    // Background fill visible behind bottom rounded corners
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 32,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Color(0xFFF9F0DE),
                              Color(0xFFF3BA3F),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const CountdownOfferWidget(),
                  ],
                );
              }),
            ),
            SliverToBoxAdapter(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                switchInCurve: Curves.easeOut,
                child: Builder(builder: (context) {
                  final dashAsync = ref.watch(homeDashboardProvider);
                  // Keep previous data visible during commodity switch (no shimmer flash)
                  final dashboard = dashAsync.valueOrNull ?? dashAsync.whenData((d) => d).valueOrNull;
                  if (dashAsync.isLoading && dashboard == null) {
                    return _buildHomeScreenSkeleton(isDark);
                  }
                  if (dashAsync.hasError && dashboard == null) {
                    return _buildDashboardError(ref, isDark, dashAsync.error!);
                  }
                  if (dashboard == null)
                    return _buildHomeScreenSkeleton(isDark);
                  return _buildDashboardContent(
                      context, ref, isDark, dashboard);
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context, WidgetRef ref,
      bool isDark, HomeDashboard dashboard) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Rate History Section ──
        if (dashboard.rateHistory != null)
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(-0.73, -0.68),
                end: Alignment(0.73, 0.68),
                colors: [
                  Color(0xFFF9F3E3),
                  Color(0xFFFFDF90),
                  Color(0xFFEB9F00),
                ],
                stops: [0.0, 0.5679, 1.0],
              ),
            ),
            padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 32.h),
            child: _buildGrowthStreakCard(isDark, dashboard.rateHistory!),
          ),
        // ── Unified Card Container ──
        Container(
          width: double.infinity,
          transform: dashboard.rateHistory != null
              ? Matrix4.translationValues(0, -32.h, 0)
              : null,
          decoration: BoxDecoration(
            gradient: isDark
                ? null
                : const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFDFBF3), Color(0xFFF9F2EA)],
                  ),
            color: isDark ? Colors.white.withValues(alpha: 0.06) : null,
            borderRadius: BorderRadius.only(
              topLeft: dashboard.rateHistory != null
                  ? Radius.circular(32.r)
                  : Radius.zero,
              topRight: dashboard.rateHistory != null
                  ? Radius.circular(32.r)
                  : Radius.zero,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 1. Invest Smart, Earn Big ──
              ...() {
                final invest = dashboard.investSection ??
                    InvestSection(title: 'Save Smart, Earn Big', blocks: []);
                return [
                  Padding(
                    padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 0),
                    child: _buildSectionHeader(invest.title, isDark),
                  ),
                  SizedBox(height: 16.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: _buildInvestContent(invest),
                  ),
                ];
              }(),
              SizedBox(height: 32.h),
              // ── 2. Discover StartGold ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: _buildSectionHeader('Discover StartGold', isDark),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: _buildDiscoverSection(isDark),
              ),
              SizedBox(height: 32.h),
              // ── 3. Learn Something New ──
              ...() {
                final learn = dashboard.learningSection ??
                    LearningSection(title: 'Learn Something New', banners: []);

                // Use dynamic banner images from API if available,
                // otherwise fall back to static asset images.
                final List<String> carouselImages = learn.banners.isNotEmpty
                    ? learn.banners.map((b) => b.image).toList()
                    : const [
                        'assets/home/learn1.png',
                        'assets/home/learn2.png',
                        'assets/home/learn3.png',
                      ];

                return [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: _buildSectionHeader(learn.title, isDark),
                  ),
                  SizedBox(height: 16.h),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w),
                    child: LearnCarousel(images: carouselImages),
                  ),
                ];
              }(),
              SizedBox(height: 32.h),
              // ── 4. Get Support ──
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: _buildSectionHeader('Get Support', isDark),
              ),
              SizedBox(height: 16.h),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.w),
                child: _buildSupportSection(isDark),
              ),
            ],
          ),
        ),
        // Footer Info
        if (dashboard.footerInfo != null)
          Container(
            transform: dashboard.rateHistory != null
                ? Matrix4.translationValues(0, -32.h, 0)
                : null,
            child: _buildFooterInfo(isDark, dashboard.footerInfo!),
          ),
        SizedBox(height: 120.h),
      ],
    );
  }

  Widget _buildDashboardError(WidgetRef ref, bool isDark, Object error) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 48.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 36.h),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(24.r),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.r,
              height: 64.r,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFFFF1F0), Color(0xFFFFE4E1)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(Icons.cloud_off_rounded,
                  size: 28.sp, color: const Color(0xFFE85D5D)),
            ),
            SizedBox(height: 20.h),
            Text(
              'Unable to Connect',
              style: GoogleFonts.playfairDisplay(
                fontSize: 17.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Please check your internet\nconnection and try again',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                height: 1.5,
                color: const Color(0xFF8E8E9A),
              ),
            ),
            SizedBox(height: 28.h),
            SizedBox(
              width: double.infinity,
              height: 48.h,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1B882C), Color(0xFF003716)],
                  ),
                  borderRadius: BorderRadius.circular(14.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF1B882C).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ElevatedButton.icon(
                  onPressed: () => ref.invalidate(homeDashboardProvider),
                  icon: Icon(Icons.refresh_rounded,
                      size: 18.sp, color: Colors.white),
                  label: Text(
                    'Try Again',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14.r)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreenSkeleton(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 32.h),
        // Growth Streak card skeleton
        AppLoaders.sectionLoader(
            height: 180.h,
            width: double.infinity,
            isDark: isDark,
            borderRadius: 24),
        SizedBox(height: 48.h),
        // Section title skeleton (e.g. "Invest in Gold")
        AppLoaders.sectionLoader(
            height: 18.h, width: 140.w, isDark: isDark, borderRadius: 8),
        SizedBox(height: 20.h),
        // Invest Block skeleton
        AppLoaders.sectionLoader(
            height: 120.h,
            width: double.infinity,
            isDark: isDark,
            borderRadius: 20),
        SizedBox(height: 16.h),
        AppLoaders.sectionLoader(
            height: 120.h,
            width: double.infinity,
            isDark: isDark,
            borderRadius: 20),
        SizedBox(height: 48.h),
        // Discover section title
        AppLoaders.sectionLoader(
            height: 18.h, width: 170.w, isDark: isDark, borderRadius: 8),
        SizedBox(height: 20.h),
        // Discover row
        Row(
          children: [
            Expanded(
                child: AppLoaders.sectionLoader(
                    height: 100.h,
                    width: double.infinity,
                    isDark: isDark,
                    borderRadius: 20)),
            SizedBox(width: 16.w),
            Expanded(
                child: AppLoaders.sectionLoader(
                    height: 100.h,
                    width: double.infinity,
                    isDark: isDark,
                    borderRadius: 20)),
          ],
        ),
        SizedBox(height: 80.h),
      ],
    );
  }

  /// Renders a full-width image card for each invest block.
  /// Supports both asset paths (assets/...) and network URLs.
  Widget _buildInvestBlock(InvestBlock block) {
    final img = block.image ?? '';
    if (img.isEmpty) return const SizedBox.shrink();

    final isAsset = img.startsWith('assets/');
    Widget image = isAsset
        ? Image.asset(
            img,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, __, ___) => _investBlockPlaceholder(),
          )
        : Image.network(
            img,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            errorBuilder: (_, __, ___) => _investBlockPlaceholder(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: image,
    );
  }

  Widget _investBlockPlaceholder() => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF7ED), Color(0xFFFFEDD5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Center(
          child: Icon(
            Icons.image_not_supported_outlined,
            color: const Color(0xFF91411D).withValues(alpha: 0.3),
            size: 40.sp,
          ),
        ),
      );

  /// Renders invest section: static SVGs if empty, dynamic cards otherwise.
  Widget _buildInvestContent(InvestSection section) {
    if (section.blocks.isEmpty) {
      return _buildStaticInvestBlocks();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: section.blocks.asMap().entries.map((entry) {
        final isLast = entry.key == section.blocks.length - 1;
        return Padding(
          padding: EdgeInsets.only(bottom: isLast ? 0 : 16.h),
          child: _buildInvestBlock(entry.value),
        );
      }).toList(),
    );
  }

  /// Static fallback invest cards when API blocks list is empty.
  Widget _buildStaticInvestBlocks() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MicroSavingsBanner(
          onSwipeComplete: () =>
              Navigator.pushNamed(context, AppRouter.autoSavings),
        ),
        SizedBox(height: 16.h),
        _buildStaticInvestCard(
          'assets/home/safe.gif',
          title: 'Safe & Secure',
          subtitle:
              'Your assets are safely stored in secure vaults and\nare available for withdrawal anytime.',
        ),
      ],
    );
  }

  Widget _buildStaticInvestCard(String imagePath,
      {String? title, String? subtitle}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: Stack(
        children: [
          Image.asset(
            imagePath,
            width: double.infinity,
            fit: BoxFit.fitWidth,
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                height: 160.h,
                color: const Color(0xFFFFEFC0),
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Colors.amber, size: 48),
                ),
              );
            },
          ),
          if (title != null || subtitle != null)
            Positioned(
              left: 20.w,
              top: 24.h,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(
                      title,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w600,
                        color: const Color(
                            0xFF643D41), // Deep premium red/brown matches yellow/gold theme
                      ),
                    ),
                  if (subtitle != null) ...[
                    SizedBox(height: 4.h),
                    Text(
                      subtitle,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF643D41).withValues(alpha: 0.8),
                      ),
                    ),
                  ]
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Text(
      title,
      style: GoogleFonts.playfairDisplay(
        fontSize: 16.sp,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black87,
        height: 1.0,
        letterSpacing: 0,
      ),
    );
  }

  Widget _buildDiscoverSection(bool isDark) {
    final items = [
      {
        'title': 'Cash\nWithdrawal',
        'svg': 'assets/home/cash.svg',
        'route': AppRouter.withdrawal,
      },
      {
        'title': 'Refer & Earn\nRewards',
        'svg': 'assets/home/referearn.svg',
        'route': AppRouter.referral,
      },
      {
        'title': "Auto Saving",
        'svg': 'assets/home/sip.svg',
        'route': AppRouter.autoSavings,
      },
    ];

    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items.map((item) {
          return Expanded(
            child: GestureDetector(
              onTap: () {
                final route = item['route'] as String?;
                if (route != null) Navigator.pushNamed(context, route);
              },
              child: Container(
                margin: EdgeInsets.symmetric(horizontal: 6.w),
                padding: EdgeInsets.symmetric(vertical: 20.h, horizontal: 8.w),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: const Color(0x1A414141),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SvgPicture.asset(
                      item['svg'] as String,
                      width: 36.r,
                      height: 36.r,
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      item['title'] as String,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSupportSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Have a question or need help? Our support team is always ready to assist you.',
          style: GoogleFonts.playfairDisplay(
            fontSize: 13.sp,
            color: isDark ? Colors.white60 : Colors.black54,
            height: 1.5,
          ),
        ),
        SizedBox(height: 16.h),
        GestureDetector(
          onTap: () => Navigator.pushNamed(context, AppRouter.contact),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              borderRadius: BorderRadius.circular(20.r),
              border: Border.all(
                color: isDark
                    ? Colors.white10
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 24.sp,
                  color: isDark ? Colors.white54 : const Color(0xFF6B7280),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Text(
                    'Help & Support?',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF6D47C),
                    borderRadius: BorderRadius.circular(100.r),
                  ),
                  child: Text(
                    'Contact Us',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF6C4B08),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooterInfo(bool isDark, FooterInfo info) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        image: isDark
            ? null
            : const DecorationImage(
                image: AssetImage('assets/home/footerinfobg.png'),
                fit: BoxFit.cover,
              ),
        color: isDark ? Colors.white.withValues(alpha: 0.06) : null,
      ),
      padding: EdgeInsets.fromLTRB(24.w, 40.h, 24.w, 48.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title
          NumericStyledText(
            info.title,
            fontSize: 26.sp,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
            height: 36 / 26,
          ),
          SizedBox(height: 16.h),
          // Subtitle
          Text(
            info.subtitle,
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : const Color(0xFF4B4B4B),
              height: 20 / 13,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 28.h),
          // Compliance badges
          Center(
            child: SvgPicture.asset(
              'assets/resources/splash_footer.svg',
              height: 40.h,
              fit: BoxFit.contain,
            ),
          ),
          SizedBox(height: 32.h),
          // CIN row
          if (info.cin.isNotEmpty) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CIN: ',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white70 : const Color(0xFF1A1A1A),
                    height: 1.4,
                  ),
                ),
                Expanded(
                  child: NumericStyledText(
                    info.cin,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white54 : const Color(0xFF4B4B4B),
                    height: 1.4,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
          ],
          // Copyright
          if (info.copyright.isNotEmpty)
            NumericStyledText(
              info.copyright,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white38 : const Color(0xFF888888),
              height: 1.4,
            ),
        ],
      ),
    );
  }

  Widget _buildPremiumHeader(
      BuildContext context,
      bool isDark,
      String customerName,
      String? photoUrl,
      AsyncValue<MarketRates> marketRates,
      CommodityType selected,
      TimerState timerState,
      bool isMarketClosed) {
    // When market is closed, skip the timer's stale locked rate and use the
    // live socket rate (which is already zeroed for that commodity).
    final lockedRates = (!isMarketClosed && timerState.isActive)
        ? timerState.lockedRates
        : null;
    final rate = selected == CommodityType.gold
        ? (lockedRates?.goldSell ?? marketRates.valueOrNull?.goldSell ?? 0.0)
        : (lockedRates?.silverSell ??
            marketRates.valueOrNull?.silverSell ??
            0.0);
    final formattedRate = rate.toStringAsFixed(2);

    // Show "Market Closed" label instead of countdown when market is offline.
    String? timerText;
    if (isMarketClosed) {
      timerText = null; // header shows Market Closed badge instead
    } else if (timerState.isActive) {
      final m = timerState.remainingSeconds ~/ 60;
      final s = timerState.remainingSeconds % 60;
      timerText =
          '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }

    final statusBarHeight = MediaQuery.of(context).padding.top;
    return SliverPersistentHeader(
      pinned: true,
      delegate: PremiumHomeHeader(
        expandedHeight: statusBarHeight + 130.h,
        statusBarHeight: statusBarHeight,
        isDark: isDark,
        customerName: customerName,
        welcomeText: ref.tr('welcome'),
        photoUrl: photoUrl,
        currentRate: '₹$formattedRate/gm',
        timerText: timerText,
        isMarketClosed: isMarketClosed,
        selected: selected,
        unreadCount: ref.watch(unreadCountProvider),
      ),
    );
  }

  /// Format number with Indian comma separators (e.g., 16446 → 16,446).
  String _formatIndianRate(double rate) {
    final intPart = rate % 1 == 0 ? rate.toInt().toString() : rate.toString();
    // Only format the integer portion
    final parts = intPart.split('.');
    String digits = parts[0];
    if (digits.length <= 3) return intPart;
    // Indian grouping: last 3 digits, then groups of 2
    final last3 = digits.substring(digits.length - 3);
    String rest = digits.substring(0, digits.length - 3);
    final buffer = StringBuffer();
    while (rest.length > 2) {
      buffer.write(rest.substring(0, rest.length - 2));
      buffer.write(',');
      rest = rest.substring(rest.length - 2);
    }
    // Rebuild: handle the remaining part
    final groups = <String>[];
    String remaining = digits.substring(0, digits.length - 3);
    while (remaining.length > 2) {
      groups.insert(0, remaining.substring(remaining.length - 2));
      remaining = remaining.substring(0, remaining.length - 2);
    }
    if (remaining.isNotEmpty) groups.insert(0, remaining);
    groups.add(last3);
    final formatted = groups.join(',');
    return parts.length > 1 ? '$formatted.${parts[1]}' : formatted;
  }

  Widget _buildGrowthStreakCard(bool isDark, RateHistory history) {
    final activeOrange = const Color(0xFFE2700D); // "Invest Now" button orange
    final textGreen =
        const Color(0xFF0F582E); // Deep green for big text and bars

    // Determine metal string from highlightText or title
    final isSilver = history.title.toLowerCase().contains('silver');
    final metalString = isSilver ? 'Silver' : 'Gold';

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // ── Column 1: Text + Button ──
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Plain label
                NumericStyledText(
                  history.title,
                  fontSize: 12.sp,
                  color: const Color(0xFF6C4B08),
                  fontWeight: FontWeight.w600,
                ),
                SizedBox(height: 12.h),

                // Main Title — mixed text/numbers
                NumericStyledText(
                  history.highlightText,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w700,
                  color: textGreen,
                  height: 1.2,
                ),
                SizedBox(height: 8.h),

                // Subtitle
                Text(
                  'Save Today, Golden Tomorrow',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    color: textGreen.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 20.h),

                // Button — compact pill
                IntrinsicWidth(
                  child: SizedBox(
                    height: 40.h,
                    child: ElevatedButton(
                      onPressed: () =>
                          ref.read(selectedTabProvider.notifier).state = 1,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: activeOrange,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 28.w),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100.r)),
                        elevation: 0,
                      ),
                      child: Text(
                        'Save Now',
                        style: GoogleFonts.playfairDisplay(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.sp,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12.h),
              ],
            ),
          ),

          // ── Column 2: Bar Chart Image + End Year Label ──
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // End Year badge
                _buildChartDataPoint(
                  '${history.endYear} : ₹${_formatIndianRate(history.endRate.toDouble())}/g',
                  backgroundColor: const Color(0xFFFFB10F),
                  textColor: const Color(0xFF000000),
                ),
                SizedBox(height: 6.h),
                // Bar chart image
                Image.asset(
                  'assets/home/rarehistory-bar.png',
                  fit: BoxFit.contain,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartDataPoint(String label,
      {required Color backgroundColor, required Color textColor}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 3.h),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(100.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: NumericStyledText(
        label,
        fontSize: 8.sp,
        fontWeight: FontWeight.w700,
        color: textColor,
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPortfolioOverview(
      bool isDark,
      PortfolioData data,
      CommodityType selected,
      AsyncValue<MarketRates> market,
      bool isCurrentMarketClosed) {
    // ── Recalculate current value & growth from live rate when API returns 0 ──
    final liveRate = selected == CommodityType.gold
        ? (market.valueOrNull?.goldSell ?? 0.0)
        : (market.valueOrNull?.silverSell ?? 0.0);

    double currentValue = data.summary.currentValue;
    double returns = data.summary.returns;
    double returnsPct = data.summary.returnsPercentage;

    if (currentValue == 0 && data.summary.balance > 0 && liveRate > 0) {
      currentValue = data.summary.balance * liveRate;
      returns = currentValue - data.summary.totalInvested;
      returnsPct = data.summary.totalInvested > 0
          ? ((returns / data.summary.totalInvested) * 100)
          : 0.0;
    }

    final isPositive = returns >= 0;
    // ── End recalculation ──

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E5631).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1.0,
        ),
      ),
      padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 24.w),
      child: Column(
        children: [
          // ── Animated content swap when commodity changes ──
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) =>
                FadeTransition(opacity: animation, child: child),
            child: Column(
              key: ValueKey('portfolio_content_${selected.name}'),
              children: [
                Text(
                  selected == CommodityType.gold
                      ? 'Total Gold Savings'
                      : 'Total Silver Savings',
                  style: GoogleFonts.playfairDisplay(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 15.sp,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 16.h),
                // ── Balance + Growth pill — always centered as a stable unit ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Gradient gm text — Flexible + FittedBox auto-scales long balances
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            begin: const Alignment(-0.87, -0.5),
                            end: const Alignment(0.87, 0.5),
                            colors: selected == CommodityType.gold
                                ? const [Color(0xFFFFB500), Color(0xFFFFCA49)]
                                : const [Color(0xFFB6B6B6), Color(0xFFE5E5E5)],
                          ).createShader(bounds),
                          blendMode: BlendMode.srcIn,
                          child: Text(
                            '${data.summary.balance.toStringAsFixed(6)} gm',
                            style: GoogleFonts.lora(
                              fontSize: 28.sp,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10.w),
                    // Growth pill
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFF023A17),
                        borderRadius: BorderRadius.circular(20.r),
                        border: Border.all(
                          color: const Color(0xFF0B7F03),
                          width: 0.6,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPositive
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                            size: 13.sp,
                            color: isPositive
                                ? const Color(0xFF0ED500)
                                : const Color(0xFFFF1A1A),
                          ),
                          SizedBox(width: 3.w),
                          Text(
                            '${returnsPct.toStringAsFixed(1)}%',
                            style: GoogleFonts.lora(
                              fontSize: 12.sp,
                              fontWeight: FontWeight.bold,
                              color: isPositive
                                  ? const Color(0xFF0ED500)
                                  : const Color(0xFFFF1A1A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 16.h),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, AppRouter.withdrawal),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF335C41),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(vertical: 15.h),
                          minimumSize: Size(0, 36.h),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100.r),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Withdrawal',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () =>
                            ref.read(selectedTabProvider.notifier).state = 1,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF064E3B),
                          padding: EdgeInsets.symmetric(vertical: 15.h),
                          minimumSize: Size(0, 36.h),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100.r),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Save More',
                          style: GoogleFonts.playfairDisplay(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.sp,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          _buildCommodityToggle(selected, isCurrentMarketClosed),
        ],
      ),
    );
  }

  Widget _buildCommodityToggle(CommodityType selected, bool isMarketClosed) {
    final isGold = selected == CommodityType.gold;
    final referralMsg = ref.watch(profileProvider).user.referralMessage.trim();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Gold / Silver pill toggle (matches Instant Saving page style) ──
        Container(
          padding: EdgeInsets.all(4.w),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(100.r),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildCommodityPillTab(
                label: ref.tr('goldLabel', fallback: 'Gold'),
                isActive: isGold,
                isGoldTab: true,
                onTap: () => ref
                    .read(commodityProvider.notifier)
                    .setCommodity(CommodityType.gold),
              ),
              _buildCommodityPillTab(
                label: ref.tr('silverLabel', fallback: 'Silver'),
                isActive: !isGold,
                isGoldTab: false,
                onTap: () => ref
                    .read(commodityProvider.notifier)
                    .setCommodity(CommodityType.silver),
              ),
            ],
          ),
        ),

        // ── Referral message (only when market is CLOSED and message non-empty) ──
        if (isMarketClosed && referralMsg.isNotEmpty) ...[
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14.sp,
                  color: const Color(0xFFD97706),
                ),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    referralMsg,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF92400E),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        // ── Market Closed Banner (commodity-specific) ──
        if (isMarketClosed) ...[
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(
                color: const Color(0xFFF59E0B).withOpacity(0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14.sp,
                  color: const Color(0xFFB45309),
                ),
                SizedBox(width: 6.w),
                Flexible(
                  child: Text(
                    '${selected == CommodityType.gold ? 'Gold' : 'Silver'} market is currently closed. Rates resume when it reopens.',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF92400E),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Individual pill tab for the Gold/Silver commodity toggle.
  /// Uses the same gradient style as the Instant Saving page tabs.
  Widget _buildCommodityPillTab({
    required String label,
    required bool isActive,
    required bool isGoldTab,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 10.h),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: const Alignment(-0.87, -0.5),
                  end: const Alignment(0.87, 0.5),
                  colors: isGoldTab
                      ? const [
                          Color(0xFFEF9B00),
                          Color(0xFFF5AC03),
                          Color(0xFFF9D522),
                          Color(0xFFF8C30D),
                          Color(0xFFF5A702),
                          Color(0xFFE78400),
                        ]
                      : const [
                          Color(0xFFABABAB),
                          Color(0xFFC2C3C5),
                          Color(0xFFDFDFDF),
                          Color(0xFFEEEEEE),
                          Color(0xFFDEDDDD),
                          Color(0xFFBDBDBD),
                          Color(0xFFAFB1AE),
                        ],
                )
              : null,
          borderRadius: BorderRadius.circular(50.r),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: isGoldTab
                        ? const Color(0xFFEF9B00).withOpacity(0.35)
                        : const Color(0xFFBDBDBD).withOpacity(0.35),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: isActive
                  ? (isGoldTab
                      ? const Color(0xFF5C3300)
                      : const Color(0xFF3D3D3D))
                  : Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortfolioSkeleton(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E5631).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.05),
          width: 1.0,
        ),
      ),
      padding: EdgeInsets.symmetric(vertical: 18.h, horizontal: 24.w),
      child: Column(
        children: [
          // ── "Total Gold Savings" label placeholder ──
          Center(
            child: AppLoaders.headerShimmerBlock(
                height: 14.h, width: 130.w, borderRadius: 6),
          ),
          SizedBox(height: 16.h),

          // ── Balance grams + growth pill row ──
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppLoaders.headerShimmerBlock(
                  height: 28.h, width: 150.w, borderRadius: 8),
              SizedBox(width: 10.w),
              AppLoaders.headerShimmerPill(height: 24.h, width: 56.w),
            ],
          ),
          SizedBox(height: 16.h),

          // ── Two action buttons (Withdrawal / Invest More) ──
          Row(
            children: [
              Expanded(
                child: AppLoaders.headerShimmerPill(
                    height: 44.h, width: double.infinity),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: AppLoaders.headerShimmerPill(
                    height: 44.h, width: double.infinity),
              ),
            ],
          ),
          SizedBox(height: 12.h),

          // ── Commodity toggle pill placeholder ──
          Center(
            child: AppLoaders.headerShimmerPill(height: 40.h, width: 180.w),
          ),
        ],
      ),
    );
  }

  Widget _buildPortfolioError(bool isDark) => Center(
      child: Text(ref.tr('portfolioError',
          fallback: 'Failed to load portfolio context.')));

  Widget _buildNewCustomerBanner(BuildContext context, CommodityType selected,
      bool isCurrentMarketClosed) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 8.w),
          decoration: const BoxDecoration(
            color: Colors
                .transparent, // Inherits the dark green from parent Container
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Text + Button (left side) ──────────────────────────
              Padding(
                padding: EdgeInsets.only(right: 130.w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 19.sp,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.3,
                        ),
                        children: [
                          TextSpan(text: 'From pocket change\n'),
                          TextSpan(
                              text: selected == CommodityType.gold
                                  ? 'to a golden future\n'
                                  : 'to a shining future\n'),
                          TextSpan(text: 'with just '),
                          TextSpan(
                            text: '₹10',
                            style: GoogleFonts.lora(
                                color: const Color(0xFFFBBF24)),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.h),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IntrinsicWidth(
                        child: SizedBox(
                          height: 40.h,
                          child: ElevatedButton(
                            onPressed: () => ref
                                .read(selectedTabProvider.notifier)
                                .state = 1,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: const Color(0xFF033214),
                              padding: EdgeInsets.symmetric(horizontal: 28.w),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(100.r),
                              ),
                              elevation: 0,
                            ),
                            child: Text(
                              'Save Now',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 13.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ── Jar GIF (right side, large) ────────────────────────
              Positioned(
                right: -4.w,
                bottom: -10.h,
                child: SizedBox(
                  width: 115.w,
                  height: 140.h,
                  child: Image.asset(
                    selected == CommodityType.gold
                        ? 'assets/home/goldgf.gif'
                        : 'assets/home/silvergf.gif',
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Icon(
                            selected == CommodityType.gold
                                ? Icons.savings
                                : Icons.auto_awesome,
                            color: const Color(0xFFFBBF24),
                            size: 48.sp),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16.h),
        _buildCommodityToggle(selected, isCurrentMarketClosed),
      ],
    );
  }
}

class PremiumHomeHeader extends SliverPersistentHeaderDelegate {
  final double expandedHeight;
  final double statusBarHeight;
  final bool isDark;
  final String customerName;
  final String welcomeText;
  final String? photoUrl;
  final String? currentRate;
  final String? timerText; // e.g. '02:00' — null if timer not active
  final CommodityType selected;
  final bool isMarketClosed;
  final int unreadCount;

  PremiumHomeHeader({
    required this.expandedHeight,
    required this.statusBarHeight,
    required this.isDark,
    required this.customerName,
    required this.welcomeText,
    this.photoUrl,
    this.currentRate,
    this.timerText,
    required this.isMarketClosed,
    required this.selected,
    this.unreadCount = 0,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          // CSS: linear-gradient(120deg, #003716 2.23%, #167525 93.99%)
          begin: Alignment(-0.87, -0.5), // top-left → dark
          end: Alignment(0.87, 0.5), // bottom-right → light
          colors: [Color(0xFF003716), Color(0xFF167525)],
          stops: [0.0223, 0.9399],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24.w, 10.h, 24.w, 4.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      customerName.isNotEmpty
                          ? 'Hello, $customerName'
                          : 'Welcome',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, AppRouter.notifications),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _buildActionIcon(isDark,
                            Icons.notifications_none_rounded, Colors.white),
                        if (unreadCount > 0)
                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              padding:
                                  EdgeInsets.all(unreadCount > 9 ? 3.r : 4.r),
                              constraints: BoxConstraints(
                                  minWidth: 18.r, minHeight: 18.r),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF1A1A),
                                    Color(0xFFCC0000)
                                  ],
                                ),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: const Color(0xFF003716), width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF1A1A)
                                        .withOpacity(0.5),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  unreadCount > 99 ? '99+' : '$unreadCount',
                                  style: GoogleFonts.lora(
                                    fontSize: unreadCount > 9 ? 8.sp : 9.sp,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              if (currentRate != null)
                Align(
                  alignment: Alignment.center,
                  child: _buildLiveRatePill(currentRate!, isMarketClosed),
                ),
              // Timer runs silently — no countdown shown to user.
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveRatePill(String rate, bool isMarketClosed) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: const Color(0xFF013916),
        borderRadius: BorderRadius.circular(100.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated LIVE or CLOSED badge
          isMarketClosed ? const _ClosedBadge() : const _LiveBadge(),
          SizedBox(width: 14.w),
          // Full rate — tabular figures so digit changes don't shift width
          Text(
            rate,
            style: GoogleFonts.lora(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          SizedBox(width: 10.w),
          ClipOval(
            child: SizedBox(
              width: 20.r,
              height: 20.r,
              child: Image.asset(
                selected == CommodityType.gold
                    ? 'assets/home/goldcoin.gif'
                    : 'assets/home/silvercoin.gif',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 20.r,
                  height: 20.r,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFACC15),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '₹',
                      style: GoogleFonts.lora(
                        fontSize: 10.sp,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF92400E),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionIcon(bool isDark, IconData icon, [Color? color]) {
    return Container(
      padding: EdgeInsets.all(8.r),
      decoration: BoxDecoration(
        color: Colors.transparent,
        border:
            Border.all(color: Colors.white.withValues(alpha: 0.5), width: 1.5),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          icon,
          size: 20.sp,
          color: color ?? Colors.white,
        ),
      ),
    );
  }

  @override
  double get maxExtent => statusBarHeight + 125.h;

  @override
  double get minExtent => statusBarHeight + 125.h;

  @override
  bool shouldRebuild(SliverPersistentHeaderDelegate oldDelegate) => true;
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATED LIVE BADGE — Signal wave bars + pulsing glow
// ═══════════════════════════════════════════════════════════════════════════════
class _LiveBadge extends StatefulWidget {
  const _LiveBadge();

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final glowVal = math.sin(t * 2 * math.pi);
        final glowOpacity = (0.2 + 0.3 * glowVal).clamp(0.0, 1.0);

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF1A1A), Color(0xFFCC0000)],
            ),
            borderRadius: BorderRadius.circular(100.r),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF1A1A).withOpacity(glowOpacity),
                blurRadius: 12,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Wave bars
              SizedBox(
                width: 16.sp,
                height: 12.sp,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(4, (i) {
                    final phase = t * 2 * math.pi + (i * 0.8);
                    final barH = 4.0 + 8.0 * ((math.sin(phase) + 1) / 2);
                    return Container(
                      width: 2.sp,
                      height: barH.sp,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(1.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.4),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(width: 5.w),
              Text(
                'LIVE',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ANIMATED CLOSED BADGE — Flat bars + gentle amber breathing
// ═══════════════════════════════════════════════════════════════════════════════
class _ClosedBadge extends StatefulWidget {
  const _ClosedBadge();

  @override
  State<_ClosedBadge> createState() => _ClosedBadgeState();
}

class _ClosedBadgeState extends State<_ClosedBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final glow = 0.1 + 0.2 * _controller.value;

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFD97706), Color(0xFFB45309)],
            ),
            borderRadius: BorderRadius.circular(100.r),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFD97706).withOpacity(glow),
                blurRadius: 8,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Static flat bars (paused wave)
              SizedBox(
                width: 16.sp,
                height: 12.sp,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: List.generate(4, (i) {
                    return Container(
                      width: 2.sp,
                      height: 3.sp,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(1.r),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(width: 5.w),
              Text(
                'CLOSED',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
