import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/core/error/failures.dart';
import 'package:startgold/features/sip/widgets/airpay_autopay_wait_view.dart';
import 'package:startgold/shared/widgets/custom_button.dart';

Map<String, dynamic> pending() => {
      'success': true,
      'data': {'subscription_id': 'SUB_1', 'status': 'BANK_APPROVAL_PENDING'},
    };

Map<String, dynamic> active() => {
      'success': true,
      'message': 'Subscription authorized successfully',
      'data': {'subscription_id': 'SUB_1', 'status': 'ACTIVE'},
    };

/// The Airpay "approve in your UPI app" wait on SipPaymentScreen.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late DateTime clock;
  late int calls;
  late List<Object> answers;
  late List<String> events;

  Future<void> pumpView(WidgetTester tester, {String vpa = 'priya@okaxis'}) async {
    // A phone-sized screen, so the buttons are on it.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, child) => MaterialApp(
        home: Scaffold(
          body: AirpayAutoPayWaitView(
            approveVpa: vpa,
            confirm: () {
              calls++;
              final a = answers.length > 1 ? answers.removeAt(0) : answers.first;
              return a is Map<String, dynamic> ? Future.value(a) : Future.error(a);
            },
            onApproved: (r) => events.add('approved:${r['data']['status']}'),
            onFailed: (m) => events.add('failed:$m'),
            onTimedOut: () => events.add('timedOut'),
            onTimedOutExit: () => events.add('exit'),
            onCancel: () => events.add('cancel'),
            now: () => clock,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// Moves the clock and the timers forward one second at a time.
  Future<void> advance(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds; i++) {
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  Finder countdown(String mmss) => find.text(mmss, findRichText: true);

  setUp(() {
    clock = DateTime(2026, 11, 10, 12);
    calls = 0;
    answers = [pending()];
    events = [];
  });

  testWidgets('tells the customer where to approve, with a countdown',
      (tester) async {
    await pumpView(tester);
    expect(find.text('Approve AutoPay in your UPI app'), findsOneWidget);
    expect(find.text('priya@okaxis'), findsOneWidget);
    expect(find.textContaining('Google Pay, PhonePe, Paytm, BHIM'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(countdown('10:00'), findsOneWidget);

    await advance(tester, 1);
    expect(countdown('09:59'), findsOneWidget);
    await advance(tester, 60);
    expect(countdown('08:59'), findsOneWidget);
  });

  testWidgets("\"I've approved it\" checks right away; ACTIVE goes to success",
      (tester) async {
    answers = [active()];
    await pumpView(tester);
    expect(calls, 0);

    await tester.tap(find.byType(CustomButton));
    await tester.pump();
    expect(calls, 1);
    expect(events, ['approved:ACTIVE']);

    await advance(tester, 30);
    expect(calls, 1, reason: 'no polling after the approval');
  });

  testWidgets('polls every 5 seconds and reports a decline', (tester) async {
    answers = [
      pending(),
      ServerFailure(
        message: 'Mandate authorization failed. Please try again.',
        statusCode: 400,
      ),
    ];
    await pumpView(tester);
    await advance(tester, 5);
    expect(calls, 1);
    expect(events, isEmpty);
    await advance(tester, 5);
    expect(calls, 2);
    expect(events, ['failed:Mandate authorization failed. Please try again.']);
  });

  testWidgets('coming back from the UPI app checks right away', (tester) async {
    await pumpView(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(calls, 1);
  });

  testWidgets('after 10 minutes shows the "check later" note', (tester) async {
    await pumpView(tester);
    await advance(tester, 600);

    expect(events, ['timedOut']);
    expect(find.text(AirpayAutoPayWaitView.timedOutMessage), findsOneWidget);
    expect(find.text('Approve AutoPay in your UPI app'), findsNothing);

    final calls0 = calls;
    await advance(tester, 30);
    expect(calls, calls0, reason: 'no polling after the time-out');

    await tester.tap(find.byType(CustomButton));
    expect(events, ['timedOut', 'exit']);
  });

  testWidgets('Cancel closes; a closed wait stops polling', (tester) async {
    await pumpView(tester);
    await tester.tap(find.text('Cancel'));
    expect(events, ['cancel']);

    // The parent pops the screen: the view goes away mid-wait.
    await tester.pumpWidget(const SizedBox());
    await advance(tester, 60);
    expect(calls, 0);
    expect(events, ['cancel']);
  });

  testWidgets('no UPI ID from the server still reads correctly',
      (tester) async {
    await pumpView(tester, vpa: '');
    expect(find.text("We've sent an AutoPay request to your UPI ID."),
        findsOneWidget);
  });
}
