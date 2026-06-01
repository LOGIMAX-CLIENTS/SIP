import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../models/kyc_document.dart';
import '../../../../core/security/encryption_service.dart';
import '../../../../core/security/secure_logger.dart';

final kycRepositoryProvider = Provider((ref) => KycRepository());

class KycRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<KycDocumentType>> getDocumentTypes({
    required String customerId,
    required String requestFrom,
  }) async {
    final response = await _apiClient.post('kyc/document-types', data: {
      'id_customer': customerId,
      'request_from': requestFrom,
    });

    if (response.data['success'] == true) {
      final List documents = response.data['data']['documents'];
      return documents.map((e) => KycDocumentType.fromJson(e)).toList();
    } else {
      throw Exception(response.data['message'] ?? 'Failed to load documents');
    }
  }

  Future<bool> uploadKyc({
    required String customerId, // Kept in case of need, but payload below follows user request
    required String requestFrom,
    required String documentId,
    required Map<String, dynamic> fields,
  }) async {
    // 1. Structure the data as per user request
    final Map<String, dynamic> rawData = {
      'id_document': documentId,
      'request_from': requestFrom,
      'fields': fields,
    };

    // 2. Encrypt sensitive fields (Rule 3)
    // We encrypt specifically for logging and to ensure structure matches
    final Map<String, dynamic> encryptedFieldsMap =
        EncryptionService.encryptJson(fields);

    final Map<String, dynamic> postData = {
      'id_document': documentId,
      'request_from': requestFrom,
      'fields': encryptedFieldsMap,
    };

    // 3. PRINT POST DATA (Requested by USER)
    final displayData = Map<String, dynamic>.from(rawData);
    final displayFields = Map<String, dynamic>.from(fields);
    displayFields.forEach((key, value) {
      if (key.contains('pan') || key.contains('aadhaar')) {
        displayFields[key] = '********';
      }
    });
    displayData['fields'] = displayFields;

    SecureLogger.d('--- KYC Upload API CALL ---');
    SecureLogger.d('URL: kyc/upload');
    SecureLogger.d('POST DATA (Logical Structure): $displayData');

    // 4. Send as JSON (Interceptor will also handle recursive encryption if needed)
    final response = await _apiClient.post('kyc/upload', data: postData);

    SecureLogger.d('KYC Upload completed — success: ${response.data['success']}');

    if (response.data['success'] == true) {
      return true;
    }

    // Extract the server's actual error message so the UI can display it.
    final errorObj = response.data['error'];
    final dataObj = response.data['data'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (dataObj is Map ? dataObj['message'] : null) ??
        response.data['message'] ??
        'KYC verification failed. Please try again.';

    throw Exception(serverMessage);
  }
}

