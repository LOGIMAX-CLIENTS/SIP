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

  // Only the bastion production API host has a separate secure server. Every
  // other host (staging, VAPT, the old production host) serves every route
  // itself, so its secure URL is its base URL. Keying this on the base URL,
  // not the environment, keeps an app that still points production at the old
  // host from sending KYC and payment calls to the bastion side, which is a
  // different database.
  static const String bastionBaseUrl =
      'https://endpoint.generic.api.startgold.com/api/api/v1/';
  // The secure host's nginx serves the API at /api/v1/, without the extra
  // /api prefix the other hosts strip.
  static const String bastionSecureBaseUrl =
      'https://secure.endpoint.payapi.startgold.com/api/v1/';

  /// Where AppConfig.secureServerRoutes go when the base URL is [baseUrl].
  static String secureBaseUrlFor(String baseUrl) =>
      baseUrl == bastionBaseUrl ? bastionSecureBaseUrl : baseUrl;

  static String _currentEnv = envStaging;
  static String _baseUrl = stagingBaseUrl;
  static String _wsUrl = stagingWsUrl;

  // static String _currentEnv = envProduction;
  // static String _baseUrl = productionBaseUrl;
  // static String _wsUrl = productionWsUrl;

  // static String _currentEnv = envVapt;
  // static String _baseUrl = vaptBaseUrl;
  // static String _wsUrl = vaptWsUrl;

  static String get currentEnv => _currentEnv;
  static String get baseUrl => _baseUrl;
  static String get secureBaseUrl => secureBaseUrlFor(_baseUrl);
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
      AppConfig.secureBaseUrl = secureBaseUrlFor(_baseUrl);
    }
  }

  /// Changes the environment dynamically, updates configurations, and updates network layer base URLs.
  static Future<void> setEnvironment(String env, {bool saveToPrefs = true}) async {
    if (env == envProduction) {
      _currentEnv = envProduction;
      _baseUrl = productionBaseUrl;
      _wsUrl = productionWsUrl;
    } else if (env == envVapt) {
      _currentEnv = envVapt;
      _baseUrl = vaptBaseUrl;
      _wsUrl = vaptWsUrl;
    } else {
      _currentEnv = envStaging;
      _baseUrl = stagingBaseUrl;
      _wsUrl = stagingWsUrl;
    }

    AppConfig.environment = _currentEnv;
    AppConfig.baseUrl = _baseUrl;
    AppConfig.secureBaseUrl = secureBaseUrlFor(_baseUrl);

    // Update the ApiClient base URL dynamically
    ApiClient().updateBaseUrl(_baseUrl);

    if (saveToPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEnv, _currentEnv);
    }
  }
}
