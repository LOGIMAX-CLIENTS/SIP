import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/features/history/controller/history_controller.dart';
import 'package:startgold/features/history/models/history_filter_options_model.dart';
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

  Future<void> pump(WidgetTester tester, TransactionDetailResponse details,
      {String type = 'purchase'}) async {
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
          builder: (context, child) => MaterialApp(
            home: TransactionDetailsScreen(
              transactionData: {'id': 'TXN1', 'type': type},
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

  // A mandate rejected after its ₹10 AutoPay setup charge was taken
  // (backend SIPAUTH{id}): nothing was bought, the ₹10 is being refunded.
  Map<String, dynamic> setupChargeJson() => jsonDecode(jsonEncode({
        'data': {
          'order_id': 'SIPAUTH42',
          'title': 'AutoGold Autopay',
          'subtitle': 'AutoPay setup charge',
          'amount': '10.00',
          'weight_grams': '0.000000',
          'metal_name': 'Pure Gold',
          'timeline': [
            {'step_name': 'AutoPay setup – ₹10.00 debited', 'status': 'Success', 'time': '06 Oct 26, 09:30 AM'},
            {'step_name': 'AutoPay activation', 'status': 'Failed', 'time': '06 Oct 26, 09:30 AM',
             'reason': 'Approved from an account other than the verified one'},
          ],
          'footer_message': 'Your AutoPay setup could not be completed. The ₹10.00 debited is being refunded.',
          'price_breakdown': {'total_amount': '10.00'},
          'technical_details': {'placed_on': '06 Oct 26, 09:30 AM', 'paid_via': 'UPI'},
          'refund': {
            'refund_id': 'cf_ref_1',
            'amount': '10.00',
            'status': 'Processing',
            'refund_to': 'The account you approved AutoPay from',
            'reference_no': '',
            'expected_by': '',
            'message': 'Refunds go back to the account the AutoPay was approved from.',
            'timeline': [
              {'step_name': 'Refund initiated', 'status': 'Success', 'time': '06 Oct 26, 09:30 AM'},
              {'step_name': 'Refund processed', 'status': 'Pending', 'time': ''},
            ],
          },
        },
      })) as Map<String, dynamic>;

  test('a breakdown without a metal quantity has no metal rows', () {
    expect(PriceBreakdown.fromJson({'total_amount': '10.00'}).hasMetal, isFalse);
    expect(PriceBreakdown.fromJson({'quantity': '0.0006', 'total_amount': '10.00'}).hasMetal, isTrue);
    expect(PriceBreakdown.fromJson({'gold_quantity': '0.0006 gm'}).hasMetal, isTrue);
  });

  test('refund statuses have fallback colours', () {
    expect(defaultStatusColorHex('Refunded'), '#10B981');
    expect(defaultStatusColorHex('Refund Processing'), '#3B82F6');
    expect(defaultStatusColorHex('Refund Failed'), '#DC2626');
  });

  testWidgets('refunded AutoPay setup charge shows no grams or metal rows', (tester) async {
    // The test font's glyphs are far wider than Playfair's, so the
    // "AutoGold Order Details" header overflows here (and only here).
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (!details.exceptionAsString().contains('overflowed')) onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);

    await pump(tester, TransactionDetailResponse.fromJson(setupChargeJson()), type: 'sip');

    expect(find.text('Refund Status'), findsOneWidget);
    expect(find.text('AutoPay setup charge', findRichText: true), findsOneWidget);
    expect(find.text('0.000000 gm'), findsNothing);

    await tester.ensureVisible(find.text('AutoGold Order Details'));
    await tester.tap(find.text('AutoGold Order Details'));
    await tester.pumpAndSettle();

    expect(find.text('Gold Rate'), findsNothing);
    expect(find.text('Gold Quantity'), findsNothing);
    expect(find.text('CGST'), findsNothing);
    expect(find.text('Amount'), findsOneWidget);
    expect(find.text('₹10.00'), findsWidgets);
  });

  testWidgets('a purchase still shows its metal rows', (tester) async {
    final json = detailJson();
    (json['data'] as Map<String, dynamic>)['price_breakdown'] = {
      'quantity': '0.000764', 'rate': '15700.00', 'value': '11.65',
      'cgst_percent': '1.5', 'cgst_value': '0.17', 'sgst_percent': '1.5',
      'sgst_value': '0.17', 'total_amount': '12.00',
    };
    await pump(tester, TransactionDetailResponse.fromJson(json));

    expect(find.text('0.000764 gm'), findsOneWidget);
    await tester.ensureVisible(find.text('Order Details'));
    await tester.tap(find.text('Order Details'));
    await tester.pumpAndSettle();

    expect(find.text('Gold Purchased At'), findsOneWidget);
    expect(find.text('CGST'), findsOneWidget);
  });
}
