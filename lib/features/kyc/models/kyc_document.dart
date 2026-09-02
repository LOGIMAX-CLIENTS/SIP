class KycDocumentType {
  final String id;
  final String name;
  final String code;
  final bool mandatory;
  final String status;
  final bool alreadyUploaded;
  final List<KycField> fields;
  final KycImagesRequirement images;
  final String? maskedValue;
  final String? verifiedName;
  // Not returned by the backend today — and not just because
  // kyc/document-types hasn't been extended to send it. Backend confirmed
  // the verified PAN DOB is never persisted anywhere retrievable in the
  // first place: KYCService._try_persist_digilocker_pan parses it
  // (authoritative_dob_raw) purely to run a transient mismatch check, then
  // discards it — no verified_dob key is written back onto the approved KYC
  // row's kyc_response. Backend needs to persist that key at approval time
  // before document-types could ever surface it here. Parsed defensively
  // from `verified_dob` (matching the update-profile-name endpoint's
  // `verified_name`-style naming) so this activates with no frontend change
  // once both the persistence and the document-types exposure exist.
  final String? verifiedDob;

  KycDocumentType({
    required this.id,
    required this.name,
    required this.code,
    required this.mandatory,
    required this.fields,
    required this.images,
    this.status = '',
    this.alreadyUploaded = false,
    this.maskedValue,
    this.verifiedName,
    this.verifiedDob,
  });

  factory KycDocumentType.fromJson(Map<String, dynamic> json) {
    return KycDocumentType(
      id: json['id_document']?.toString() ?? '',
      name: json['document_name'] ?? '',
      code: json['code'] ?? '',
      mandatory: json['mandatory'] ?? false,
      status: json['status'] ?? '',
      alreadyUploaded: json['already_uploaded'] ?? false,
      maskedValue: json['masked_value']?.toString(),
      verifiedName: json['verified_name']?.toString(),
      verifiedDob: json['verified_dob']?.toString(),
      fields: (json['fields'] as List?)
              ?.map((e) => KycField.fromJson(e))
              .toList() ??
          [],
      images: KycImagesRequirement.fromJson(json['images'] ?? {}),
    );
  }

  /// True when this document was submitted via "Upload manually instead"
  /// (see manual_kyc_upload_screen.dart) and is awaiting admin review —
  /// backend KYCService.get_document_types() reports this as `status`
  /// ("UNDER_REVIEW") once a (PENDING + MANUAL) KYC row exists for it.
  bool get isUnderReview => status.toUpperCase() == 'UNDER_REVIEW';
}

/// Wraps the `/kyc/document-types` response: the field-driven documents
/// list (PAN today) plus Aadhaar's own approval status, which is reported
/// separately since Aadhaar is rendered as its own client-side card rather
/// than a generic fields form (see kyc_screen.dart).
class KycDocumentsResult {
  final List<KycDocumentType> documents;
  final bool aadhaarApproved;
  final String? aadhaarMaskedNumber;
  final String? aadhaarName;
  // Same caveat as KycDocumentType.verifiedDob above, Aadhaar side:
  // KYCService._check_aadhaar_kyc computes verified_dob_parsed purely for
  // its own mismatch gate and never writes it back onto the approved row's
  // kyc_response — so there's nothing for document-types to expose yet
  // either. Parsed defensively from `aadhaar_dob`.
  final String? aadhaarDob;
  // True only once the backend's CustomerPan/CustomerAadhaar mirror is
  // fully APPROVED for both PAN and Aadhaar — i.e. the customer has already
  // completed the mandatory Profile Name Selection confirmation. Distinct
  // from `documents[].alreadyUploaded`/`aadhaarApproved` above, which can
  // both be true the instant DigiLocker/the PAN provider auto-verifies,
  // before that confirmation ever happens. See kyc_screen.dart's on-load
  // completion-recovery check, which uses this to detect a customer who
  // auto-verified but never reached the confirmation dialog.
  final bool kycConfirmed;
  // True when a manual Aadhaar upload (see manual_kyc_upload_screen.dart) is
  // awaiting admin review — backend reports `aadhaar_status: "UNDER_REVIEW"`
  // (KYCService.get_document_types(), the manual-review branch). PAN's own
  // "under review" state lives on its own KycDocumentType.isUnderReview
  // instead, since PAN is a `documents[]` entry, not a top-level field.
  final bool aadhaarUnderReview;
  // True once the customer has tried "Verify via DigiLocker" at least once
  // for PAN/Aadhaar — win, lose, or abandoned mid-consent (backend:
  // KYCService._digilocker_attempted). Gates when "Upload manually
  // instead" first appears: never on the very first screen visit, always
  // from the next visit onward once DigiLocker has genuinely been tried.
  final bool digilockerAttempted;
  // True when Aadhaar's latest attempt (of EITHER kind — DigiLocker or a
  // manual upload) was refused (`aadhaar_status: "REJECTED"`). A manual
  // upload that gets rejected without DigiLocker ever having been tried
  // would otherwise leave digilockerAttempted false and "Upload manually
  // instead" hidden right when the customer most needs to retry it — see
  // kyc_screen.dart's allowManualUpload computation.
  final bool aadhaarRejected;

  KycDocumentsResult({
    required this.documents,
    required this.aadhaarApproved,
    this.aadhaarMaskedNumber,
    this.aadhaarName,
    this.aadhaarDob,
    this.kycConfirmed = false,
    this.aadhaarUnderReview = false,
    this.digilockerAttempted = false,
    this.aadhaarRejected = false,
  });
}

class KycField {
  final String name;
  final String label;
  final String type;
  final String? regex;

  KycField({
    required this.name,
    required this.label,
    required this.type,
    this.regex,
  });

  factory KycField.fromJson(Map<String, dynamic> json) {
    return KycField(
      name: json['name'] ?? '',
      label: json['label'] ?? '',
      type: json['type'] ?? 'text',
      regex: json['regex'],
    );
  }
}

class KycImagesRequirement {
  final bool front;
  final bool back;

  KycImagesRequirement({
    required this.front,
    required this.back,
  });

  factory KycImagesRequirement.fromJson(Map<String, dynamic> json) {
    return KycImagesRequirement(
      front: json['front'] ?? false,
      back: json['back'] ?? false,
    );
  }
}

