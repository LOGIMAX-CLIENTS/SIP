import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import '../../core/config/app_config.dart';
import '../security/encryption_service.dart';
import '../security/secure_storage_service.dart';
import '../security/session_manager.dart';
import '../security/secure_logger.dart';
import '../security/certificate_pinning.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../shared/widgets/session_invalidated_dialog.dart';

class ApiSecurityInterceptor extends QueuedInterceptor {
  // ── Token Refresh Lock ──────────────────────────────────────────────────
  /// Prevents concurrent 401 handlers from each firing a separate refresh.
  /// The first 401 sets this Completer and performs the refresh; subsequent
  /// 401s await it and retry with the already-refreshed token.
  static Completer<bool>? _refreshLock;

  /// Timestamp of the last successful token refresh.
  /// Used to prevent re-refreshing when multiple 401s arrive sequentially
  /// (with QueuedInterceptor, they are processed one after another).
  static DateTime? _lastRefreshTime;
  // ── Public Key Bootstrap ─────────────────────────────────────────────────
  /// Fetches the RSA public key from the server and caches it.
  /// Safe to call multiple times – skips fetch if already loaded.
  static Future<void> fetchAndCachePublicKey() async {
    if (EncryptionService.isRsaReady) return; // already loaded

    // First, try to load from local secure cache
    await EncryptionService.loadPublicKey();
    if (EncryptionService.isRsaReady) return;

    // Not in cache – fetch from server
    SecureLogger.d('ENCRYPTION: Fetching RSA public key from server...');
    try {
      final plainDio = Dio(BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ));

      // Apply certificate pinning to public key fetch
      CertificatePinning.setup(plainDio);

      final response = await plainDio.get(AppConfig.publicKeyEndpoint);

      if (response.statusCode == 200 && response.data != null) {
        // Attempt to extract from root ('public_key') or from nested 'data' ('data' -> 'public_key')
        final dynamic respData = response.data;
        final String? publicKey = respData is Map
            ? (respData['public_key'] ?? respData['data']?['public_key'])
            : null;

        if (publicKey != null && publicKey.isNotEmpty) {
          await EncryptionService.setPublicKeyFromServer(pemKey: publicKey);
          SecureLogger.d(
              'ENCRYPTION: RSA public key fetched and cached successfully.');
        } else {
          SecureLogger.e(
              'ENCRYPTION: Public key not found in API response. Sensitive requests will fail.');
        }
      } else {
        SecureLogger.e(
            'ENCRYPTION: Server returned unexpected response for public key endpoint.');
      }
    } on DioException catch (e) {
      SecureLogger.e(
          'ENCRYPTION: Failed to fetch RSA public key (DioException: ${e.type}). Sensitive requests will fail until key is fetched.');
    } catch (e) {
      SecureLogger.e(
          'ENCRYPTION: Unexpected error fetching RSA public key: $e');
    }
  }

  // ── Request Interceptor ──────────────────────────────────────────────────
  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final path = options.path;
    SecureLogger.logRequest(options);

    // ── Force Logout Gate ─────────────────────────────────────────────────
    // If the session was invalidated (409), block ALL further API calls
    // immediately. No network I/O, no retries.
    if (SessionManager.isForceLoggedOut) {
      SecureLogger.e(
          'SESSION BLOCKED: Request to $path rejected — session invalidated.');
      return handler.reject(
        DioException(
          requestOptions: options,
          error: 'Session invalidated. Please log in again.',
          type: DioExceptionType.cancel,
        ),
      );
    }

    // Rule 8: Offline Handling
    try {
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult.contains(ConnectivityResult.none)) {
        SecureLogger.e('OFFLINE BLOCK: skipping request to ${options.path}');
        return handler.reject(
          DioException(
            requestOptions: options,
            error: 'No internet connection',
            type: DioExceptionType.connectionError,
          ),
        );
      }
    } catch (e) {
      SecureLogger.d('Connectivity check error: $e');
    }

    // 1. Ensure RSA public key is loaded before any sensitive request
    final isSensitive =
        AppConfig.encryptedEndpoints.any((e) => path.contains(e));
    if (isSensitive && !EncryptionService.isRsaReady) {
      // Attempt a last-chance fetch (non-blocking on failure)
      await fetchAndCachePublicKey();
    }

    // 2. Attach Authorization token (except unauthenticated endpoints)
    // NOTE: Use an explicit list of public endpoints instead of a broad
    // path.contains('/auth/') check. Endpoints like 'users/auth/referral/details'
    // and 'auth/has-mpin' contain 'auth' in the path but ARE authenticated.
    const unauthenticatedEndpoints = [
      'auth/generate-otp',
      'auth/verify-otp',
      'auth/register-check',
      'auth/register',
      'auth/token/refresh',
      'shared/country-codes',
      'app/control',
      'crypto/public-key',
    ];
    final isPublicEndpoint =
        unauthenticatedEndpoints.any((e) => path.contains(e));
    if (!isPublicEndpoint) {
      String? token = await SecureStorageService.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }

    // 3. Encrypt sensitive fields for designated endpoints
    if (isSensitive) {
      if (options.data != null && options.data is Map) {
        final originalDataStr = options.data.toString();
        try {
          // Safe cast to Map<String, dynamic> for the encryption service
          final mapData = Map<String, dynamic>.from(options.data);
          options.data = EncryptionService.encryptJson(mapData);
          final dataChanged = originalDataStr != options.data.toString();
          final algo =
              EncryptionService.isRsaReady ? 'RSA-OAEP-SHA256' : 'AES-256-CBC';
          SecureLogger.d(
              'SECURE LAYER: Payload ${dataChanged ? 'encrypted ($algo)' : 'has no sensitive fields'} for $path');
        } catch (e) {
          SecureLogger.e('ENCRYPTION ERROR: $e');
        }
      }
    }

    return handler.next(options);
  }

  // ── Response Interceptor ─────────────────────────────────────────────────
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    SecureLogger.logResponse(response);

    final path = response.requestOptions.path;
    final shouldDecrypt =
        AppConfig.encryptedEndpoints.any((e) => path.contains(e));

    if (shouldDecrypt && response.data != null && response.data is Map) {
      // Safe cast
      final mapData = Map<String, dynamic>.from(response.data);
      response.data = EncryptionService.decryptJson(mapData);
      SecureLogger.d('SECURE LAYER: Response decrypted (AES-256) for $path');
    }

    return handler.next(response);
  }

  // ── Error Interceptor ────────────────────────────────────────────────────
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    SecureLogger.logError(err);

    // ── 5. Session Invalidated on 409 Conflict ─────────────────────────────
    // MUST be checked BEFORE 401 to prevent token-refresh logic from running
    // on an invalidated session.
    if (err.response?.statusCode == 409) {
      final data = err.response?.data;

      // Accept both explicit code AND bare 409 (server may omit code)
      final isSessionInvalidated = data is Map &&
          (data['error']?['code'] == 'session_invalidated' ||
              data['error']?['code'] == 'SESSION_INVALIDATED' ||
              data['code'] == 'session_invalidated' ||
              data['code'] == 'SESSION_INVALIDATED');

      // Also handle bare 409 without structured error body
      if (isSessionInvalidated || (data is! Map)) {
        final serverMsg = data is Map
            ? (data['error']?['message'] as String? ??
                data['message'] as String? ??
                '')
            : '';

        SecureLogger.e('SESSION INVALIDATED: 409 Conflict — $serverMsg');

        // forceLogout() returns false if already triggered (deduplication).
        // This ensures only ONE dialog is shown even if 5 concurrent API
        // calls all return 409 at the same time.
        final isFirstTrigger = await SessionManager.forceLogout();

        if (isFirstTrigger) {
          // Show the premium dialog on the UI thread.
          // Use addPostFrameCallback so we never call into the widget
          // tree from inside a Dio async handler.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            SessionInvalidatedDialog.show(message: serverMsg);
          });
        }

        // Do NOT call handler.next() — reject immediately so the caller
        // gets a clean error and does NOT attempt retries.
        return handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            response: err.response,
            error: 'Session invalidated. Please log in again.',
            type: DioExceptionType.cancel,
          ),
        );
      }
    }

    // 4. Silent Token Refresh on 401 (with concurrency lock)
    if (err.response?.statusCode == 401) {
      // Skip token refresh if session is already force-invalidated
      if (SessionManager.isForceLoggedOut) {
        return handler.next(err);
      }

      // ── If another 401 handler is already refreshing, wait for it ──
      if (_refreshLock != null) {
        SecureLogger.d('TOKEN REFRESH: Waiting for in-flight refresh...');
        final success = await _refreshLock!.future;
        if (success) {
          // Refresh succeeded — retry with the new token
          final newToken = await SecureStorageService.getToken();
          if (newToken != null) {
            final retryOptions = err.requestOptions;
            retryOptions.headers['Authorization'] = 'Bearer $newToken';
            try {
              final retryDio = Dio(BaseOptions(
                baseUrl: AppConfig.baseUrl,
                connectTimeout:
                    const Duration(milliseconds: AppConfig.connectTimeout),
                receiveTimeout:
                    const Duration(milliseconds: AppConfig.receiveTimeout),
              ));
              CertificatePinning.setup(retryDio);
              final retryResponse = await retryDio.fetch(retryOptions);
              return handler.resolve(retryResponse);
            } catch (e) {
              SecureLogger.e('TOKEN REFRESH: Retry after wait failed: $e');
              return handler.next(err);
            }
          }
        }
        // Refresh failed — fall through to handler.next(err)
        return handler.next(err);
      }

      // ── Token was JUST refreshed (within 30s) — skip re-refresh, just retry ──
      if (_lastRefreshTime != null &&
          DateTime.now().difference(_lastRefreshTime!).inSeconds < 30) {
        SecureLogger.d('TOKEN REFRESH: Recently refreshed, retrying with current token...');
        final currentToken = await SecureStorageService.getToken();
        if (currentToken != null) {
          final retryOptions = err.requestOptions;
          retryOptions.headers['Authorization'] = 'Bearer $currentToken';
          try {
            final retryDio = Dio(BaseOptions(
              baseUrl: AppConfig.baseUrl,
              connectTimeout:
                  const Duration(milliseconds: AppConfig.connectTimeout),
              receiveTimeout:
                  const Duration(milliseconds: AppConfig.receiveTimeout),
            ));
            CertificatePinning.setup(retryDio);
            final retryResponse = await retryDio.fetch(retryOptions);
            return handler.resolve(retryResponse);
          } catch (e) {
            SecureLogger.e('TOKEN REFRESH: Retry with recent token failed: $e');
            // Token truly expired — clear timestamp and fall through to full refresh
            _lastRefreshTime = null;
          }
        }
      }

      // ── First 401 — acquire lock and perform refresh ──
      _refreshLock = Completer<bool>();

      final refreshToken = await SecureStorageService.getRefreshToken();

      if (refreshToken != null && refreshToken.isNotEmpty) {
        SecureLogger.d('TOKEN REFRESH: Attempting silent refresh...');
        try {
          final refreshDio = Dio(BaseOptions(
            baseUrl: AppConfig.baseUrl,
            connectTimeout:
                const Duration(milliseconds: AppConfig.connectTimeout),
            receiveTimeout:
                const Duration(milliseconds: AppConfig.receiveTimeout),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ));

          // Apply certificate pinning to token refresh
          CertificatePinning.setup(refreshDio);

          final refreshResponse = await refreshDio.post(
            'users/auth/token/refresh',
            data: {'refresh': refreshToken},
          );

          if (refreshResponse.statusCode == 200) {
            final respData = refreshResponse.data;

            // Server response format:
            //   {"success": true, "data": {"access_token": "...", "refresh_token": "..."}}
            // Also handle flat format or "access"/"refresh" keys for flexibility.
            final nested = respData is Map ? respData['data'] : null;
            final newAccess =
                (nested is Map ? (nested['access_token'] ?? nested['access']) : null) ??
                (respData is Map ? (respData['access_token'] ?? respData['access']) : null);
            final newRefresh =
                (nested is Map ? (nested['refresh_token'] ?? nested['refresh']) : null) ??
                (respData is Map ? (respData['refresh_token'] ?? respData['refresh']) : null);

            if (newAccess != null && newAccess.toString().isNotEmpty) {
              await SecureStorageService.saveToken(newAccess);
              if (newRefresh != null && newRefresh.toString().isNotEmpty) {
                await SecureStorageService.saveRefreshToken(newRefresh);
              }
              _lastRefreshTime = DateTime.now();
              SecureLogger.d(
                  'TOKEN REFRESH: Success. Retrying original request.');

              // Unlock waiting 401s — they can now retry with new token
              _refreshLock!.complete(true);
              _refreshLock = null;

              final retryOptions = err.requestOptions;
              retryOptions.headers['Authorization'] = 'Bearer $newAccess';

              final retryResponse = await refreshDio.fetch(retryOptions);
              return handler.resolve(retryResponse);
            } else {
              // Refresh returned 200 but no access token in response
              SecureLogger.e(
                  'TOKEN REFRESH: No access token in refresh response. Logging out.');
              _refreshLock!.complete(false);
              _refreshLock = null;
              await SessionManager.logout();
            }
          } else {
            SecureLogger.e(
                'TOKEN REFRESH: Server rejected refresh (${refreshResponse.statusCode}). Logging out.');
            _refreshLock!.complete(false);
            _refreshLock = null;
            await SessionManager.logout();
          }
        } catch (e) {
          SecureLogger.e('TOKEN REFRESH: Failed with error: $e. Logging out.');
          _refreshLock!.complete(false);
          _refreshLock = null;
          await SessionManager.logout();
        }
      } else {
        SecureLogger.e('TOKEN REFRESH: No refresh token found. Logging out.');
        _refreshLock!.complete(false);
        _refreshLock = null;
        await SessionManager.logout();
      }
    }

    // Global error info (Rule 7)
    if (err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout) {
      SecureLogger.e('Network connection lost or timeout (${err.type})');
    }

    return handler.next(err);
  }
}
