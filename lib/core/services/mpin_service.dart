import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../network/api_client.dart';
import '../error/failures.dart';

// --- SERVICE LAYER ---

class MpinService {
  final ApiClient _apiClient = ApiClient();

  /// Sets the MPIN on the server after registration.
  /// Throws an [Exception] with the backend message if success == false.
  Future<void> setMpin(String mpin) async {
    final response = await _apiClient.post(
      'mpin/create',
      data: {'mpin': mpin},
    );
    final data = response.data;
    // Server always returns HTTP 200 — check application-level flag
    if (data?['success'] == true) return;

    final errObj = data?['error'];
    final msg = (errObj is Map ? errObj['message'] : null) ??
        data?['message'] ??
        'Failed to set PIN. Please try again.';
    throw Exception(msg);
  }

  /// Verifies the MPIN with the server.
  Future<bool> verifyMpin(String mpin) async {
    final response = await _apiClient.post(
      'mpin/validate',
      data: {'mpin': mpin},
    );
    final data = response.data;
    // Server returns HTTP 200 even on failure — must check app-level flag
    if (data?['success'] == true) return true;

    // Check for SESSION_EXPIRED in the response body
    final errorCode = data?['error']?['code'] ?? data?['data']?['code'];
    if (errorCode == 'SESSION_EXPIRED') {
      throw DioException(
        requestOptions: response.requestOptions,
        response: Response(
          requestOptions: response.requestOptions,
          statusCode: 401,
          data: data,
        ),
        type: DioExceptionType.badResponse,
      );
    }

    return false;
  }

  /// Changes the MPIN with the server.
  /// Throws an [Exception] with the backend message if success == false.
  Future<bool> changeMpin(String oldMpin, String newMpin) async {
    final response = await _apiClient.post(
      'mpin/change',
      data: {
        'old_mpin': oldMpin,
        'new_mpin': newMpin,
      },
    );
    final data = response.data;
    // Server always returns HTTP 200 — check the application-level flag
    if (data?['success'] == true) return true;

    // Extract the real error message from the response
    final errObj = data?['error'];
    final msg = (errObj is Map ? errObj['message'] : null) ??
        data?['message'] ??
        'Failed to change PIN. Please try again.';
    throw Exception(msg);
  }

  /// Resets the MPIN after forgot-PIN OTP verification.
  /// Requires temp_token from the OTP verify response.
  Future<void> resetMpin(String tempToken, String newMpin,
      {String? mobile}) async {
    final response = await _apiClient.post(
      'mpin/reset',
      data: {
        'temp_token': tempToken,
        'new_mpin': newMpin,
        if (mobile != null) 'mobile': mobile,
      },
    );
    final data = response.data;
    if (data?['success'] == true) return;

    final errObj = data?['error'];
    final msg = (errObj is Map ? errObj['message'] : null) ??
        data?['message'] ??
        'Failed to reset PIN. Please try again.';
    throw Exception(msg);
  }

  /// Checks if the user already has an MPIN set on the backend.
  Future<bool> hasMpinSet() async {
    final response = await _apiClient.post('auth/has-mpin');
    return response.data['hasMpin'] ?? false;
  }
}

// --- STATE MANAGEMENT LAYER ---

final mpinServiceProvider = Provider<MpinService>((ref) => MpinService());

class MpinState {
  final String mpin;
  final bool isComplete;
  final bool isLoading;
  final String? error;

  final int failedAttempts;
  final bool isLocked;

  MpinState({
    this.mpin = '',
    this.isComplete = false,
    this.isLoading = false,
    this.error,
    this.failedAttempts = 0,
    this.isLocked = false,
  });

  MpinState copyWith({
    String? mpin,
    bool? isComplete,
    bool? isLoading,
    String? error,
    bool clearError = false,
    int? failedAttempts,
    bool? isLocked,
  }) {
    return MpinState(
      mpin: mpin ?? this.mpin,
      isComplete: isComplete ?? this.isComplete,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      failedAttempts: failedAttempts ?? this.failedAttempts,
      isLocked: isLocked ?? this.isLocked,
    );
  }
}

class MpinNotifier extends StateNotifier<MpinState> {
  final MpinService _mpinService;
  static const int pinLength = 6;

  MpinNotifier(this._mpinService) : super(MpinState());

  void addKey(String key) {
    if (state.mpin.length < pinLength) {
      final newMpin = state.mpin + key;
      state = state.copyWith(
        mpin: newMpin,
        isComplete: newMpin.length == pinLength,
      );
    }
  }

