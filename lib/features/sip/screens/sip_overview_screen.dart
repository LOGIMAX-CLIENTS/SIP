import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/widgets/numeric_styled_text.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../routes/app_router.dart';
import '../controller/sip_controller.dart';
import '../models/sip_models.dart';

/// Auto Savings Overview (Profile → Auto Savings)
///
/// Displays the user's active SIP plans organized by frequency tabs
/// (Daily / Weekly / Monthly / Custom) with Gold/Silver commodity radio
/// selector.
/// Mirrors the reference design: pill tabs, invest type radio, and
/// plan detail card with status badge.
class SipOverviewScreen extends ConsumerStatefulWidget {
  const SipOverviewScreen({super.key});

  @override
  ConsumerState<SipOverviewScreen> createState() => _SipOverviewScreenState();
}

class _SipOverviewScreenState extends ConsumerState<SipOverviewScreen> {
  /// Currently selected frequency name (Daily / Weekly / Monthly / Custom).
  String _selectedFrequency = 'Daily';

  /// Currently selected commodity name for display filtering.
  /// Defaults to Gold.
  String _selectedCommodity = 'Gold';

  @override
  void initState() {
    super.initState();
    // Always fetch fresh data on screen entry
    Future.microtask(() {
      ref.invalidate(sipDetailsProvider);
      ref.invalidate(customSipSchemeDetailsProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final plansAsync = ref.watch(sipDetailsProvider);
    // Custom SIP is a separate backend product from regular Daily/Weekly/
    // Monthly plans (see CustomSipService doc comment) — loaded permissively
    // so a slow/failed fetch degrades to "no Custom plan" instead of
    // blocking the Daily/Weekly/Monthly tabs that already loaded fine.
    final customPlans =
        ref.watch(customSipSchemeDetailsProvider).valueOrNull ?? [];

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.lightGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(
              title: 'Auto Savings',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: plansAsync.when(
                data: (plans) => _buildContent(plans, customPlans),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF064E3B),
                    strokeWidth: 2.5,
                  ),
                ),
                error: (err, _) => _buildErrorState(
                    err.toString().replaceAll('Exception: ', '')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Main Content ─────────────────────────────────────────────────────
  Widget _buildContent(
      List<SipPlanDetail> plans, List<CustomSipSchemeDetail> customPlans) {
    // All frequencies for tabs (show all four always)
    final allFrequencies = ['Daily', 'Weekly', 'Monthly', 'Custom'];

    final isCustomTab = _selectedFrequency == 'Custom';

    // Find plans matching the current selection. Custom SIP is a separate
    // backend product (CustomSipSchemeDetail, not SipPlanDetail — see
    // customSipSchemeDetailsProvider), so it's filtered from its own list.
    final matchingCustomPlans = isCustomTab
        ? customPlans.where((p) {
            final commodityMatch = p.commodityName
                .toLowerCase()
                .contains(_selectedCommodity.toLowerCase());
            return commodityMatch && (p.isActive || p.isPaused);
          }).toList()
        : <CustomSipSchemeDetail>[];

    final matchingPlans = isCustomTab
        ? <SipPlanDetail>[]
        : plans.where((p) {
            final freqMatch =
                p.frequency.toLowerCase() == _selectedFrequency.toLowerCase();
            final commodityMatch = p.commodityName
                .toLowerCase()
                .contains(_selectedCommodity.toLowerCase());
            return freqMatch && commodityMatch && (p.isActive || p.isPaused);
          }).toList();

    // Derive available commodities
    final commodities = <String>['Gold', 'Silver'];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 20.h),

          // ── Frequency Pill Tabs ───────────────────────────────
          _buildFrequencyTabs(allFrequencies),

          SizedBox(height: 24.h),

          // ── Invest Type Radio ─────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select Savings Type',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                ),
                SizedBox(height: 12.h),
                _buildInvestTypeRadio(commodities),
              ],
            ),
          ),

          SizedBox(height: 24.h),

          // ── Plan Card or Empty State ──────────────────────────
          if (isCustomTab)
            if (matchingCustomPlans.isNotEmpty)
              ...matchingCustomPlans.map((plan) => Padding(
                    padding: EdgeInsets.only(bottom: 16.h),
                    child: _buildCustomPlanCard(plan),
                  ))
            else
              _buildNoPlanState()
          else if (matchingPlans.isNotEmpty)
            ...matchingPlans.map((plan) => Padding(
                  padding: EdgeInsets.only(bottom: 16.h),
                  child: _buildPlanCard(plan),
                ))
          else
            _buildNoPlanState(),

          SizedBox(height: 40.h),

          // ── Quick Actions ─────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Actions',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    Expanded(
                      child: _buildQuickAction(
                        icon: Icons.history_rounded,
                        label: 'AutoGold Transactions',
                        onTap: () => Navigator.pushNamed(
                            context, AppRouter.sipTransactions),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: _buildQuickAction(
                        icon: Icons.add_circle_outline_rounded,
                        label: 'New Auto Save',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRouter.autoSavings),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SizedBox(height: 120.h),
        ],
      ),
    );
  }

  // Display-only relabel — the "Custom" frequency value still drives tab
  // selection and backend matching (p.frequency), only its shown text changes.
  String _frequencyLabel(String freq) => freq == 'Custom' ? 'Flexi' : freq;

  // ─── Frequency Pill Tabs ──────────────────────────────────────────────
  Widget _buildFrequencyTabs(List<String> frequencies) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 40.w),
      child: Container(
        padding: EdgeInsets.all(4.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(50.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: frequencies.map((freq) {
            final isSelected =
                _selectedFrequency.toLowerCase() == freq.toLowerCase();
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedFrequency = freq),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [Color(0xFF003716), Color(0xFF167525)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(50.r),
                  ),
                  child: Center(
                    child: Text(
                      _frequencyLabel(freq),
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color:
                            isSelected ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ─── Invest Type Radio ────────────────────────────────────────────────
  Widget _buildInvestTypeRadio(List<String> commodities) {
    return Row(
      children: commodities.map((commodity) {
        final isSelected =
            _selectedCommodity.toLowerCase() == commodity.toLowerCase();
        final isGold = commodity.toLowerCase().contains('gold');
        return Padding(
          padding: EdgeInsets.only(right: 24.w),
          child: GestureDetector(
            onTap: () => setState(() => _selectedCommodity = commodity),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22.w,
                  height: 22.w,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isSelected ? const Color(0xFF167525) : Colors.black26,
                      width: isSelected ? 2 : 1.5,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12.w,
                            height: 12.w,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF167525),
                            ),
                          ),
                        )
                      : null,
                ),
                SizedBox(width: 8.w),
                NumericStyledText(
                  isGold ? 'Gold 24K' : 'Silver',
                  fontSize: 14.sp,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      isSelected ? const Color(0xFF1A1A2E) : Colors.black45,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── Plan Card (Matches Reference Design) ─────────────────────────────
  Widget _buildPlanCard(SipPlanDetail plan) {
    final isGold = plan.commodityName.toLowerCase().contains('gold');
    final statusColor = plan.isActive
        ? const Color(0xFF16A34A)
        : plan.isPaused
            ? const Color(0xFFD97706)
            : const Color(0xFF2563EB);

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRouter.sipManage,
            arguments: {'subscription_id': plan.subscriptionId},
          );
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title Row with image ──────────────────────────
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: Image.asset(
                      isGold ? 'assets/sip/gold.jpg' : 'assets/sip/silver.jpg',
                      width: 44.w,
                      height: 44.w,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: NumericStyledText(
                      'You\'ve already subscribed to a\n${plan.frequency} ${plan.commodityName} Auto-Savings plan',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                      height: 1.4,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20.h),

              // ── Detail Rows ───────────────────────────────────
              _buildDetailRow('Started On', _formatDate(plan.startDate)),
              _buildDetailRow(
                  'Savings Amount', '₹${plan.amount.toStringAsFixed(0)}'),
              _buildDetailRow('Frequency', plan.frequency),
              _buildDetailRow('Reference ID', plan.subscriptionId),

              // Status with colored badge
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        color: Colors.black45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20.r),
                        border:
                            Border.all(color: statusColor.withOpacity(0.25)),
                      ),
                      child: Text(
                        plan.status.toUpperCase(),
                        style: GoogleFonts.lora(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Custom SIP Plan Card ──────────────────────────────────────────────
  /// Mirrors _buildPlanCard's layout for CustomSipSchemeDetail — separate
  /// backend product (see customSipSchemeDetailsProvider), so it has its own
  /// "Dates" row instead of "Frequency" (Custom SIP runs on multiple
  /// day-of-month values, not a single Daily/Weekly/Monthly cadence).
  Widget _buildCustomPlanCard(CustomSipSchemeDetail plan) {
    final isGold = plan.commodityName.toLowerCase().contains('gold');
    final statusColor = plan.isActive
        ? const Color(0xFF16A34A)
        : plan.isPaused
            ? const Color(0xFFD97706)
            : const Color(0xFF2563EB);
    final sortedDates = plan.customDates.toList()..sort();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: GestureDetector(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRouter.customSipManage,
            arguments: {'scheme_id': plan.schemeId},
          );
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(20.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title Row with image ──────────────────────────
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: Image.asset(
                      isGold ? 'assets/sip/gold.jpg' : 'assets/sip/silver.jpg',
                      width: 44.w,
                      height: 44.w,
                      fit: BoxFit.cover,
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: NumericStyledText(
                      'You\'ve already subscribed to a\nFlexi ${plan.commodityName} Auto-Savings plan',
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A2E),
                      height: 1.4,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 20.h),

              // ── Detail Rows ───────────────────────────────────
              _buildDetailRow(
                  'Started On', _formatDate(plan.startDate ?? '')),
              _buildDetailRow(
                  'Savings Amount', '₹${plan.amount.toStringAsFixed(0)}'),
              _buildDetailRow('Dates', '${sortedDates.join(', ')} every month'),
              _buildDetailRow('Reference ID', plan.subscriptionId),

              // Status with colored badge
              Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Status',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        color: Colors.black45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20.r),
                        border:
                            Border.all(color: statusColor.withOpacity(0.25)),
                      ),
                      child: Text(
                        plan.status.toUpperCase(),
                        style: GoogleFonts.lora(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w800,
                          color: statusColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Detail Row ───────────────────────────────────────────────────────
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.playfairDisplay(
              fontSize: 12.sp,
              color: Colors.black45,
              fontWeight: FontWeight.w500,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: GoogleFonts.lora(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1A1A2E),
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  // ─── No Plan State ────────────────────────────────────────────────────
  Widget _buildNoPlanState() {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 40.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(20.r),
              decoration: BoxDecoration(
                color: const Color(0xFF064E3B).withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.savings_outlined,
                size: 40.sp,
                color: const Color(0xFF064E3B).withOpacity(0.4),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'No Active Plan',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF334155),
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'You don\'t have a $_selectedFrequency $_selectedCommodity\nauto-savings plan yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                color: const Color(0xFF94A3B8),
                height: 1.5,
              ),
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              onTap: () => Navigator.pushNamed(context, AppRouter.autoSavings),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 12.h),
                decoration: BoxDecoration(
                  gradient: AppTheme.greenGradient,
                  borderRadius: BorderRadius.circular(50.r),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF064E3B).withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  'Setup Auto Savings',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Quick Action Card ────────────────────────────────────────────────
  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: const Color(0xFF064E3B).withOpacity(0.07),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, size: 22.sp, color: const Color(0xFF064E3B)),
            ),
            SizedBox(height: 10.h),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF334155),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Error State ──────────────────────────────────────────────────────
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded,
                color: const Color(0xFFDC2626), size: 48.sp),
            SizedBox(height: 16.h),
            Text(
              'Failed to load plans',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              message,
              style: GoogleFonts.playfairDisplay(
                fontSize: 14.sp,
                color: const Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 20.h),
            GestureDetector(
              onTap: () => ref.invalidate(sipDetailsProvider),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
                decoration: BoxDecoration(
                  gradient: AppTheme.greenGradient,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 16.sp, color: Colors.white),
                    SizedBox(width: 8.w),
                    Text(
                      'Retry',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────
  String _formatDate(String dateStr) {
    try {
      final parts = dateStr.split('-');
      if (parts.length != 3) return dateStr;
      final months = [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      final day = int.parse(parts[2]);
      final month = int.parse(parts[1]);
      final year = parts[0];
      return '$day ${months[month]} $year';
    } catch (_) {
      return dateStr;
    }
  }
}
