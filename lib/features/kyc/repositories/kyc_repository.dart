import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/network/api_client.dart';
import '../models/kyc_document.dart';
import '../../../../core/security/encryption_service.dart';
import '../../../../core/security/secure_logger.dart';

final kycRepositoryProvider = Provider((ref) => KycRepository());

class KycRepository {
  final ApiClient _apiClient = ApiClient();

  Future<KycDocumentsResult> getDocumentTypes({
    required String customerId,
    required String requestFrom,
  }) async {
    final response = await _apiClient.post('kyc/document-types', data: {
      'id_customer': customerId,
      'request_from': requestFrom,
    });

    if (response.data['success'] == true) {
      final data = response.data['data'];
      final List documents = data['documents'];
      final aadhaarStatus = (data['aadhaar_status'] ?? '').toString();
      return KycDocumentsResult(
        documents: documents.map((e) => KycDocumentType.fromJson(e)).toList(),
        aadhaarApproved: aadhaarStatus.toUpperCase() == 'APPROVED',
        aadhaarMaskedNumber: data['aadhaar_masked_number']?.toString(),
        aadhaarName: data['aadhaar_name']?.toString(),
      );
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

  // ─── Aadhaar / DigiLocker (id_document = "2") ────────────────────────────
  //
  // Unlike PAN, Aadhaar is a two-step, poll-based flow against the same
  // `kyc/upload` endpoint (see backend `KYCService._initiate_aadhaar_kyc` /
  // `_check_aadhaar_kyc`), and the caller needs the full response payload
  // (consent_url, verification_id, status) rather than a plain bool — so
  // these return the raw `data` map instead of reusing `uploadKyc()`.

  /// Step 1: ask the backend to create a Cashfree DigiLocker consent
  /// session. Returns `data` — either
  /// `{status:"PENDING", verification_id, consent_url, message}` or, if
  /// Aadhaar was already verified in a prior attempt,
  /// `{status:"already approved", is_already_approved:true}`.
  ///
  /// Both [aadhaarNumber] and [fullName] are REQUIRED by the backend for
  /// this call (`KYCService._initiate_aadhaar_kyc` — `upload_document`
  /// returns `False, "Aadhaar number is required."` /
  /// `False, "Name is required for Aadhaar verification."` if either is
  /// missing). The backend reads the name from the exact key `name` (not
  /// `full_name`). Beyond the required-ness check, [aadhaarNumber] is used
  /// for a real Cashfree "does a DigiLocker account exist for this Aadhaar"
  /// call before the consent URL is created, and [fullName] is stored and
  /// later compared against DigiLocker's returned name in
  /// `_check_aadhaar_kyc` to populate `name_matched`/`name_match_score` —
  /// a mismatch does not block approval, but it is recorded.
  /// [allowReverify] is set when the user deliberately taps "Edit" on an
  /// already-verified Aadhaar card to redo verification — tells the backend
  /// to bypass its already-approved idempotency short-circuit (see
  /// `KYCService._initiate_aadhaar_kyc`'s `allow_reverify` param).
  Future<Map<String, dynamic>> initiateAadhaar({
    required String requestFrom,
    required String aadhaarNumber,
    required String fullName,
    bool allowReverify = false,
  }) {
    return _uploadAadhaar(
      requestFrom: requestFrom,
      fields: {
        'aadhaar_number': aadhaarNumber,
        'name': fullName,
        if (allowReverify) 'allow_reverify': true,
      },
    );
  }

  /// Step 2: poll for the DigiLocker consent outcome using the
  /// `verification_id` returned by [initiateAadhaar]. Returns `data` with
  /// `status` in PENDING | APPROVED | EXPIRED | REJECTED.
  Future<Map<String, dynamic>> pollAadhaar({
    required String requestFrom,
    required String verificationId,
  }) {
    return _uploadAadhaar(
      requestFrom: requestFrom,
      fields: {'verification_id': verificationId},
    );
  }

  Future<Map<String, dynamic>> _uploadAadhaar({
    required String requestFrom,
    required Map<String, dynamic> fields,
  }) async {
    // Same client-side encryption pass uploadKyc() applies to PAN fields —
    // `aadhaar_number` is in AppConfig.sensitiveFields, so this is a no-op
    // for the poll call's `verification_id` (not a sensitive field) but
    // encrypts the number on the initiate call when the user supplied one.
    final encryptedFields = EncryptionService.encryptJson(fields);

    final response = await _apiClient.post('kyc/upload', data: {
      'id_document': '2', // AADHAAR
      'request_from': requestFrom,
      'fields': encryptedFields,
    });

    final data = response.data['data'];
    if (response.data['success'] == true) {
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    // Same error-extraction convention as uploadKyc() above.
    final errorObj = response.data['error'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (data is Map ? data['message'] : null) ??
        response.data['message'] ??
        'Aadhaar verification failed. Please try again.';
    throw Exception(serverMessage);
  }

  /// Fetches the merchant config Meon's native `flutter_digilocker_aadhar_pan`
  /// SDK needs to launch directly (companyName + secretToken + redirectUrl) —
  /// see `meon_digilocker_sdk_screen.dart`'s SECURITY NOTE for why this is a
  /// dedicated backend call rather than a bundled constant. Server-gated on
  /// the MEON gateway row's own active status; throws if it's not enabled,
  /// so callers should only offer this path when they expect it to succeed
  /// (e.g. behind a feature flag) rather than showing it unconditionally.
  Future<Map<String, dynamic>> getMeonSdkConfig() async {
    final response = await _apiClient.post('kyc/meon-sdk-config', data: {});

    if (response.data['success'] == true) {
      final data = response.data['data'];
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    final errorObj = response.data['error'];
    final dataObj = response.data['data'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (dataObj is Map ? dataObj['message'] : null) ??
        response.data['message'] ??
        'Meon DigiLocker verification is not available right now.';
    throw Exception(serverMessage);
  }

  /// Updates the customer's profile name (cus_name) to the verified name
  /// from the latest APPROVED PAN or Aadhaar KYC record — used by the
  /// mandatory Profile Name Selection popup shown after every successful
  /// PAN + Aadhaar completion. [source] must be `'PAN'` or `'AADHAAR'`; the
  /// backend resolves the actual name server-side from the verified
  /// record, never trusting a client-supplied name string.
  Future<void> updateProfileName({required String source}) async {
    final response = await _apiClient.post('kyc/update-profile-name', data: {
      'source': source,
    });

    if (response.data['success'] == true) return;

    final errorObj = response.data['error'];
    final dataObj = response.data['data'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (dataObj is Map ? dataObj['message'] : null) ??
        response.data['message'] ??
        'Could not update profile name.';
    throw Exception(serverMessage);
  }
}

