import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routes/app_router.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/theme/app_theme.dart';
import '../controller/sip_controller.dart';
import '../../history/models/history_models.dart';

/// SIP Transaction History screen.
///
/// • Fetches fresh data every time the screen is entered.
/// • Primary segmentation: frequency (Daily / Weekly / Monthly / Custom).
/// • Secondary filter: commodity (Gold / Silver) via toggle chips — shown
///   only when the selected frequency has multiple commodities.
/// • Transaction card design mirrors the main Transaction History page.
class SipTransactionHistoryScreen extends ConsumerStatefulWidget {
  const SipTransactionHistoryScreen({super.key});

  @override
  ConsumerState<SipTransactionHistoryScreen> createState() =>
      _SipTransactionHistoryScreenState();
}

class _SipTransactionHistoryScreenState
    extends ConsumerState<SipTransactionHistoryScreen>
    with TickerProviderStateMixin {
  static const _green = Color(0xFF1B882C);
  static const _darkGreen = Color(0xFF003716);
  static const _teal = Color(0xFF0D9488);

  TabController? _tabController;

  /// Frequency segments present in the response (e.g., ["Daily", "Weekly"]).
  List<String> _frequencies = [];

  /// Secondary commodity filter within the selected frequency tab.
  /// null = show all commodities.
  String? _selectedCommodity;

  @override
  void initState() {
    super.initState();
    // Always fetch fresh data on screen entry
    Future.microtask(() => ref.invalidate(sipTransactionsProvider));
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txAsync = ref.watch(sipTransactionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.lightGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(
              title: 'SIP Transactions',
              onBack: () => Navigator.pop(context),
            ),
            Expanded(
              child: txAsync.when(
                data: (response) => _buildBody(context, response, isDark),
                loading: () => const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF064E3B),
                    strokeWidth: 2.5,
                  ),
                ),
                error: (err, _) => _buildErrorState(
                    err.toString().replaceAll('Exception: ', ''), isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Body ────────────────────────────────────────────────────────────
  Widget _buildBody(
      BuildContext context, Map<String, dynamic> response, bool isDark) {
    final data = response['data'] as Map<String, dynamic>? ?? {};

    // Build HistoryResponse from grouped transactions
    final historyResponse = HistoryResponse.fromJson({'data': data});
    final transactions = historyResponse.transactions;

    if (transactions.isEmpty) return _buildEmptyState(isDark);

    // ── Extract frequency segments from API plans or transaction subtitles ──
    final plansList = data['plans'] as List<dynamic>? ?? [];
    final frequencySet = <String>{};

    // From plans array
    for (final p in plansList) {
      if (p is Map<String, dynamic>) {
        final freq = p['frequency']?.toString() ?? '';
        if (freq.isNotEmpty) frequencySet.add(freq);
      }
    }

    // Fallback: derive from transaction subtitles (e.g. "Daily Gold Auto-Savings")
    if (frequencySet.isEmpty) {
      for (final tx in transactions) {
        final sub = tx.subtitle.toLowerCase();
        if (sub.contains('daily')) {
          frequencySet.add('Daily');
        } else if (sub.contains('weekly')) {
          frequencySet.add('Weekly');
        } else if (sub.contains('monthly')) {
          frequencySet.add('Monthly');
        } else if (sub.contains('custom')) {
          frequencySet.add('Custom');
        }
      }
    }

    // If still empty, just show everything without tabs
    if (frequencySet.isEmpty) {
      return _buildTransactionList(
          context, historyResponse.groupedData, isDark, transactions);
    }

    // Sort: Daily → Weekly → Monthly → Custom
    final orderedFreqs = <String>[];
    for (final f in ['Daily', 'Weekly', 'Monthly', 'Custom']) {
      if (frequencySet.contains(f)) orderedFreqs.add(f);
    }
    // Add any remaining that don't match the above
    for (final f in frequencySet) {
      if (!orderedFreqs.contains(f)) orderedFreqs.add(f);
    }

    // Rebuild tab controller if frequencies changed
    if (_frequencies.length != orderedFreqs.length ||
        !_listEquals(_frequencies, orderedFreqs)) {
      _frequencies = orderedFreqs;
      _tabController?.dispose();
      _tabController = TabController(length: _frequencies.length, vsync: this);
      _tabController!.addListener(() {
        if (!_tabController!.indexIsChanging) {
          setState(() => _selectedCommodity = null); // Reset commodity filter
        }
      });
    }

    // Single frequency — no tabs needed
    if (_frequencies.length == 1) {
      final freqTxns = _filterByFrequency(transactions, _frequencies[0]);
      final commodities = _uniqueCommodities(freqTxns);
      final filtered = _applyCommodityFilter(freqTxns);
      final grouped = _groupByDate(filtered);

      return Column(
        children: [
          _buildFrequencyBadge(_frequencies[0], isDark),
          if (commodities.length > 1)
            _buildCommoditySelector(commodities, isDark),
          Expanded(
            child: grouped.isEmpty
                ? _buildEmptyState(isDark)
                : _buildList(context, grouped, isDark),
          ),
        ],
      );
    }

    // Multiple frequencies — use TabBar
    return Column(
      children: [
        _buildFrequencyTabs(isDark),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: _frequencies.map((freq) {
              final freqTxns = _filterByFrequency(transactions, freq);
              final commodities = _uniqueCommodities(freqTxns);
              final filtered = _applyCommodityFilter(freqTxns);
              final grouped = _groupByDate(filtered);

              return Column(
                children: [
                  if (commodities.length > 1)
                    _buildCommoditySelector(commodities, isDark),
                  Expanded(
                    child: grouped.isEmpty
                        ? _buildEmptyState(isDark)
                        : _buildList(context, grouped, isDark),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ── Frequency Tabs (pill style — matches SipOverviewScreen) ─────────
  Widget _buildFrequencyTabs(bool isDark) {
    return Padding(
      padding: EdgeInsets.fromLTRB(40.w, 12.h, 40.w, 4.h),
      child: Container(
        padding: EdgeInsets.all(4.w),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
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
          children: List.generate(_frequencies.length, (index) {
            final freq = _frequencies[index];
            final isSelected = _tabController?.index == index;
            return Expanded(
              child: GestureDetector(
                onTap: () {
                  _tabController?.animateTo(index);
                  setState(() => _selectedCommodity = null);
                },
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
                      freq,
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w500,
                        color: isSelected
                            ? Colors.white
                            : isDark
                                ? Colors.white54
                                : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Single frequency badge (pill style — when only one segment exists)
  Widget _buildFrequencyBadge(String frequency, bool isDark) {
    return Padding(
      padding: EdgeInsets.fromLTRB(40.w, 12.h, 40.w, 4.h),
      child: Container(
        padding: EdgeInsets.all(4.w),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.white,
          borderRadius: BorderRadius.circular(50.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: 10.h),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF003716), Color(0xFF167525)],
            ),
            borderRadius: BorderRadius.circular(50.r),
          ),
          child: Center(
            child: Text(
              frequency,
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Commodity Toggle Chips ─────────────────────────────────────────
  Widget _buildCommoditySelector(List<String> commodities, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
      child: Row(
        children: [
          _buildChip(
            label: 'All',
            isSelected: _selectedCommodity == null,
            onTap: () => setState(() => _selectedCommodity = null),
          ),
          SizedBox(width: 8.w),
          ...commodities.map((c) => Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: _buildChip(
                  label: c,
                  isSelected: _selectedCommodity == c,
                  onTap: () => setState(() => _selectedCommodity = c),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final isGold = label.toLowerCase().contains('gold');
    final chipColor = isSelected
        ? (label == 'All'
            ? const Color(0xFF064E3B)
            : isGold
                ? const Color(0xFFD4A036)
                : const Color(0xFF94A3B8))
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: isSelected
              ? chipColor.withOpacity(0.15)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: isSelected ? chipColor : Colors.black.withOpacity(0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: NumericStyledText(
          label,
          fontSize: 11.sp,
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected
              ? (label == 'All'
                  ? const Color(0xFF064E3B)
                  : isGold
                      ? const Color(0xFF92400E)
                      : const Color(0xFF475569))
              : const Color(0xFF64748B),
        ),
      ),
    );
  }

  // ── Transactions List + Content ────────────────────────────────────
  Widget _buildTransactionList(
      BuildContext context,
      Map<String, List<TransactionItem>> grouped,
      bool isDark,
      List<TransactionItem> allTxns) {
    final commodities = _uniqueCommodities(allTxns);
    final filtered = _applyCommodityFilter(allTxns);
    final filteredGrouped = _groupByDate(filtered);

    return Column(
      children: [
        if (commodities.length > 1)
          _buildCommoditySelector(commodities, isDark),
        Expanded(
          child: filteredGrouped.isEmpty
              ? _buildEmptyState(isDark)
              : _buildList(context, filteredGrouped, isDark),
        ),
      ],
    );
  }

  Widget _buildList(BuildContext context,
      Map<String, List<TransactionItem>> grouped, bool isDark) {
    final dateKeys = grouped.keys.toList();
    return ListView.builder(
      padding: EdgeInsets.only(top: 4.h, bottom: 140.h),
      itemCount: dateKeys.length,
      itemBuilder: (context, index) {
        final dateKey = dateKeys[index];
        final items = grouped[dateKey]!;
        return _buildDateGroup(context, dateKey, items, isDark);
      },
    );
  }

  // ── Date Group ─────────────────────────────────────────────────────
  Widget _buildDateGroup(BuildContext context, String date,
      List<TransactionItem> transactions, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 8.h),
          child: Row(
            children: [
              Container(
                width: 6.w,
                height: 6.w,
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.6),
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8.w),
              NumericStyledText(
                date,
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? Colors.white.withOpacity(0.7)
                    : const Color(0xFF475569),
                letterSpacing: 0.3,
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: Container(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFE2E8F0),
                ),
              ),
              SizedBox(width: 8.w),
              NumericStyledText(
                '${transactions.length} ${transactions.length == 1 ? 'txn' : 'txns'}',
                fontSize: 10.sp,
                color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ],
          ),
        ),
        ...transactions
            .map((tx) => _buildTransactionCard(context, tx, isDark))
            .toList(),
      ],
    );
  }

  // ── Transaction Card ───────────────────────────────────────────────
  Widget _buildTransactionCard(
      BuildContext context, TransactionItem tx, bool isDark) {
    final cardColor = isDark ? Colors.white.withOpacity(0.04) : Colors.white;
    final borderColor =
        isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final mutedColor = isDark ? Colors.white54 : const Color(0xFF64748B);
    final statusColor = _statusColor(tx.status);

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 5.h),
      child: TextButton(
        style: TextButton.styleFrom(
          padding: EdgeInsets.all(16.w),
          backgroundColor: cardColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16.r),
            side: BorderSide(color: borderColor),
          ),
        ),
        onPressed: () {
          Navigator.pushNamed(
            context,
            AppRouter.sipTransactionDetails,
            arguments: {
              'id': tx.transactionId,
              'type': 'sip',
            },
          );
        },
        child: Row(
          children: [
            // SIP Icon
            SvgPicture.asset(
              _getSipIcon(tx.metalName),
              width: 44.w,
              height: 44.w,
            ),
            SizedBox(width: 14.w),
            // Left info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NumericStyledText(
                    tx.metalName,
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                  SizedBox(height: 3.h),
                  Text(
                    'SIP Autopay',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: _teal,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Row(
                    children: [
                      Container(
                        width: 6.r,
                        height: 6.r,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: 4.w),
                      Text(
                        _capitalise(tx.status),
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                      SizedBox(width: 8.w),
                      Flexible(
                        child: Text(
                          tx.displayDate,
                          style: GoogleFonts.lora(
                            fontSize: 10.sp,
                            color: mutedColor,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Right: amount + weight
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${tx.amount.toStringAsFixed(2)}',
                  style: GoogleFonts.lora(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  '${tx.weightGrams.toStringAsFixed(6)} gm',
                  style: GoogleFonts.lora(
                    fontSize: 12.sp,
                    color: mutedColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty State ────────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.r),
            decoration: BoxDecoration(
              color: _teal.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 48.sp,
              color: _teal.withOpacity(0.45),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No SIP Transactions Yet',
            style: GoogleFonts.playfairDisplay(
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Your auto savings transactions will appear here',
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }

  // ── Error State ────────────────────────────────────────────────────
  Widget _buildErrorState(String message, bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: const Color(0xFFDC2626), size: 48.sp),
          SizedBox(height: 16.h),
          Text(
            'Failed to load transactions',
            style: GoogleFonts.playfairDisplay(
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            message,
            style: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () => ref.invalidate(sipTransactionsProvider),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_green, _darkGreen]),
                borderRadius: BorderRadius.circular(20.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, size: 16.sp, color: Colors.white),
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
    );
  }

  // ── Data Helpers ───────────────────────────────────────────────────

  /// Filter transactions by frequency using the subtitle field.
  List<TransactionItem> _filterByFrequency(
      List<TransactionItem> all, String frequency) {
    final freqLower = frequency.toLowerCase();
    return all.where((tx) {
      return tx.subtitle.toLowerCase().contains(freqLower);
    }).toList();
  }

  /// Extract unique commodity names from a list of transactions.
  List<String> _uniqueCommodities(List<TransactionItem> txns) {
    final set = <String>{};
    for (final tx in txns) {
      set.add(tx.metalName);
    }
    return set.toList();
  }

  /// Apply the current commodity filter.
  List<TransactionItem> _applyCommodityFilter(List<TransactionItem> txns) {
    if (_selectedCommodity == null) return txns;
    return txns.where((tx) => tx.metalName == _selectedCommodity).toList();
  }

  /// Re-group a flat transaction list by their date key.
  Map<String, List<TransactionItem>> _groupByDate(List<TransactionItem> txns) {
    final map = <String, List<TransactionItem>>{};
    for (final tx in txns) {
      final key = tx.date.isNotEmpty ? tx.date : tx.displayDate;
      map.putIfAbsent(key, () => []).add(tx);
    }
    return map;
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ── Helpers ────────────────────────────────────────────────────────
  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Color _statusColor(String raw) {
    switch (raw.toLowerCase()) {
      case 'success':
        return const Color(0xFF10B981);
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'cancelled':
      case 'failed':
        return const Color(0xFFDC2626);
      default:
        return const Color(0xFF64748B);
    }
  }

  String _getSipIcon(String metalName) {
    final isGold = metalName.toLowerCase().contains('gold');
    return isGold
        ? 'assets/withdraw/sip_gold.svg'
        : 'assets/withdraw/sip_silver.svg';
  }
}
