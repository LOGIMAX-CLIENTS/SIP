import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/commodity_provider.dart';
import '../../../core/providers/market_provider.dart';
import '../../../core/providers/timer_provider.dart';
import '../../instant_saving/controller/saving_controller.dart';
import '../../instant_saving/models/saving_models.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/theme/app_text_styles.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../providers/withdrawal_provider.dart';
import '../models/withdrawal_method.dart';
import '../services/withdrawal_service.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/app_toast.dart';
import '../../../core/providers/user_provider.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../market/models/market_rates.dart';

class WithdrawalConfirmationScreen extends ConsumerStatefulWidget {
  const WithdrawalConfirmationScreen({super.key});

  @override
  ConsumerState<WithdrawalConfirmationScreen> createState() =>
      _WithdrawalConfirmationScreenState();
}

class _WithdrawalConfirmationScreenState
    extends ConsumerState<WithdrawalConfirmationScreen> {
  // We'll use the global buyRateTimerProvider instead of a local timer

  @override
  void initState() {
    super.initState();
    // Immediately lock freshest live rate when confirmation screen opens.
    // Only trigger when market is open for the current commodity.
    Future.microtask(() {
      if (!mounted) return;
      final type = ref.read(commodityProvider);
      final commodityId = type == CommodityType.gold ? '1' : '3';
      final statusMap =
          ref.read(marketStatusProvider).valueOrNull ?? const {};
      if (statusMap[commodityId] != false) {
        _handleRateExpiry();
      }
    });
  }

  bool _isRefreshing = false;
  bool _showUpdateSuccess = false;
  bool _isSubmitting = false;

  void _handleRateExpiry() {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
      _showUpdateSuccess = false;
    });
    // Force config re-fetch so _onRateUpdated is triggered when it resolves.
    // Without this, _isRefreshing stays true and 'Updating...' is stuck.
    ref.invalidate(savingConfigProvider);
  }

  void _onRateUpdated(SavingConfig config) {
    if (!_isRefreshing) return;

    // Restart timer with new rates
    ref
        .read(buyRateTimerProvider.notifier)
        .startOrRefresh(config.buyRateLockSeconds);

    setState(() {
      _isRefreshing = false;
      _showUpdateSuccess = true;
    });

    // Hide success message after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showUpdateSuccess = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final withdrawal = ref.watch(withdrawalProvider);
    final timerState = ref.watch(buyRateTimerProvider);
    final type = ref.watch(commodityProvider);

    // Per-commodity market status
    final marketStatusMap =
        ref.watch(marketStatusProvider).valueOrNull ?? const {};
    final commodityId = type == CommodityType.gold ? '1' : '3';
    final isCurrentMarketClosed = marketStatusMap[commodityId] == false;

    // Bypass stale locked rate when market is closed
    final market = (!isCurrentMarketClosed && timerState.isActive)
        ? AsyncData(timerState.lockedRates!)
        : ref.watch(marketRatesStreamProvider);

    // Market reopen \u2192 restart timer
    ref.listen<AsyncValue<Map<String, bool>>>(marketStatusProvider,
        (prev, next) {
      next.whenData((statusMap) {
        final wasOpen = prev?.valueOrNull?[commodityId] != false;
        final isNowOpen = statusMap[commodityId] != false;
        if (!wasOpen && isNowOpen && mounted) {
          ref.read(buyRateTimerProvider.notifier).clear();
          final config = ref.read(savingConfigProvider).valueOrNull;
          if (config != null) {
            ref
                .read(buyRateTimerProvider.notifier)
                .startOrRefresh(config.buyRateLockSeconds);
          }
        }
      });
    });

    // Race-condition guard: market-reopen vs first rate frame
    // `5|...|1` fires before `3|...` rate arrives \u2014 buyRateTimer may lock 0.
    // Restart as soon as the first valid buy rate is received from the socket.
    ref.listen<AsyncValue<MarketRates>>(marketRatesStreamProvider, (prev, next) {
      next.whenData((rates) {
        if (!mounted) return;
        final isMarketOpen =
            (ref.read(marketStatusProvider).valueOrNull ?? {})[commodityId] != false;
        if (!isMarketOpen) return;
        final liveRate = type == CommodityType.gold ? rates.goldBuy : rates.silverBuy;
        if (liveRate <= 0) return;
        final tState = ref.read(buyRateTimerProvider);
        final lockedRate = type == CommodityType.gold
            ? (tState.lockedRates?.goldBuy ?? 0.0)
            : (tState.lockedRates?.silverBuy ?? 0.0);
        if (tState.isActive && lockedRate <= 0) {
          final config = ref.read(savingConfigProvider).valueOrNull;
          if (config != null) {
            if (_isRefreshing) {
              _onRateUpdated(config); // also clears _isRefreshing
            } else {
              ref
                  .read(buyRateTimerProvider.notifier)
                  .startOrRefresh(config.buyRateLockSeconds);
            }
          }
        }
      });
    });

    // Watch config to trigger the API fetch
    final configAsync = ref.watch(savingConfigProvider);

    // Sync timer with config \u2014 prioritise _isRefreshing over timer.isActive
    // so _onRateUpdated fires even after our clear()+startOrRefresh() cycle.
    ref.listen<AsyncValue<SavingConfig>>(savingConfigProvider, (prev, next) {
      final config = next.valueOrNull;
      if (config != null) {
        if (_isRefreshing) {
          _onRateUpdated(config);
        } else if (!ref.read(buyRateTimerProvider).isActive && !isCurrentMarketClosed) {
          ref
              .read(buyRateTimerProvider.notifier)
              .startOrRefresh(config.buyRateLockSeconds);
        }
      }
    });

    // Also start timer immediately if config is already loaded
    if (configAsync.hasValue &&
        configAsync.value != null &&
        !timerState.isActive &&
        !isCurrentMarketClosed) {
      Future.microtask(() {
        ref
            .read(buyRateTimerProvider.notifier)
            .startOrRefresh(configAsync.value!.buyRateLockSeconds);
      });
    }

    // Listen to timer expiration
    ref.listen<TimerState>(buyRateTimerProvider, (prev, next) {
      if (prev != null &&
          prev.remainingSeconds > 0 &&
          next.remainingSeconds <= 0) {
        _handleRateExpiry();
      }
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Gradient Header
          GradientHeader(
            title: AppConstants.confirmWithdrawal,
            onBack: () => Navigator.pop(context),
          ),

          // Market Closed amber banner
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: isCurrentMarketClosed
                ? Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(
                        horizontal: 20.w, vertical: 10.h),
                    color: const Color(0xFFFEF3C7),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: const Color(0xFFB45309), size: 16.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            '${type == CommodityType.gold ? 'Gold' : 'Silver'} market is closed. Confirmation unavailable.',
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

          // Body
          Expanded(
            child: market.when(
              data: (rates) {
                final price = type == CommodityType.gold
                    ? rates.goldBuy
                    : rates.silverBuy;
                final amountInINR = withdrawal.isGrams
                    ? withdrawal.amount * price
                    : withdrawal.amount;
                // Guard: price may be 0.0 when market is closed \u2014 avoid Infinity
                final amountInGrams = withdrawal.isGrams
                    ? withdrawal.amount
                    : (price > 0 ? withdrawal.amount / price : 0.0);

                return Padding(
                  padding: EdgeInsets.all(24.w),
                  child: Column(
                    children: [
                      if (_showUpdateSuccess)
                        Padding(
                          padding: EdgeInsets.only(top: 8.h),
                          child: Text(
                            'Rate updated based on latest market price',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 12.sp,
                              color: Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      SizedBox(height: 24.h),
                      _buildSummaryCard(
                          isDark, amountInINR, amountInGrams, price, type,
                          isCurrentMarketClosed, withdrawal.isGrams),
                      SizedBox(height: 24.h),
                      _buildDestinationCard(isDark, withdrawal.selectedMethod),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) =>
                  const Center(child: Text('Error loading market rates')),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildFinalAction(context, isCurrentMarketClosed),
    );
  }

  Widget _buildSummaryCard(bool isDark, double amountINR, double amountGrams,
      double rate, CommodityType type, bool isCurrentMarketClosed, bool isGrams) {
    // When market is closed: weight and rate can't be calculated reliably.
    final weightText = isCurrentMarketClosed
        ? '\u2014'
        : '${amountGrams.toStringAsFixed(6)} gm';
    final rateText = isCurrentMarketClosed
        ? 'Market Closed'
        : '\u20b9${rate.toStringAsFixed(2)} / gm';
    // Suppress INR display in grams mode when market is closed (amountINR = 0)
    final amountText = (isGrams && isCurrentMarketClosed)
        ? '\u2014'
        : '\u20b9${amountINR.toStringAsFixed(2)}';

    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        children: [
          Text('You will receive',
              style: GoogleFonts.playfairDisplay(
                  color: isDark ? Colors.white54 : Colors.black54,
                  fontSize: 14.sp)),
          SizedBox(height: 8.h),
          Text(amountText,
              style: GoogleFonts.lora(
                  fontSize: 36.sp,
                  fontWeight: FontWeight.w900,
                  color: isCurrentMarketClosed
                      ? Colors.grey
                      : AppTheme.arcticBlue)),
          SizedBox(height: 24.h),
          const Divider(),
          SizedBox(height: 24.h),
          _buildSummaryRow('Weight', weightText, isDark),
          SizedBox(height: 16.h),
          _buildSummaryRow('Withdrawal Rate', rateText, isDark),
          SizedBox(height: 16.h),
          _buildSummaryRow('Commodity',
              type == CommodityType.gold ? 'Gold 24KT' : 'Silver 999', isDark),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium(isDark)),
        Text(value,
            style: AppTextStyles.valueSmall(isDark)
                .copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _buildDestinationCard(bool isDark, WithdrawalMethod? method) {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.03)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        children: [
          Icon(Icons.account_balance_wallet_outlined,
              color: isDark ? Colors.white70 : Colors.black54),
          SizedBox(width: 16.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CREDIT TO',
                    style: AppTextStyles.labelSmall(isDark).copyWith(
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white38 : Colors.black38)),
                Text(method?.identifier ?? 'N/A',
                    style: AppTextStyles.valueSmall(isDark)
                        .copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFinalAction(BuildContext context, bool isCurrentMarketClosed) {
    final isDisabled = _isRefreshing || _isSubmitting || isCurrentMarketClosed;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.security,
                    color: Colors.greenAccent[400], size: 16.sp),
                SizedBox(width: 8.w),
                Text('Secure Bank Transfer',
                    style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        color: Colors.greenAccent[700],
                        fontWeight: FontWeight.w600)),
              ],
            ),
            SizedBox(height: 16.h),
            CustomButton(
              text: 'Confirm Sale & Transfer', svgIconPath: 'assets/buttons/tick.svg',
              isLoading: _isSubmitting,
              loadingText: 'Processing...',
              onPressed: isDisabled ? null : () => _completeWithdrawal(context),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isDisabled
                    ? const [Color(0xFF9CA3AF), Color(0xFF6B7280)]
                    : const [Color(0xFF1B882C), Color(0xFF003716)],
              ),
              boxShadow: isDisabled
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFF1B882C).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  void _completeWithdrawal(BuildContext context) async {
    final withdrawal = ref.read(withdrawalProvider);
    final user = ref.read(userProvider);
    final commodity = ref.read(commodityProvider);
    final timerState = ref.read(buyRateTimerProvider);

    if (user == null ||
        withdrawal.selectedMethod == null ||
        !timerState.isActive) {
      AppToast.show(context, 'Missing required information to proceed',
          type: ToastType.warning, position: ToastPosition.center);
      return;
    }

    final price = commodity == CommodityType.gold
        ? timerState.lockedRates!.goldBuy
        : timerState.lockedRates!.silverBuy;
    final amountInINR =
        withdrawal.isGrams ? withdrawal.amount * price : withdrawal.amount;
    final amountInGrams = double.parse(
        (withdrawal.isGrams
                ? withdrawal.amount
                : (price > 0 ? withdrawal.amount / price : 0.0))
            .toStringAsFixed(4));

    final pin = await Navigator.pushNamed(
      context,
      AppRouter.mpin,
      arguments: {'type': 'withdrawal_pin'},
    );

    if (pin != null && pin is String && pin.isNotEmpty) {
      if (!mounted) return;
      setState(() => _isSubmitting = true);
      try {
        final response =
            await ref.read(withdrawalServiceProvider).submitWithdrawal(
                  metalId: ref.read(selectedMetalIdProvider),
                  amount: amountInINR,
                  weight: amountInGrams,
                  buyRate: price,
                  withdrawalMethodId: withdrawal.selectedMethod!.id,
                  withdrawalMethod:
                      withdrawal.selectedMethod!.isUpi ? 'UPI' : 'BANK',
                );

        if (response['success'] == true && mounted) {
          setState(() => _isSubmitting = false);
          final responseData = response['data'] ?? {};
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRouter.withdrawalSuccess,
            (route) => false,
            arguments: {
              'amount': responseData['amount']?.toString() ??
                  amountInINR.toStringAsFixed(2),
              'txnId': responseData['transfer_id']?.toString() ??
                  responseData['withdrawal_id']?.toString() ??
                  '',
              'account': withdrawal.selectedMethod?.identifier ?? '',
              'status': responseData['status']?.toString() ?? 'COMPLETED',
              'commodity': responseData['commodity']?.toString() ??
                  (commodity == CommodityType.gold ? 'GOLD' : 'SILVER'),
            },
          );
        } else {
          if (mounted) {
            setState(() => _isSubmitting = false);
            // Extract message from nested error or data fields
            final errorMsg = response['error']?['message']?.toString()
                ?? response['data']?['message']?.toString()
                ?? response['message']?.toString()
                ?? 'Withdrawal failed. Please try again.';
            AppToast.show(context, errorMsg,
                type: ToastType.error, position: ToastPosition.center);
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          AppToast.show(
              context, 'Failed to process withdrawal. Please try again.',
              type: ToastType.error, position: ToastPosition.center);
        }
      }
    }
  }
}
