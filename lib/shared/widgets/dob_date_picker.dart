import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

import '../theme/app_text_styles.dart';

/// Date-of-birth picker with a **Day → Month → Year** selection flow.
///
/// Flutter's own `showDatePicker` only toggles between the day grid and a bare
/// YEAR list — there is no month step, and the month is not visible while the
/// customer is scrolling years, so they lose track of what they are picking.
/// This replaces it for DOB fields:
///
///  * the header line always reads `<Month> <Year>` **in every mode**, so the
///    month stays visible while choosing a year — the specific thing the stock
///    picker doesn't do;
///  * tapping that line steps Day → Month → Year, and choosing a value steps
///    back down again, so the flow is explicit rather than a single toggle;
///  * `‹ ›` move by month in day mode and by year elsewhere.
///
/// Returns the chosen date, or null if dismissed.
Future<DateTime?> showDobPicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _DobDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

enum _PickerMode { day, month, year }

class _DobDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;

  const _DobDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  @override
  State<_DobDatePickerDialog> createState() => _DobDatePickerDialogState();
}

class _DobDatePickerDialogState extends State<_DobDatePickerDialog> {
  static const _accent = Color(0xFF0E5723);

  late DateTime _selected;
  /// The month currently on screen — not necessarily the selected one, since
  /// the customer can page around before committing.
  late DateTime _visibleMonth;
  _PickerMode _mode = _PickerMode.day;

  @override
  void initState() {
    super.initState();
    _selected = _clamp(widget.initialDate);
    _visibleMonth = DateTime(_selected.year, _selected.month);
  }

  DateTime _clamp(DateTime d) {
    if (d.isBefore(widget.firstDate)) return widget.firstDate;
    if (d.isAfter(widget.lastDate)) return widget.lastDate;
    return d;
  }

