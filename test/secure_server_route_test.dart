import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:startgold/core/config/app_config.dart';
import 'package:startgold/core/services/environment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.isSecureServerRoute', () {
    const secureRoutes = [
      'kyc/upload',
      'kyc/verification-status',
      'mpin/validate',
      'payments/methods',
      'withdrawal/withdraw',
      'account/verify-bank/penny/initiate',
      'sip/create',
      'sip/custom/12/pause',
      'transactions/invoice/download/',
      'savings/check-eligibility',
      'savings/initiate',
      'savings/confirm-payment',
      'savings/cancel_order',
      'profile/accountdetails',
      'profile/bank-accounts',
      'profile/bank-accounts/upi/remove',
      'customer/bank-accounts/set-primary',
      'users/nominee/details',
      'users/upload',
      'crypto/decrypt',
      '/kyc/upload?step=1',
    ];

    const customerRoutes = [
      'users/auth/token/refresh',
      'auth/generate-otp',
      'crypto/public-key',
      'profile/update',
      'profile/customer_details',
      'profile/mpin-lock-timing',
      'customer/update-profile-photo',
      'savings/config',
      'transactions/history',
      'users/notifications',
      'users/delete-account',
      'app/control',
    ];

    for (final route in secureRoutes) {
      test('$route goes to the secure server', () {
        expect(AppConfig.isSecureServerRoute(route), isTrue);
      });
    }

    for (final route in customerRoutes) {
      test('$route stays on the base URL', () {
        expect(AppConfig.isSecureServerRoute(route), isFalse);
      });
    }
  });

  group('Secure base URL per environment', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Production uses the secure host', () async {
      await EnvironmentService.setEnvironment(EnvironmentService.envProduction);

      expect(AppConfig.secureBaseUrl, EnvironmentService.productionSecureBaseUrl);
      expect(AppConfig.secureBaseUrl, isNot(AppConfig.baseUrl));
    });

    test('Staging and VAPT, which have no secure server, use their base URL', () async {
      await EnvironmentService.setEnvironment(EnvironmentService.envStaging);
      expect(AppConfig.secureBaseUrl, EnvironmentService.stagingBaseUrl);

      await EnvironmentService.setEnvironment(EnvironmentService.envVapt);
      expect(AppConfig.secureBaseUrl, EnvironmentService.vaptBaseUrl);
    });

    test('A saved environment restores its secure host on startup', () async {
      await EnvironmentService.setEnvironment(EnvironmentService.envProduction);
      AppConfig.secureBaseUrl = 'https://stale.example/';
      await EnvironmentService.initialize();

      expect(AppConfig.secureBaseUrl, EnvironmentService.productionSecureBaseUrl);
    });
  });
}
