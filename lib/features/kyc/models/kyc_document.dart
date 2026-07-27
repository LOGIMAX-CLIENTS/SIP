class KycDocumentType {
  final String id;
  final String name;
  final String code;
  final bool mandatory;
  final String status;
  final bool alreadyUploaded;
  final List<KycField> fields;
  final KycImagesRequirement images;

  KycDocumentType({
    required this.id,
    required this.name,
    required this.code,
    required this.mandatory,
    required this.fields,
    required this.images,
    this.status = '',
    this.alreadyUploaded = false,
  });

  factory KycDocumentType.fromJson(Map<String, dynamic> json) {
    return KycDocumentType(
      id: json['id_document']?.toString() ?? '',
      name: json['document_name'] ?? '',
      code: json['code'] ?? '',
      mandatory: json['mandatory'] ?? false,
      status: json['status'] ?? '',
      alreadyUploaded: json['already_uploaded'] ?? false,
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

  KycDocumentsResult({required this.documents, required this.aadhaarApproved});
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

