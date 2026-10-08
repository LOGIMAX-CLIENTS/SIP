import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../network/api_client.dart';

class EnvironmentService {
  static const String _keyEnv = 'selected_environment';

  // Constants for environments
  static const String envStaging = 'staging';
  static const String envProduction = 'production';
  static const String envVapt = 'vapt';

  static const String stagingBaseUrl = 'https://startgoldapi.logimaxindia.com/api/api/v1/';
  static const String stagingWsUrl = 'wss://startgoldapp.logimaxindia.com/ws/';

  static const String productionBaseUrl = 'https://api.startgold.com/api/api/v1/';
  static const String productionWsUrl = 'wss://sgbackoffice.startgold.com/ws/';

  static const String vaptBaseUrl = 'https://vaptapi.startgold.com/api/api/v1/';
  static const String vaptWsUrl = 'wss://vaptbackoffice.startgold.com/ws/';

  // Where AppConfig.secureServerRoutes go. Staging and VAPT have no secure
  // server — their one server serves every route — so they reuse the base URL.
  static const String stagingSecureBaseUrl = stagingBaseUrl;
  static const String productionSecureBaseUrl =
      'https://secure.endpoint.payapi.startgold.com/api/api/v1/';
  static const String vaptSecureBaseUrl = vaptBaseUrl;

  static String _currentEnv = envStaging;
  static String _baseUrl = stagingBaseUrl;
  static String _secureBaseUrl = stagingSecureBaseUrl;
  static String _wsUrl = stagingWsUrl;

  // static String _currentEnv = envProduction;
  // static String _baseUrl = productionBaseUrl;
  // static String _secureBaseUrl = productionSecureBaseUrl;
  // static String _wsUrl = productionWsUrl;

  // static String _currentEnv = envVapt;
  // static String _baseUrl = vaptBaseUrl;
  // static String _secureBaseUrl = vaptSecureBaseUrl;
  // static String _wsUrl = vaptWsUrl;

  static String get currentEnv => _currentEnv;
  static String get baseUrl => _baseUrl;
  static String get secureBaseUrl => _secureBaseUrl;
  static String get wsUrl => _wsUrl;

  /// Loads the saved environment from SharedPreferences on startup.
  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEnv = prefs.getString(_keyEnv);
    if (savedEnv != null) {
      await setEnvironment(savedEnv, saveToPrefs: false);
    } else {
      // No saved preference — trust the compile-time default already set
      // above (_currentEnv/_baseUrl/_wsUrl), instead of re-deriving it from
      // AppConfig.baseUrl (which used to silently override this on every
      // launch regardless of what was hardcoded here).
      AppConfig.environment = _currentEnv;
      AppConfig.baseUrl = _baseUrl;
      AppConfig.secureBaseUrl = _secureBaseUrl;
    }
  }

  /// Changes the environment dynamically, updates configurations, and updates network layer base URLs.
  static Future<void> setEnvironment(String env, {bool saveToPrefs = true}) async {
    if (env == envProduction) {
      _currentEnv = envProduction;
      _baseUrl = productionBaseUrl;
      _secureBaseUrl = productionSecureBaseUrl;
      _wsUrl = productionWsUrl;
    } else if (env == envVapt) {
      _currentEnv = envVapt;
      _baseUrl = vaptBaseUrl;
      _secureBaseUrl = vaptSecureBaseUrl;
      _wsUrl = vaptWsUrl;
    } else {
      _currentEnv = envStaging;
      _baseUrl = stagingBaseUrl;
      _secureBaseUrl = stagingSecureBaseUrl;
      _wsUrl = stagingWsUrl;
    }

    AppConfig.environment = _currentEnv;
    AppConfig.baseUrl = _baseUrl;
    AppConfig.secureBaseUrl = _secureBaseUrl;

    // Update the ApiClient base URL dynamically
    ApiClient().updateBaseUrl(_baseUrl);

    if (saveToPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEnv, _currentEnv);
    }
  }
}