  void backspace() {
    if (state.mpin.isNotEmpty) {
      final newMpin = state.mpin.substring(0, state.mpin.length - 1);
      state = state.copyWith(
        mpin: newMpin,
        isComplete: false,
      );
    }
  }

  Future<bool> setMpin() async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _mpinService.setMpin(state.mpin);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(
        isLoading: false,
        mpin: '',
        isComplete: false,
        error: msg.isNotEmpty ? msg : 'Failed to set security PIN. Try again.',
      );
      return false;
    }
  }

  Future<bool> verifyMpin() async {
    if (state.isLoading || state.isLocked) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final success = await _mpinService.verifyMpin(state.mpin);
      if (success) {
        state = state.copyWith(isLoading: false, failedAttempts: 0);
        return true;
      } else {
        final newAttempts = state.failedAttempts + 1;
        final isLocked = newAttempts >= 5;
        state = state.copyWith(
          isLoading: false,
          mpin: '',
          isComplete: false,
          failedAttempts: newAttempts,
          isLocked: isLocked,
          error: isLocked
              ? 'ACCOUNT LOCKED: Too many failed attempts. Contact support.'
              : 'Invalid PIN. $newAttempts/5 attempts used.',
        );
        return false;
      }
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;

      // ── Session invalidated (409) ──
      // The interceptor already shows the force-logout dialog and rejects
      // with DioExceptionType.cancel. Do NOT set any error here — it would
      // cause a duplicate toast on top of the dialog.
      final isSessionInvalidated = statusCode == 409 ||
          (e.type == DioExceptionType.cancel &&
              e.error?.toString().contains('Session invalidated') == true);

      if (isSessionInvalidated) {
        state = state.copyWith(
          isLoading: false,
          mpin: '',
          isComplete: false,
          // No error — the interceptor dialog handles everything.
        );
        return false;
      }

      // ── SESSION_EXPIRED Detection ──
      // Check response body for SESSION_EXPIRED code (covers both HTTP 200
      // and HTTP 401 scenarios, regardless of interceptor token refresh)
      final respData = e.response?.data;
      final bodyErrorCode = respData is Map
          ? (respData['error']?['code'] ?? respData['data']?['code'] ?? respData['code'])
          : null;

      if (statusCode == 401 || statusCode == 403 || bodyErrorCode == 'SESSION_EXPIRED') {
        state = state.copyWith(
          isLoading: false,
          mpin: '',
          isComplete: false,
          error: 'SESSION_EXPIRED',
        );
      } else {
        // Extract real server message instead of hardcoded fallback
        final failure = ApiFailureMapper.map(e);
        state = state.copyWith(
          isLoading: false,
          mpin: '',
          isComplete: false,
          error: failure.message,
        );
      }
      return false;
    } on SessionInvalidatedFailure catch (_) {
      // _apiClient.post() converts the interceptor's rejected DioException
      // into a SessionInvalidatedFailure before it reaches us — so the
      // DioException 409 branch above never actually matches this path.
      // The interceptor already shows the force-logout dialog and rejects
      // the request. Do NOT set any error here — it would cause a
      // duplicate/confusing toast on top of the dialog.
      state = state.copyWith(
        isLoading: false,
        mpin: '',
        isComplete: false,
        // No error — the interceptor dialog handles everything.
      );
      return false;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      // Safety net: if error message mentions session expiry, treat as SESSION_EXPIRED
      final isSessionExpired = msg.toLowerCase().contains('session') &&
          msg.toLowerCase().contains('expired');
      state = state.copyWith(
        isLoading: false,
        mpin: '',
        isComplete: false,
        error: isSessionExpired
            ? 'SESSION_EXPIRED'
            : (msg.isNotEmpty ? msg : 'Something went wrong. Please try again.'),
      );
      return false;
    }
  }

  /// Resets the MPIN (forgot PIN flow).
  Future<bool> resetMpin(String tempToken, {String? mobile}) async {
    if (state.isLoading) return false;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _mpinService.resetMpin(tempToken, state.mpin, mobile: mobile);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      state = state.copyWith(
        isLoading: false,
        mpin: '',
        isComplete: false,
        error: msg.isNotEmpty ? msg : 'Failed to reset PIN. Try again.',
      );
      return false;
    }
  }

  void clear() {
    state = MpinState();
  }
}

final mpinProvider = StateNotifierProvider<MpinNotifier, MpinState>((ref) {
  final service = ref.watch(mpinServiceProvider);
  return MpinNotifier(service);
});
