// lib/features/instant_saving/widgets/payment_method_sheet.dart
//
// ─────────────────────────────────────────────────────────────────────────────
// PaymentMethodSheet — Bottom Sheet for Payment Method Selection
//
// Fetches payment method categories from the API (POST /payments/methods)
// and renders each option with:
//   • Network image icon (from server / S3)
//   • Sub-brand badge row (e.g. GPay, Visa logos)
//   • Radio-style selection
//
// Falls back to Material icons if icon_url is empty or image fails to load.
//
// Returns the selected payment method string ("upi", "card", "netbanking")
// via the onProceed callback when user taps "Proceed to Pay".
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/theme/app_text_styles.dart';

import '../controller/saving_controller.dart';
import '../models/saving_models.dart';

/// Fallback Material icons keyed by payment method id.
const _fallbackIcons = <String, IconData>{
  'upi': Icons.account_balance_wallet_rounded,
  'card': Icons.credit_card_rounded,
  'netbanking': Icons.account_balance_rounded,
};

class PaymentMethodSheet extends ConsumerStatefulWidget {
  /// Callback when user taps "Proceed to Pay".
  /// Receives the selected payment method id: "upi", "card", or "netbanking".
  /// The "netbanking" id is unchanged by [isRecurring] — only its displayed
  /// label changes — so SipService.createSip() is what translates it to the
  /// backend's canonical 'emandate' wire value for SIP requests.
  final void Function(String paymentMethod) onProceed;

  /// When true (SIP/recurring context only — never for one-time payments),
  /// relabels the "netbanking" option as an eMandate mandate registration
  /// rather than a per-cycle netbanking charge. Neither Razorpay nor
  /// Cashfree support netbanking as a standalone recurring/MIR instrument —
  /// selecting it here always registers a bank-account eMandate/eNACH
  /// mandate authenticated via netbanking, never a repeat netbanking debit.
  /// See docs/features/mir_requirement_review_and_validation.md in the
  /// backend repo. Defaults to false so one-time-payment callers (Instant
  /// Saving) are unaffected.
  final bool isRecurring;

  /// When set, only methods whose id is in this list are shown (e.g.
  /// ['upi', 'netbanking'] to hide Card for SIP flows gated on a registered
  /// bank account). Null/empty means no filtering — every fetched/default
  /// method is shown, matching pre-existing behaviour for callers that
  /// don't pass this.
  final List<String>? allowedMethodIds;

  const PaymentMethodSheet({
    super.key,
    required this.onProceed,
    this.isRecurring = false,
    this.allowedMethodIds,
  });

