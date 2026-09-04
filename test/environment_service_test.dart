import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:startgold/core/config/app_config.dart';
import 'package:startgold/core/services/environment_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EnvironmentService Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes environment to the compile-time default if nothing is saved', () async {
      await EnvironmentService.initialize();

      expect(EnvironmentService.currentEnv, EnvironmentService.envProduction);
      expect(EnvironmentService.baseUrl, EnvironmentService.productionBaseUrl);
      expect(EnvironmentService.wsUrl, EnvironmentService.productionWsUrl);

      expect(AppConfig.environment, EnvironmentService.envProduction);
      expect(AppConfig.baseUrl, EnvironmentService.productionBaseUrl);
    });

    test('Switches environment to Production and persists it', () async {
      await EnvironmentService.initialize();

      await EnvironmentService.setEnvironment(EnvironmentService.envProduction);

      expect(EnvironmentService.currentEnv, EnvironmentService.envProduction);
      expect(EnvironmentService.baseUrl, EnvironmentService.productionBaseUrl);
      expect(EnvironmentService.wsUrl, EnvironmentService.productionWsUrl);

      expect(AppConfig.environment, EnvironmentService.envProduction);
      expect(AppConfig.baseUrl, EnvironmentService.productionBaseUrl);

      // Re-initialize to verify persistence
      await EnvironmentService.initialize();

      expect(EnvironmentService.currentEnv, EnvironmentService.envProduction);
      expect(EnvironmentService.baseUrl, EnvironmentService.productionBaseUrl);
      expect(EnvironmentService.wsUrl, EnvironmentService.productionWsUrl);
    });
  });
}
