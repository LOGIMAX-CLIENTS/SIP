import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/api_client.dart';
import '../security/secure_storage_service.dart';
import '../security/session_manager.dart';
import 'device_id_service.dart';

// --- SERVICE LAYER ---

class AuthService {
  final ApiClient _apiClient = ApiClient();

  Future<String> _getAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version;
    } catch (e) {
      return '1.0.0';
    }
  }

  Future<Map<String, dynamic>> sendOtp({
    required String mobile,
    required String countryCode,
    required String idCountry,
    String type = 'LOGIN',
  }) async {
    final appVersion = await _getAppVersion();

    final response = await _apiClient.post(
      'users/auth/generate-otp',
      data: {
        'mobile': mobile,
        'country_code': countryCode,
        'id_country': idCountry,
        'type': type,
        'device_id': await DeviceIdService.getDeviceId(),
        'device_type': await DeviceIdService.getDeviceType(),
        'appVersion': appVersion,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> verifyOtp({
    required String mobile,
    required String otp,
    required String otpReferenceId,
  }) async {
    final response = await _apiClient.post(
      'users/auth/verify-otp',
      data: {
        'mobile': mobile,
        'otp': otp,
        'otp_reference_id': otpReferenceId,
      },
    );
    // Save tokens if present
    if (response.data != null && response.data['data'] != null) {
      final data = response.data['data'];
      final accessToken = data['access_token'];
      final refreshToken = data['refresh_token'];
      if (accessToken != null) {
        await SecureStorageService.saveToken(accessToken);
      }
      if (refreshToken != null) {
        await SecureStorageService.saveRefreshToken(refreshToken);
      }
      // ── Reset force-logout flag on fresh login ───────────────────────
      // If the user was force-logged-out (409), the interceptor blocks
      // all API calls. Now that we have fresh tokens, clear the flag
      // so the new session is fully operational.
      SessionManager.resetForceLogout();
      if (data['mpin_enabled'] != null) {
        await SecureStorageService.setMpinEnabled(data['mpin_enabled'] == true);
      }
      if (data['user']?['id_customer'] != null) {
        await SecureStorageService.saveCustomerId(
            data['user']['id_customer'].toString());
      }
      if (data['user']?['name'] != null) {
        await SecureStorageService.saveCustomerName(data['user']['name']);
      } else if (data['user']?['full_name'] != null) {
        await SecureStorageService.saveCustomerName(data['user']['full_name']);
      }
      if (data['user']?['photo_url'] != null) {
        await SecureStorageService.saveCustomerPhoto(data['user']['photo_url']);
      }
      if (mobile.isNotEmpty) {
        await SecureStorageService.saveMobile(mobile);
      }
    }
    return response.data;
  }

  Future<Map<String, dynamic>> sendEmailOtp({
    required String email,
    String? fullName,
  }) async {
    final response = await _apiClient.post(
      'users/auth/generate-email-otp',
      data: {
        'email': email,
        'full_name': fullName,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> verifyEmailOtp({
    required String email,
    required String otp,
    required String otpReferenceId,
  }) async {
    final response = await _apiClient.post(
      'users/auth/verify-email-otp',
      data: {
        'email': email,
        'otp': otp,
        'otp_reference_id': otpReferenceId,
      },
    );
    return response.data;
  }

  Future<Map<String, dynamic>> register({
    required String mobile,
    required String fullName,
    required String email,
    required String tempToken,
    String? dob,
    String? referralCode,
  }) async {
    final response = await _apiClient.post(
      'users/auth/register',
      data: {
        'mobile': mobile,
        'full_name': fullName,
        'email': email,
        'dob': dob,
        'referral_code': referralCode,
        'temp_token': tempToken,
        'device_id': await DeviceIdService.getDeviceId(),
        'device_type': await DeviceIdService.getDeviceType(),
      },
    );
    // Save tokens if present
    if (response.data != null && response.data['data'] != null) {
      final data = response.data['data'];
      final accessToken = data['access_token'];
      final refreshToken = data['refresh_token'];
      if (accessToken != null) {
        await SecureStorageService.saveToken(accessToken);
      }
      if (refreshToken != null) {
        await SecureStorageService.saveRefreshToken(refreshToken);
      }
      if (data['user']?['id_customer'] != null) {
        await SecureStorageService.saveCustomerId(
            data['user']['id_customer'].toString());
      }
      if (data['user']?['name'] != null) {
        await SecureStorageService.saveCustomerName(data['user']['name']);
      } else if (data['user']?['full_name'] != null) {
        await SecureStorageService.saveCustomerName(data['user']['full_name']);
      }
      if (mobile.isNotEmpty) {
        await SecureStorageService.saveMobile(mobile);
      }
    }
    return response.data ?? {};
  }

  /// Pre-validates registration fields before navigating to PIN creation.
  /// Returns the raw API response for the caller to check success/error.
  Future<Map<String, dynamic>> registerCheck({
    required String mobile,
    required String fullName,
    required String email,
    required String tempToken,
    String? dob,
    String? referralCode,
  }) async {
    final response = await _apiClient.post(
      'users/auth/register-check',
      data: {
        'mobile': mobile,
        'full_name': fullName,
        'email': email,
        'dob': dob,
        'referral_code': referralCode,
        'temp_token': tempToken,
        'device_id': await DeviceIdService.getDeviceId(),
        'device_type': await DeviceIdService.getDeviceType(),
      },
    );
    return response.data ?? {};
  }

  Future<void> logout() async {
    await SecureStorageService.logout();
  }
}

// --- STATE MANAGEMENT LAYER ---

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

class AuthState {
  final bool isLoading;
  final String? error;
  final Map<String, dynamic>? data; // Transient result data
  final Map<String, dynamic>? sessionData; // Persistent user/session data
  final bool? isRegistered;

  AuthState({
    this.isLoading = false,
    this.error,
    this.data,
    this.sessionData,
    this.isRegistered,
  });

  AuthState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? data,
    Map<String, dynamic>? sessionData,
    bool? isRegistered,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      data: data ?? this.data,
      sessionData: sessionData ?? this.sessionData,
      isRegistered: isRegistered ?? this.isRegistered,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;

  AuthNotifier(this._authService) : super(AuthState()) {
    rehydrateFromStorage();
  }

  /// Populates sessionData from SecureStorage.
  /// Called in constructor and can be called externally when sessionData
  /// may have been overwritten (e.g. forgot PIN flow overwrites it with
  /// temp_token, losing the user.id_customer needed by providers).
  Future<void> rehydrateFromStorage() async {
    final customerId = await SecureStorageService.getCustomerId();
    final mobile = await SecureStorageService.getMobile();
    final name = await SecureStorageService.getCustomerName();
    final photo = await SecureStorageService.getCustomerPhoto();

    if (customerId != null || mobile != null) {
      final Map<String, dynamic> data = {
        'mobile': mobile ?? '',
        'user': {
          'id_customer': customerId ?? '',
          'name': name ?? '',
          'photo_url': photo,
        }
      };
      state = state.copyWith(sessionData: data, isRegistered: true);
    }
  }

  Future<bool> sendOtp(String mobile, String countryCode, String idCountry,
      {String type = 'LOGIN'}) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.sendOtp(
          mobile: mobile,
          countryCode: countryCode,
          idCountry: idCountry,
          type: type);

      if (data['success'] == true) {
        state = state.copyWith(isLoading: false, data: data['data']);
        return true;
      } else {
        // Handle error field if present (nested structure)
        String? errorMessage;
        if (data['error'] != null && data['error']['message'] != null) {
          final msg = data['error']['message'];
          if (msg is Map) {
            errorMessage = msg.values.first.toString();
          } else {
            errorMessage = msg.toString();
          }
        }
        errorMessage ??=
            data['message'] ?? 'Failed to send OTP. Please try again.';
        state = state.copyWith(isLoading: false, error: errorMessage);
        return false;
      }
    } catch (e, stack) {
      debugPrint('AUTH ERROR: $e\n$stack');
      String errorMessage = 'Connection error. Please check your internet.';
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          errorMessage = 'Server timeout. Please try again later.';
        } else if (e.response?.data != null) {
          final respData = e.response?.data;
          if (respData['error'] != null &&
              respData['error']['message'] != null) {
            final msg = respData['error']['message'];
            if (msg is Map) {
              errorMessage = msg.values.first.toString();
              if (errorMessage.startsWith('[')) {
                // Remove brackets if it's a list toString
                errorMessage =
                    errorMessage.replaceAll('[', '').replaceAll(']', '');
              }
            } else {
              errorMessage = msg.toString();
            }
          } else {
            errorMessage = respData['message'] ??
                'Server unreachable [${e.response?.statusCode ?? 'No Connection'}]';
          }
        } else {
          errorMessage = 'Server unreachable [No Data]';
        }
      } else {
        errorMessage = 'Internal Error: ${e.toString()}';
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  Future<bool> verifyOtp(
      String mobile, String otp, String otpReferenceId) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.verifyOtp(
        mobile: mobile,
        otp: otp,
        otpReferenceId: otpReferenceId,
      );

      if (data['success'] == true) {
        state = state.copyWith(
          isLoading: false,
          isRegistered: !(data['data']?['is_new_user'] ?? false),
          sessionData: data['data'],
          data: data['data'],
        );
        return true;
      } else {
        String? errorMessage;
        if (data['error'] != null && data['error']['message'] != null) {
          final msg = data['error']['message'];
          if (msg is Map) {
            errorMessage = msg.values.first
                .toString()
                .replaceAll('[', '')
                .replaceAll(']', '');
          } else {
            errorMessage = msg.toString();
          }
        }
        errorMessage ??=
            data['message'] ?? 'Invalid or expired OTP. Please try again.';
        state = state.copyWith(isLoading: false, error: errorMessage);
        return false;
      }
    } catch (e) {
      String errorMessage = 'Verification failed. Please try again.';
      if (e is DioException) {
        if (e.response?.data != null) {
          final respData = e.response?.data;
          if (respData['error'] != null &&
              respData['error']['message'] != null) {
            final msg = respData['error']['message'];
            if (msg is Map) {
              errorMessage = msg.values.first
                  .toString()
                  .replaceAll('[', '')
                  .replaceAll(']', '');
            } else {
              errorMessage = msg.toString();
            }
          } else {
            errorMessage = respData['message'] ??
                'Verification error [${e.response?.statusCode ?? 'No Connection'}]';
          }
        }
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  Future<bool> sendEmailOtp(String email, {String? fullName}) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.sendEmailOtp(email: email, fullName: fullName);

      if (data['success'] == true) {
        state = state.copyWith(isLoading: false, data: data['data']);
        return true;
      } else {
        String? errorMessage;
        if (data['error'] != null && data['error']['message'] != null) {
          final msg = data['error']['message'];
          if (msg is Map) {
            errorMessage = msg.values.first.toString();
          } else {
            errorMessage = msg.toString();
          }
        }
        errorMessage ??=
            data['message'] ?? 'Failed to send OTP. Please try again.';
        state = state.copyWith(isLoading: false, error: errorMessage);
        return false;
      }
    } catch (e) {
      String errorMessage = 'Connection error. Please check your internet.';
      if (e is DioException) {
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout) {
          errorMessage = 'Server timeout. Please try again later.';
        } else if (e.response?.data != null) {
          final respData = e.response?.data;
          if (respData['error'] != null &&
              respData['error']['message'] != null) {
            final msg = respData['error']['message'];
            if (msg is Map) {
              errorMessage = msg.values.first
                  .toString()
                  .replaceAll('[', '')
                  .replaceAll(']', '');
            } else {
              errorMessage = msg.toString();
            }
          } else {
            errorMessage = respData['message'] ??
                'Server unreachable [${e.response?.statusCode ?? 'No Connection'}]';
          }
        } else {
          errorMessage = 'Server unreachable [No Data]';
        }
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  Future<bool> verifyEmailOtp(String email, String otp, String otpReferenceId) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.verifyEmailOtp(
        email: email,
        otp: otp,
        otpReferenceId: otpReferenceId,
      );

      if (data['success'] == true) {
        state = state.copyWith(isLoading: false, data: data['data']);
        return true;
      } else {
        String? errorMessage;
        if (data['error'] != null && data['error']['message'] != null) {
          final msg = data['error']['message'];
          if (msg is Map) {
            errorMessage = msg.values.first
                .toString()
                .replaceAll('[', '')
                .replaceAll(']', '');
          } else {
            errorMessage = msg.toString();
          }
        }
        errorMessage ??=
            data['message'] ?? 'Invalid or expired OTP. Please try again.';
        state = state.copyWith(isLoading: false, error: errorMessage);
        return false;
      }
    } catch (e) {
      String errorMessage = 'Verification failed. Please try again.';
      if (e is DioException) {
        if (e.response?.data != null) {
          final respData = e.response?.data;
          if (respData['error'] != null &&
              respData['error']['message'] != null) {
            final msg = respData['error']['message'];
            if (msg is Map) {
              errorMessage = msg.values.first
                  .toString()
                  .replaceAll('[', '')
                  .replaceAll(']', '');
            } else {
              errorMessage = msg.toString();
            }
          } else {
            errorMessage = respData['message'] ??
                'Verification error [${e.response?.statusCode ?? 'No Connection'}]';
          }
        }
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  Future<bool> register({
    required String mobile,
    required String fullName,
    required String email,
    required String tempToken,
    String? dob,
    String? referralCode,
  }) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final data = await _authService.register(
        mobile: mobile,
        fullName: fullName,
        email: email,
        tempToken: tempToken,
        dob: dob,
        referralCode: referralCode,
      );

      if (data['success'] == true) {
        state = state.copyWith(
          isLoading: false,
          isRegistered: true,
          sessionData: data['data'],
          data: data['data'],
        );
        return true;
      } else {
        // Extract error from nested error.message structure
        String? errorMessage;
        if (data['error'] != null && data['error']['message'] != null) {
          final msg = data['error']['message'];
          if (msg is Map) {
            errorMessage = msg.values.first.toString();
          } else {
            errorMessage = msg.toString();
          }
        }
        errorMessage ??= data['message'] ?? 'Registration failed.';
        state = state.copyWith(isLoading: false, error: errorMessage);
        return false;
      }
    } on DioException catch (e) {
      String errorMessage = 'Registration failed. Please try again.';
      if (e.response?.data != null) {
        final respData = e.response?.data;
        if (respData['error'] != null && respData['error']['message'] != null) {
          final msg = respData['error']['message'];
          if (msg is Map) {
            errorMessage = msg.values.first
                .toString()
                .replaceAll('[', '')
                .replaceAll(']', '');
          } else {
            errorMessage = msg.toString();
          }
        } else {
          errorMessage = respData['message'] ?? errorMessage;
        }
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    } catch (e) {
      state = state.copyWith(
          isLoading: false, error: 'Registration failed. Please try again.');
      return false;
    }
  }

  Future<void> logout() async {
    await _authService.logout();
    state = AuthState();
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final service = ref.watch(authServiceProvider);
  return AuthNotifier(service);
});