  bool _isSelectable(DateTime d) =>
      !d.isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day)) &&
      !d.isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day));

  /// Whether any day in [month] is selectable — used to grey out months
  /// outside the allowed range (e.g. months after the 18-year cutoff).
  bool _monthHasSelectableDay(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0);
    return _isSelectable(month) || _isSelectable(lastDay) ||
        (month.isBefore(widget.firstDate) && lastDay.isAfter(widget.lastDate));
  }

  void _step(int direction) {
    setState(() {
      if (_mode == _PickerMode.day) {
        _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + direction);
      } else {
        _visibleMonth = DateTime(_visibleMonth.year + direction, _visibleMonth.month);
      }
    });
  }

  /// Day -> **Year** -> Month -> Day.
  ///
  /// Year comes first because it is the coarsest choice and the one furthest
  /// from today for a date of birth — picking 1992 then narrowing to a month
  /// is far less scrolling than stepping months from the current year.
  void _cycleMode() {
    setState(() {
      _mode = switch (_mode) {
        _PickerMode.day => _PickerMode.year,
        _PickerMode.year => _PickerMode.month,
        _PickerMode.month => _PickerMode.day,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final onSurface = isDark ? Colors.white : Colors.black87;

    return Dialog(
      backgroundColor: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 360.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 18.h, 20.w, 8.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Select date of birth',
                      style: AppTextStyles.fieldLabel(isDark)),
                  SizedBox(height: 6.h),
                  Text(
                    DateFormat('EEE, d MMM yyyy').format(_selected),
                    style: AppTextStyles.titleMedium(isDark).copyWith(color: _accent),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: onSurface.withOpacity(0.12)),
            _buildModeBar(isDark, onSurface),
            SizedBox(
              height: 260.h,
              child: switch (_mode) {
                _PickerMode.day => _buildDayGrid(isDark, onSurface),
                _PickerMode.month => _buildMonthGrid(isDark, onSurface),
                _PickerMode.year => _buildYearGrid(isDark, onSurface),
              },
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(12.w, 4.h, 12.w, 8.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: onSurface.withOpacity(0.7))),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    child: const Text('OK',
                        style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `<  September 2008 ▾  >` — the month/year label is ALWAYS shown, in every
  /// mode. That is what keeps the month visible while the year list is open.
  Widget _buildModeBar(bool isDark, Color onSurface) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: _cycleMode,
              borderRadius: BorderRadius.circular(8.r),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        DateFormat('MMMM yyyy').format(_visibleMonth),
                        style: AppTextStyles.fieldLabel(isDark)
                            .copyWith(color: onSurface, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      _mode == _PickerMode.day
                          ? Icons.arrow_drop_down
                          : Icons.arrow_drop_up,
                      color: onSurface,
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () => _step(-1),
            icon: Icon(Icons.chevron_left, color: onSurface),
            tooltip: _mode == _PickerMode.day ? 'Previous month' : 'Previous year',
          ),
          IconButton(
            onPressed: () => _step(1),
            icon: Icon(Icons.chevron_right, color: onSurface),
            tooltip: _mode == _PickerMode.day ? 'Next month' : 'Next year',
          ),
        ],
      ),
    );
  }

  Widget _buildDayGrid(bool isDark, Color onSurface) {
    final first = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    // weekday: Mon=1..Sun=7; the grid starts on Sunday.
    final leading = first.weekday % 7;
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          child: Row(
            children: labels
                .map((l) => Expanded(
                      child: Center(
                        child: Text(l, style: AppTextStyles.fieldHelper(isDark)),
                      ),
                    ))
                .toList(),
          ),
        ),
        SizedBox(height: 4.h),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.symmetric(horizontal: 12.w),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemCount: leading + daysInMonth,
            itemBuilder: (context, i) {
              if (i < leading) return const SizedBox.shrink();
              final day = i - leading + 1;
              final date = DateTime(_visibleMonth.year, _visibleMonth.month, day);
              final selectable = _isSelectable(date);
              final isSelected = date.year == _selected.year &&
                  date.month == _selected.month &&
                  date.day == _selected.day;
              return _cell(
                label: '$day',
                selected: isSelected,
                enabled: selectable,
                isDark: isDark,
                onSurface: onSurface,
                circular: true,
                onTap: () => setState(() => _selected = date),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthGrid(bool isDark, Color onSurface) {
    return GridView.builder(
      padding: EdgeInsets.all(12.r),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.1,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: 12,
      itemBuilder: (context, i) {
        final month = DateTime(_visibleMonth.year, i + 1);
        final enabled = _monthHasSelectableDay(month);
        return _cell(
          label: DateFormat('MMM').format(month),
          selected: _visibleMonth.month == i + 1,
          enabled: enabled,
          isDark: isDark,
          onSurface: onSurface,
          onTap: () => setState(() {
            _visibleMonth = month;
            // Month -> Day: the last step, so picking a month lands the
            // customer on the day grid for that month.
            _mode = _PickerMode.day;
          }),
        );
      },
    );
  }

  Widget _buildYearGrid(bool isDark, Color onSurface) {
    final firstYear = widget.firstDate.year;
    final lastYear = widget.lastDate.year;
    final count = lastYear - firstYear + 1;
    // Open near the current selection rather than at 1900.
    final initialScroll =
        ((_visibleMonth.year - firstYear) ~/ 3).toDouble() * 48.h - 80.h;

    return GridView.builder(
      controller: ScrollController(
          initialScrollOffset: initialScroll.clamp(0, double.infinity)),
      padding: EdgeInsets.all(12.r),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.1,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemCount: count,
      itemBuilder: (context, i) {
        final year = firstYear + i;
        return _cell(
          label: '$year',
          selected: _visibleMonth.year == year,
          enabled: true,
          isDark: isDark,
          onSurface: onSurface,
          onTap: () => setState(() {
            _visibleMonth = DateTime(year, _visibleMonth.month);
            // Year -> Month: the next step down in the Year -> Month -> Day
            // flow, so the customer narrows rather than jumping back to days.
            _mode = _PickerMode.month;
          }),
        );
      },
    );
  }

  Widget _cell({
    required String label,
    required bool selected,
    required bool enabled,
    required bool isDark,
    required Color onSurface,
    required VoidCallback onTap,
    bool circular = false,
  }) {
    final radius = circular ? BorderRadius.circular(100.r) : BorderRadius.circular(10.r);
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: radius,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? _accent : Colors.transparent,
          borderRadius: radius,
        ),
        child: Text(
          label,
          style: AppTextStyles.kycFieldInput(isDark).copyWith(
            color: selected
                ? Colors.white
                : enabled
                    ? onSurface
                    : onSurface.withOpacity(0.3),
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
