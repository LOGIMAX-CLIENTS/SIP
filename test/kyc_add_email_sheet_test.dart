import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/kyc/widgets/kyc_add_email_sheet.dart';

/// The KYC checklist's E-mail step asks for an address in place when the
/// customer registered without one (RULE-KYC-022). The sheet must only send
/// a code to a well-formed address, stay open when sending fails, and hand
/// the trimmed address back once the code is on its way.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late List<String> sentTo;
  late bool sendSucceeds;
  String? result;
  bool closed = false;

  Future<void> openSheet(WidgetTester tester) async {
    sentTo = [];
    result = null;
    closed = false;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showKycAddEmailSheet(
                    context,
                    onSend: (email) async {
                      sentTo.add(email);
                      return sendSucceeds;
                    },
                  );
                  closed = true;
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String typed) async {
    await tester.enterText(find.byType(TextField), typed);
    await tester.tap(find.text('Send Code'));
    await tester.pumpAndSettle();
  }

  testWidgets('a blank address is refused without sending', (tester) async {
    sendSucceeds = true;
    await openSheet(tester);
    await submit(tester, '   ');

    expect(find.text('E-Mail is required'), findsOneWidget);
    expect(sentTo, isEmpty);
    expect(closed, isFalse);
  });

  testWidgets('a malformed address is refused without sending', (tester) async {
    sendSucceeds = true;
    await openSheet(tester);
    await submit(tester, 'someone@nowhere');

    expect(find.text('Enter a valid e-mail address'), findsOneWidget);
    expect(sentTo, isEmpty);
    expect(closed, isFalse);
  });

  testWidgets('a failed send keeps the sheet open', (tester) async {
    sendSucceeds = false;
    await openSheet(tester);
    await submit(tester, 'taken@example.com');

    expect(sentTo, ['taken@example.com']);
    expect(closed, isFalse);
    expect(find.text('Add your e-mail'), findsOneWidget);
  });

  testWidgets('a sent code closes the sheet with the trimmed address', (tester) async {
    sendSucceeds = true;
    await openSheet(tester);
    await submit(tester, '  new@example.com ');

    expect(sentTo, ['new@example.com']);
    expect(closed, isTrue);
    expect(result, 'new@example.com');
  });
}
