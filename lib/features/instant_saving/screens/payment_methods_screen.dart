import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/widgets/custom_button.dart';
import '../controller/saving_controller.dart';
import 'package:startgold/core/providers/user_provider.dart';
import 'package:startgold/core/providers/timer_provider.dart';
import 'package:startgold/core/providers/market_provider.dart';
import 'package:startgold/core/error/failures.dart';
import '../models/saving_models.dart';
import './purchase_success_screen.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/features/market/models/market_rates.dart';
import 'package:startgold/shared/widgets/app_toast.dart';
import 'package:startgold/shared/widgets/numeric_styled_text.dart';
import '../../../core/security/secure_logger.dart';
import '../hdfc_payment_handler.dart';
import '../razorpay_payment_handler.dart';

// ─────────────────────────────────────────────────────────────────────────────
// [LEGACY] PaymentMethodsScreen
//
// This screen is superseded by PaymentHandler (payment_handler.dart).
// New payment flows (InvestScreen PAYMENT path and post-KYC path) now call
// PaymentHandler.startPayment() directly and bypass this screen entirely.
//
// This file is kept intact for:
//   • Backwards compatibility with any remaining route references
//   • Reference implementation of the Cashfree integration pattern
//   • Gradual migration — do NOT delete until PaymentHandler is fully validated
// ─────────────────────────────────────────────────────────────────────────────
class PaymentMethodsScreen extends ConsumerStatefulWidget {
  final double amount;
  final String metalId;
  final double rate;
  final String? couponCode;

  /// 1 = buy in rupees (AMOUNT), 2 = buy in grams (GRAMS).
  final int buyType;

  /// For buy-in-grams (buyType==2): the weight in grams the customer wants.
  /// For buy-in-amount (buyType==1): unused (weight derived from amount/rate).
  final double weight;

  const PaymentMethodsScreen({
    super.key,
    required this.amount,
    required this.metalId,
    required this.rate,
    this.couponCode,
    this.buyType = 1,
    this.weight = 0.0,
  });

