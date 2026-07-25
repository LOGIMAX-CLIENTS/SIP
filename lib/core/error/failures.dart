import 'package:dio/dio.dart';

abstract class Failure {
  final String message;
  final int? statusCode;

  Failure(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class NetworkFailure extends Failure {
  NetworkFailure([String? message]) : super(message ?? 'Network connection lost');
}

class ServerFailure extends Failure {
  ServerFailure({String? message, int? statusCode}) 
    : super(message ?? 'Server temporarily unavailable', statusCode: statusCode);
}

class AuthenticationFailure extends Failure {
  AuthenticationFailure([String? message]) : super(message ?? 'Session expired');
}

/// Thrown when the server returns **409 Conflict** with SESSION_INVALIDATED.
/// The interceptor handles the dialog + forced logout automatically;
/// this failure type allows callers to silently swallow the error in
/// their catch blocks instead of showing duplicate error UI.
class SessionInvalidatedFailure extends Failure {
  SessionInvalidatedFailure([String? message])
      : super(message ?? 'Session invalidated. Please log in again.');
}

class InvalidResponseFailure extends Failure {
  InvalidResponseFailure([String? message]) : super(message ?? 'Invalid response from server');
}

/// Thrown when the server signals that KYC (PAN + Aadhaar) must be completed
/// before the requested action (SIP create, withdrawal, etc.) can proceed.
/// Backend sends this as `error.code == 'KYC_REQUIRED'` — today only on SIP
/// create and withdrawal-initiate (both HTTP 403/400) — but any endpoint
/// that starts returning the same code is covered automatically.
/// Callers should catch this specifically and route the user through
/// `KycVerificationFlow.start()` (see lib/features/kyc/kyc_flow.dart), then
/// retry the original action once verification completes.
class KycRequiredFailure extends Failure {
  KycRequiredFailure([String? message])
      : super(message ?? 'KYC verification is required to proceed.');
}

class ApiFailureMapper {
  static Failure map(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.connectionError:
        return NetworkFailure();

      // 409 session-invalidated errors are rejected as `cancel` by the
      // interceptor. Map them to SessionInvalidatedFailure so callers
      // can silently ignore (the interceptor already shows the dialog).
      case DioExceptionType.cancel:
        if (err.error?.toString().contains('Session invalidated') == true) {
          return SessionInvalidatedFailure();
        }
        return InvalidResponseFailure('Request cancelled');
      
      case DioExceptionType.badResponse:
        final status = err.response?.statusCode;
        if (status == 409) {
          return SessionInvalidatedFailure();
        }

        // Always try to extract the real server message first,
        // regardless of status code — the server always sends useful context.
        final responseData = err.response?.data;
        String? serverMessage;
        String? errorCode;
        if (responseData is Map<String, dynamic>) {
          serverMessage = responseData['message']?.toString() ??
              (responseData['error'] as Map<String, dynamic>?)?['message']
                  ?.toString() ??
              (responseData['validation_errors'] as Map<String, dynamic>?)?['detail']
                  ?.toString() ??
              (responseData['data'] as Map<String, dynamic>?)?['message']
                  ?.toString();
          // KYC gate: checked ahead of the generic 401/403 handling below so
          // it isn't swallowed into a generic "Authentication failed" message.
          errorCode = (responseData['error'] as Map<String, dynamic>?)?['code']
                  ?.toString() ??
              (responseData['data'] as Map<String, dynamic>?)?['code']?.toString();
        }

        if (errorCode == 'KYC_REQUIRED') {
          return KycRequiredFailure(serverMessage);
        }

        if (status == 401 || status == 403) {
          // Use real server message; fall back to generic only if absent.
          return AuthenticationFailure(
              serverMessage ?? 'Authentication credentials were not provided.');
        }
        if (status != null && status >= 500) {
          return ServerFailure(
            message: serverMessage ?? 'Server temporarily unavailable',
            statusCode: status,
          );
        }
        return ServerFailure(
          message: serverMessage ?? 'Server error code: $status',
          statusCode: status,
        );
      
      default:
        return ServerFailure(message: 'Something went wrong. Please try again later.');
    }
  }
}
