import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:startgold/features/profile/screens/reverse_penny_drop_screen.dart';
import 'package:startgold/features/profile/services/reverse_penny_drop_service.dart';

const _link = 'upi://pay?pa=SUREPASS@dbs&pn=&am=1&cu=INR&tn=ReversePennyDrop&tr=CHE0004376747';

/// Records calls instead of hitting the network — `implements` (not
/// `extends`) so the real service's ApiClient is never constructed.
class _FakeRpdService implements ReversePennyDropService {
  _FakeRpdService({required this.initiateResult, this.statusResult = const {'verified': false, 'status': 'PENDING'}});

  Map<String, dynamic> initiateResult;
  Map<String, dynamic> statusResult;
  int initiateCalls = 0;
  final List<String> statusClientIds = [];

  @override
  Future<Map<String, dynamic>> initiate({required String cbankId}) async {
    initiateCalls++;
    return initiateResult;
  }

  @override
  Future<Map<String, dynamic>> status({required String clientId}) async {
    statusClientIds.add(clientId);
    return statusResult;
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => [];
}

/// "Pay using another device" (PM-STG-0571) — a phone with no UPI app shows
/// the backend's payment_link as a QR for a second phone to scan, and keeps
/// polling the SAME session until it resolves.
void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Object? popped;

  Future<void> pump(WidgetTester tester, _FakeRpdService fake) async {
    popped = null;
    // Phone-sized, so the whole screen is on-screen and tappable.
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reversePennyDropServiceProvider.overrideWithValue(fake)],
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  popped = await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ReversePennyDropScreen(cbankId: '42')),
                  );
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

  /// Tears the tree down so the screen's poll timer is cancelled before the
  /// test ends (a live Timer.periodic fails the test).
  Future<void> dispose(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  /// The success toast dismisses itself on a timer (AppToast, 2.8s).
  Future<void> expireToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the payment_link as a QR and polls that session', (tester) async {
    final fake = _FakeRpdService(initiateResult: {'client_id': 'c1', 'payment_link': _link, 'amount': '1'});
    await pump(tester, fake);

    await tester.tap(find.text('Pay using another device'));
    await tester.pump();

    expect(find.byKey(const ValueKey(_link)), findsOneWidget);
    expect(find.text('Waiting for payment…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(fake.statusClientIds, ['c1']);

    await tester.tap(find.text('Pay on this phone instead'));
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Choose UPI App / Pay ₹1'), findsOneWidget);

    await dispose(tester);
  });

  testWidgets('pops verified when the scanned payment succeeds', (tester) async {
    final fake = _FakeRpdService(
      initiateResult: {'client_id': 'c1', 'payment_link': _link},
      statusResult: {'verified': true, 'status': 'SUCCESS'},
    );
    await pump(tester, fake);

    await tester.tap(find.text('Pay using another device'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(popped, true);
    expect(find.byType(ReversePennyDropScreen), findsNothing);
    await expireToast(tester);
  });

  testWidgets('skips the QR when the account was already verified', (tester) async {
    final fake = _FakeRpdService(initiateResult: {'already_verified': true, 'verified': true});
    await pump(tester, fake);

    await tester.tap(find.text('Pay using another device'));
    await tester.pumpAndSettle();

    expect(popped, true);
    expect(find.byType(QrImageView), findsNothing);
    await expireToast(tester);
  });

  testWidgets('Refresh QR re-initiates once polling stops and shows the new session', (tester) async {
    final fake = _FakeRpdService(initiateResult: {'client_id': 'c1', 'payment_link': _link});
    await pump(tester, fake);

    await tester.tap(find.text('Pay using another device'));
    await tester.pump();

    // Run out the QR poll window (~5 min at 5s).
    for (var i = 0; i < 61; i++) {
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('Waiting for payment…'), findsNothing);

    // The old session outlived its window — backend hands back a fresh one.
    const newLink = 'upi://pay?pa=SUREPASS@dbs&am=1&cu=INR&tr=NEW';
    fake.initiateResult = {'client_id': 'c2', 'payment_link': newLink};
    await tester.tap(find.text('Refresh QR'));
    await tester.pump();

    expect(fake.initiateCalls, 2);
    expect(find.byKey(const ValueKey(newLink)), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(fake.statusClientIds.last, 'c2');

    await dispose(tester);
  });
}
