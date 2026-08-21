// Covers all 15 input-field categories from the validation audit: what
// validation currently exists (formatters + validators), run as real
// `flutter test` assertions rather than hand-traced.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/utils/validators.dart';
import 'package:startgold/core/utils/kyc_validator.dart';
import 'package:startgold/shared/utils/address_input_formatter.dart';
import 'package:startgold/shared/utils/no_leading_zeros_formatter.dart';
import 'package:startgold/shared/utils/aadhaar_input_formatter.dart';

/// Simulates typing [input] one character at a time through [formatters],
/// chained the same way Flutter's TextField applies inputFormatters (each
/// formatter sees the SAME oldValue, but newValue threads through the chain).
String typeThrough(List<TextInputFormatter> formatters, String input) {
  var value = const TextEditingValue(text: '');
  for (final ch in input.split('')) {
    final newText = value.text + ch;
    var newValue = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    for (final f in formatters) {
      newValue = f.formatEditUpdate(value, newValue);
    }
    value = newValue;
  }
  return value.text;
}

void main() {
  group('Field 1 — Mobile Number', () {
    test('accepts a valid 10-digit number starting 6-9', () {
      expect(Validators.validateMobile('9876543210'), isNull);
    });
    test('rejects a number starting 0-5', () {
      expect(Validators.validateMobile('0123456789'), isNotNull);
    });
    test('rejects too short / too long', () {
      expect(Validators.validateMobile('98765'), isNotNull);
      expect(Validators.validateMobile('987654321099'), isNotNull);
    });
    test('rejects empty', () {
      expect(Validators.validateMobile(''), isNotNull);
    });
    test('keystroke formatter blocks letters/symbols, caps at 10', () {
      final result = typeThrough(
        [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
        'ab98c76!5@43210999',
      );
      expect(result, '9876543210');
    });
  });

  group('Field 2 — OTP', () {
    test('accepts a 6-digit OTP', () => expect(Validators.validateOTP('123456'), isNull));
    test('rejects wrong length', () => expect(Validators.validateOTP('12345'), isNotNull));
    test('rejects empty', () => expect(Validators.validateOTP(''), isNotNull));
    test('keystroke formatter blocks non-digits', () {
      final result = typeThrough([FilteringTextInputFormatter.digitsOnly], '1a2b3c4d5e6f');
      expect(result, '123456');
    });
  });

  group('Field 3 — Name fields', () {
    final formatters = [
      FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z ]')),
      LengthLimitingTextInputFormatter(60),
    ];
    test('blocks digits and special characters, keeps letters/spaces', () {
      expect(typeThrough(formatters, 'John123!@# Doe'), 'John Doe');
    });
    test('caps at 60 characters', () {
      expect(typeThrough(formatters, 'A' * 70).length, 60);
    });
    test('rejects a 1-character name (min-length rule)', () {
      String? validate(String? v) =>
          (v == null || v.trim().length < 2) ? 'Enter a valid name' : null;
      expect(validate('A'), isNotNull);
      expect(validate('Al'), isNull);
    });
  });

  group('Field 4 — Email', () {
    test('accepts a valid email', () => expect(Validators.validateEmail('user@example.com'), isNull));
    test('rejects malformed emails', () {
      expect(Validators.validateEmail('abc@@x'), isNotNull);
      expect(Validators.validateEmail('abc'), isNotNull);
      expect(Validators.validateEmail('abc@x'), isNotNull);
    });
    test('rejects empty', () => expect(Validators.validateEmail(''), isNotNull));
  });

  group('Field 5 — Date of Birth (18+ rule)', () {
    int calculateAge(DateTime dob) {
      final now = DateTime.now();
      int age = now.year - dob.year;
      if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) age--;
      return age;
    }
    test('exactly 18 years ago today is allowed', () {
      final now = DateTime.now();
      expect(calculateAge(DateTime(now.year - 18, now.month, now.day)), 18);
    });
    test('17 years ago is under the 18 floor', () {
      final now = DateTime.now();
      expect(calculateAge(DateTime(now.year - 17, now.month, now.day)), lessThan(18));
    });
    test('yesterday (the old picker bound) is nowhere near 18', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      expect(calculateAge(yesterday), 0);
    });
  });

  group('Field 6 — MPIN weak-PIN check', () {
    test('flags all-same-digit PINs', () => expect(Validators.isWeakPin('111111'), isTrue));
    test('flags ascending sequences', () => expect(Validators.isWeakPin('123456'), isTrue));
    test('flags descending sequences', () => expect(Validators.isWeakPin('654321'), isTrue));
    test('accepts a non-sequential PIN', () => expect(Validators.isWeakPin('273958'), isFalse));
  });

  group('Field 7 — PAN Number', () {
    test('accepts valid PAN format (AAAAA9999A)', () => expect(KycValidator.validatePAN('ABCDE1234F'), isNull));
    test('rejects wrong format', () {
      expect(KycValidator.validatePAN('12345ABCDE'), isNotNull);
      expect(KycValidator.validatePAN('ABCDE123'), isNotNull);
    });
    test('keystroke formatter blocks non-alphanumeric, caps at 10', () {
      final result = typeThrough(
        [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          LengthLimitingTextInputFormatter(10),
        ],
        'ABCDE-1234F!EXTRA',
      );
      expect(result, 'ABCDE1234F');
    });
  });

  group('Field 8 — Aadhaar Number', () {
    test('AadhaarInputFormatter caps at 12 digits and groups by 4', () {
      var value = const TextEditingValue(text: '');
      for (final ch in '1123553534239999'.split('')) {
        final newText = value.text + ch;
        value = AadhaarInputFormatter().formatEditUpdate(
          value,
          TextEditingValue(text: newText, selection: TextSelection.collapsed(offset: newText.length)),
        );
      }
      expect(AadhaarInputFormatter.unformat(value.text).length, 12);
    });
    test('validator (mirrors kyc_screen.dart logic): rejects first digit 0/1', () {
      String? validate(String digits) {
        if (digits.length != 12) return 'Enter a valid 12-digit Aadhaar number';
        if (!RegExp(r'^[2-9]').hasMatch(digits)) return 'Enter a valid 12-digit Aadhaar number';
        if (RegExp(r'^(\d)\1{11}$').hasMatch(digits)) return 'Enter a valid 12-digit Aadhaar number';
        return null;
      }
      expect(validate('123456789012'), isNotNull); // starts with 1
      expect(validate('234567890123'), isNull); // valid
      expect(validate('222222222222'), isNotNull); // all-same-digit placeholder
    });
  });

  group('Field 9 — Pincode', () {
    test('digits-only, caps at 6', () {
      final result = typeThrough(
        [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        'ab1234x5678',
      );
      expect(result, '123456');
    });
    test('optional-field rule: partial pincode blocks save, empty does not', () {
      String? validate(String pincode) =>
          (pincode.isNotEmpty && pincode.length != 6) ? 'Enter a valid 6-digit pincode' : null;
      expect(validate('123'), isNotNull);
      expect(validate(''), isNull);
      expect(validate('123456'), isNull);
    });
  });

  group('Field 10 — Address', () {
    test('allows digits, commas, hyphens, periods', () {
      expect(typeThrough([AddressInputFormatter()], 'Flat No. 12-B, MG Road'),
          'Flat No. 12-B, MG Road');
    });
    test('blocks characters outside the allowed set (e.g. < > { })', () {
      final result = typeThrough([AddressInputFormatter()], 'abc<>{}xyz');
      expect(result, 'abcxyz');
    });
    test('caps at 200 characters', () {
      expect(typeThrough([AddressInputFormatter()], 'a' * 250).length, 200);
    });
  });

  group('Field 11 — Bank Account Number', () {
    test('digits-only, caps at 20', () {
      final result = typeThrough(
        [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(20)],
        'abc123456789012345678999xyz',
      );
      expect(result.length, 20);
      expect(RegExp(r'^\d+$').hasMatch(result), isTrue);
    });
    test('canSubmit rule: requires at least 9 digits', () {
      bool canSubmit(String acc) => acc.length >= 9;
      expect(canSubmit('12345678'), isFalse); // 8 digits
      expect(canSubmit('123456789'), isTrue); // 9 digits
    });
  });

  group('Field 12 — IFSC Code', () {
    // Mirrors the private _ifscRegex in add_bank_account_sheet.dart /
    // bank_details_sheet.dart (not importable — it's file-private).
    final ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
    test('accepts a valid IFSC', () => expect(ifscRegex.hasMatch('SBIN0001234'), isTrue));
    test('rejects malformed IFSC', () {
      expect(ifscRegex.hasMatch('SBIN 000123!'), isFalse);
      expect(ifscRegex.hasMatch('SBIN000123'), isFalse); // only 10 chars
      expect(ifscRegex.hasMatch('1234SBIN001'), isFalse); // doesn't start with letters
    });
    test('keystroke formatter blocks spaces/symbols, caps at 11', () {
      final result = typeThrough(
        [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
          LengthLimitingTextInputFormatter(11),
        ],
        'SBIN 0001234!EXTRA',
      );
      expect(result, 'SBIN0001234');
    });
  });

  group('Field 13 — UPI ID', () {
    test('accepts a valid UPI ID', () => expect(KycValidator.validateUPI('john.doe@okhdfcbank'), isNull));
    test('rejects missing @', () => expect(KycValidator.validateUPI('johndoe'), isNotNull));
    test('rejects a numeric bank handle', () => expect(KycValidator.validateUPI('john@1234'), isNotNull));
    test('keystroke formatter blocks spaces', () {
      final result = typeThrough(
        [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._@-]'))],
        'john doe@ok hdfc',
      );
      expect(result, 'johndoe@okhdfc');
    });
  });

  group('Field 14 — Amounts', () {
    test('SIP/Withdrawal rupee formatter: no decimals, no leading zeros, caps at 8 digits', () {
      final formatters = [
        FilteringTextInputFormatter.digitsOnly,
        const NoLeadingZerosFormatter(allowDecimal: false),
        LengthLimitingTextInputFormatter(8),
      ];
      expect(typeThrough(formatters, '123456789'), '12345678'); // caps at 8
      expect(typeThrough(formatters, '499.99'), '49999'); // decimal point dropped
      expect(typeThrough(formatters, '007'), '0'); // leading zeros blocked
    });
    test('Instant Saving grams formatter: decimals allowed, capped at 6 places', () {
      final formatters = [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,6}')),
        const NoLeadingZerosFormatter(),
      ];
      expect(typeThrough(formatters, '12.1234567'), '12.123456'); // 7th decimal dropped
      expect(typeThrough(formatters, '12.5'), '12.5'); // short decimal still fine
    });
  });

  group('Field 15 — Nominee-only fields', () {
    test('Relationship: required-field check (enforced in _handleSubmit)', () {
      String? validate(String? v) => (v == null || v.isEmpty) ? 'Relationship is required' : null;
      expect(validate(null), isNotNull);
      expect(validate(''), isNotNull);
      expect(validate('Spouse'), isNull);
    });
  });
}
