import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';

class ProfileService {
  final ApiClient _apiClient;

  ProfileService(this._apiClient);

  Future<Map<String, dynamic>?> getProfileDetails(String customerId) async {
    try {
      final response = await _apiClient.post(
        'profile/customer_details',
        data: {'id_customer': customerId},
      );
      if (response.data != null && response.data['success'] == true) {
        return response.data['data'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Returns `{'success': true}` or `{'success': false, 'message': '...'}`.
  Future<Map<String, dynamic>> updateProfile({
    required String customerId,
    required String firstName,
    String? lastName,
    required String email,
    required String dob,
    required String pincode,
    required String state,
    required String city,
    required String address,
    required String idCountry,
    required String idState,
    required String idCity,
  }) async {
    try {
      final response = await _apiClient.post(
        'profile/update',
        data: {
          'id_customer': customerId,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'dob': dob,
          'pincode': pincode,
          'state': state,
          'city': city,
          'address': address,
          'id_country': idCountry,
          'id_state': idState,
          'id_city': idCity,
        },
      );
      if (response.data['success'] == true) {
        return {'success': true};
      }
      // API returned success: false — extract the error message
      final data = response.data;
      final msg = data['message']?.toString()
          ?? (data['error'] as Map<String, dynamic>?)?['message']?.toString()
          ?? 'Failed to update profile.';
      return {'success': false, 'message': msg};
    } catch (e) {
      // e is a Failure from ApiFailureMapper — use its message
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Returns a map with 'success' bool, 'data' (location info), and 'message' (error message).
  Future<Map<String, dynamic>> checkPincode(String pincode) async {
    try {
      final response = await _apiClient.post(
        'users/shared/check-pincode',
        data: {'pincode': pincode},
      );
      if (response.data != null && response.data['success'] == true) {
        return {
          'success': true,
          'data': response.data['data'],
        };
      }
      // API returned success: false — extract message
      final msg = response.data?['message']?.toString()
          ?? response.data?['error']?['details']?.toString()
          ?? 'Pincode not found.';
      return {'success': false, 'message': msg};
    } catch (e) {
      return {'success': false, 'message': 'Failed to verify pincode. Please try again.'};
    }
  }

  Future<bool> updateProfilePhoto({
    required File photo,
    required String customerId,
  }) async {
    try {
      final fileName = photo.path.split('/').last;
      final formData = FormData.fromMap({
        'photo': await MultipartFile.fromFile(
          photo.path,
          filename: fileName,
        ),
        'id_customer': customerId,
      });



      final response = await _apiClient.post(
        'customer/update-profile-photo',
        data: formData,
      );

      return response.data['success'] == true;
    } catch (e) {
      return false;
    }
  }
}

final profileServiceProvider = Provider<ProfileService>((ref) {
  return ProfileService(ApiClient());
});
