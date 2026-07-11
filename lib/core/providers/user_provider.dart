import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../features/auth/controller/auth_controller.dart';

class UserProfile {
  final String id;
  final String name;
  final String mobile;
  final String email;
  final String? photoUrl;
  final bool isNewUser;
  final bool mpinEnabled;
  final bool isKycVerified;
  final bool isVip;

  UserProfile({
    required this.id,
    required this.name,
    required this.mobile,
    this.email = '',
    this.photoUrl,
    this.isNewUser = false,
    this.mpinEnabled = false,
    this.isKycVerified = false,
    this.isVip = false,
  });
}

final userProvider = Provider<UserProfile?>((ref) {
  final authState = ref.watch(authControllerProvider);
  final data = authState.sessionData;

  if (data != null) {
    final isNew = data['is_new_user'] == true;

    if (isNew) {
      return UserProfile(
        id: '',
        name: 'New User',
        mobile: data['mobile'] ?? '',
        isNewUser: true,
      );
    } else {
      final userData = data['user'] ?? {};
      return UserProfile(
        id: userData['id_customer']?.toString() ?? '',
        name: userData['name'] ?? userData['full_name'] ?? '',
        mobile: userData['mobile'] ?? data['mobile'] ?? '',
        email: userData['email'] ?? '',
        photoUrl: userData['photo_url'] ?? data['photo_url'],
        isNewUser: false,
        mpinEnabled: data['mpin_enabled'] == true,
      );
    }
  }
  return null;
});
