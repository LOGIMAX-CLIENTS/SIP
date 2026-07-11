import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/profile_service.dart';
import '../../core/providers/user_provider.dart';

class UserProfile {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String dob;
  final String pincode;
  final String state;
  final String city;
  final String address;
  final String idCountry;
  final String idState;
  final String idCity;
  final String? photoUrl;
  final int kycStatus;
  final String referralMessage; // from API referral_message field
  final String? lastLoginAt; // VAPT Finding 6: last login timestamp
  final String? lastFailedLoginAt; // VAPT Finding 6: last failed login timestamp

  UserProfile({
    required this.id,
    required this.name,
    this.email = '',
    required this.phone,
    required this.dob,
    required this.pincode,
    required this.state,
    required this.city,
    required this.address,
    required this.idCountry,
    required this.idState,
    required this.idCity,
    this.photoUrl,
    this.kycStatus = 0,
    this.referralMessage = '',
    this.lastLoginAt,
    this.lastFailedLoginAt,
  });

  UserProfile copyWith({
    String? name,
    String? email,
    String? phone,
    String? dob,
    String? pincode,
    String? state,
    String? city,
    String? address,
    String? idCountry,
    String? idState,
    String? idCity,
    String? photoUrl,
    int? kycStatus,
    String? referralMessage,
    String? lastLoginAt,
    String? lastFailedLoginAt,
  }) {
    return UserProfile(
      id: this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      dob: dob ?? this.dob,
      pincode: pincode ?? this.pincode,
      state: state ?? this.state,
      city: city ?? this.city,
      address: address ?? this.address,
      idCountry: idCountry ?? this.idCountry,
      idState: idState ?? this.idState,
      idCity: idCity ?? this.idCity,
      photoUrl: photoUrl ?? this.photoUrl,
      kycStatus: kycStatus ?? this.kycStatus,
      referralMessage: referralMessage ?? this.referralMessage,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      lastFailedLoginAt: lastFailedLoginAt ?? this.lastFailedLoginAt,
    );
  }
}

class ProfileState {
  final UserProfile user;
  final bool isLoading;
  final bool isPhotoLoading;
  final bool isEditing;
  final String? error;

  ProfileState({
    required this.user,
    this.isLoading = false,
    this.isPhotoLoading = false,
    this.isEditing = false,
    this.error,
  });

  ProfileState copyWith({
    UserProfile? user,
    bool? isLoading,
    bool? isPhotoLoading,
    bool? isEditing,
    String? error,
  }) {
    return ProfileState(
      user: user ?? this.user,
      isLoading: isLoading ?? this.isLoading,
      isPhotoLoading: isPhotoLoading ?? this.isPhotoLoading,
      isEditing: isEditing ?? this.isEditing,
      error: error ?? this.error,
    );
  }
}

class ProfileNotifier extends StateNotifier<ProfileState> {
  final ProfileService _profileService;
  final String _customerId;

  ProfileNotifier(this._profileService, this._customerId)
      : super(ProfileState(
          user: UserProfile(
            id: _customerId,
            name: '',
            phone: '',
            dob: '',
            pincode: '',
            state: '',
            city: '',
            address: '',
            idCountry: '101',
            idState: '',
            idCity: '',
          ),
        )) {
    fetchProfileDetails();
  }

