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

  KycDocumentsResult({
    required this.documents,
    required this.aadhaarApproved,
    this.aadhaarMaskedNumber,
    this.aadhaarName,
    this.aadhaarDob,
    this.kycConfirmed = false,
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

