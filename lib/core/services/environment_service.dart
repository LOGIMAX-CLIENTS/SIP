import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';

class EnvironmentService {
  static const String _keyEnv = 'selected_environment';

  // Constants for environments
  static const String envStaging = 'staging';
  static const String envProduction = 'production';

  static const String stagingBaseUrl = 'https://startgoldapi.logimaxindia.com/api/api/v1/';
  static const String stagingWsUrl = 'wss://startgoldapp.logimaxindia.com/ws/';

  static const String productionBaseUrl = 'https://api.startgold.com/api/api/v1/';
  static const String productionWsUrl = 'wss://sgbackoffice.startgold.com/ws/';

  static String _currentEnv = envStaging;
  static String _baseUrl = stagingBaseUrl;
  static String _wsUrl = stagingWsUrl;

  static String get currentEnv => _currentEnv;
  static String get baseUrl => _baseUrl;
  static String get wsUrl => _wsUrl;

  /// Loads the saved environment from SharedPreferences on startup.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEnv = prefs.getString(_keyEnv);
    if (savedEnv != null) {
      await setEnvironment(savedEnv, saveToPrefs: false);
    } else {
      // Determine default based on existing AppConfig settings
      if (AppConfig.baseUrl.contains('api.startgold.com')) {
        _currentEnv = envProduction;
        _baseUrl = productionBaseUrl;
        _wsUrl = productionWsUrl;
      } else {
        _currentEnv = envStaging;
        _baseUrl = stagingBaseUrl;
        _wsUrl = stagingWsUrl;
      }
      AppConfig.environment = _currentEnv;
      AppConfig.baseUrl = _baseUrl;
    }
  }

  /// Changes the environment dynamically, updates configurations, and updates network layer base URLs.
  static Future<void> setEnvironment(String env, {bool saveToPrefs = true}) async {
    if (env == envProduction) {
      _currentEnv = envProduction;
      _baseUrl = productionBaseUrl;
      _wsUrl = productionWsUrl;
    } else {
      _currentEnv = envStaging;
      _baseUrl = stagingBaseUrl;
      _wsUrl = stagingWsUrl;
    }

    AppConfig.environment = _currentEnv;
    AppConfig.baseUrl = _baseUrl;

    // Update the ApiClient base URL dynamically
    ApiClient().updateBaseUrl(_baseUrl);

    if (saveToPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEnv, _currentEnv);
    }
  }
}
