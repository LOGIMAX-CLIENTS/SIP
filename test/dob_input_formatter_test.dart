import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/shared/utils/dob_input_formatter.dart';

void main() {
  TextEditingValue apply(TextEditingValue oldValue, TextEditingValue newValue) {
    return DobInputFormatter().formatEditUpdate(oldValue, newValue);
  }

  /// Types [input] one character at a time, as a real keyboard would.
  /// Starts from an explicit offset 0 — a bare `TextEditingValue(text: '')`
  /// carries selection offset -1, not 0.
  TextEditingValue typeAll(String input) {
    var value = const TextEditingValue(
      text: '',
      selection: TextSelection.collapsed(offset: 0),
    );
    for (var i = 0; i < input.length; i++) {
      final caret = value.selection.baseOffset.clamp(0, value.text.length);
      final typed =
          value.text.substring(0, caret) + input[i] + value.text.substring(caret);
      value = apply(
        value,
        TextEditingValue(
          text: typed,
          selection: TextSelection.collapsed(offset: caret + 1),
        ),
      );
    }
    return value;
  }

  group('helpers', () {
    test('unformat strips slashes', () {
      expect(DobInputFormatter.unformat('19/06/1992'), '19061992');
    });

    test('format inserts slashes at the group boundaries', () {
      expect(DobInputFormatter.format('19061992'), '19/06/1992');
    });

    test('formatDate pads single digits', () {
      expect(DobInputFormatter.formatDate(DateTime(1992, 6, 9)), '09/06/1992');
    });
  });

  group('the separators the spec asks for', () {
    test('19 -> 19/', () {
      expect(DobInputFormatter.format('19'), '19/');
    });

    test('1906 -> 19/06/', () {
      expect(DobInputFormatter.format('1906'), '19/06/');
    });

    test('19061992 -> 19/06/1992', () {
      expect(DobInputFormatter.format('19061992'), '19/06/1992');
    });
  });

  group('typing straight through, no separators', () {
    test('19061992 formats itself and leaves the caret at the end', () {
      final value = typeAll('19061992');
      expect(value.text, '19/06/1992');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('caret steps over each slash so digits land in the next group', () {
      // After the day, the caret must sit AFTER the slash — otherwise the
      // month's first digit would be typed in front of it.
      expect(typeAll('19').text, '19/');
      expect(typeAll('19').selection.baseOffset, 3);
      expect(typeAll('1906').text, '19/06/');
      expect(typeAll('1906').selection.baseOffset, 6);
    });

    test('slashes the user types themselves are absorbed, not doubled', () {
      expect(typeAll('19/06/1992').text, '19/06/1992');
    });

    test('input is capped at 8 digits', () {
      expect(typeAll('190619921234').text, '19/06/1992');
    });

    test('non-digits are ignored', () {
      expect(typeAll('19a06b1992').text, '19/06/1992');
    });
  });

  group('deleting', () {
    test('backspace can move left past a slash instead of it being re-added', () {
      // "19/" then backspace: without the deleting guard the trailing slash
      // would be re-inserted and the caret could never get back to the day.
      final typed = typeAll('19');
      expect(typed.text, '19/');
      final afterBackspace = apply(
        typed,
        const TextEditingValue(text: '19', selection: TextSelection.collapsed(offset: 2)),
      );
      expect(afterBackspace.text, '19');
    });

    test('clearing the field leaves it empty', () {
      final typed = typeAll('19061992');
      final cleared = apply(
        typed,
        const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)),
      );
      expect(cleared.text, '');
    });
  });

  group('parse', () {
    test('reads a complete DD/MM/YYYY', () {
      expect(DobInputFormatter.parse('19/06/1992'), DateTime(1992, 6, 19));
    });

    test('null while still incomplete', () {
      expect(DobInputFormatter.parse('19/06/19'), isNull);
      expect(DobInputFormatter.parse(''), isNull);
    });

    test('rejects a day that does not exist in that month', () {
      // DateTime(1990, 2, 31) silently rolls over to 3 March — parse must not
      // accept that, or an impossible DOB would be stored as a real one.
      expect(DobInputFormatter.parse('31/02/1990'), isNull);
      expect(DobInputFormatter.parse('31/04/1990'), isNull);
    });

    test('rejects an impossible month or a zero day', () {
      expect(DobInputFormatter.parse('19/13/1992'), isNull);
      expect(DobInputFormatter.parse('19/00/1992'), isNull);
      expect(DobInputFormatter.parse('00/06/1992'), isNull);
    });

    test('accepts a real leap day and rejects a fake one', () {
      expect(DobInputFormatter.parse('29/02/1992'), DateTime(1992, 2, 29));
      expect(DobInputFormatter.parse('29/02/1993'), isNull);
    });
  });
}
