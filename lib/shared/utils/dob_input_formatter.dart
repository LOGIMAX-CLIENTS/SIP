import 'package:flutter/services.dart';

/// Formats a date of birth as `DD/MM/YYYY` while typing, inserting the `/`
/// separators automatically:
///
/// ```
/// 19        -> 19/
/// 1906      -> 19/06/
/// 19061992  -> 19/06/1992
/// ```
///
/// Only digits are accepted and input is capped at 8 digits (excluding the
/// slashes it inserts). Use [DobInputFormatter.unformat] to strip the slashes
/// back out.
///
/// This exists so the customer can type a DOB straight through without
/// separators and still land on a valid value. Flutter's own
/// `showDatePicker` keyboard-entry mode parses by locale (`en_US` =>
/// MM/DD/YYYY) and rejects `19061992` with "Invalid format." — the fields
/// using this formatter own their typing instead, and open the picker in
/// `DatePickerEntryMode.calendarOnly` so that path is never reachable.
///
/// Formatting only — it deliberately does NOT reject an impossible day or
/// month (`45/99/...`). Range and age checks belong in the field's validator,
/// so a half-typed value is never fought mid-keystroke. Mirrors
/// `AadhaarInputFormatter`'s split of concerns.
class DobInputFormatter extends TextInputFormatter {
  /// ddMMyyyy — 2 + 2 + 4.
  static const int maxDigits = 8;

  /// Digit positions the separator is written *before*.
  static const List<int> _separatorAfter = [2, 4];

  /// Removes every non-digit character: `19/06/1992` -> `19061992`.
  static String unformat(String value) => value.replaceAll(RegExp(r'\D'), '');

  /// Inserts the slashes. [trailing] appends the separator once a group is
  /// complete (`19` -> `19/`), which is what makes the next keystroke land in
  /// the following group without the customer typing `/` themselves. It is
  /// suppressed while deleting — otherwise backspacing over a slash would
  /// immediately re-add it and the caret could never move left past it.
  static String format(String digits, {bool trailing = true}) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (_separatorAfter.contains(i)) buffer.write('/');
      buffer.write(digits[i]);
    }
    if (trailing && _separatorAfter.contains(digits.length)) buffer.write('/');
    return buffer.toString();
  }

  /// Parses `DD/MM/YYYY` into a real date, or null when incomplete or when the
  /// value isn't a real calendar date (`31/02/1990` -> null: DateTime would
  /// silently roll that over to 03 March).
  static DateTime? parse(String value) {
    final digits = unformat(value);
    if (digits.length != maxDigits) return null;
    final day = int.parse(digits.substring(0, 2));
    final month = int.parse(digits.substring(2, 4));
    final year = int.parse(digits.substring(4));
    if (month < 1 || month > 12 || day < 1) return null;
    final parsed = DateTime(year, month, day);
    if (parsed.day != day || parsed.month != month || parsed.year != year) {
      return null;
    }
    return parsed;
  }

  /// `DateTime` -> `DD/MM/YYYY`, the inverse of [parse].
  static String formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final deleting = newValue.text.length < oldValue.text.length;

    var digits = unformat(newValue.text);
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);

    // Count digits before the caret in the raw input so it can be re-anchored
    // to the same digit once slashes are re-inserted — this is what keeps the
    // caret correct when editing in the middle, not just typing at the end.
    // Same approach as AadhaarInputFormatter.
    final rawUpToCursor = unformat(
      newValue.text.substring(0, newValue.selection.end.clamp(0, newValue.text.length)),
    );
    final digitsBeforeCursor = rawUpToCursor.length.clamp(0, digits.length);

    final formatted = format(digits, trailing: !deleting);

    var newOffset = formatted.length;
    if (digitsBeforeCursor == 0) {
      newOffset = 0;
    } else {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != '/') {
          seen++;
          if (seen == digitsBeforeCursor) {
            newOffset = i + 1;
            break;
          }
        }
      }
      // Typing the last digit of a group leaves the caret before the slash the
      // trailing pass just added; step over it so the next digit types into
      // the next group rather than in front of the separator.
      if (!deleting && newOffset < formatted.length && formatted[newOffset] == '/') {
        newOffset++;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
