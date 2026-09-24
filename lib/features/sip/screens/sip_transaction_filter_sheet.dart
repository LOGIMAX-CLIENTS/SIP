import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../shared/widgets/numeric_styled_text.dart';
import '../models/sip_transaction_filter.dart';
import '../models/sip_transaction_filter_options_model.dart';
import '../../history/models/history_filter_options_model.dart' show FilterOption;
import '../../history/screens/transaction_filter_sheet.dart' show resolveHexColor;

/// Filter bottom sheet for one SIP Transactions tab (Status + Date Range).
///
/// Frequency isn't a field here — the tab itself already scopes the request
/// — and Commodity stays as the always-visible inline chip row above the
/// list (see SipTransactionHistoryScreen), rather than living in this sheet.
/// Status options come entirely from the backend
/// (`POST sip/transaction-filter-options` — see [SipTransactionFilterOptions]).
///
/// Usage:
/// ```dart
/// final result = await showSipTransactionFilterSheet(
///   context: context,
///   current: notifier.currentFilter,
///   filterOptions: ref.watch(sipHistoryFilterOptionsProvider),
/// );
/// if (result != null) notifier.applyFilter(result);
/// ```
Future<SipTransactionFilter?> showSipTransactionFilterSheet({
  required BuildContext context,
  required SipTransactionFilter current,
  required AsyncValue<SipTransactionFilterOptions> filterOptions,
}) {
  return showModalBottomSheet<SipTransactionFilter>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SipTransactionFilterSheet(
      current: current,
      filterOptions: filterOptions,
    ),
  );
}

class _SipTransactionFilterSheet extends StatefulWidget {
  final SipTransactionFilter current;
  final AsyncValue<SipTransactionFilterOptions> filterOptions;

  const _SipTransactionFilterSheet({
    required this.current,
    required this.filterOptions,
  });

  @override
  State<_SipTransactionFilterSheet> createState() =>
      _SipTransactionFilterSheetState();
}