  @override
  ConsumerState<PaymentMethodsScreen> createState() =>
      _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends ConsumerState<PaymentMethodsScreen> {
  String? _selectedMethodId;
  bool _isLoading = false;
  bool _isVerifying = false;
  final CFPaymentGatewayService _cfPaymentGatewayService =
      CFPaymentGatewayService();

  @override
  void initState() {
    super.initState();
    _cfPaymentGatewayService.setCallback(_verifyPayment, _onPaymentError);

    // Immediately lock the freshest live rate when this screen opens.
    // The rate was locked on the Instant Saving screen up to 80s ago —
    // refresh it now so the "Live Price / Gm" card is always up to date.
    // Only do this when the market is open (skip if closed).
    Future.microtask(() {
      if (!mounted) return;
      final statusMap = ref.read(marketStatusProvider).valueOrNull ?? const {};
      final isMarketOpen = statusMap[widget.metalId] != false;
      if (isMarketOpen) {
        _handleRateExpiry();
      }
    });
  }

  void _verifyPayment(String orderId) async {
    setState(() {
      _isLoading = false;
      _isVerifying = true;
    });
    try {
      final response =
          await ref.read(savingServiceProvider).confirmPayment(orderId);

      if (!mounted) return;
      if (response['success'] == true) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseSuccessScreen(
              data: {
                'isSuccess': true,
                'orderId': response['data']?['order_id'] ?? orderId,
                'weight': response['data']?['grams_credited'] ??
                    response['data']?['credited_weight'] ??
                    response['data']?['weight'],
                'message': response['message'] ??
                    'Gold has been successfully added to your locker.',
                'commodity_name': response['data']?['commodity_name'],
                // Use server's total_amount from confirm API;
                // fall back to amount_inr received from initiate API.
                'total_amount': response['data']?['total_amount'] ??
                    (_confirmedAmountInr > 0
                        ? _confirmedAmountInr
                        : widget.amount),
                'rate': response['data']?['rate'],
                'payment_mode': response['data']?['payment_mode'],
              },
            ),
          ),
        );
      } else {
        // Extract error message from response — API may use
        // response['message'] or response['error']['message']
        final errorMsg = response['message'] ??
            response['error']?['message'] ??
            'Your order could not be processed. Please try again.';
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => PurchaseSuccessScreen(
              data: {
                'isSuccess': false,
                'orderId': orderId,
                'message': errorMsg,
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PurchaseSuccessScreen(
            data: {
              'isSuccess': false,
              'orderId': orderId,
              'message': (e is Failure)
                  ? e.message
                  : 'Payment verification failed. Please try again.',
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  void _onPaymentError(CFErrorResponse errorResponse, String orderId) async {
    if (!mounted) return;

    // Notify server about the failed payment so it can update order status.
    // Server needs the orderId regardless of success/failure.
    String failureMessage =
        'Payment failed for order $orderId.\n${errorResponse.getMessage()}';

    setState(() {
      _isLoading = false;
      _isVerifying = true;
    });
    try {
      final response =
          await ref.read(savingServiceProvider).confirmPayment(orderId);
      // Use server's message if available (may have more detail)
      final serverMsg = response['message'] ?? response['error']?['message'];
      if (serverMsg != null) {
        failureMessage = serverMsg;
      }
    } catch (_) {
      // Ignore server errors here — we still navigate to failure screen
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseSuccessScreen(
          data: {
            'isSuccess': false,
            'orderId': orderId,
            'message': failureMessage,
          },
        ),
      ),
    );
  }

  Future<void> _createPaymentOrder() async {
    if (_selectedMethodId == null) return;

    setState(() => _isLoading = true);
    try {
      final user = ref.read(userProvider);
      if (user == null) throw Exception('User not logged in');

      // Get locked rate from timer or fallback to initial rate
      final timerState = ref.read(sellRateTimerProvider);
      final activeRate = timerState.isActive
          ? (widget.metalId == '1'
              ? timerState.lockedRates!.goldSell
              : timerState.lockedRates!.silverSell)
          : widget.rate;

      // ── Weight calculation based on buy type ────────────────────────
      // buyType 1 = AMOUNT: weight derived from amount / rate (net of GST).
      // buyType 2 = GRAMS : weight is exactly what the customer requested.
      final double weightForApi;
      if (widget.buyType == 2) {
        weightForApi = double.parse(widget.weight.toStringAsFixed(4));
      } else {
        final config = ref.read(savingConfigProvider).valueOrNull;
        final gstRate = (config?.gst ?? 3.0) / 100;
        final raw = (widget.amount / (1 + gstRate)) / activeRate;
        weightForApi = double.parse(raw.toStringAsFixed(4));
      }

      // 1. Initiate Purchase
      final PurchaseInitiateResponse purchase =
          await ref.read(savingServiceProvider).initiatePurchase(
                customerId: user.id,
                metalId: widget.metalId,
                mobile: user.mobile,
                buyType: widget.buyType,   // int: 1 = AMOUNT, 2 = GRAMS
                amount: widget.amount,
                rate: activeRate,
                weight: weightForApi,
                couponCode: widget.couponCode,
              );

      // 2. Use server-confirmed amount_inr (authoritative for payment gateway)
      //    For GRAMS mode this will differ from widget.amount when the rate
      //    changed between the previous screen and now.
      //    Falls back to widget.amount if server did not return it.
      final confirmedAmount =
          (purchase.amountInr != null && purchase.amountInr!.isNotEmpty)
              ? double.tryParse(purchase.amountInr!) ?? widget.amount
              : widget.amount;

      // 3. Update the displayed "Total Payable" immediately so the user
      //    sees the server-confirmed amount before Cashfree launches.
      if (mounted) {
        setState(() => _confirmedAmountInr = confirmedAmount);
      }

      // 4. Launch Payment Gateway
      if (mounted) {
        _routePayment(purchase, confirmedAmount);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String message = (e is Failure)
            ? e.message
            : 'Payment initiation failed. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    } finally {
      // Only reset _isLoading if gateway launch failed.
    }
  }

  // Stores the server-confirmed amount_inr after initiate succeeds.
  // Used in success/failure screen data when confirm API doesn’t return amount.
  double _confirmedAmountInr = 0;

  void _routePayment(
      PurchaseInitiateResponse purchase, double confirmedAmount) {
    _confirmedAmountInr = confirmedAmount;

    final gwRaw = purchase.paymentGateway.toLowerCase().trim();
    final isRazorpayPayload = (purchase.keyId != null && purchase.keyId!.isNotEmpty) ||
        (purchase.rzOrderId != null && purchase.rzOrderId!.startsWith('order_')) ||
        (purchase.sessionId != null && purchase.sessionId!.startsWith('order_'));
    final isHdfcPayload = purchase.sdkPayload != null ||
        (purchase.merchantId != null && purchase.merchantId!.isNotEmpty);

    if (gwRaw.contains('razorpay') || isRazorpayPayload) {
      final razorpay = RazorpayPaymentHandler(ref: ref, context: context);
      razorpay.launchPayment(
        purchase: purchase,
        confirmedAmountInr: confirmedAmount,
        paymentMethod: _selectedMethodId,
        onLoadingStart: () {
          if (mounted) setState(() => _isLoading = true);
        },
        onLoadingEnd: () {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } else if (gwRaw.contains('hdfc') || isHdfcPayload) {
      final hdfc = HdfcPaymentHandler(ref: ref, context: context);
      hdfc.launchPayment(
        purchase: purchase,
        confirmedAmountInr: confirmedAmount,
        paymentMethod: _selectedMethodId,
        onLoadingStart: () {
          if (mounted) setState(() => _isLoading = true);
        },
        onLoadingEnd: () {
          if (mounted) setState(() => _isLoading = false);
        },
      );
    } else {
      _startCashfreePayment(purchase, confirmedAmount);
    }
  }

  void _startCashfreePayment(
      PurchaseInitiateResponse purchase, double confirmedAmount) {
    // Store server-confirmed amount so callbacks can reference it.
    _confirmedAmountInr = confirmedAmount;

    final orderId = purchase.orderId;
    final sessionId = purchase.sessionId;

    if (orderId == null ||
        orderId.trim().isEmpty ||
        sessionId == null ||
        sessionId.trim().isEmpty) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(
            context, 'Failed to initiate payment session. Please try again.',
            type: ToastType.error);
      }
      return;
    }

    // Safety guard: if sessionId starts with order_, this is Razorpay, NEVER send to Cashfree!
    if (sessionId.startsWith('order_')) {
      SecureLogger.d(
          '[PaymentMethods] Session ID starts with "order_" ($sessionId). Redirecting to Razorpay checkout...');
      _routePayment(purchase, confirmedAmount);
      return;
    }

    if (purchase.isMock || sessionId.startsWith('MOCK_')) {
      if (mounted) {
        setState(() => _isLoading = false);
        SecureLogger.e(
            '[PaymentMethods] Backend returned mock session ID ($sessionId). Live Cashfree SDK cannot process mock sessions.');
        AppToast.show(
          context,
          'Payment gateway is in mock mode on the server. Live payment is unavailable.',
          type: ToastType.error,
        );
      }
      return;
    }

    if (!sessionId.startsWith('session_')) {
      SecureLogger.e(
          '[PaymentMethods] Cashfree session ID does not start with "session_": $sessionId');
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(
          context,
          'Invalid payment session received from gateway. Please try again.',
          type: ToastType.error,
        );
      }
      return;
    }

    try {
      final env = purchase.environment?.toUpperCase() == 'PRODUCTION'
          ? CFEnvironment.PRODUCTION
          : CFEnvironment.SANDBOX;

      var session = CFSessionBuilder()
          .setEnvironment(env)
          .setOrderId(orderId)
          .setPaymentSessionId(sessionId)
          .build();

      var cfWebCheckoutPayment =
          CFWebCheckoutPaymentBuilder().setSession(session).build();

      SecureLogger.d(
          '[PaymentMethods] Launching Cashfree SDK: orderId=$orderId, env=$env, sessionId=$sessionId');
      _cfPaymentGatewayService.doPayment(cfWebCheckoutPayment);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String message = (e is Failure)
            ? e.message
            : 'Payment initiation failed. Please try again.';
        AppToast.show(context, message, type: ToastType.error);
      }
    }
  }

  bool _isRefreshing = false;
  bool _showUpdateSuccess = false;

  void _handleRateExpiry() {
    if (_isRefreshing) return;
    setState(() {
      _isRefreshing = true;
    });
    // Force a fresh config fetch so _onRateUpdated is triggered when it resolves.
    // Without this, _isRefreshing stays true forever (stuck "Updating...")
    // because savingConfigProvider never changes on its own.
    ref.invalidate(savingConfigProvider);
  }

  void _onRateUpdated(SavingConfig config) {
    if (!_isRefreshing) return;

    ref
        .read(sellRateTimerProvider.notifier)
        .startOrRefresh(config.sellRateLockSeconds);

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
    final methodsAsync = ref.watch(paymentMethodsProvider);

    // Auto-select first method when data arrives
    ref.listen<AsyncValue<List<PaymentMethod>>>(paymentMethodsProvider,
        (prev, next) {
      if (next is AsyncData<List<PaymentMethod>> && next.value.isNotEmpty) {
        if (_selectedMethodId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _selectedMethodId = next.value.first.id);
            }
          });
        }
      }
    });