  /// Safely parse nullable API fields.
  /// Returns null for: null, empty string, or literal "null" string.
  static String? _parseNullableField(dynamic value) {
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty || str == 'null') return null;
    return str;
  }

  Future<void> fetchProfileDetails() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final data = await _profileService.getProfileDetails(_customerId);
      if (data != null) {
        state = state.copyWith(
          user: UserProfile(
            id: _customerId,
            name: data['name'] ?? data['full_name'] ?? '',
            email: data['email'] ?? '',
            phone: data['mobile'] ?? data['phone'] ?? '',
            dob: data['dob'] ?? '',
            pincode: data['pincode'] ?? '',
            state: data['state'] ?? data['state_name'] ?? '',
            city: data['city'] ?? data['city_name'] ?? '',
            address: data['address'] ?? '',
            idCountry: data['id_country']?.toString() ?? '101',
            idState: data['id_state']?.toString() ?? '',
            idCity: data['id_city']?.toString() ?? '',
            photoUrl: data['photo_url'],
            kycStatus: data['kyc_status'] != null
                ? int.tryParse(data['kyc_status'].toString()) ?? 0
                : 0,
            referralMessage: data['referral_message']?.toString() ?? '',
            lastLoginAt: _parseNullableField(data['last_login_at']),
            lastFailedLoginAt: _parseNullableField(data['last_failed_login_at']),
          ),
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, error: 'Failed to load profile');
    }
  }

  void setEditing(bool editing) {
    state = state.copyWith(isEditing: editing, error: null);
  }

  /// Returns {'success': true, 'data': {...}} or {'success': false, 'message': '...'}.
  Future<Map<String, dynamic>> checkPincode(String pincode) async {
    try {
      final result = await _profileService.checkPincode(pincode);
      if (result['success'] == true && result['data'] != null) {
        final data = result['data'] as Map<String, dynamic>;
        return {
          'success': true,
          'data': {
            'state': data['state']?.toString() ?? '',
            'city': data['city']?.toString() ?? '',
            'id_country': data['id_country']?.toString() ?? '101',
            'id_state': data['id_state']?.toString() ?? '',
            'id_city': data['id_city']?.toString() ?? '',
          },
        };
      }
      return {
        'success': false,
        'message': result['message']?.toString() ?? 'Pincode not found.',
      };
    } catch (e) {
      return {'success': false, 'message': 'Failed to verify pincode.'};
    }
  }

  void updateLocationInfo({
    required String stateVal,
    required String city,
    required String idCountry,
    required String idState,
    required String idCity,
  }) {
    state = state.copyWith(
      user: state.user.copyWith(
        state: stateVal,
        city: city,
        idCountry: idCountry,
        idState: idState,
        idCity: idCity,
      ),
    );
  }

  Future<bool> updateProfile({
    required String name,
    required String email,
    required String dob,
    required String pincode,
    required String stateVal,
    required String city,
    required String address,
  }) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final result = await _profileService.updateProfile(
        customerId: _customerId,
        name: name,
        email: email,
        dob: dob,
        pincode: pincode,
        state: stateVal,
        city: city,
        address: address,
        idCountry: state.user.idCountry,
        idState: state.user.idState,
        idCity: state.user.idCity,
      );

      if (result['success'] == true) {
        final updatedUser = state.user.copyWith(
          name: name,
          email: email,
          dob: dob,
          pincode: pincode,
          state: stateVal,
          city: city,
          address: address,
        );
        state = state.copyWith(
          user: updatedUser,
          isLoading: false,
          isEditing: false,
        );
        return true;
      } else {
        state = state.copyWith(
          isLoading: false,
          error: result['message']?.toString() ??
              'Failed to update profile. Please try again.',
        );
        return false;
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to update profile. Please try again.',
      );
      return false;
    }
  }

  Future<bool> updateProfilePhoto(File photo) async {
    state = state.copyWith(isPhotoLoading: true, error: null);

    try {
      final success = await _profileService.updateProfilePhoto(
        photo: photo,
        customerId: state.user.id,
      );

      if (success) {
        // Re-fetch profile to get the updated photo_url from server
        await fetchProfileDetails();
        state = state.copyWith(isPhotoLoading: false);
        return true;
      } else {
        throw Exception('Upload failed');
      }
    } catch (e) {
      state = state.copyWith(
        isPhotoLoading: false,
        error: 'Failed to upload photo. Please try again.',
      );
      return false;
    }
  }
}

final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  final service = ref.watch(profileServiceProvider);
  final user = ref.watch(userProvider);
  final customerId = user?.id ?? '';
  return ProfileNotifier(service, customerId);
});
