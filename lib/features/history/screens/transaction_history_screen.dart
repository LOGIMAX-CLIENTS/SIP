import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import 'package:intl/intl.dart';
import '../../../routes/app_router.dart';
import '../../main/main_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controller/history_controller.dart';
import '../models/history_models.dart';
import '../models/transaction_filter.dart';
import '../models/history_filter_options_model.dart';
import '../../../shared/widgets/gradient_header.dart';
import './transaction_filter_sheet.dart';

class TransactionHistoryScreen extends ConsumerStatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  ConsumerState<TransactionHistoryScreen> createState() =>
      _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState
    extends ConsumerState<TransactionHistoryScreen> {
  // Filter state — persists across rebuilds
  TransactionFilter _filter = TransactionFilter.empty;

  // ── Colors ────────────────────────────────────────────────────────
  static const _green = Color(0xFF1B882C);
  static const _darkGreen = Color(0xFF003716);

  // ── Lazy-load scroll trigger ────────────────────────────────────────
  late final ScrollController _scrollController;

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
  /// before the user actually hits the end (smooth, no visible pause).
  /// [HistoryNotifier.loadMore] itself guards against duplicate in-flight
  /// requests and stops once the backend reports no more pages, so calling
  /// it repeatedly while inside the threshold zone is safe.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      ref.read(historyProvider.notifier).loadMore();
    }
  }

  // ── Open filter sheet ─────────────────────────────────────────────
  /// Commodity/Type/Status options are sourced entirely from
  /// [historyFilterOptionsProvider] (`transactions/filter-options`) — never
  /// derived from the locally-loaded transaction list.
  ///
  /// Tapping "Apply" *or* "Show All" both flow through here — "Show All"
  /// just pops an empty [TransactionFilter] — and either way
  /// [_applyFilter] fetches page 1 fresh from the backend with those
  /// criteria, so the button always reflects the customer's full history,
  /// not just whatever page is already cached locally.
  Future<void> _openFilterSheet(
    AsyncValue<HistoryFilterOptions> filterOptionsAsync,
  ) async {
    final result = await showTransactionFilterSheet(
      context: context,
      current: _filter,
      filterOptions: filterOptionsAsync,
    );
    if (result != null && mounted) {
      _applyFilter(result);
    }
  }

  /// Updates local UI state (active chips, badge count) and triggers a
  /// fresh server-side fetch for the new filter criteria.
  void _applyFilter(TransactionFilter filter) {
    setState(() => _filter = filter);
    ref.read(historyProvider.notifier).applyFilter(filter);
  }

  // ── Remove individual chip ────────────────────────────────────────
  void _removeChip(String chipType) {
    late final TransactionFilter next;
    switch (chipType) {
      case 'date':
        next = _filter.copyWith(clearDates: true);
        break;
      case 'metal':
        next = _filter.copyWith(clearMetal: true);
        break;
      case 'type':
        next = _filter.copyWith(clearType: true);
        break;
      case 'status':
        next = _filter.copyWith(clearStatus: true);
        break;
      default:
        next = _filter;
    }
    _applyFilter(next);
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final historyState = ref.watch(historyProvider);
    final filterOptionsAsync = ref.watch(historyFilterOptionsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget body;
    if (historyState.error != null) {
      body = Center(child: Text('Error: ${historyState.error}'));
    } else if (historyState.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _buildBody(context, historyState, filterOptionsAsync, isDark);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Transaction History',
            onBack: () {
              final routeName = ModalRoute.of(context)?.settings.name;
              if (routeName == AppRouter.transactionHistory) {
                Navigator.pop(context);
              } else {
                ref.read(selectedTabProvider.notifier).state = 0;
              }
            },
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRefreshButton(historyState.isLoading),
                if (!historyState.isLoading && historyState.error == null)
                  _buildFilterButton(filterOptionsAsync, isDark),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }

  // ── Header refresh button ──────────────────────────────────────────
  /// Manual refresh — the History tab intentionally does NOT auto-refetch
  /// on every tab switch (see MainScreen._onTabTapped's comment: the lazy
  /// list preserves already-loaded pages and scroll position across tab
  /// switches), so a transaction made elsewhere in the app while History
  /// was last loaded won't appear until the customer either backs out and
  /// re-enters the tab from scratch, or taps this. Always visible (unlike
  /// the filter button, which hides during the very first load/error) so
  /// there's always a way to pull fresh data on demand.
  Widget _buildRefreshButton(bool isLoading) {
    return GestureDetector(
      onTap: isLoading
          ? null
          : () => ref.read(historyProvider.notifier).refresh(),
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

  // ── Header filter button ─────────────────────────────────────────
  Widget _buildFilterButton(
      AsyncValue<HistoryFilterOptions> filterOptionsAsync, bool isDark) {
    final count = _filter.activeCount;
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

  // ── Body ──────────────────────────────────────────────────────────
  Widget _buildBody(BuildContext context, HistoryPageState historyState,
      AsyncValue<HistoryFilterOptions> filterOptionsAsync, bool isDark) {
    // Filtering is applied server-side (see HistoryNotifier.applyFilter) —
    // groupedData already reflects the currently-active filter, so it's
    // rendered as-is rather than re-filtered locally.
    final filtered = historyState.groupedData;
    // Status color lookup is backend-driven (filterOptionsAsync); while it's
    // loading/erroring, _statusColor falls back to a built-in color for
    // already-known statuses — it never invents new status values.
    final statusOptions = filterOptionsAsync.valueOrNull?.statuses ?? const [];

    return Column(
      children: [
        // ── Active filter chips row ──────────────────────────────
        if (!_filter.isEmpty) _buildActiveChipsRow(isDark, statusOptions),

        // ── Transactions list ────────────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState(isDark)
              : _buildList(context, filtered, statusOptions,
                  historyState.isLoadingMore, isDark),
        ),
      ],
    );
  }

  // ── Active chips row ──────────────────────────────────────────────
  Widget _buildActiveChipsRow(bool isDark, List<FilterOption> statusOptions) {
    final chips = <Widget>[];

    // Date chip
    if (_filter.fromDate != null || _filter.toDate != null) {
      final fmt = DateFormat('dd MMM');
      String label = '';
      if (_filter.fromDate != null && _filter.toDate != null) {
        label =
            '${fmt.format(_filter.fromDate!)} – ${fmt.format(_filter.toDate!)}';
      } else if (_filter.fromDate != null) {
        label = 'From ${fmt.format(_filter.fromDate!)}';
      } else {
        label = 'Until ${fmt.format(_filter.toDate!)}';
      }
      chips.add(_buildActiveChip(
        label: label,
        icon: Icons.calendar_today_rounded,
        color: const Color(0xFF7C3AED),
        onRemove: () => _removeChip('date'),
      ));
    }

    // Metal chip
    if (_filter.metalName != null && _filter.metalName!.isNotEmpty) {
      chips.add(_buildActiveChip(
        label: _filter.metalName!,
        icon: Icons.auto_awesome_rounded,
        color: const Color(0xFFD97706),
        onRemove: () => _removeChip('metal'),
      ));
    }

    // Type chip
    if (_filter.type != null && _filter.type!.isNotEmpty) {
      chips.add(_buildActiveChip(
        label: _capitalise(_filter.type!),
        icon: Icons.swap_horiz_rounded,
        color: _green,
        onRemove: () => _removeChip('type'),
      ));
    }

    // Status chip
    if (_filter.status != null && _filter.status!.isNotEmpty) {
      chips.add(_buildActiveChip(
        label: _capitalise(_filter.status!),
        icon: Icons.verified_rounded,
        color: _statusColor(_filter.status!, statusOptions),
        onRemove: () => _removeChip('status'),
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 4.h),
      child: Row(
        children: [
          // Count badge
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20.r),
            ),
            child: NumericStyledText(
              '${_filter.activeCount} Filter${_filter.activeCount > 1 ? 's' : ''}',
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
          // Clear all
          GestureDetector(
            onTap: () => _applyFilter(TransactionFilter.empty),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626).withOpacity(0.08),
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                    color: const Color(0xFFDC2626).withOpacity(0.2)),
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
        // Tapping the chip label area does nothing (only ✕ removes)
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
              // Label area
              Padding(
                padding: EdgeInsets.only(
                    left: 10.w, top: 6.h, bottom: 6.h),
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
              // ✕ remove area — dedicated InkWell with generous tap zone
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

  // ── Transaction list ──────────────────────────────────────────────
  Widget _buildList(
      BuildContext context,
      Map<String, List<TransactionItem>> filtered,
      List<FilterOption> statusOptions,
      bool isLoadingMore,
      bool isDark) {
    final dateKeys = filtered.keys.toList();
    final itemCount = dateKeys.length + (isLoadingMore ? 1 : 0);
    return RefreshIndicator(
      color: _green,
      onRefresh: () => ref.read(historyProvider.notifier).refresh(),
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.only(top: 4.h, bottom: 120.h),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index >= dateKeys.length) {
            return _buildBottomLoader();
          }
          final dateKey = dateKeys[index];
          final items = filtered[dateKey]!;
          return _buildDateGroup(context, dateKey, items, statusOptions, isDark);
        },
      ),
    );
  }

  // ── Bottom "loading next batch" indicator ──────────────────────────
  Widget _buildBottomLoader() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 20.h),
      child: Center(
        child: SizedBox(
          width: 22.w,
          height: 22.w,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: _green,
          ),
        ),
      ),
    );
  }

  // ── Date group ────────────────────────────────────────────────────
  Widget _buildDateGroup(BuildContext context, String date,
      List<TransactionItem> transactions,
      List<FilterOption> statusOptions, bool isDark) {
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
                  color: isDark
                      ? Colors.white10
                      : const Color(0xFFE2E8F0),
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
            .map((tx) =>
                _buildTransactionCard(context, tx, statusOptions, isDark))
            .toList(),
      ],
    );
  }

  // ── Transaction card ──────────────────────────────────────────────
  Widget _buildTransactionCard(BuildContext context, TransactionItem tx,
      List<FilterOption> statusOptions, bool isDark) {
    final isSaving = tx.type == 'purchase';
    final isReferral = tx.type == 'referral';
    final isSip = tx.type == 'sip';
    final isOffer = tx.type == 'offer';
    final cardColor = isDark ? Colors.white.withOpacity(0.04) : Colors.white;
    final borderColor =
        isDark ? Colors.white10 : Colors.black.withOpacity(0.05);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final mutedColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    final typeLabel = isSip
        ? 'SIP Autopay'
        : isSaving
            ? 'Instant Saving'
            : isReferral
                ? 'Referral Reward'
                : isOffer
                    ? 'Offer Reward'
                    : 'Withdrawal';

    final typeColor = isSip
        ? const Color(0xFF0D9488)  // teal — SIP
        : isSaving
            ? const Color(0xFF1B882C)   // green — Instant Saving
            : isReferral
                ? const Color(0xFF7C3AED) // purple — Referral
                : isOffer
                    ? const Color(0xFF0D9488) // teal — Offer Reward (same as SIP)
                    : const Color(0xFFDC2626); // red — Withdrawal

    final statusColor = _statusColor(tx.status, statusOptions);

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
          Navigator.pushNamed(context, AppRouter.transactionDetails,
              arguments: {
                'id': tx.transactionId,
                'type': tx.type,
              });
        },
        child: Row(
          children: [
            // Icon
            SvgPicture.asset(
              _getTransactionIcon(tx.type, tx.metalName),
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
                    typeLabel,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: typeColor,
                    ),
                  ),
                  SizedBox(height: 5.h),
                  Row(
                    children: [
                      // Status dot + label
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

  // ── Empty state ───────────────────────────────────────────────────
  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(24.r),
            decoration: BoxDecoration(
              color: _green.withOpacity(0.07),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.filter_list_off_rounded,
              size: 48.sp,
              color: _green.withOpacity(0.45),
            ),
          ),
          SizedBox(height: 20.h),
          Text(
            'No Transactions Found',
            style: GoogleFonts.playfairDisplay(
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Try adjusting or clearing your filters',
            style: GoogleFonts.playfairDisplay(
              fontSize: 13.sp,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
          ),
          SizedBox(height: 20.h),
          GestureDetector(
            onTap: () => _applyFilter(TransactionFilter.empty),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_green, _darkGreen],
                ),
                borderRadius: BorderRadius.circular(20.r),
                boxShadow: [
                  BoxShadow(
                    color: _green.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.restart_alt_rounded,
                      size: 16.sp, color: Colors.white),
                  SizedBox(width: 8.w),
                  Text(
                    'Clear Filters',
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

  /// Resolves a status's display color from the backend-driven
  /// [statusOptions] (`transactions/filter-options`), falling back to
  /// [defaultStatusColorHex] for a status not present there.
  Color _statusColor(String raw, List<FilterOption> statusOptions) {
    String? hex;
    for (final option in statusOptions) {
      if (option.value.toLowerCase() == raw.toLowerCase()) {
        hex = option.colorHex;
        break;
      }
    }
    hex ??= defaultStatusColorHex(raw);
    return resolveHexColor(hex, const Color(0xFF64748B));
  }

  String _getTransactionIcon(String type, String metalName) {
    final isGold = metalName.toLowerCase().contains('gold');
    switch (type) {
      case 'purchase':
        return isGold
            ? 'assets/withdraw/inst_gold.svg'
            : 'assets/withdraw/inst_silver.svg';
      case 'sip':
        return isGold
            ? 'assets/withdraw/sip_gold.svg'
            : 'assets/withdraw/sip_silver.svg';
      case 'referral':
        return 'assets/withdraw/trans_referal.svg';
      case 'offer':
        return 'assets/withdraw/offer-reward-silver.svg';
      default:
        return isGold
            ? 'assets/withdraw/with_gold.svg'
            : 'assets/withdraw/with_silver.svg';
    }
  }
}
