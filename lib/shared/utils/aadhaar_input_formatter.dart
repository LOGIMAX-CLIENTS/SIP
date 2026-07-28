import 'package:flutter/services.dart';

/// Formats a 12-digit Aadhaar number into the official grouping while typing:
/// "XXXX XXXX XXXX" (a space inserted after every 4th digit).
///
/// Only digits are accepted and input is capped at 12 digits (excluding the
/// spaces it inserts). Use [AadhaarInputFormatter.unformat] to strip the
/// spaces back out before sending the value to the backend/API.
class AadhaarInputFormatter extends TextInputFormatter {
  static const int maxDigits = 12;

  /// Removes every non-digit character — the form the backend expects.
  static String unformat(String value) => value.replaceAll(RegExp(r'\D'), '');

  /// Inserts a space after every 4th digit: "112355353423" → "1123 5535 3423".
  static String format(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = unformat(newValue.text);
    if (digits.length > maxDigits) digits = digits.substring(0, maxDigits);

    // Count digits before the cursor in the raw input so the cursor can be
    // re-anchored at the same digit after grouping spaces are re-inserted —
    // this is what keeps the caret correct while inserting/deleting/editing
    // anywhere in the field, not just when typing at the end.
    final rawUpToCursor = unformat(
      newValue.text.substring(0, newValue.selection.end.clamp(0, newValue.text.length)),
    );
    final digitsBeforeCursor = rawUpToCursor.length.clamp(0, digits.length);

    final formatted = format(digits);

    var newOffset = formatted.length;
    if (digitsBeforeCursor == 0) {
      newOffset = 0;
    } else {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ' ') {
          seen++;
          if (seen == digitsBeforeCursor) {
            newOffset = i + 1;
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
