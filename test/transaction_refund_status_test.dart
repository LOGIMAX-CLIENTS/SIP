import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/history/controller/history_controller.dart';
import 'package:startgold/features/history/models/history_models.dart';
import 'package:startgold/features/history/screens/transaction_details_screen.dart';

/// Transaction Details shows a step-by-step "Refund Status" card only when
/// the backend sends a `refund` object for a failed purchase.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Round-tripped through JSON so nested maps are typed exactly like a real
  // API response.
  Map<String, dynamic> detailJson({Map<String, dynamic>? refund}) =>
      jsonDecode(jsonEncode({
        'data': {
          'transaction_id': 'TXN1',
          'title': 'Instant Saving',
          'amount': '12.00',
          'weight_grams': '0.000764',
          'metal_name': 'Pure Gold',
          'timeline': [
            {'step_name': 'Payment', 'status': 'Success', 'time': '06 Oct 26, 09:33 AM'},
            {'step_name': 'Pure Gold order', 'status': 'Failed', 'time': '06 Oct 26, 09:33 AM'},
            {'step_name': 'Pure Gold purchase', 'status': 'Failed', 'time': '06 Oct 26, 09:33 AM'},
          ],
          'footer_message': 'Your gold purchase failed. A refund has been initiated.',
          'price_breakdown': {},
          'technical_details': {},
          if (refund != null) 'refund': refund,
        },
      })) as Map<String, dynamic>;

  final refundJson = {
    'refund_id': 'RFND123',
    'amount': '12.00',
    'status': 'Processing',
    'refund_to': 'HDFC Bank ••1234',
    'reference_no': '',
    'expected_by': '13 Oct 26',
    'message': 'The amount will be credited to your source account.',
    'timeline': [
      {'step_name': 'Refund initiated', 'status': 'Success', 'time': '06 Oct 26, 09:40 AM'},
      {'step_name': 'Processed by bank', 'status': 'Pending', 'time': ''},
      {'step_name': 'Credited to your account', 'status': 'Upcoming', 'time': ''},
    ],
  };

  Future<void> pump(WidgetTester tester, TransactionDetailResponse details) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transactionDetailsProvider('TXN1').overrideWith((ref) async => details),
        ],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => const MaterialApp(
            home: TransactionDetailsScreen(
              transactionData: {'id': 'TXN1', 'type': 'purchase'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('parses the optional refund object', () {
    final withRefund =
        TransactionDetailResponse.fromJson(detailJson(refund: refundJson));
    expect(withRefund.refund?.refundId, 'RFND123');
    expect(withRefund.refund?.timeline.map((s) => s.status),
        ['Success', 'Pending', 'Upcoming']);

    expect(TransactionDetailResponse.fromJson(detailJson()).refund, isNull);
  });

  testWidgets('renders each refund step with its details', (tester) async {
    await pump(tester,
        TransactionDetailResponse.fromJson(detailJson(refund: refundJson)));

    expect(find.text('Refund Status'), findsOneWidget);
    expect(find.text('Processing'), findsOneWidget);
    final stepTops = [
      for (final name in [
        'Refund initiated',
        'Processed by bank',
        'Credited to your account',
      ])
        tester.getTopLeft(find.text(name, findRichText: true)).dy,
    ];
    expect(stepTops, [...stepTops]..sort());
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_unchecked_rounded), findsOneWidget);
    expect(find.text('RFND123'), findsOneWidget);
    expect(find.text('13 Oct 26'), findsOneWidget);
    // Empty reference number is hidden rather than shown blank.
    expect(find.text('Bank Reference No.'), findsNothing);
  });

  testWidgets('no refund card when the backend sends no refund', (tester) async {
    await pump(tester, TransactionDetailResponse.fromJson(detailJson()));

    expect(find.text('Transaction Status'), findsOneWidget);
    expect(find.text('Refund Status'), findsNothing);
  });
}