class _SipTransactionFilterSheetState
    extends State<_SipTransactionFilterSheet> {
  late DateTime? _fromDate;
  late DateTime? _toDate;
  late String? _status;

  static const _green = Color(0xFF1B882C);
  static const _darkGreen = Color(0xFF003716);
  static const _bgLight = Color(0xFFF8F9FA);
  static const _cardLight = Colors.white;
  static const _borderLight = Color(0xFFE9ECEF);
  static const _labelLight = Color(0xFF495057);
  static const _mutedLight = Color(0xFF868E96);

  @override
  void initState() {
    super.initState();
    _fromDate = widget.current.fromDate;
    _toDate = widget.current.toDate;
    _status = widget.current.status;
  }

  int get _activeCount {
    int c = 0;
    if (_fromDate != null || _toDate != null) c++;
    if (_status != null && _status!.isNotEmpty) c++;
    return c;
  }

  void _reset() => setState(() {
        _fromDate = null;
        _toDate = null;
        _status = null;
      });

  void _apply() => Navigator.pop(
        context,
        SipTransactionFilter(
          fromDate: _fromDate,
          toDate: _toDate,
          commodity: widget.current.commodity, // commodity is chip-driven, carried through unchanged
          status: _status,
        ),
      );

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_fromDate ?? DateTime.now())
        : (_toDate ?? _fromDate ?? DateTime.now());
    final first = isFrom ? DateTime(2020) : (_fromDate ?? DateTime(2020));
    final last = isFrom ? (_toDate ?? DateTime.now()) : DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: first,
      lastDate: last,
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _green,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
        if (_toDate != null && _toDate!.isBefore(picked)) _toDate = null;
      } else {
        _toDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F172A) : _bgLight;
    final card = isDark ? const Color(0xFF1E293B) : _cardLight;
    final border = isDark ? const Color(0xFF334155) : _borderLight;
    final label = isDark ? Colors.white70 : _labelLight;
    final muted = isDark ? Colors.white38 : _mutedLight;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.8,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 30,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHandle(isDark),
            _buildHeader(isDark, muted),
            Expanded(
              child: ListView(
                controller: scrollCtrl,
                padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 20.h),
                children: [
                  _buildSection(
                    label: 'Date Range',
                    icon: Icons.date_range_rounded,
                    card: card,
                    border: border,
                    labelColor: label,
                    child: _buildDateRange(isDark),
                  ),
                  SizedBox(height: 16.h),
                  _buildSection(
                    label: 'Status',
                    icon: Icons.verified_rounded,
                    card: card,
                    border: border,
                    labelColor: label,
                    child: _buildDynamicChipGroup(
                      selector: (o) => o.statuses,
                      selected: _status,
                      onTap: (val) =>
                          setState(() => _status = val == _status ? null : val),
                    ),
                  ),
                ],
              ),
            ),
            _buildActionBar(isDark, card, border),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(bool isDark) {
    return Padding(
      padding: EdgeInsets.only(top: 12.h, bottom: 4.h),
      child: Container(
        width: 42.w,
        height: 4.h,
        decoration: BoxDecoration(
          color: isDark ? Colors.white24 : Colors.black12,
          borderRadius: BorderRadius.circular(100.r),
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark, Color muted) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 12.h),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter AutoGold Transactions',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
                if (_activeCount > 0) ...[
                  SizedBox(height: 2.h),
                  NumericStyledText(
                    '$_activeCount filter${_activeCount > 1 ? 's' : ''} applied',
                    fontSize: 12.sp,
                    color: _green,
                    fontWeight: FontWeight.w600,
                  ),
                ],
              ],
            ),
          ),
          if (_activeCount > 0)
            GestureDetector(
              onTap: _reset,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 7.h),
                decoration: BoxDecoration(
                  color: const Color(0xFFDC2626).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(
                    color: const Color(0xFFDC2626).withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.restart_alt_rounded,
                        size: 14.sp, color: const Color(0xFFDC2626)),
                    SizedBox(width: 5.w),
                    Text(
                      'Reset All',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
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

  Widget _buildSection({
    required String label,
    required IconData icon,
    required Color card,
    required Color border,
    required Color labelColor,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.r),
              decoration: BoxDecoration(
                color: _green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Icon(icon, size: 14.sp, color: _green),
            ),
            SizedBox(width: 8.w),
            Text(
              label,
              style: GoogleFonts.playfairDisplay(
                fontSize: 13.sp,
                fontWeight: FontWeight.w800,
                color: labelColor,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        Container(
          decoration: BoxDecoration(
            color: card,
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: border),
          ),
          padding: EdgeInsets.all(16.r),
          child: child,
        ),
      ],
    );
  }

  Widget _buildDateRange(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildDateButton(
            label: 'From',
            date: _fromDate,
            isDark: isDark,
            onTap: () => _pickDate(isFrom: true),
            onClear: _fromDate != null
                ? () => setState(() => _fromDate = null)
                : null,
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.w),
          child: Text('→',
              style: GoogleFonts.playfairDisplay(
                fontSize: 16.sp,
                color: _green,
                fontWeight: FontWeight.w700,
              )),
        ),
        Expanded(
          child: _buildDateButton(
            label: 'To',
            date: _toDate,
            isDark: isDark,
            onTap: () => _pickDate(isFrom: false),
            onClear:
                _toDate != null ? () => setState(() => _toDate = null) : null,
          ),
        ),
      ],
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime? date,
    required bool isDark,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final isSet = date != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: isSet
              ? _green.withOpacity(0.07)
              : (isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF8FAFC)),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isSet ? _green.withOpacity(0.4) : Colors.grey.withOpacity(0.2),
            width: isSet ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 14.sp, color: isSet ? _green : Colors.grey),
            SizedBox(width: 6.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 9.sp,
                      fontWeight: FontWeight.w600,
                      color: isSet ? _green : Colors.grey,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    date != null
                        ? DateFormat('dd MMM yy').format(date)
                        : 'Select',
                    style: date != null
                        ? GoogleFonts.lora(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: _darkGreen,
                          )
                        : GoogleFonts.playfairDisplay(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white38 : Colors.grey,
                          ),
                  ),
                ],
              ),
            ),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child:
                    Icon(Icons.close_rounded, size: 14.sp, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicChipGroup({
    required List<FilterOption> Function(SipTransactionFilterOptions) selector,
    required String? selected,
    required ValueChanged<String> onTap,
  }) {
    return widget.filterOptions.when(
      data: (options) {
        final list = selector(options);
        if (list.isEmpty) return _buildOptionsMessage('No options available');
        return _buildChipGroup(options: list, selected: selected, onTap: onTap);
      },
      loading: () => Row(
        children: [
          SizedBox(
            width: 14.w,
            height: 14.w,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8.w),
          _buildOptionsMessage('Loading options…'),
        ],
      ),
      error: (_, __) => _buildOptionsMessage('Unable to load options'),
    );
  }

  Widget _buildOptionsMessage(String text) {
    return Text(
      text,
      style: GoogleFonts.playfairDisplay(
        fontSize: 12.sp,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade500,
      ),
    );
  }

  Widget _buildChipGroup({
    required List<FilterOption> options,
    required String? selected,
    required ValueChanged<String> onTap,
  }) {
    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: options.map((opt) {
        final isSelected = opt.value == selected;
        final color = resolveHexColor(opt.colorHex, _green);
        return GestureDetector(
          onTap: () => onTap(opt.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
            decoration: BoxDecoration(
              gradient: isSelected
                  ? LinearGradient(
                      colors: [color.withOpacity(0.9), color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: isSelected ? null : Colors.transparent,
              borderRadius: BorderRadius.circular(30.r),
              border: Border.all(
                color: isSelected ? color : Colors.grey.withOpacity(0.3),
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withOpacity(0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check_rounded, size: 12.sp, color: Colors.white),
                  SizedBox(width: 4.w),
                ],
                NumericStyledText(
                  _capitalise(opt.label),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildActionBar(bool isDark, Color card, Color border) {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 16.h),
        decoration: BoxDecoration(
          color: card,
          border: Border(top: BorderSide(color: border)),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: GestureDetector(
                onTap: _reset,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE2E8F0),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'Reset',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white60 : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              flex: 3,
              child: GestureDetector(
                onTap: _apply,
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [_green, _darkGreen],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(16.r),
                    boxShadow: [
                      BoxShadow(
                        color: _green.withOpacity(0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          size: 16.sp, color: Colors.white),
                      SizedBox(width: 8.w),
                      NumericStyledText(
                        _activeCount > 0 ? 'Apply ($_activeCount)' : 'Show All',
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
