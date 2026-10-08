class AppConfig {
  static const String appName = 'startGOLD';

  /// Current environment name (dev | staging | production).
  /// Override at build time: --dart-define=ENV=dev
  static String environment =
      const String.fromEnvironment('ENV', defaultValue: 'production');

  /// If no flag is passed the production URL is used as default.
  static String baseUrl = const String.fromEnvironment(
    'BASE_URL',
   // defaultValue: 'https://api.startgold.com/api/api/v1/', //  Live
   defaultValue:'https://startgoldapi.logimaxindia.com/api/api/v1/', // Staging
    //defaultValue: 'https://vaptapi.startgold.com/api/api/v1/', // VAPT Server
  );

  /// Host for [secureServerRoutes]. EnvironmentService sets it with [baseUrl].
  static String secureBaseUrl = baseUrl;

  /// Routes the backend serves only from its secure server: KYC, MPIN,
  /// payments, mandates, bank accounts, nominee, uploads and invoices. Must
  /// match secure_service/config/urls.py in fintect_application. An entry
  /// ending in '/' covers everything under it; any other entry covers that
  /// route and its sub-paths.
  static const List<String> secureServerRoutes = [
    'kyc/',
    'mpin/',
    'payments/',
    'withdrawal/',
    'account/',
    'sip/',
    'transactions/invoice/',
    'savings/check-eligibility',
    'savings/initiate',
    'savings/confirm-payment',
    'savings/cancel_order',
    'profile/accountdetails',
    'profile/bank-accounts',
    'customer/accountdetails',
    'customer/bank-accounts',
    'crypto/encrypt',
    'crypto/decrypt',
    'users/nominee/',
    'users/upload',
  ];

  static bool isSecureServerRoute(String path) {
    final route = path.split('?').first.replaceFirst(RegExp(r'^/+'), '');
    return secureServerRoutes.any((r) => r.endsWith('/')
        ? route.startsWith(r)
        : route == r || route.startsWith('$r/'));
  }

  // Storage Keys
  static const String keyHasSeenOnboarding = 'hasSeenOnboarding';
  static const String keyAccessToken = 'access_token';
  static const String keyRefreshToken = 'refresh_token';
  static const String keyMobileNumber = 'mobile_number';
  static const String keyIsMpinEnabled = 'is_mpin_enabled';
  static const String keyIsBiometricEnabled = 'is_biometric_enabled';
  static const String keyMpinLockTimeoutSeconds = 'mpin_lock_timeout_seconds';
  static const String keyCustomerId = 'customer_id';
  static const String keyHasSeenManualKycSupportPrompt = 'has_seen_manual_kyc_support_prompt';
  static const String keyCustomerName = 'customer_name';
  static const String keyCustomerPhoto = 'customer_photo';
  static const String keyServerPublicKey =
      'server_public_key'; // RSA public key cache
  static const String keyFcmToken = 'fcm_token'; // last registered FCM token

  // Network Config
  static const int connectTimeout = 60000;
  static const int receiveTimeout = 60000;

  // Crypto / Key Exchange
  static const String publicKeyEndpoint = 'crypto/public-key';

  // Security
  static bool enableScreenshotProtection = true;

  // MPIN lock / biometric timing — populated from the server's
  // APP_CONTROL_MPIN_LOCK config row (see AppControlProvider), with these
  // as the pre-fetch fallback.
  static List<int> mpinLockTimeoutOptionsSeconds = [30, 60, 300, 900, 1800];
  static int mpinLockDefaultTimeoutSeconds = 1800;
  static bool biometricLoginEnabled = true;

  static const List<String> allowedCertFingerprints = [
    'F3:AB:FB:70:B3:D0:A7:F2:CB:EF:02:8A:2C:C4:95:62:55:D8:FC:35:71:E5:32:0E:7F:04:D7:00:47:10:86:AC', // cert fingerprint (changes on renewal)
    'hEdBgpqZW1U6x1XwUf+0UfNg4zu2oy/OwkIOGCppqXs=', // public key pin (stable across renewals)
  ];

  // List of sensitive endpoints that REQUIRE encryption
  static const List<String> encryptedEndpoints = [
    'auth/generate-otp',
    'auth/verify-otp',
    'auth/generate-email-otp',
    'auth/verify-email-otp',
    'auth/register',
    'savings/initiate',
    'savings/check-eligibility',
    'submit-kyc',
    'update-kyc',
    'kyc/upload',
    'withdraw',
    'verify-upi',
    'verify-bank',
    'payment',
    'investment',
    'mpin/create',
    'mpin/validate',
    'mpin/change',
    'mpin/reset',
    'sip/create',
    'sip/cancel',
    'sip/pause',
    'users/nominee/update',
  ];

  // These fields in the payload will be encrypted
  static const List<String> sensitiveFields = [
    'password',
    'otp',
    'login_pin',
    'transaction_pin',
    'aadhaar_number',
    'pan_number', // this is for testing
    'pan',
    'bank_account_number',
    'account_no',
    'ifsc_code',
    'upi_id',
    'kyc_details',
    'withdrawal_amount',
    'payment_details',
    'amount', // from Payment APIs rule
    'amount_inr',
    'payment_pin', // from Payment APIs rule
    'bank_details', // from Payment APIs rule
    'mpin', // MPIN rule
    'old_mpin',
    'new_mpin',
    'mobile', // encrypt PII
    'weight',
    'buy_rate', // withdrawal: rate at time of sale
  ];
}
