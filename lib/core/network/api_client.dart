import 'package:dio/dio.dart';
import '../config/app_config.dart';
import '../security/certificate_pinning.dart';
import '../security/api_interceptor.dart';

import '../error/failures.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  late final Dio _dio;

  factory ApiClient() => _instance;

  ApiClient._internal() {
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: AppConfig.connectTimeout),
        receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(ApiSecurityInterceptor());
    if (AppConfig.baseUrl.startsWith('https')) {
      CertificatePinning.setup(_dio);
    }

    // Bootstrap RSA public key fetch – runs asynchronously; failures are handled gracefully
    ApiSecurityInterceptor.fetchAndCachePublicKey();
  }

  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      return await _dio.get(path, queryParameters: queryParameters);
    } on DioException catch (e) {
      throw ApiFailureMapper.map(e);
    } catch (e) {
      throw ServerFailure(message: 'Something went wrong. Please try again.');
    }
  }

  Future<Response> post(String path, {dynamic data}) async {
    try {
      // When sending FormData (file uploads), remove the JSON content-type
      // so Dio can auto-set 'multipart/form-data' with the correct boundary.
      Options? options;
      if (data is FormData) {
        options = Options(contentType: 'multipart/form-data');
      }
      return await _dio.post(path, data: data, options: options);
    } on DioException catch (e) {
      throw ApiFailureMapper.map(e);
    } catch (e) {
      throw ServerFailure(message: 'Something went wrong. Please try again.');
    }
  }
}