  @override
  ConsumerState<PaymentMethodSheet> createState() => _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<PaymentMethodSheet> {
  String _selected = 'upi'; // Default: UPI pre-selected

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final methodsAsync = ref.watch(paymentMethodsProvider);

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
              // ── Drag handle ────────────────────────────────────────────
              Container(
                width: 40.w,
                height: 4.h,
                margin: EdgeInsets.only(bottom: 16.h),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),

              // ── Header row ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Payment Methods',
                    style: AppTextStyles.titleLarge(isDark)
                        .copyWith(color: Colors.black),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: EdgeInsets.all(6.w),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.05),
                      ),
                      child: Icon(Icons.close,
                          size: 18.sp, color: Colors.black54),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              // ── Payment options card ───────────────────────────────────
              methodsAsync.when(
                data: (methods) => _buildMethodsList(methods),
                loading: () => _buildShimmerList(),
                error: (err, stack) {
                  debugPrint('PaymentMethodSheet API Error: $err\n$stack');
                  return _buildMethodsList([]);
                },
              ),
              SizedBox(height: 24.h),

              // ── Proceed to Pay button ──────────────────────────────────
              GestureDetector(
                onTap: () {
                  Navigator.pop(context); // close sheet
                  // Deferred to the next frame — onProceed (see callers,
                  // e.g. instant_saving_screen.dart's _handleConfirmOrder)
                  // synchronously calls setState()/opens further
                  // modals/dialogs on the screen THIS sheet sits on top of.
                  // Doing that in the same tick as Navigator.pop() is the
                  // "_dependents.isEmpty"/"attached: is not true" widget-tree
                  // corruption documented in add_bank_account_sheet.dart's
                  // own pop/invalidate/toast fix — this is the actual
                  // upstream trigger of that same crash reported when
                  // BANK_VERIFICATION_REQUIRED opens the Add Bank Account
                  // sheet right after this "Proceed to Pay" tap.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    widget.onProceed(_selected);
                  });
                },
                child: Container(
                  width: double.infinity,
                  height: 56.h,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1B882C), Color(0xFF003716)],
                    ),
                    borderRadius: BorderRadius.circular(50.r),
                    boxShadow: [
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
                      Text(
                        'Proceed to Pay',
                        style: AppTextStyles.button(isDark)
                            .copyWith(letterSpacing: 0.3),
                      ),
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

  // ── Methods list (API data or fallback) ──────────────────────────────────

  Widget _buildMethodsList(List<PaymentMethod> methods) {
    // If API returned data, use it; otherwise fall back to hardcoded defaults
    final rawOptions = methods.isNotEmpty ? methods : _defaultMethods;
    final allowed = widget.allowedMethodIds;
    final filteredOptions = (allowed == null || allowed.isEmpty)
        ? rawOptions
        : rawOptions.where((m) => allowed.contains(m.id)).toList();
    final options = widget.isRecurring
        ? filteredOptions.map(_relabelForRecurring).toList()
        : filteredOptions;

    // Auto-select first if current selection not in list
    if (!options.any((m) => m.id == _selected) && options.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selected = options.first.id);
      });
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: options.asMap().entries.map((entry) {
          final method = entry.value;
          final isSelected = _selected == method.id;
          final isLast = entry.key == options.length - 1;
          return Column(
            children: [
              _buildOptionTile(method, isSelected),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 16.w,
                  endIndent: 16.w,
                  color: Colors.black.withOpacity(0.06),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildOptionTile(PaymentMethod method, bool isSelected) {
    return GestureDetector(
      onTap: () => setState(() => _selected = method.id),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
        child: Row(
          children: [
            // ── Icon (network or fallback) ──
            Container(
              width: 44.r,
              height: 44.r,
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF1B882C).withOpacity(0.08)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1B882C).withOpacity(0.2)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11.r),
                child: method.iconUrl.isNotEmpty
                    ? Padding(
                        padding: EdgeInsets.all(8.r),
                        child: Image.network(
                          method.iconUrl,
                          width: 28.r,
                          height: 28.r,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(
                            _fallbackIcons[method.id] ?? Icons.payment_rounded,
                            color: isSelected
                                ? const Color(0xFF1B882C)
                                : Colors.black38,
                            size: 22.sp,
                          ),
                        ),
                      )
                    : Icon(
                        _fallbackIcons[method.id] ?? Icons.payment_rounded,
                        color: isSelected
                            ? const Color(0xFF1B882C)
                            : Colors.black38,
                        size: 22.sp,
                      ),
              ),
            ),
            SizedBox(width: 14.w),

            // ── Title + badge row ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.name,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                    ),
                  ),
                  SizedBox(height: 4.h),
                  // Badge icons row (sub-brands) or subtitle text
                  method.badgeIcons.isNotEmpty
                      ? Row(
                          children: [
                            ...method.badgeIcons.take(4).map((url) => Padding(
                                  padding: EdgeInsets.only(right: 6.w),
                                  child: Container(
                                    width: 24.r,
                                    height: 18.r,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius:
                                          BorderRadius.circular(4.r),
                                      border: Border.all(
                                        color: Colors.black.withOpacity(0.08),
                                        width: 0.5,
                                      ),
                                    ),
                                    child: ClipRRect(
                                      borderRadius:
                                          BorderRadius.circular(3.r),
                                      child: Image.network(
                                        url,
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            Icon(Icons.image_not_supported,
                                                size: 10.sp,
                                                color: Colors.black12),
                                      ),
                                    ),
                                  ),
                                )),
                            Text(
                              '& more',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w500,
                                color: Colors.black45,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          method.subtitle.isNotEmpty
                              ? method.subtitle
                              : method.description,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.black45,
                          ),
                        ),
                ],
              ),
            ),

            // ── Radio indicator ──
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24.r,
              height: 24.r,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? const Color(0xFF1B882C) : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF1B882C)
                      : Colors.black.withOpacity(0.2),
                  width: isSelected ? 0 : 2,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, size: 16.sp, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ── Shimmer loading placeholder ──────────────────────────────────────────

  Widget _buildShimmerList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        children: List.generate(3, (i) {
          return Column(
            children: [
              _buildShimmerTile(),
              if (i < 2)
                Divider(
                  height: 1,
                  indent: 16.w,
                  endIndent: 16.w,
                  color: Colors.black.withOpacity(0.06),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildShimmerTile() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      child: Row(
        children: [
          // Icon placeholder
          Container(
            width: 44.r,
            height: 44.r,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12.r),
            ),
          ),
          SizedBox(width: 14.w),
          // Text placeholders
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100.w,
                  height: 14.h,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
                SizedBox(height: 6.h),
                Container(
                  width: 160.w,
                  height: 10.h,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(4.r),
                  ),
                ),
              ],
            ),
          ),
          // Radio placeholder
          Container(
            width: 24.r,
            height: 24.r,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black.withOpacity(0.1), width: 2),
            ),
          ),
        ],
      ),
    );
  }

  /// Relabels the "netbanking" option for SIP/recurring context — see
  /// [PaymentMethodSheet.isRecurring] doc comment for why. Leaves every
  /// other option (and the "netbanking" id itself) untouched, whether the
  /// list came from the API or [_defaultMethods].
  PaymentMethod _relabelForRecurring(PaymentMethod method) {
    if (method.id != 'netbanking') return method;
    return PaymentMethod(
      id: method.id,
      name: 'eMandate (Netbanking)',
      icon: method.icon,
      description: 'Register a bank mandate — auto-debited each cycle',
      iconUrl: method.iconUrl,
      subtitle: 'Register a bank mandate — auto-debited each cycle',
      badgeIcons: method.badgeIcons,
    );
  }

  // ── Fallback defaults (used when API is unreachable) ─────────────────────

  static final _defaultMethods = [
    PaymentMethod(
      id: 'upi',
      name: 'UPI Apps',
      icon: 'upi.png',
      description: 'GPay, PhonePe, Paytm & more',
      subtitle: 'GPay, PhonePe, Paytm & more',
    ),
    PaymentMethod(
      id: 'card',
      name: 'Cards',
      icon: 'cards.png',
      description: 'Visa, Mastercard, RuPay & more',
      subtitle: 'Visa, Mastercard, RuPay & more',
    ),
    PaymentMethod(
      id: 'netbanking',
      name: 'Netbanking',
      icon: 'bank.png',
      description: 'All Indian banks',
      subtitle: 'All Indian banks',
    ),
  ];
}
