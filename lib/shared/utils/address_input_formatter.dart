import 'package:flutter/services.dart';

/// Allows the character set a real address actually needs — letters,
/// digits, spaces, and common address punctuation (comma, period, hyphen,
/// slash, hash, ampersand, apostrophe) — and caps length. Unlike
/// [UpperCaseWordsFormatter] (built for name fields), this does NOT strip
/// digits/punctuation or force per-word capitalization, since house/flat
/// numbers and separators like "Flat No. 12-B, MG Road" are normal,
/// legitimate address content.
class AddressInputFormatter extends TextInputFormatter {
  static final _allowed = RegExp(r"[a-zA-Z0-9 ,./#&'-]");
  static const _maxLength = 200;

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final cleaned =
        newValue.text.split('').where((ch) => _allowed.hasMatch(ch)).join();
    final text =
        cleaned.length > _maxLength ? cleaned.substring(0, _maxLength) : cleaned;

    final offset = newValue.selection.end.clamp(0, text.length);
    return newValue.copyWith(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
