/// Nominee data model.
///
/// Follows the same defensive null-coalescing serialisation
/// pattern used across the codebase.
class NomineeDetails {
  final int? id;
  final String name;
  final String relationship;
  final int? relationshipId;
  final String dob;
  final String mobile;
  final String? email;
  final String? idType;
  final String? idNumber;
  final String? address;
  final String? city;
  final String? state;
  final String? pincode;
  final int? idCity;
  final int? idState;
  final int? idCountry;

  NomineeDetails({
    this.id,
    required this.name,
    required this.relationship,
    this.relationshipId,
    required this.dob,
    required this.mobile,
    this.email,
    this.idType,
    this.idNumber,
    this.address,
    this.city,
    this.state,
    this.pincode,
    this.idCity,
    this.idState,
    this.idCountry,
  });

  factory NomineeDetails.fromJson(Map<String, dynamic> json) {
    return NomineeDetails(
      id: json['id'] as int?,
      name: json['name']?.toString() ?? '',
      relationship: json['relationship']?.toString() ?? '',
      relationshipId: json['relationship_id'] as int?,
      dob: json['dob']?.toString() ?? '',
      mobile: json['mobile']?.toString() ?? '',
      email: json['email']?.toString(),
      idType: json['id_type']?.toString(),
      idNumber: json['id_number']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      state: json['state']?.toString(),
      pincode: json['pincode']?.toString(),
      idCity: json['id_city'] as int?,
      idState: json['id_state'] as int?,
      idCountry: json['id_country'] as int?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'name': name,
      'relationship': relationship,
      'dob': dob,
      'mobile': mobile,
      'id_country': idCountry ?? 101,
    };
    if (id != null) map['id'] = id;
    if (relationshipId != null) map['relationship_id'] = relationshipId;
    if (email != null && email!.isNotEmpty) map['email'] = email;
    if (idType != null && idType!.isNotEmpty) map['id_type'] = idType;
    if (idNumber != null && idNumber!.isNotEmpty) map['id_number'] = idNumber;
    if (address != null && address!.isNotEmpty) map['address'] = address;
    if (city != null && city!.isNotEmpty) map['city'] = city;
    if (state != null && state!.isNotEmpty) map['state'] = state;
    if (pincode != null && pincode!.isNotEmpty) map['pincode'] = pincode;
    if (idCity != null) map['id_city'] = idCity;
    if (idState != null) map['id_state'] = idState;
    return map;
  }

  /// Whether nominee data has been submitted (non-empty required fields).
  bool get isValid =>
      name.isNotEmpty && relationship.isNotEmpty && dob.isNotEmpty && mobile.isNotEmpty;

  NomineeDetails copyWith({
    int? id,
    String? name,
    String? relationship,
    int? relationshipId,
    String? dob,
    String? mobile,
    String? email,
    String? idType,
    String? idNumber,
    String? address,
    String? city,
    String? state,
    String? pincode,
    int? idCity,
    int? idState,
    int? idCountry,
  }) {
    return NomineeDetails(
      id: id ?? this.id,
      name: name ?? this.name,
      relationship: relationship ?? this.relationship,
      relationshipId: relationshipId ?? this.relationshipId,
      dob: dob ?? this.dob,
      mobile: mobile ?? this.mobile,
      email: email ?? this.email,
      idType: idType ?? this.idType,
      idNumber: idNumber ?? this.idNumber,
      address: address ?? this.address,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      idCity: idCity ?? this.idCity,
      idState: idState ?? this.idState,
      idCountry: idCountry ?? this.idCountry,
    );
  }
}

/// Nominee relationship with ID from the server.
class NomineeRelationship {
  final int id;
  final String name;

  const NomineeRelationship({required this.id, required this.name});

  factory NomineeRelationship.fromJson(Map<String, dynamic> json) =>
      NomineeRelationship(
        id: json['id'] as int? ?? 0,
        name: json['name']?.toString() ?? '',
      );
}

/// Server-driven nominee form settings, from `users/nominee/relationships`.
class NomineeFormOptions {
  final List<NomineeRelationship> relationships;

  /// NOMINEE_FORM_VALIDATION.email_mandatory — true: Email ID is required and
  /// must be OTP-verified; false: optional, verifying is the user's choice.
  final bool emailMandatory;

  const NomineeFormOptions({
    required this.relationships,
    this.emailMandatory = true,
  });

  /// Used when the API call fails — keeps today's strict behaviour.
  static const fallback =
      NomineeFormOptions(relationships: nomineeRelationships);
}

/// Pre-defined nominee relationships (fallback when API fails).
const List<NomineeRelationship> nomineeRelationships = [
  NomineeRelationship(id: 1, name: 'Father'),
  NomineeRelationship(id: 2, name: 'Mother'),
  NomineeRelationship(id: 3, name: 'Spouse'),
  NomineeRelationship(id: 4, name: 'Son'),
  NomineeRelationship(id: 5, name: 'Daughter'),
  NomineeRelationship(id: 6, name: 'Brother'),
  NomineeRelationship(id: 7, name: 'Sister'),
  NomineeRelationship(id: 8, name: 'Other'),
];

/// Pre-defined ID proof types.
const List<String> nomineeIdProofTypes = [
  'Aadhaar',
  'PAN',
  'Voter ID',
  'Passport',
  'Driving License',
  'Others',
];
