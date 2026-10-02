import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/sip/utils/upi_handle_apps.dart';

void main() {
  // Shapes returned by CFUPIUtils().getUPIApps() on Android.
  const gpay = {'id': 'com.google.android.apps.nbu.paisa.user', 'displayName': 'GPay'};
  const phonePe = {'id': 'com.phonepe.app', 'displayName': 'PhonePe'};
  const yono = {'id': 'com.sbi.lotusintouch', 'displayName': 'YONO SBI'};
  const iMobile = {'id': 'com.csam.icici.bank.imobile', 'displayName': 'iMobile'};
  const idfc = {'id': 'com.idfcfirstbank.optimus', 'displayName': 'IDFC FIRST Bank'};
  const miPay = {'id': 'com.mipay.wallet.in', 'displayName': 'Mi Pay'};
  const all = [gpay, phonePe, yono, iMobile, idfc, miPay];

  List<String> matches(String vpa) => all
      .where((app) => upiAppMatchesVpa(app, vpa))
      .map((app) => app['displayName']!)
      .toList();

  group('upiAppMatchesVpa', () {
    test('Google Pay bank handles match GPay only', () {
      expect(matches('joejoethish2212@oksbi'), ['GPay']);
      expect(matches('a@okaxis'), ['GPay']);
      expect(matches('a@okhdfcbank'), ['GPay']);
      expect(matches('a@okicici'), ['GPay']);
    });

    test('PhonePe handles match PhonePe', () {
      expect(matches('a@ybl'), ['PhonePe']);
      expect(matches('a@ibl'), ['PhonePe']);
      expect(matches('a@axl'), ['PhonePe']);
    });

    test('@sbi matches the SBI app', () {
      expect(matches('akila@sbi'), ['YONO SBI']);
    });

    test('@icici matches iMobile', () {
      expect(matches('a@icici'), ['iMobile']);
    });

    test('@idfcfirst matches IDFC FIRST Bank', () {
      expect(matches('a@idfcfirst'), ['IDFC FIRST Bank']);
    });

    test('handle is case- and space-insensitive', () {
      expect(matches('A@OKSBI '), ['GPay']);
    });

    test('matches on the iOS URL scheme too', () {
      expect(upiAppMatchesVpa({'id': 'tez://', 'displayName': ''}, 'a@oksbi'), isTrue);
      expect(upiAppMatchesVpa({'id': 'phonepe://'}, 'a@ybl'), isTrue);
    });

    test('unknown handle, empty value or no @ matches nothing', () {
      expect(matches('a@unknownbank'), isEmpty);
      expect(matches(''), isEmpty);
      expect(matches('oksbi'), isEmpty);
      expect(matches('a@'), isEmpty);
    });
  });
}