    // Handle cached data if already available
    final methodsVal = ref.read(paymentMethodsProvider);
    if (methodsVal is AsyncData<List<PaymentMethod>> &&
        methodsVal.value.isNotEmpty) {
      if (_selectedMethodId == null) {
        // We use a post-frame callback to avoid setState during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedMethodId = methodsVal.value.first.id);
          }
        });
      }
    }

    final timerState = ref.watch(sellRateTimerProvider);
    final configAsync = ref.watch(savingConfigProvider);

    // Sync timer with config if not active
    ref.listen<AsyncValue<SavingConfig>>(savingConfigProvider, (prev, next) {
      final config = next.valueOrNull;
      if (config != null) {
        if (_isRefreshing) {
          // Rate expiry (or market reopen clear) triggered a refresh.
          // Resolve the "Updating..." state immediately when config resolves,
          // regardless of whether the timer is currently active.
          _onRateUpdated(config);
        } else if (!ref.read(sellRateTimerProvider).isActive) {
          // No refresh pending but timer stopped — restart it.
          ref
              .read(sellRateTimerProvider.notifier)
              .startOrRefresh(config.sellRateLockSeconds);
        }
      }
    });

    // Listen to timer expiration / instant market-closed signal
    ref.listen<TimerState>(sellRateTimerProvider, (prev, next) {
      if (prev != null &&
          prev.remainingSeconds > 0 &&
          next.remainingSeconds <= 0) {
        _handleRateExpiry();
      }
    });

    // ── Per-commodity market status ────────────────────────────────
    // widget.metalId '1' = Gold, '3' = Silver — matches socket commodity IDs
    final marketStatusMap =
        ref.watch(marketStatusProvider).valueOrNull ?? const {};
    final isCurrentMarketClosed = marketStatusMap[widget.metalId] == false;

    // Market re-opened while user is on this screen →
    // restart the timer so the rate chip shows a fresh live rate lock.
    ref.listen<AsyncValue<Map<String, bool>>>(marketStatusProvider,
        (prev, next) {
      next.whenData((statusMap) {
        final wasOpen = prev?.valueOrNull?[widget.metalId] != false;
        final isNowOpen = statusMap[widget.metalId] != false;
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
    // `5|...|1` fires before `3|...` rate arrives — sellRateTimer may lock 0.
    // Restart (or call _onRateUpdated) as soon as a valid rate arrives.
    ref.listen<AsyncValue<MarketRates>>(marketRatesStreamProvider,
        (prev, next) {
      next.whenData((rates) {
        if (!mounted) return;
        final isMarketOpen = (ref.read(marketStatusProvider).valueOrNull ??
                {})[widget.metalId] !=
            false;
        if (!isMarketOpen) return;
        final liveRate =
            widget.metalId == '1' ? rates.goldSell : rates.silverSell;
        if (liveRate <= 0) return;
        final tState = ref.read(sellRateTimerProvider);
        final lockedRate = widget.metalId == '1'
            ? (tState.lockedRates?.goldSell ?? 0.0)
            : (tState.lockedRates?.silverSell ?? 0.0);
        if (tState.isActive && lockedRate <= 0) {
          final config = ref.read(savingConfigProvider).valueOrNull;
          if (config != null) {
            if (_isRefreshing) {
              _onRateUpdated(config); // clears _isRefreshing too
            } else {
              ref
                  .read(sellRateTimerProvider.notifier)
                  .startOrRefresh(config.sellRateLockSeconds);
            }
          }
        }
      });
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // ── Gradient Header ─────────────────────────────────────
                GradientHeader(
                  title: 'Select Payment Method',
                  onBack: () => Navigator.pop(context),
                ),

                // ── Market Closed Amber Banner ───────────────────────────
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
                                  '${widget.metalId == '1' ? 'Gold' : 'Silver'} market is closed. Rates resume when market opens.',
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

                // ── Body ──────────────────────────────────────────────────
                _buildAmountHeader(
                    isDark, timerState, configAsync, isCurrentMarketClosed),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 24.w, vertical: 8.h),
                        child: Text(
                          'Recommended Payment Gateway',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white38 : Colors.black38,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      Expanded(
                        child: methodsAsync.when(
                          data: (methods) => ListView.builder(
                            padding: EdgeInsets.fromLTRB(24.w, 8.h, 24.w, 8.h),
                            itemCount: methods.length + 1,
                            itemBuilder: (context, index) {
                              if (index < methods.length) {
                                return _buildMethodTile(methods[index], isDark);
                              }
                              // Footer: 100% Secure — right below last card
                              return Padding(
                                padding:
                                    EdgeInsets.only(top: 8.h, bottom: 16.h),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.security_rounded,
                                        color: const Color(0xFF1B882C),
                                        size: 14.sp),
                                    SizedBox(width: 8.w),
                                    NumericStyledText(
                                      '100% Secure Payments',
                                      fontSize: 12.sp,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF1B882C),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, _) => const Center(
                              child: Text(
                                  'Failed to load payment methods. Please try again later.')),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_isVerifying)
              Container(
                color: Colors.black.withOpacity(0.4),
                child: Center(
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 40.w, vertical: 30.h),
                    margin: EdgeInsets.symmetric(horizontal: 40.w),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(24.r),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(
                            color: Color(0xFF064E3B)),
                        SizedBox(height: 20.h),
                        Text(
                          'Verifying Payment...',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomAction(isDark, isCurrentMarketClosed),
    );
  }

  Widget _buildAmountHeader(bool isDark, TimerState timerState,
      AsyncValue<SavingConfig> configAsync, bool isCurrentMarketClosed) {
    final gstRate = (configAsync.valueOrNull?.gst ?? 3.0) / 100;
    // Rate resolution priority:
    //   1. Market open + timer active  → use locked rate (stable for 80s)
    //   2. Market CLOSED               → 0.0 (socket already zeroed the rate)
    //   3. Market open + timer inactive → widget.rate (rate from prev screen)
    final currentRate = (!isCurrentMarketClosed && timerState.isActive)
        ? (widget.metalId == '1'
            ? timerState.lockedRates!.goldSell
            : timerState.lockedRates!.silverSell)
        : isCurrentMarketClosed
            ? 0.0
            : widget.rate;
    final goldValueWithoutTax = widget.amount / (1 + gstRate);
    // Guard against division by zero when rate is 0 (market closed)
    final weight = currentRate > 0 ? goldValueWithoutTax / currentRate : 0.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 20.h),
      child: Column(
        children: [
          if (_showUpdateSuccess) _buildUpdateBanner(),
          Container(
            padding: EdgeInsets.all(20.r),
            decoration: BoxDecoration(
              gradient: isDark
                  ? const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : const LinearGradient(
                      // same gradient as the page header
                      begin: Alignment(-0.87, -0.5),
                      end: Alignment(0.87, 0.5),
                      colors: [Color(0xFF003716), Color(0xFF167525)],
                      stops: [0.0223, 0.9399],
                    ),
              borderRadius: BorderRadius.circular(20.r),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withOpacity(0.3)
                      : const Color(0xFF003716).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total Payable',
                            style: GoogleFonts.playfairDisplay(
                                fontSize: 10.sp,
                                color: Colors.white.withOpacity(0.6),
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.5)),
                        SizedBox(height: 6.h),
                        // Show server-confirmed amount_inr when available.
                        // For GRAMS mode the server recomputes the amount at
                        // the CURRENT rate, so this may differ from widget.amount.
                        Text(
                          '\u20b9${(_confirmedAmountInr > 0 ? _confirmedAmountInr : widget.amount).toStringAsFixed(2)}',
                          style: GoogleFonts.lora(
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5),
                        ),
                        // Show "Rate Updated" note when server amount differs.
                        if (_confirmedAmountInr > 0 &&
                            (_confirmedAmountInr - widget.amount).abs() > 0.01)
                          Padding(
                            padding: EdgeInsets.only(top: 4.h),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 10.sp,
                                    color: const Color(0xFFFBBF24)),
                                SizedBox(width: 4.w),
                                Text(
                                  'Updated at current rate',
                                  style: GoogleFonts.playfairDisplay(
                                    fontSize: 9.sp,
                                    color: const Color(0xFFFBBF24),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(100.r),
                        border:
                            Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.auto_graph_rounded,
                              color: Colors.white, size: 14.sp),
                          SizedBox(width: 8.w),
                          NumericStyledText(
                            widget.metalId == '1' ? '24K GOLD' : 'PURE SILVER',
                            fontSize: 10.sp,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),
                Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 11,
                        child: _buildSummaryItem(
                          'Wt. Accumulated',
                          isCurrentMarketClosed
                              ? '—'
                              : '${_isRefreshing ? "..." : weight.toStringAsFixed(4)} gm',
                          true,
                          Icons.scale_rounded,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 30.h,
                        color: Colors.white.withOpacity(0.12),
                        margin: EdgeInsets.symmetric(horizontal: 12.w),
                      ),
                      Expanded(
                        flex: 10,
                        child: _buildSummaryItem(
                          isCurrentMarketClosed ? 'Rate' : 'Live Price / Gm',
                          isCurrentMarketClosed
                              ? 'Unavailable'
                              : (_isRefreshing
                                  ? 'Updating...'
                                  : '₹${currentRate.toStringAsFixed(2)}'),
                          true,
                          Icons.trending_up_rounded,
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
    );
  }

  Widget _buildUpdateBanner() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: EdgeInsets.only(bottom: 16.h),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: const Color(0xFF064E3B).withOpacity(0.1),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: const Color(0xFF064E3B).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: const Color(0xFF064E3B), size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              'Live Price Updated Successfully',
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF064E3B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, bool isDarkHeader, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12.sp, color: Colors.white.withOpacity(0.5)),
            SizedBox(width: 6.w),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 9.sp,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withOpacity(0.5),
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 6.h),
        Text(
          value,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          style: GoogleFonts.lora(
            fontSize: 14.sp,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildMethodTile(PaymentMethod method, bool isDark) {
    final isSelected = _selectedMethodId == method.id;
    return Padding(
      padding: EdgeInsets.only(bottom: 16.h),
      child: GestureDetector(
        onTap: () => setState(() => _selectedMethodId = method.id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF1B882C).withOpacity(0.06)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white),
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(
                color: isSelected
                    ? const Color(0xFF1B882C)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.black.withValues(alpha: 0.05)),
                width: isSelected ? 2 : 1),
            boxShadow: [
              if (isSelected)
                BoxShadow(
                    color: const Color(0xFF1B882C).withOpacity(0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 8)),
              if (!isDark && !isSelected)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54.r,
                height: 54.r,
                decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16.r)),
                child: Center(
                    child: Icon(_getPaymentIcon(method.name),
                        color: isSelected
                            ? const Color(0xFF1B882C)
                            : (isDark ? Colors.white24 : Colors.black26),
                        size: 24.sp)),
              ),
              SizedBox(width: 16.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(method.name,
                        style: GoogleFonts.playfairDisplay(
                            fontSize: 14.sp,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: isDark ? Colors.white : Colors.black)),
                    SizedBox(height: 4.h),
                    Text(
                      method.description,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Container(
                  padding: EdgeInsets.all(4.r),
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B882C),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check, color: Colors.white, size: 12.sp),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getPaymentIcon(String name) {
    name = name.toLowerCase();
    if (name.contains('card')) return Icons.credit_card_rounded;
    if (name.contains('upi')) return Icons.account_balance_wallet_rounded;
    if (name.contains('bank')) return Icons.account_balance_rounded;
    if (name.contains('cashfree')) return Icons.bolt_rounded;
    return Icons.payment_rounded;
  }

  Widget _buildBottomAction(bool isDark, bool isCurrentMarketClosed) {
    // Disable when loading, refreshing, no method selected, OR market is closed
    final isDisabled = _isLoading ||
        _isRefreshing ||
        _selectedMethodId == null ||
        isCurrentMarketClosed;
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 16.h),
        decoration: const BoxDecoration(color: Colors.transparent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Transaction Charges Info Note ──
            Container(
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withOpacity(0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.lightbulb_outline_rounded,
                      size: 16.sp, color: const Color(0xFFD97706)),
                  SizedBox(width: 10.w),
                  Expanded(
                    child: Text(
                      'Transaction charges may vary based on your chosen '
                      'payment method and may include gateway fees. Please '
                      'verify the final payable amount before proceeding.',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF92400E),
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16.h),
            CustomButton(
              text: 'Proceed to Pay',
              svgIconPath: 'assets/buttons/tick.svg',
              isLoading: _isLoading,
              onPressed: isDisabled ? null : _createPaymentOrder,
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isDisabled
                    ? [
                        const Color(0xFF1B882C).withOpacity(0.45),
                        const Color(0xFF003716).withOpacity(0.45),
                      ]
                    : const [Color(0xFF1B882C), Color(0xFF003716)],
              ),
              boxShadow: isDisabled
                  ? []
                  : [
                      BoxShadow(
                        color: const Color(0xFF1B882C).withOpacity(0.35),
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
}
