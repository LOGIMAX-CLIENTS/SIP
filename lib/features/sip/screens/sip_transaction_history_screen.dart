import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../routes/app_router.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/theme/app_theme.dart';
import '../controller/sip_controller.dart';
import '../models/sip_transaction_filter.dart';
import '../models/sip_transaction_filter_options_model.dart';
import '../../history/models/history_models.dart';
import '../../history/models/history_filter_options_model.dart' show FilterOption;
import './sip_transaction_filter_sheet.dart';

/// SIP Transaction History screen.
///
/// • Fetches fresh data every time the screen is entered.
/// • Primary segmentation: frequency (Daily / Weekly / Monthly / Custom) —
///   always rendered as 4 tabs; each tab lazy-loads and filters
///   independently via [sipHistoryProvider] (family keyed by frequency),
///   mirroring the general Transaction History screen's pagination pattern.
/// • Secondary filter: commodity toggle chips (per tab, server-side) plus a
///   header filter sheet for status/date range — both backed by
///   `sip/transaction-filter-options`.
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
  static const List<String> _frequencies = [
    'Daily',
    'Weekly',
    'Monthly',
    'Custom',
  ];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _frequencies.length, vsync: this);
    // Rebuild the header filter button's badge/tap-target when the selected
    // tab changes — each tab has its own independent filter state.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    // Always fetch fresh data on screen entry, for every tab.
    Future.microtask(() {
      for (final freq in _frequencies) {
        ref.invalidate(sipHistoryProvider(freq));
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _currentFrequency => _frequencies[_tabController.index];

  // ── Open filter sheet (status + date range) for the current tab ──────
  Future<void> _openFilterSheet(
    AsyncValue<SipTransactionFilterOptions> filterOptionsAsync,
  ) async {
    final notifier = ref.read(sipHistoryProvider(_currentFrequency).notifier);
    final result = await showSipTransactionFilterSheet(
      context: context,
      current: notifier.currentFilter,
      filterOptions: ref.read(sipHistoryFilterOptionsProvider),
    );
    if (result != null && mounted) {
      notifier.applyFilter(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filterOptionsAsync = ref.watch(sipHistoryFilterOptionsProvider);
    // Watching the current tab's state (not just reading it) so the header
    // filter badge and refresh spinner update the instant applyFilter()/
    // refresh() lands, without needing a separate listener wired up just
    // for the buttons.
    final currentTabState = ref.watch(sipHistoryProvider(_currentFrequency));
    final currentFilterCount =
        ref.read(sipHistoryProvider(_currentFrequency).notifier).currentFilter.activeCount;

    return Container(
      decoration: BoxDecoration(gradient: AppTheme.lightGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(
              title: 'AutoGold Transactions',
              onBack: () => Navigator.pop(context),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRefreshButton(currentTabState.isLoading),
                  _buildFilterButton(currentFilterCount, filterOptionsAsync),
                ],
              ),
            ),
            _buildFrequencyTabs(isDark),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _frequencies
                    .map((freq) => _SipHistoryTabView(frequency: freq))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header refresh button ──────────────────────────────────────────────
  /// Manual refresh for the currently-selected frequency tab — mirrors
  /// TransactionHistoryScreen's header refresh button. Each tab keeps its
  /// own lazy-loaded pages via [sipHistoryProvider]'s per-frequency family,
  /// so this only re-fetches page 1 for [_currentFrequency], not every tab.
  Widget _buildRefreshButton(bool isLoading) {
    return GestureDetector(
      onTap: isLoading
          ? null
          : () => ref.read(sipHistoryProvider(_currentFrequency).notifier).refresh(),
      child: Container(
        margin: EdgeInsets.only(right: 8.w),
        padding: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.12),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: isLoading
            ? SizedBox(
                width: 15.sp,
                height: 15.sp,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(Icons.refresh_rounded, size: 15.sp, color: Colors.white),
      ),
    );
  }

  // ── Header filter button ──────────────────────────────────────────────
  Widget _buildFilterButton(
      int count, AsyncValue<SipTransactionFilterOptions> filterOptionsAsync) {
    return GestureDetector(
      onTap: () => _openFilterSheet(filterOptionsAsync),
      child: Container(
        margin: EdgeInsets.only(right: 16.w),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
        decoration: BoxDecoration(
          color: count > 0
              ? Colors.white.withOpacity(0.25)
              : Colors.white.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: Colors.white.withOpacity(count > 0 ? 0.5 : 0.2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tune_rounded, size: 15.sp, color: Colors.white),
            SizedBox(width: 5.w),
            NumericStyledText(
              count > 0 ? 'Filter ($count)' : 'Filter',
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ],
        ),
      ),
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
            final isSelected = _tabController.index == index;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tabController.animateTo(index)),
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
}

// ── One tab's lazy-loaded, filterable transaction list ─────────────────────
class _SipHistoryTabView extends ConsumerStatefulWidget {
  final String frequency;

  const _SipHistoryTabView({required this.frequency});

  @override
  ConsumerState<_SipHistoryTabView> createState() =>
      _SipHistoryTabViewState();
}

class _SipHistoryTabViewState extends ConsumerState<_SipHistoryTabView>
    with AutomaticKeepAliveClientMixin {
  static const _green = Color(0xFF1B882C);
  static const _darkGreen = Color(0xFF003716);
  static const _teal = Color(0xFF0D9488);

  late final ScrollController _scrollController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Fires ~300px before the physical bottom so the next batch is ready
  /// before the user actually hits the end. [SipHistoryNotifier.loadMore]
  /// itself guards against duplicate in-flight requests and stops once the
  /// backend reports no more pages.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(sipHistoryProvider(widget.frequency).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin
    final state = ref.watch(sipHistoryProvider(widget.frequency));
    final filterOptionsAsync = ref.watch(sipHistoryFilterOptionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Once data has been loaded once, a refresh/filter re-fetch must never
    // blank the list back to a full-page spinner or error state — those
    // full-page states are only for the true first load of this tab. While
    // refreshing, the header refresh button's own spinner is the activity
    // indicator.
    if (state.error != null && state.isEmpty) {
      return _buildErrorState(state.error!, isDark);
    }
    if (state.isLoading && state.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF064E3B),
          strokeWidth: 2.5,
        ),
      );
    }

    final commodities = filterOptionsAsync.valueOrNull?.commodities ?? const [];
    final notifier = ref.read(sipHistoryProvider(widget.frequency).notifier);
    final filter = notifier.currentFilter;
    final selectedCommodity = filter.commodity;

    return Column(
      children: [
        if (commodities.isNotEmpty)
          _buildCommoditySelector(commodities, selectedCommodity, notifier),
        // Date/Status chips from the filter sheet — commodity isn't repeated
        // here since the toggle row above already shows it selected.
        if (filter.fromDate != null || filter.toDate != null || (filter.status?.isNotEmpty ?? false))
          _buildActiveChipsRow(filter, notifier, isDark),
        Expanded(
          child: state.isEmpty
              ? _buildEmptyState(isDark)
              : _buildList(context, state.groupedData, state.isLoadingMore, isDark),
        ),
      ],
    );
  }

  // ── Active filter chips row (Date/Status — from the filter sheet) ────
  Widget _buildActiveChipsRow(
      SipTransactionFilter filter, SipHistoryNotifier notifier, bool isDark) {
    final chips = <Widget>[];

    if (filter.fromDate != null || filter.toDate != null) {
      final fmt = DateFormat('dd MMM');
      String label;
      if (filter.fromDate != null && filter.toDate != null) {
        label = '${fmt.format(filter.fromDate!)} – ${fmt.format(filter.toDate!)}';
      } else if (filter.fromDate != null) {
        label = 'From ${fmt.format(filter.fromDate!)}';
      } else {
        label = 'Until ${fmt.format(filter.toDate!)}';
      }
      chips.add(_buildActiveChip(
        label: label,
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF7C3AED),
        onRemove: () => notifier.applyFilter(filter.copyWith(clearDates: true)),
      ));
    }

    if (filter.status != null && filter.status!.isNotEmpty) {
      chips.add(_buildActiveChip(
        label: _capitalise(filter.status!),
        icon: Icons.verified_rounded,
        color: _statusColor(filter.status!),
        onRemove: () => notifier.applyFilter(filter.copyWith(clearStatus: true)),
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 4.h),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: NumericStyledText(
              '${filter.activeCount} Filter${filter.activeCount > 1 ? 's' : ''}',
              fontSize: 11.sp,
              fontWeight: FontWeight.w700,
              color: _green,
            ),
          ),
          SizedBox(width: 8.w),
          ...chips.map((c) => Padding(
                padding: EdgeInsets.only(right: 6.w),
                child: c,
              )),
          GestureDetector(
            onTap: () => notifier.applyFilter(
                filter.copyWith(clearDates: true, clearStatus: true)),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.08),
                borderRadius: BorderRadius.circular(20.r),
                border:
                    Border.all(color: const Color(0xFFDC2626).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.close_rounded,
                      size: 12.sp, color: const Color(0xFFDC2626)),
                  SizedBox(width: 4.w),
                  Text(
                    'Clear All',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFDC2626),
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

  Widget _buildActiveChip({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onRemove,
  }) {
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(20.r),
      child: InkWell(
        onTap: null,
        borderRadius: BorderRadius.circular(20.r),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.only(left: 10.w, top: 6.h, bottom: 6.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 12.sp, color: color),
                    SizedBox(width: 5.w),
                    NumericStyledText(
                      label,
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.only(
                  topRight: Radius.circular(20.r),
                  bottomRight: Radius.circular(20.r),
                ),
                child: SizedBox(
                  width: 28.w,
                  height: 30.h,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.all(3.r),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        size: 11.sp,
                        color: color,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Commodity Toggle Chips (backend-driven, server-side filter) ──────
  Widget _buildCommoditySelector(
    List<FilterOption> commodities,
    String? selected,
    SipHistoryNotifier notifier,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 4.h),
      child: Row(
        children: [
          _buildChip(
            label: 'All',
            isSelected: selected == null,
            onTap: () => notifier
                .applyFilter(notifier.currentFilter.copyWith(clearCommodity: true)),
          ),
          SizedBox(width: 8.w),
          ...commodities.map((c) => Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: _buildChip(
                  label: c.label,
                  isSelected: selected == c.value,
                  onTap: () => notifier
                      .applyFilter(notifier.currentFilter.copyWith(commodity: c.value)),
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

  // ── Transactions List ─────────────────────────────────────────────────
  Widget _buildList(BuildContext context,
      Map<String, List<TransactionItem>> grouped, bool isLoadingMore, bool isDark) {
    final dateKeys = grouped.keys.toList();
    final itemCount = dateKeys.length + (isLoadingMore ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.only(top: 4.h, bottom: 140.h),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index >= dateKeys.length) return _buildBottomLoader();
        final dateKey = dateKeys[index];
        final items = grouped[dateKey]!;
        return _buildDateGroup(context, dateKey, items, isDark);
      },
    );
  }

  Widget _buildBottomLoader() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.h),
      child: Center(
        child: SizedBox(
          width: 22.w,
          height: 22.w,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: Color(0xFF064E3B),
          ),
        ),
      ),
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
            SvgPicture.asset(
              _getSipIcon(tx.metalName),
              width: 44.w,
              height: 44.w,
            ),
            SizedBox(width: 14.w),
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
                    'AutoGold Autopay',
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
            'No AutoGold Transactions Yet',
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
            message.replaceAll('Exception: ', ''),
            style: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () =>
                ref.read(sipHistoryProvider(widget.frequency).notifier).refresh(),
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
