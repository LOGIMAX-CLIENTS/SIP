import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../shared/widgets/numeric_styled_text.dart';
import 'package:startgold/core/providers/market_provider.dart';
import 'package:startgold/core/providers/commodity_provider.dart';
import 'package:startgold/core/services/shared_service.dart';
import 'package:startgold/core/providers/user_provider.dart';
import 'package:startgold/core/localization/language_provider.dart';
import 'controller/saving_controller.dart';
import 'models/saving_models.dart';
import '../../routes/app_router.dart';
import 'package:startgold/core/providers/timer_provider.dart';
import '../market/models/market_rates.dart';
import '../main/main_screen.dart';

import '../../shared/widgets/app_toast.dart';

import '../../shared/widgets/gradient_header.dart';
import '../../shared/widgets/loaders.dart';
import '../../core/security/secure_logger.dart';
import '../../core/error/failures.dart';
import '../../shared/utils/no_leading_zeros_formatter.dart';
import 'payment_handler.dart';
import '../../core/providers/countdown_offer_provider.dart';

class InstantSavingScreen extends ConsumerStatefulWidget {
  const InstantSavingScreen({super.key});

  @override
  ConsumerState<InstantSavingScreen> createState() =>
      _InstantSavingScreenState();
}

class _InstantSavingScreenState extends ConsumerState<InstantSavingScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _amountController = TextEditingController();
  late AnimationController _pulseController;
  String _selectedAmount = '';
  bool _isAmountMode = true;

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ── Route args (optional deep-link amount) ──
      final args = ModalRoute.of(context)?.settings.arguments as Map?;
      if (args != null && args['initialAmount'] != null) {
        final amount = args['initialAmount'].toString();
        setState(() {
          _selectedAmount = amount;
          _amountController.text = amount;
        });
      }

      // ── Always lock the freshest live rate on screen entry ─────────────
      // Clear any stale lock (even if timer is still running with an 80s-old
      // rate) and restart immediately with the current socket rate.
      // Only skip when market is closed for the current commodity.
      final entryType = ref.read(commodityProvider);
      final entryCommodityId = entryType == CommodityType.gold ? '1' : '3';
      final entryStatusMap =
          ref.read(marketStatusProvider).valueOrNull ?? const {};
      if (entryStatusMap[entryCommodityId] != false) {
        ref.read(sellRateTimerProvider.notifier).clear();
        final existingConfig = ref.read(savingConfigProvider).valueOrNull;
        if (existingConfig != null) {
          ref
              .read(sellRateTimerProvider.notifier)
              .startOrRefresh(existingConfig.sellRateLockSeconds);
        }
      }
      // Always re-fetch rate config and denominations so the listener fires
      // and re-locks rates, and denomination chips show fresh API data.
      ref.invalidate(savingConfigProvider);
      ref.invalidate(amountDenominationsProvider);
      ref.invalidate(weightDenominationsProvider);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final type = ref.watch(commodityProvider);
    final configAsync = ref.watch(savingConfigProvider);
    final amountDenoms = ref.watch(amountDenominationsProvider);
    final weightDenoms = ref.watch(weightDenominationsProvider);
    final timerState = ref.watch(sellRateTimerProvider);

    // Refresh rate config and denominations when navigating back to the Invest tab.
    ref.listen<int>(selectedTabProvider, (previous, next) {
      if (next == 1) {
        ref.invalidate(savingConfigProvider);
        ref.invalidate(amountDenominationsProvider);
        ref.invalidate(weightDenominationsProvider);
      }
    });

    // Sync timer with config
    ref.listen<AsyncValue<SavingConfig>>(savingConfigProvider, (prev, next) {
      if (next.hasValue &&
          next.value != null &&
          !ref.read(sellRateTimerProvider).isActive) {
        ref
            .read(sellRateTimerProvider.notifier)
            .startOrRefresh(next.value!.sellRateLockSeconds);
      }
    });

    // Safety guard: if config is already loaded but timer is not active
    // (e.g. after timer hits 0:00 and briefly loses isActive), restart it
    // immediately. This is the same guard withdrawal screen uses and is why
    // withdrawal correctly restarts but instant saving previously didn't.
    if (configAsync.hasValue &&
        configAsync.value != null &&
        !timerState.isActive) {
      Future.microtask(() {
        if (mounted) {
          ref
              .read(sellRateTimerProvider.notifier)
              .startOrRefresh(configAsync.value!.sellRateLockSeconds);
        }
      });
    }

    // Reset input when switching between Gold and Silver.
    // Do NOT invalidate denomination providers here — they use
    // selectedMetalIdProvider as a key and ALREADY auto-refresh when the
    // commodity changes. Invalidating them here causes a visible loading
    // flicker on the full page each time the user taps Gold/Silver.
    ref.listen<CommodityType>(commodityProvider, (prev, next) {
      if (prev != next) {
        _amountController.clear();
        _selectedAmount = '';

        // Reset the shared timer so the new commodity's market state is
        // evaluated fresh.
        ref.read(sellRateTimerProvider.notifier).clear();
        final config = ref.read(savingConfigProvider).valueOrNull;
        if (config != null) {
          ref
              .read(sellRateTimerProvider.notifier)
              .startOrRefresh(config.sellRateLockSeconds);
        }
      }
    });

    // ── Market status: detect open/close for CURRENT commodity ─────────────
    // closed → banner + badge show (driven by isCurrentMarketClosed below)
    // opened → banner/badge clear AND timer restarts with a fresh rate lock
    ref.listen<AsyncValue<Map<String, bool>>>(marketStatusProvider,
        (prev, next) {
      next.whenData((statusMap) {
        final currId = type == CommodityType.gold ? '1' : '3';
        final wasOpen = prev?.valueOrNull?[currId] != false; // null = open
        final isNowOpen = statusMap[currId] != false; // null = open

        if (!wasOpen && isNowOpen && mounted) {
          // Transition: closed → open. Restart timer so LIVE countdown
          // reappears and the new live rate gets locked.
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
    // `5|...|1` (market open) fires before `3|...` (rate update) arrives.
    // The market-open listener calls startOrRefresh with the current (still-0)
    // rate. Fix: when the first non-zero rate comes in and the timer is
    // locked on 0, restart immediately to capture the correct live rate.
    ref.listen<AsyncValue<MarketRates>>(marketRatesStreamProvider,
        (prev, next) {
      next.whenData((rates) {
        if (!mounted) return;
        final currId = type == CommodityType.gold ? '1' : '3';
        final isMarketOpen =
            (ref.read(marketStatusProvider).valueOrNull ?? {})[currId] != false;
        if (!isMarketOpen) return;
        final liveRate =
            type == CommodityType.gold ? rates.goldSell : rates.silverSell;
        if (liveRate <= 0) return;
        final tState = ref.read(sellRateTimerProvider);
        final lockedRate = type == CommodityType.gold
            ? (tState.lockedRates?.goldSell ?? 0.0)
            : (tState.lockedRates?.silverSell ?? 0.0);
        if (tState.isActive && lockedRate <= 0) {
          // Timer was started with a 0 rate — lock the freshly arrived rate.
          final config = ref.read(savingConfigProvider).valueOrNull;
          if (config != null) {
            ref
                .read(sellRateTimerProvider.notifier)
                .startOrRefresh(config.sellRateLockSeconds);
          }
        }
      });
    });

    ref.listen<AsyncValue<List<AmountDenomination>>>(
        amountDenominationsProvider, (prev, next) {
      if (next.hasValue && next.value != null && _isAmountMode) {
        final denoms = next.value!;
        if (denoms.isNotEmpty) {
          final popular =
              denoms.firstWhere((d) => d.isPopular, orElse: () => denoms.first);
          final String valStr = popular.value % 1 == 0
              ? popular.value.toInt().toString()
              : popular.value.toString();
          setState(() {
            _amountController.text = valStr;
            _selectedAmount = valStr;
          });
        }
      }
    });

    // Seed popular weight denomination
    ref.listen<AsyncValue<List<WeightDenomination>>>(
        weightDenominationsProvider, (prev, next) {
      if (next.hasValue && next.value != null && !_isAmountMode) {
        final denoms = next.value!;
        if (denoms.isNotEmpty) {
          final popular =
              denoms.firstWhere((d) => d.isPopular, orElse: () => denoms.first);
          final String valStr = popular.value % 1 == 0
              ? popular.value.toInt().toString()
              : popular.value.toString();
          setState(() {
            _amountController.text = valStr;
            _selectedAmount = valStr;
          });
        }
      }
    });

    // \u2500\u2500 Per-commodity market status (from socket) \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // '1' = Gold 24K, '3' = Silver (socket commodity IDs).
    // Commodity absent from map = no signal yet = assume open.
    final marketStatusMap =
        ref.watch(marketStatusProvider).valueOrNull ?? const {};
    final commodityId = type == CommodityType.gold ? '1' : '3';
    final isCurrentMarketClosed = marketStatusMap[commodityId] == false;

    // \u2500\u2500 Stable market rate computation \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    // Always watch the live stream (so Riverpod tracks the dependency)
    // but prefer the timer-locked rate when available.
    // The old ternary approach switched ref.watch between branches —
    // when isActive briefly went false, the UI flicked to a different
    // data source causing the zig-zag shake effect.
    final liveMarket = ref.watch(marketRatesStreamProvider);
    final MarketRates? displayRates = isCurrentMarketClosed
        ? liveMarket.valueOrNull // market closed \u2192 use socket (0)
        : (timerState.lockedRates ?? // timer active OR just expired
            liveMarket.valueOrNull); // fallback to live rate
    final marketState = displayRates != null
        ? AsyncData<MarketRates>(displayRates)
        : liveMarket; // still loading on first open

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // \u2500\u2500 Gradient Header \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          GradientHeader(
            title: ref.tr('Instant Saving'),
            onBack: () {
              final routeName = ModalRoute.of(context)?.settings.name;
              if (routeName == AppRouter.instantSaving) {
                Navigator.pop(context);
              } else {
                ref.read(selectedTabProvider.notifier).state = 0;
              }
            },
          ),

          // \u2500\u2500 Market Closed Amber Banner \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          // Slides in/out smoothly; no popup — stays inline with the page.
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isCurrentMarketClosed
                ? Container(
                    width: double.infinity,
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                    color: const Color(0xFFFEF3C7),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: const Color(0xFFB45309), size: 16.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            '${type == CommodityType.gold ? 'Gold' : 'Silver'} market is closed. Rates resume when market opens.',
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
                  )
                : const SizedBox.shrink(),
          ),

          // \u2500\u2500 Scrollable body \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: 12.h),
                  // Live rate — on light background per Figma
                  _buildLiveRateChip(isDark, type, marketState, timerState,
                      isCurrentMarketClosed),
                  SizedBox(height: 12.h),
                  _buildCommodityTabs(isDark, type),
                  SizedBox(height: 10.h),
                  _buildAmountInputCard(isDark, type, marketState, configAsync,
                      amountDenoms, weightDenoms),
                  // ── Best Offer block (Gold only, when countdown offer is enabled & silver market open) ──
                  if (type == CommodityType.gold && marketStatusMap['3'] != false)
                    _buildBestOfferBlock(isDark, marketState, configAsync),
                  SizedBox(height: 16.h),
                ],
              ),
            ),
          ),

          // ── Pinned bottom action ─────────────────────────────
          _buildBottomAction(isDark, marketState, type, configAsync),
        ],
      ),
    );
  }

  Widget _buildLiveRateChip(
      bool isDark,
      CommodityType type,
      AsyncValue<MarketRates> market,
      TimerState timerState,
      bool isCurrentMarketClosed) {
    // Use maybeWhen so we can give the loading state the SAME layout
    // as the data state. market.when's loading branch collapsed the chip
    // to SizedBox(50) which caused the visible zig-zag shake.
    final rates = market.valueOrNull;
    final price = rates != null
        ? (type == CommodityType.gold ? rates.goldSell : rates.silverSell)
        : 0.0;
    final hasData = rates != null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left: label + metal badge
              Row(
                children: [
                  Text(
                    'Live Selling Price',
                    style: TextStyle(
                      fontSize: 14.sp,
                      color: Colors.black45,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(width: 8.w),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: const Color(0xFF064E3B).withOpacity(0.05),
                      borderRadius: BorderRadius.circular(4.r),
                      border: Border.all(
                          color: const Color(0xFF064E3B).withOpacity(0.1)),
                    ),
                    child: NumericStyledText(
                      type == CommodityType.gold ? '24K Gold' : 'Pure Silver',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF064E3B),
                    ),
                  ),
                ],
              ),

              // Right: countdown OR market-closed badge.
              if (isCurrentMarketClosed)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                        color: const Color(0xFFD97706).withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_mall_directory_outlined,
                          size: 12.sp, color: const Color(0xFFD97706)),
                      SizedBox(width: 4.w),
                      Text(
                        'Market Closed',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: const Color(0xFFD97706),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else if (timerState.isActive)
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: const Color(0xFF064E3B).withOpacity(0.07),
                    borderRadius: BorderRadius.circular(20.r),
                    border: Border.all(
                        color: const Color(0xFF064E3B).withOpacity(0.15)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 12.sp, color: const Color(0xFF064E3B)),
                      SizedBox(width: 4.w),
                      SizedBox(
                        width: 38.w,
                        child: Text(
                          '${timerState.remainingSeconds ~/ 60}:${(timerState.remainingSeconds % 60).toString().padLeft(2, '0')}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.lora(
                            fontSize: 12.sp,
                            color: const Color(0xFF064E3B),
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          SizedBox(height: 8.h),
          // Rate row — shimmer while loading, real price once data arrives
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (!hasData)
                AppLoaders.sectionLoader(
                    height: 24.h, width: 140.w, isDark: false, borderRadius: 6)
              else
                Text(
                  '\u20b9${price.toStringAsFixed(2)}/gm',
                  style: GoogleFonts.lora(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.black,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (hasData) ...[
                SizedBox(width: 8.w),
                Text(
                  '+3% GST',
                  style: GoogleFonts.lora(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: Colors.black38,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommodityTabs(bool isDark, CommodityType current) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        padding: EdgeInsets.all(4.w),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(100.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildTabItem(
                  'Gold', current == CommodityType.gold, isDark, () {
                ref
                    .read(commodityProvider.notifier)
                    .setCommodity(CommodityType.gold);
              }),
            ),
            Expanded(
              child: _buildTabItem(
                  'Silver', current == CommodityType.silver, isDark, () {
                ref
                    .read(commodityProvider.notifier)
                    .setCommodity(CommodityType.silver);
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(
      String label, bool isActive, bool isDark, VoidCallback onTap) {
    final isGold = label == 'Gold';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(vertical: 10.h),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: const Alignment(-0.87, -0.5),
                  end: const Alignment(0.87, 0.5),
                  colors: isGold
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
                    color: isGold
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
            style: TextStyle(
              fontSize: 14.sp,
              fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
              color: isActive
                  ? (isGold ? const Color(0xFF5C3300) : const Color(0xFF3D3D3D))
                  : (isDark ? Colors.white60 : const Color(0xFF064E3B)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInvestModeItem(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24.w,
            height: 24.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? const Color(0xFF064E3B) : Colors.transparent,
              border: Border.all(
                color: isActive
                    ? const Color(0xFF064E3B)
                    : Colors.black.withOpacity(0.15),
                width: isActive ? 0 : 1.5,
              ),
            ),
            child: isActive
                ? Icon(Icons.check, size: 16.sp, color: Colors.white)
                : null,
          ),
          SizedBox(width: 10.w),
          Text(label,
              style: TextStyle(
                  fontSize: 14.sp,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? Colors.black : Colors.black45)),
        ],
      ),
    );
  }

  Widget _buildAmountInputCard(
      bool isDark,
      CommodityType type,
      AsyncValue<dynamic> market,
      AsyncValue<SavingConfig> configAsync,
      AsyncValue<List<AmountDenomination>> amountDenoms,
      AsyncValue<List<WeightDenomination>> weightDenoms) {
    double inputVal = double.tryParse(_amountController.text) ?? 0.0;
    double conversion = 0.0;
    if (market.hasValue) {
      final rate = type == CommodityType.gold
          ? market.value.goldSell
          : market.value.silverSell;

      if (_isAmountMode) {
        final double gstRate = configAsync.valueOrNull?.gst ?? 3.0;
        final double goldValue = _trunc2(inputVal / (1 + (gstRate / 100)));
        conversion = rate > 0 ? _trunc6(goldValue / rate) : 0.0;
      } else {
        conversion = _trunc2(inputVal * rate);
      }
    }

    // ── Inline validation ──
    final config = configAsync.valueOrNull;
    String? errorMsg;
    if (inputVal > 0 && config != null) {
      double comparable = inputVal;
      if (!_isAmountMode && market.hasValue) {
        final rate = type == CommodityType.gold
            ? market.value.goldSell
            : market.value.silverSell;
        comparable = inputVal * rate;
      }
      if (comparable < config.minAmount) {
        errorMsg =
            'Minimum investment amount is ₹${config.minAmount.toStringAsFixed(0)}';
      } else if (comparable > config.maxAmount) {
        errorMsg =
            'Maximum investment amount is ₹${config.maxAmount.toStringAsFixed(0)}';
      }
    }
    final bool hasError = errorMsg != null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Select invest type ──
            Text('Select Invest Type',
                style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.black45,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child:
                      _buildInvestModeItem('Buy in Rupees', _isAmountMode, () {
                    setState(() {
                      _isAmountMode = true;
                      _amountController.clear();
                      _selectedAmount = '';
                      final denoms =
                          ref.read(amountDenominationsProvider).valueOrNull;
                      if (denoms != null && denoms.isNotEmpty) {
                        final popular = denoms.firstWhere((d) => d.isPopular,
                            orElse: () => denoms.first);
                        final String valStr = popular.value % 1 == 0
                            ? popular.value.toInt().toString()
                            : popular.value.toString();
                        _amountController.text = valStr;
                        _selectedAmount = valStr;
                      }
                    });
                  }),
                ),
                Expanded(
                  child:
                      _buildInvestModeItem('Buy in Grams', !_isAmountMode, () {
                    setState(() {
                      _isAmountMode = false;
                      _amountController.clear();
                      _selectedAmount = '';
                      final denoms =
                          ref.read(weightDenominationsProvider).valueOrNull;
                      if (denoms != null && denoms.isNotEmpty) {
                        final popular = denoms.firstWhere((d) => d.isPopular,
                            orElse: () => denoms.first);
                        final String valStr = popular.value % 1 == 0
                            ? popular.value.toInt().toString()
                            : popular.value.toString();
                        _amountController.text = valStr;
                        _selectedAmount = valStr;
                      }
                    });
                  }),
                ),
              ],
            ),

            SizedBox(height: 10.h),
            Divider(height: 1, color: Colors.black.withOpacity(0.05)),
            SizedBox(height: 8.h),

            // ── Enter your saving amount ──
            Text('Enter Your Saving Amount',
                style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.black45,
                    fontWeight: FontWeight.w600)),
            SizedBox(height: 6.h),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(
                  color: hasError
                      ? const Color(0xFFE53935).withOpacity(0.5)
                      : Colors.black.withOpacity(0.05),
                  width: hasError ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  // Left prefix: '₹' for amount mode, 'gms' for grams mode
                  if (_isAmountMode)
                    Text('₹',
                        style: GoogleFonts.lora(
                            fontSize: 20.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black)),
                  if (!_isAmountMode)
                    Text('Gm',
                        style: GoogleFonts.lora(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54)),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      onChanged: (v) => setState(() => _selectedAmount = v),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*')),
                        const NoLeadingZerosFormatter(),
                      ],
                      style: GoogleFonts.lora(
                          fontSize: 20.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.black),
                      decoration: const InputDecoration(
                          border: InputBorder.none, hintText: '0'),
                    ),
                  ),
                  // Right side: INR equivalent (grams mode) or weight (amount mode)
                  if (inputVal > 0)
                    Text(
                      _isAmountMode
                          ? '${conversion.toStringAsFixed(6)}gm'
                          : '\u20b9${conversion.toStringAsFixed(2)}',
                      style: GoogleFonts.lora(
                          fontSize: 12.sp,
                          color: Colors.black45,
                          fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            if (hasError) ...[
              SizedBox(height: 6.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(
                      color: const Color(0xFFE53935).withOpacity(0.18)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14.sp, color: const Color(0xFFE53935)),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        errorMsg!,
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            SizedBox(height: 8.h),
            _isAmountMode
                ? amountDenoms.maybeWhen(
                    data: (list) => _buildDenominationsRow(list),
                    orElse: () => const SizedBox(),
                  )
                : weightDenoms.maybeWhen(
                    data: (list) => _buildDenominationsRow(list),
                    orElse: () => const SizedBox(),
                  ),
          ],
        ),
      ),
    );
  }

  /// Best Offer block — shows FREE SILVER reward info.
  /// Only rendered when:
  ///   1. Countdown offer is enabled (server settings)
  ///   2. Gold commodity is selected (not Silver)
  Widget _buildBestOfferBlock(
      bool isDark,
      AsyncValue<MarketRates> marketState,
      AsyncValue<SavingConfig> configAsync) {
    final offerAsync = ref.watch(countdownOfferProvider);

    return offerAsync.maybeWhen(
      data: (offer) {
        if (!offer.enabled) return const SizedBox.shrink();

        // Determine reward percentage from the offer
        // For NEW customers: if input amount >= benchmark_amount, use
        // benchmark_percentage; otherwise use reward_percentage.
        final double inputVal =
            double.tryParse(_amountController.text) ?? 0.0;
        final int rewardPercentage;
        if (offer.customerType == 'EXISTING' && offer.existingOffer != null) {
          rewardPercentage = offer.existingOffer!.currentRewardPercentage;
        } else if (offer.customerType == 'NEW' && offer.newOffer != null) {
          final newOffer = offer.newOffer!;
          if (newOffer.benchmarkEnabled &&
              newOffer.benchmarkAmount > 0 &&
              inputVal >= newOffer.benchmarkAmount) {
            rewardPercentage = newOffer.benchmarkPercentage;
          } else {
            rewardPercentage = newOffer.rewardPercentage;
          }
        } else {
          return const SizedBox.shrink();
        }

        // Calculate silver reward step-by-step.
        // Precision rules (matching backend):
        //   - Amounts (₹) → truncate to 2 decimals
        //   - Weights (gm) → truncate to 6 decimals
        //
        // Backend formula:
        //   so_qty       = gold weight in grams                    (6 decimals)
        //   target_wt    = so_qty × (reward_pct / 100)             (6 decimals)
        //   reward_amt   = target_wt × silver_sell_rate             (2 decimals)
        //   reward_net   = reward_amt / (1 + gst / 100)            (2 decimals)
        //   reward_qty   = reward_net / silver_sell_rate            (6 decimals)
        final double goldRate =
            marketState.valueOrNull?.goldSell ?? 0.0;
        final double silverRate =
            marketState.valueOrNull?.silverSell ?? 0.0;
        final double gstRate = configAsync.valueOrNull?.gst ?? 3.0;

        // Step 0: Determine gold quantity (so_qty) in grams → 6 decimals
        double goldQty = 0.0;
        if (inputVal > 0 && goldRate > 0) {
          if (_isAmountMode) {
            // ₹ mode → remove GST → convert to grams
            final double goldValue = _trunc2(inputVal / (1 + (gstRate / 100)));
            goldQty = _trunc6(goldValue / goldRate);
          } else {
            // Grams mode → user entered gold grams directly
            goldQty = _trunc6(inputVal);
          }
        }

        // Steps 1–3: Silver reward with proper precision at each step
        double silverGrams = 0.0;
        if (goldQty > 0 && silverRate > 0) {
          final targetWt   = _trunc6(goldQty * rewardPercentage / 100);
          final rewardAmt  = _trunc2(targetWt * silverRate);
          final rewardNet  = _trunc2(rewardAmt / (1 + (gstRate / 100)));
          silverGrams      = _trunc6(rewardNet / silverRate);
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // "Best Offer" label
              Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [Color(0xFF1B882C), Color(0xFF003716)],
                  ),
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12.r),
                    topRight: Radius.circular(12.r),
                  ),
                ),
                child: Text(
                  'Best Offer',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              // Offer content card
              Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FFF4),
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(16.r),
                    bottomLeft: Radius.circular(16.r),
                    bottomRight: Radius.circular(16.r),
                  ),
                  border: Border.all(
                    color: const Color(0xFF1B882C).withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32.w,
                      height: 32.w,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1B882C).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.card_giftcard_rounded,
                        size: 18.sp,
                        color: const Color(0xFF1B882C),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FREE SILVER',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 14.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF064E3B),
                            ),
                          ),
                          SizedBox(height: 4.h),
                          if (silverGrams > 0) ...[
                            RichText(
                              text: TextSpan(
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 12.sp,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF064E3B).withValues(alpha: 0.7),
                                  height: 1.5,
                                ),
                                children: [
                                  const TextSpan(text: 'You will receive '),
                                  TextSpan(
                                    text: '${silverGrams.toStringAsFixed(6)} gm',
                                    style: GoogleFonts.lora(
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF064E3B),
                                    ),
                                  ),
                                  const TextSpan(
                                      text: ' of silver rewards equivalent to your gold investment.'),
                                ],
                              ),
                            ),
                            SizedBox(height: 2.h),
                            Text(
                              'Incl. 3% GST',
                              style: GoogleFonts.lora(
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF064E3B).withValues(alpha: 0.45),
                              ),
                            ),
                          ] else ...[
                            Text(
                              'Get free silver rewards equivalent to your gold investment.',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 12.sp,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF064E3B).withValues(alpha: 0.7),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  Widget _buildDenominationsRow(List<dynamic> denoms) {
    // Filter out zero/null values and deduplicate by value
    final seen = <double>{};
    final validDenoms = denoms.where((d) {
      final double val = d.value ?? 0.0;
      if (val <= 0) return false;
      return seen.add(val); // false if already present → deduplicates
    }).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: validDenoms.map((d) {
          final double val = d.value;
          final bool isPopular = d.isPopular;

          // Robust selection check
          final double inputVal =
              double.tryParse(_amountController.text.trim()) ?? 0.0;
          final double selectedVal = double.tryParse(_selectedAmount) ?? 0.0;
          final bool isSelected = (inputVal - val).abs() < 0.0001 ||
              (selectedVal - val).abs() < 0.0001;

          final label = _isAmountMode
              ? '₹${val % 1 == 0 ? val.toInt() : val}'
              : '${val % 1 == 0 ? val.toInt() : val}g';

          return Padding(
            padding: EdgeInsets.only(right: 12.w, top: 12.h),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                InkWell(
                  onTap: () {
                    final String valStr =
                        val % 1 == 0 ? val.toInt().toString() : val.toString();
                    _amountController.text = valStr;
                    setState(() => _selectedAmount = valStr);
                  },
                  borderRadius: BorderRadius.circular(12.r),
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 24.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF064E3B)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : Colors.black.withOpacity(0.1),
                        width: 1,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: const Color(0xFF064E3B).withOpacity(0.2),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      style: GoogleFonts.lora(
                        fontSize: 14.sp,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
                if (isPopular)
                  Positioned(
                    top: -14.h,
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEA580C), // accent orange
                        borderRadius: BorderRadius.circular(6.r),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Text(
                        'POPULAR',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8.sp,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Breakdown helpers (used in bottom sheet) ────────────────────
  Map<String, double> _computeBreakdown(AsyncValue<dynamic> market,
      CommodityType type, AsyncValue<SavingConfig> configAsync) {
    final config = configAsync.valueOrNull;
    if (config == null || !market.hasValue) {
      return {'total': 0, 'metalValue': 0, 'gst': 0, 'grams': 0, 'gstRate': 3};
    }
    final inputVal = double.tryParse(_selectedAmount) ?? 0.0;
    final double gstRate = config.gst / 100;
    final rate = type == CommodityType.gold
        ? market.value.goldSell
        : market.value.silverSell;
    double totalPayable, metalValue, gstAmount, grams;
    if (_isAmountMode) {
      totalPayable = _trunc2(inputVal);
      metalValue = _trunc2(totalPayable / (1 + gstRate));
      gstAmount = _trunc2(totalPayable - metalValue);
      grams = rate > 0 ? _trunc6(metalValue / rate) : 0.0;
    } else {
      grams = _trunc6(inputVal);
      metalValue = _trunc2(grams * rate);
      gstAmount = _trunc2(metalValue * gstRate);
      totalPayable = _trunc2(metalValue + gstAmount);
    }
    return {
      'total': totalPayable,
      'metalValue': metalValue,
      'gst': gstAmount,
      'grams': grams,
      'gstRate': config.gst,
    };
  }

  void _showBreakdownSheet(AsyncValue<dynamic> market, CommodityType type,
      AsyncValue<SavingConfig> configAsync) {
    final b = _computeBreakdown(market, type, configAsync);
    final metalLabel =
        type == CommodityType.gold ? 'Gold Value' : 'Silver Value';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _BreakdownSheet(
        totalPayable: b['total']!,
        metalValue: b['metalValue']!,
        gstAmount: b['gst']!,
        grams: b['grams']!,
        gstRate: b['gstRate']!,
        metalLabel: metalLabel,
        isInvalid: b['total']! <= 0 ||
            b['total']! < (configAsync.valueOrNull?.minAmount ?? 0) ||
            b['total']! >
                (configAsync.valueOrNull?.maxAmount ?? double.infinity),
        isProcessing: _isProcessing,
        onPayNow: () {
          Navigator.pop(context); // close sheet
          final config = configAsync.valueOrNull!;
          _handleConfirmOrder(market, type, b['total']!, config, b['grams']!);
        },
      ),
    );
  }

/*   Widget _buildSecurityPill(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.shield_outlined,
            color: const Color(0xFF91411D), size: 16.sp),
        SizedBox(width: 8.w),
        Text(
          '100% Secure Transaction & Bank Grade Storage',
          style: TextStyle(
            fontSize: 12.sp,
            fontWeight: FontWeight.w600,
            color: const Color(0xFF91411D).withOpacity(0.75),
          ),
        ),
      ],
    );
  }
 */
  // ── Wise-style pinned footer ─────────────────────────────────────
  Widget _buildBottomAction(bool isDark, AsyncValue<dynamic> market,
      CommodityType type, AsyncValue<SavingConfig> configAsync) {
    final config = configAsync.valueOrNull;
    if (config == null || !market.hasValue) return const SizedBox.shrink();

    final b = _computeBreakdown(market, type, configAsync);
    final totalPayable = b['total']!;
    final grams = b['grams']!;
    final isInvalid = (totalPayable < config.minAmount ||
        totalPayable > config.maxAmount ||
        totalPayable <= 0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Security badge — floats above the white footer strip ────────────
        Padding(
          padding: EdgeInsets.only(bottom: 6.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_outlined,
                  color: const Color(0xFF91411D), size: 14.sp),
              SizedBox(width: 6.w),
              Text(
                '100% Secure Transaction & Bank Grade Storage',
                style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF91411D).withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
        // ── White footer strip ───────────────────────────────────────────────
        SafeArea(
          top: false,
          child: Container(
            padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                  top: BorderSide(color: Colors.black.withOpacity(0.06))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // ── Left: ₹Amount dropdown ──
                GestureDetector(
                  onTap: totalPayable > 0
                      ? () => _showBreakdownSheet(market, type, configAsync)
                      : null,
                  child: Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 4.w, vertical: 10.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '₹${totalPayable > 0 ? totalPayable.toStringAsFixed(0) : '0'}',
                          style: GoogleFonts.lora(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(width: 4.w),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            size: 20.sp, color: Colors.black54),
                      ],
                    ),
                  ),
                ),
                // ── Right: Pay Now pill ──
                GestureDetector(
                  onTap: (isInvalid || _isProcessing)
                      ? null
                      : () => _handleConfirmOrder(
                          market, type, totalPayable, config, grams),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    height: 48.h,
                    padding: EdgeInsets.symmetric(horizontal: 32.w),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isInvalid
                            ? [
                                const Color(0xFF1B882C).withOpacity(0.4),
                                const Color(0xFF003716).withOpacity(0.4)
                              ]
                            : const [Color(0xFF1B882C), Color(0xFF003716)],
                      ),
                      borderRadius: BorderRadius.circular(50.r),
                      boxShadow: isInvalid
                          ? []
                          : [
                              BoxShadow(
                                color: const Color(0xFF1B882C).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isProcessing)
                          SizedBox(
                            width: 18.sp,
                            height: 18.sp,
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        else ...[
                          Icon(Icons.check_circle,
                              color: Colors.white, size: 20.sp),
                          SizedBox(width: 8.w),
                          Text(
                            'Pay Now',
                            style: TextStyle(
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ],
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

  Future<void> _handleConfirmOrder(AsyncValue<dynamic> market,
      CommodityType type, double totalPayable, SavingConfig config,
      [double grams = 0.0]) async {
    SecureLogger.d(
        'ORDER FLOW: Starting confirmation for $type - total: $totalPayable');
    setState(() => _isProcessing = true);
    try {
      final marketValue = market.valueOrNull;
      final rate = (type == CommodityType.gold
              ? marketValue?.goldSell
              : marketValue?.silverSell) ??
          0.0;

      final user = ref.read(userProvider);
      final customerId = user?.id ?? '';
      final mobile = user?.mobile ?? '';

      if (customerId.isEmpty || rate == 0) {
        SecureLogger.e(
            'ORDER FLOW BLOCKED: Invalid state (customer: $customerId, rate: $rate)');
        if (mounted) {
          setState(() => _isProcessing = false);
          AppToast.show(
              context, 'Market rates not ready. Please wait a moment.',
              type: ToastType.warning, position: ToastPosition.center);
        }
        return;
      }

      SecureLogger.d('ORDER FLOW: Calling check-eligibility API...');
      // Resolve id_metal dynamically from the API commodity list
      final metalId = ref.read(selectedMetalIdProvider);
      final eligibility =
          await ref.read(savingServiceProvider).checkEligibility(
                customerId: customerId,
                metalId: metalId,
                mobile: mobile,
                amount: totalPayable,
                rate: rate,
              );

      SecureLogger.d(
          'ORDER FLOW: API returned nextStep: ${eligibility.nextStep}');

      if (mounted) setState(() => _isProcessing = false);

      if (eligibility.nextStep == 'KYC_REQUIRED') {
        // Push KYC and AWAIT the result (true = KYC completed successfully).
        // KycScreen now does Navigator.pop(context, true) on 'instant' flow
        // instead of navigating to PaymentMethodsScreen.
        //
        // [LEGACY — kept for reference]
        // Navigator.pushNamed(context, '/kyc', arguments: {...});
        //   └─ previously KycScreen did pushReplacementNamed('/payment-methods')
        final kycDone = await Navigator.pushNamed(
          context,
          '/kyc',
          arguments: {
            'request_from': 'instant',
            'amount': totalPayable,
            'metal_id': metalId,
            'rate': rate,
            'buy_type': _isAmountMode ? 1 : 2,
            'weight': grams,
          },
        );

        if (kycDone == true && mounted) {
          SecureLogger.d(
              'ORDER FLOW: KYC completed → continuing to PaymentHandler');
          // KYC done — continue to Cashfree payment directly from here.
          final handler = PaymentHandler(ref: ref, context: context);
          await handler.startPayment(
            amount: totalPayable,
            metalId: metalId,
            rate: rate,
            buyType: _isAmountMode ? 1 : 2,
            weight: grams,
            onLoadingStart: () => setState(() => _isProcessing = true),
            onLoadingEnd: () {
              if (mounted) setState(() => _isProcessing = false);
            },
          );
        }
      } else if (eligibility.nextStep == 'PAYMENT') {
        // No KYC required — go straight to payment via the centralized handler.
        //
        // [LEGACY — kept for reference]
        // Navigator.pushNamed(context, AppRouter.paymentMethods, arguments: {...});
        SecureLogger.d(
            'ORDER FLOW: Eligibility PAYMENT → calling PaymentHandler');
        final handler = PaymentHandler(ref: ref, context: context);
        await handler.startPayment(
          amount: totalPayable,
          metalId: metalId,
          rate: rate,
          buyType: _isAmountMode ? 1 : 2,
          weight: grams,
          onLoadingStart: () => setState(() => _isProcessing = true),
          onLoadingEnd: () {
            if (mounted) setState(() => _isProcessing = false);
          },
        );
      } else if (eligibility.nextStep == 'UPI_LIST') {
        // UPI selection flow — unchanged.
        Navigator.pushNamed(context, AppRouter.upiSelection, arguments: {
          'amount': totalPayable,
          'metal_id': metalId,
          'rate': rate,
          'buy_type': _isAmountMode ? 1 : 2,
          'weight': grams,
        });
      } else {
        // Fallback — treat as direct payment via PaymentHandler.
        //
        // [LEGACY — kept for reference]
        // Navigator.pushNamed(context, AppRouter.paymentMethods, arguments: {...});
        SecureLogger.d(
            'ORDER FLOW: Unknown nextStep → defaulting to PaymentHandler');
        final handler = PaymentHandler(ref: ref, context: context);
        await handler.startPayment(
          amount: totalPayable,
          metalId: metalId,
          rate: rate,
          buyType: _isAmountMode ? 1 : 2,
          weight: grams,
          onLoadingStart: () => setState(() => _isProcessing = true),
          onLoadingEnd: () {
            if (mounted) setState(() => _isProcessing = false);
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        // Show real server message when available (Failure.message),
        // otherwise fall back to a generic user-friendly string.
        final msg = (e is Failure)
            ? e.message
            : 'Something went wrong. Please try again later.';
        AppToast.show(context, msg,
            type: ToastType.error, position: ToastPosition.center);
      }
    }
  }

  // ── Truncation helpers (floor, NOT round) ─────────────────────────────
  // Match backend precision: weights → 6 decimals, amounts → 2 decimals.
  static double _trunc6(double v) => (v * 1000000).floorToDouble() / 1000000;
  static double _trunc2(double v) => (v * 100).floorToDouble() / 100;
}

/// Wise-style breakdown bottom sheet
class _BreakdownSheet extends StatelessWidget {
  final double totalPayable;
  final double metalValue;
  final double gstAmount;
  final double grams;
  final double gstRate;
  final String metalLabel;
  final bool isInvalid;
  final bool isProcessing;
  final VoidCallback onPayNow;

  const _BreakdownSheet({
    required this.totalPayable,
    required this.metalValue,
    required this.gstAmount,
    required this.grams,
    required this.gstRate,
    required this.metalLabel,
    required this.isInvalid,
    required this.isProcessing,
    required this.onPayNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Breakdown',
                      style: GoogleFonts.lora(
                        fontSize: 20.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                      )),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.05),
                      ),
                      child:
                          Icon(Icons.close, size: 18.sp, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              // Breakdown card
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(color: Colors.black.withOpacity(0.06)),
                ),
                child: Column(
                  children: [
                    _row('Total Amount', '₹${totalPayable.toStringAsFixed(0)}',
                        subtitle: 'Incl. GST', isBold: true),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Divider(
                          height: 1, color: Colors.black.withOpacity(0.06)),
                    ),
                    _row(metalLabel, '₹${metalValue.toStringAsFixed(2)}'),
                    SizedBox(height: 12.h),
                    _row('GST (${gstRate.toStringAsFixed(0)}%)',
                        '₹${gstAmount.toStringAsFixed(2)}'),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10.h),
                      child: Divider(
                          height: 1, color: Colors.black.withOpacity(0.06)),
                    ),
                    _row('Quantity', '${grams.toStringAsFixed(6)}gm'),
                  ],
                ),
              ),
              SizedBox(height: 20.h),
              // Pay Now CTA
              GestureDetector(
                onTap: (isInvalid || isProcessing) ? null : onPayNow,
                child: Container(
                  width: double.infinity,
                  height: 56.h,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isInvalid
                          ? [
                              const Color(0xFF1B882C).withOpacity(0.4),
                              const Color(0xFF003716).withOpacity(0.4)
                            ]
                          : const [Color(0xFF1B882C), Color(0xFF003716)],
                    ),
                    borderRadius: BorderRadius.circular(50.r),
                    boxShadow: isInvalid
                        ? []
                        : [
                            BoxShadow(
                              color: const Color(0xFF1B882C).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle,
                          color: Colors.white, size: 22.sp),
                      SizedBox(width: 10.w),
                      Text('Pay Now',
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          )),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value,
      {String? subtitle, bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(
                  fontSize: isBold ? 16.sp : 14.sp,
                  fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
                  color: Colors.black,
                )),
            if (subtitle != null)
              Text(subtitle,
                  style: TextStyle(
                    fontSize: 12.sp,
                    color: Colors.black38,
                    fontWeight: FontWeight.w500,
                  )),
          ],
        ),
        Text(value,
            style: GoogleFonts.lora(
              fontSize: isBold ? 16.sp : 14.sp,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            )),
      ],
    );
  }
}

class TrendLinePainter extends CustomPainter {
  final Color color;

  TrendLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.2), color.withOpacity(0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.quadraticBezierTo(size.width * 0.2, size.height * 0.8,
        size.width * 0.4, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.6, size.height * 0.1,
        size.width * 0.8, size.height * 0.3);
    path.lineTo(size.width, 0);

    canvas.drawPath(path, paint);

    final areaPath = Path.from(path);
    areaPath.lineTo(size.width, size.height);
    areaPath.lineTo(0, size.height);
    areaPath.close();

    canvas.drawPath(areaPath, areaPaint);
  }

  @override
  bool shouldRepaint(TrendLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

class DashedDivider extends StatelessWidget {
  const DashedDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boxWidth = constraints.constrainWidth();
        const dashWidth = 5.0;
        final dashCount = (boxWidth / (2 * dashWidth)).floor();
        return Flex(
          direction: Axis.horizontal,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(dashCount, (_) {
            return SizedBox(
              width: dashWidth,
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white24
                      : Colors.black26,
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
