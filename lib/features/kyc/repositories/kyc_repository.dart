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
        aadhaarDob: data['aadhaar_dob']?.toString(),
        kycConfirmed: data['kyc_confirmed'] == true,
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
  /// `status` in PENDING | APPROVED | EXPIRED | REJECTED | CONFIRM_NAME_UPDATE.
  ///
  /// CONFIRM_NAME_UPDATE (KYC_NAME_MISMATCH_RESOLUTION, backend
  /// `KYCService._check_aadhaar_kyc`) means the Aadhaar-verified name/DOB
  /// don't match the profile on file — a plain re-poll (leave
  /// [confirmNameUpdate] false) just re-returns the same prompt, it doesn't
  /// re-call DigiLocker. To resolve it, resubmit with the SAME
  /// [verificationId], [confirmNameUpdate]=true, and the customer's
  /// corrected [name]/[dob] (`DD-MM-YYYY`, matching KYCService's
  /// `_parse_flexible_date`) — the backend re-validates them against the
  /// Aadhaar record it already fetched (no second DigiLocker round trip)
  /// and, on match, applies them to the profile in that same call. A
  /// continued mismatch comes back as a thrown Exception (status
  /// NAME_MISMATCH), same as any other rejected `success:false` response —
  /// there is no separate "still mismatched" data shape to branch on.
  Future<Map<String, dynamic>> pollAadhaar({
    required String requestFrom,
    required String verificationId,
    bool confirmNameUpdate = false,
    String? name,
    String? dob,
  }) {
    return _uploadAadhaar(
      requestFrom: requestFrom,
      fields: {
        'verification_id': verificationId,
        if (confirmNameUpdate) 'confirm_name_update': true,
        if (name != null && name.isNotEmpty) 'name': name,
        if (dob != null && dob.isNotEmpty) 'dob': dob,
      },
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

  /// Resolves a PAN name/DOB mismatch prompt (`pan_confirmation` piggybacked
  /// on an Aadhaar poll response — see NameMismatchPrompt's doc comment in
  /// kyc_controller.dart). Unlike Aadhaar's mismatch resolution, this is
  /// NOT part of the `kyc/upload` id_document="2" poll cycle — PAN has no
  /// verification_id/poll of its own, so the backend created a dedicated
  /// PENDING PAN KYC row instead and this targets it directly via
  /// `id_document="3"` (`KYCService._confirm_pan_name_mismatch`).
  ///
  /// [panKycId] is [NameMismatchPrompt.verificationId] from that prompt
  /// (the dedicated PAN row's id, despite the field's name). [confirm]=true
  /// with [name]/[dob] re-validates them against the PAN-verified record and
  /// applies them to the profile on match (same
  /// `_validate_mismatch_resubmission` rule Aadhaar uses — DD-MM-YYYY for
  /// [dob], matching `KYCService._parse_flexible_date`); [confirm]=false
  /// declines and leaves the PAN row PENDING (a successful no-op, not an
  /// error). Returns `data` — `status` is APPROVED | NAME_MISMATCH |
  /// DECLINED.
  Future<Map<String, dynamic>> confirmPanNameMismatch({
    required String panKycId,
    required bool confirm,
    String? name,
    String? dob,
  }) async {
    final fields = {
      'pan_kyc_id': panKycId,
      'confirm': confirm,
      if (name != null && name.isNotEmpty) 'name': name,
      if (dob != null && dob.isNotEmpty) 'dob': dob,
    };
    final response = await _apiClient.post('kyc/upload', data: {
      'id_document': '3', // PAN_NAME_MISMATCH_CONFIRM
      'fields': fields,
    });

    final data = response.data['data'];
    if (response.data['success'] == true) {
      return data is Map<String, dynamic> ? data : <String, dynamic>{};
    }

    final errorObj = response.data['error'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (data is Map ? data['message'] : null) ??
        response.data['message'] ??
        'Could not confirm PAN details.';
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

  /// Updates the customer's profile name (cus_name) from the latest
  /// APPROVED PAN or Aadhaar KYC record — used by the mandatory verified-
  /// details confirmation dialog shown after every successful PAN/Aadhaar
  /// completion. [source] must be `'PAN'` or `'AADHAAR'`.
  ///
  /// [name] is what the customer typed/edited in that dialog's Profile Name
  /// field — the backend (`update_profile_name_from_kyc`) requires it to
  /// match the verified [source] name (NameMatchingService) and rejects a
  /// mismatch with PROFILE_NAME_MISMATCH rather than storing it; omitting
  /// [name] falls back to the server-resolved verified name as-is.
  Future<void> updateProfileName({required String source, String? name}) async {
    final response = await _apiClient.post('kyc/update-profile-name', data: {
      'source': source,
      if (name != null && name.isNotEmpty) 'name': name,
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

  /// Companion to [updateProfileName] for the customer's date of birth
  /// (cus_dob) — mirrors its contract exactly: [source] is `'PAN'` or
  /// `'AADHAAR'`, [dob] is what the customer typed/picked in the
  /// confirmation dialog's date field, sent as `DD-MM-YYYY` (see
  /// _VerifiedDetailsDialogState._formatDob in kyc_screen.dart) because
  /// that's the one format `KYCService._parse_flexible_date` tries first —
  /// do not switch this to ISO without checking that server-side parser.
  /// A mismatch against the verified [source] DOB is expected to come back
  /// the same way PROFILE_NAME_MISMATCH does (a `PROFILE_DOB_MISMATCH`-coded
  /// error with a human-readable `message`), which the generic error
  /// handling below already surfaces correctly without special-casing it.
  ///
  /// NOT backed by a live endpoint yet — `kyc/update-profile-dob` doesn't
  /// exist on the backend, and building it needs a prerequisite the name
  /// endpoint didn't: the verified DOB isn't persisted anywhere retrievable
  /// today (see KycDocumentType.verifiedDob's doc comment), so even the
  /// "resolve without a typed value" fallback path can't work until that's
  /// fixed. Callers must treat this as best-effort (catch and ignore) so it
  /// stays dormant rather than blocking the dialog's save action.
  Future<void> updateProfileDob({required String source, String? dob}) async {
    final response = await _apiClient.post('kyc/update-profile-dob', data: {
      'source': source,
      if (dob != null && dob.isNotEmpty) 'dob': dob,
    });

    if (response.data['success'] == true) return;

    final errorObj = response.data['error'];
    final dataObj = response.data['data'];
    final String serverMessage = (errorObj is Map ? errorObj['message'] : null) ??
        (dataObj is Map ? dataObj['message'] : null) ??
        response.data['message'] ??
        'Could not update profile date of birth.';
    throw Exception(serverMessage);
  }
}

