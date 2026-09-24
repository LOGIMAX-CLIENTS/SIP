import 'package:flutter/services.dart';

/// Formats a 10-character PAN into its structural grouping while typing:
/// "AAAAA 9999 A" (5 letters, 4 digits, 1 letter — mirrors the PAN's own
/// structure, `^[A-Z]{5}[0-9]{4}[A-Z]{1}$`) — the same visual treatment
/// [AadhaarInputFormatter] already gives the Aadhaar number field
/// ("XXXX XXXX XXXX"), so both government-ID fields read the same way.
///
/// Only letters/digits are accepted (forced uppercase) and input is capped
/// at 10 characters (excluding the spaces it inserts). Use
/// [PanInputFormatter.unformat] to strip the spaces back out before
/// validating or sending the value to the backend/API.
class PanInputFormatter extends TextInputFormatter {
  static const int maxChars = 10;
  static const List<int> _groupSizes = [5, 4, 1];

  /// Removes every non-alphanumeric character and uppercases — the form
  /// the backend/validator expects.
  static String unformat(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase();

  /// Inserts a space after the 5th and 9th character:
  /// "ABCDE1234F" -> "ABCDE 1234 F".
  static String format(String chars) {
    final buffer = StringBuffer();
    var groupIndex = 0;
    var posInGroup = 0;
    for (var i = 0; i < chars.length; i++) {
      if (posInGroup == _groupSizes[groupIndex]) {
        buffer.write(' ');
        groupIndex++;
        posInGroup = 0;
      }
      buffer.write(chars[i]);
      posInGroup++;
    }
    return buffer.toString();
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var chars = unformat(newValue.text);
    if (chars.length > maxChars) chars = chars.substring(0, maxChars);

    // Count characters before the cursor in the raw input so the cursor can
    // be re-anchored at the same character after grouping spaces are
    // re-inserted — mirrors AadhaarInputFormatter's identical cursor logic.
    final rawUpToCursor = unformat(
      newValue.text.substring(0, newValue.selection.end.clamp(0, newValue.text.length)),
    );
    final charsBeforeCursor = rawUpToCursor.length.clamp(0, chars.length);

    final formatted = format(chars);

    var newOffset = formatted.length;
    if (charsBeforeCursor == 0) {
      newOffset = 0;
    } else {
      var seen = 0;
      for (var i = 0; i < formatted.length; i++) {
        if (formatted[i] != ' ') {
          seen++;
          if (seen == charsBeforeCursor) {
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
