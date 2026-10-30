import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/profile/profile_controller.dart';
import 'package:startgold/features/profile/services/profile_service.dart';

class _FakeProfileService extends Fake implements ProfileService {
  _FakeProfileService(this.profile);

  final Map<String, dynamic> profile;
  final List<String> sentEmails = [];

  @override
  Future<Map<String, dynamic>?> getProfileDetails(String customerId) async => profile;

  @override
  Future<Map<String, dynamic>> updateProfile({
    required String customerId,
    required String firstName,
    String? lastName,
    required String email,
    required String dob,
    required String pincode,
    required String state,
    String? area,
    required String city,
    required String address,
    required String idCountry,
    required String idState,
    required String idCity,
  }) async {
    sentEmails.add(email);
    return {'success': true};
  }
}

Map<String, dynamic> _profile({required bool emailVerified}) => {
      'first_name': 'Asha',
      'email': 'asha@example.com',
      'email_verified': emailVerified,
      'dob': '1990-01-01',
      'pincode': '642002',
      'state_name': 'TAMIL NADU',
      'city_name': 'COIMBATORE',
      'address': '',
    };

Future<ProfileNotifier> _loaded(_FakeProfileService service) async {
  final notifier = ProfileNotifier(service, 'cus-1');
  await notifier.fetchProfileDetails();
  return notifier;
}

Future<bool> _save(ProfileNotifier notifier, {required String email}) =>
    notifier.updateProfile(
      firstName: 'Asha',
      email: email,
      dob: '01/01/1990',
      pincode: '642002',
      stateVal: 'TAMIL NADU',
      city: 'Coimbatore',
      address: '',
    );

/// PM-STG-0603: a verified e-mail can be replaced on Personal Details, but
/// only by an address verified by OTP first — so the saved one is verified.
void main() {
  test('a verified e-mail replaced by a new one is still shown verified', () async {
    final service = _FakeProfileService(_profile(emailVerified: true));
    final notifier = await _loaded(service);

    expect(await _save(notifier, email: 'asha.new@example.com'), isTrue);

    expect(service.sentEmails, ['asha.new@example.com']);
    expect(notifier.state.user.email, 'asha.new@example.com');
    expect(notifier.state.user.isEmailVerified, isTrue);
  });

  test('saving the same unverified e-mail leaves it unverified', () async {
    final notifier = await _loaded(_FakeProfileService(_profile(emailVerified: false)));

    await _save(notifier, email: 'ASHA@example.com');

    expect(notifier.state.user.isEmailVerified, isFalse);
  });
}
