import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/screens/kyc_screen.dart';

/// The mismatch dialog must ask for ONLY the field the server says actually
/// failed — a name-only mismatch shouldn't make the customer re-pick a DOB
/// that was already correct, and vice versa. The hidden field is still
/// submitted, pre-filled from the verified value, because the server
/// re-validates both (KYCService._validate_mismatch_resubmission).
void main() {
  NameMismatchPrompt prompt({
    required bool nameMismatch,
    required bool dobMismatch,
    String? verifiedDob = '2000-12-11',
  }) {
    return NameMismatchPrompt(
      document: 'PAN',
      verificationId: '123',
      verifiedName: 'ESAKKIRAJA',
      verifiedDob: verifiedDob,
      profileName: 'ESAKKI RAJA',
      profileDob: '1999-01-02',
      message: 'server message',
      nameMismatch: nameMismatch,
      dobMismatch: dobMismatch,
    );
  }

  /// Captures what the dialog would send back, so the hidden-field pre-fill
  /// can be asserted rather than assumed.
  late List<(String, String)> submitted;

  Future<void> pump(WidgetTester tester, NameMismatchPrompt p) async {
    submitted = [];
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: NameMismatchDialog(
              prompt: p,
              onSubmit: (name, dob) async {
                submitted.add((name, dob));
                // Not `resolved` — that pops the dialog via the root
                // navigator, which this bare test harness has nothing to pop.
                return (NameMismatchOutcome.stillMismatched, 'nope');
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('field visibility follows the server flags', () {
    testWidgets('name-only mismatch shows the name field alone', (tester) async {
      await pump(tester, prompt(nameMismatch: true, dobMismatch: false));

      expect(find.text('Name Mismatch'), findsOneWidget);
      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('Date of Birth'), findsNothing);
      // The DOB the customer isn't being asked about isn't displayed either.
      expect(find.text('Current Profile Date of Birth:'), findsNothing);
      expect(find.text('Current Profile Name:'), findsOneWidget);
    });

    testWidgets('dob-only mismatch shows the DOB field alone', (tester) async {
      await pump(tester, prompt(nameMismatch: false, dobMismatch: true));

      expect(find.text('Date of Birth Mismatch'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
      expect(find.text('Your Name'), findsNothing);
      expect(find.text('Current Profile Name:'), findsNothing);
      expect(find.text('Current Profile Date of Birth:'), findsOneWidget);
    });

    testWidgets('both mismatched shows both fields', (tester) async {
      await pump(tester, prompt(nameMismatch: true, dobMismatch: true));

      expect(find.text('Name / DOB Mismatch'), findsOneWidget);
      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
    });

    testWidgets('neither flag set falls back to showing both', (tester) async {
      // Shouldn't happen — the prompt only exists because something
      // mismatched — but an empty dialog would leave no way forward.
      await pump(tester, prompt(nameMismatch: false, dobMismatch: false));

      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
    });

    testWidgets('a document with no DOB never shows the DOB field', (tester) async {
      // Meon's PAN branch returns name only — the server won't demand a DOB
      // back, so asking for one would be unanswerable.
      await pump(
        tester,
        prompt(nameMismatch: true, dobMismatch: true, verifiedDob: null),
      );

      expect(find.text('Your Name'), findsOneWidget);
      expect(find.text('Date of Birth'), findsNothing);
    });
  });

  group('the hidden field is still submitted, pre-filled', () {
    testWidgets('name-only prompt sends back the verified DOB', (tester) async {
      await pump(tester, prompt(nameMismatch: true, dobMismatch: false));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      final (name, dob) = submitted.single;
      expect(name, 'ESAKKIRAJA');
      // Sent in DD-MM-YYYY, the format the backend's _parse_flexible_date
      // tries first — and it is the VERIFIED dob, not the profile's.
      expect(dob, '11-12-2000');
    });

    testWidgets('dob-only prompt sends back the verified name', (tester) async {
      await pump(tester, prompt(nameMismatch: false, dobMismatch: true));
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      expect(submitted, hasLength(1));
      final (name, dob) = submitted.single;
      expect(name, 'ESAKKIRAJA');
      expect(dob, '11-12-2000');
    });
  });

  group('NameMismatchPrompt.fromJson defaults', () {
    test('an older backend that sends neither flag asks for both', () {
      final p = NameMismatchPrompt.fromJson({
        'document': 'PAN',
        'verification_id': '1',
        'verified_name': 'A',
        'verified_dob': '2000-12-11',
      });
      expect(p.nameMismatch, isTrue);
      expect(p.dobMismatch, isTrue, reason: 'document carried a DOB');
    });

    test('no verified DOB means no DOB ask by default', () {
      final p = NameMismatchPrompt.fromJson({
        'document': 'PAN',
        'verification_id': '1',
        'verified_name': 'A',
      });
      expect(p.nameMismatch, isTrue);
      expect(p.dobMismatch, isFalse);
    });

    test('explicit flags win over the fallbacks', () {
      final p = NameMismatchPrompt.fromJson({
        'document': 'PAN',
        'verification_id': '1',
        'verified_name': 'A',
        'verified_dob': '2000-12-11',
        'name_mismatch': false,
        'dob_mismatch': true,
      });
      expect(p.nameMismatch, isFalse);
      expect(p.dobMismatch, isTrue);
    });
  });
}
