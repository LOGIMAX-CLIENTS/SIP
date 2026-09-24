import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/shared/utils/aadhaar_input_formatter.dart';

void main() {
  TextEditingValue apply(TextEditingValue oldValue, TextEditingValue newValue) {
    return AadhaarInputFormatter().formatEditUpdate(oldValue, newValue);
  }

  test('unformat strips non-digits', () {
    expect(AadhaarInputFormatter.unformat('1123 5535 3423'), '112355353423');
  });

  test('format groups every 4 digits', () {
    expect(AadhaarInputFormatter.format('112355353423'), '1123 5535 3423');
  });

  test('typing digit by digit builds correct groups and caret', () {
    var value = const TextEditingValue(text: '');
    const digits = '112355353423';
    for (var i = 0; i < digits.length; i++) {
      final typed = value.text + digits[i];
      final newValue = TextEditingValue(
        text: typed,
        selection: TextSelection.collapsed(offset: typed.length),
      );
      value = apply(value, newValue);
    }
    expect(value.text, '1123 5535 3423');
    expect(value.selection.baseOffset, value.text.length);
  });

  test('caps at 12 digits, ignoring extra input', () {
    final newValue = const TextEditingValue(
      text: '1123553534239999',
      selection: TextSelection.collapsed(offset: 16),
    );
    final result = apply(const TextEditingValue(text: ''), newValue);
    expect(result.text, '1123 5535 3423');
    expect(AadhaarInputFormatter.unformat(result.text).length, 12);
  });

  test('inserting a digit mid-string keeps caret after the inserted digit', () {
    const oldFormatted = '1123 5535 3423';
    final oldValue = TextEditingValue(
      text: oldFormatted,
      selection: const TextSelection.collapsed(offset: 7),
    );
    final typed = '${oldFormatted.substring(0, 7)}9${oldFormatted.substring(7)}';
    final newValue = TextEditingValue(
      text: typed,
      selection: const TextSelection.collapsed(offset: 8),
    );
    final result = apply(oldValue, newValue);
    final digitsBeforeCaret =
        AadhaarInputFormatter.unformat(result.text.substring(0, result.selection.end)).length;
    expect(digitsBeforeCaret, 7);
  });

  test('deleting a digit produces the correct remaining digit string', () {
    const oldFormatted = '1123 5535 3423';
    final oldValue = TextEditingValue(
      text: oldFormatted,
      selection: const TextSelection.collapsed(offset: 14),
    );
    final newValue = TextEditingValue(
      text: oldFormatted.substring(0, 13),
      selection: const TextSelection.collapsed(offset: 13),
    );
    final result = apply(oldValue, newValue);
    expect(AadhaarInputFormatter.unformat(result.text), '11235535342');
  });
}
