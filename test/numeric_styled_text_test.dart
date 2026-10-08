import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/shared/widgets/numeric_styled_text.dart';

/// NumericStyledText puts numbers in Lora and letters in Playfair Display.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// The runs [text] renders in Lora, in order.
  Future<List<String>> loraRuns(WidgetTester tester, String text) async {
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: NumericStyledText(text, fontSize: 14),
    ));
    final root = tester.widget<RichText>(find.byType(RichText)).text as TextSpan;
    final spans = root.children!.cast<TextSpan>();
    expect(spans.map((s) => s.text).join(), text);
    return [
      for (final s in spans)
        if (s.style!.fontFamily!.startsWith('Lora')) s.text!,
    ];
  }

  testWidgets('letters inside words stay in Playfair', (tester) async {
    expect(await loraRuns(tester, 'AutoPay activation'), isEmpty);
    expect(await loraRuns(tester, '07 Oct 26, 04:15 PM'), ['07', '26', '04:15']);
    expect(await loraRuns(tester, 'AutoPay setup – ₹10.00 debited'), ['₹10.00']);
    expect(await loraRuns(tester, 'may take 5-7 working days.'), ['5-7']);
  });

  testWidgets('symbols and units that belong to a number are Lora', (tester) async {
    expect(await loraRuns(tester, 'Gold 24KT'), ['24KT']);
    expect(await loraRuns(tester, '24K Gold'), ['24K']);
    expect(await loraRuns(tester, 'CGST (1.50%) +2.5%'), ['1.50%', '+2.5%']);
    expect(await loraRuns(tester, '₹ 1,234.50'), ['₹ 1,234.50']);
    expect(await loraRuns(tester, 'HDFC XXXX1234'), ['XXXX1234']);
    expect(await loraRuns(tester, 'the 4th cycle'), ['4']);
  });

  testWidgets('mixed IDs alternate fonts', (tester) async {
    expect(await loraRuns(tester, 'SUB_dad6ed04-9fec'), ['6', '04-9']);
  });
}
