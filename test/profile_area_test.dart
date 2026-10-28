import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/profile/profile_controller.dart';
import 'package:startgold/features/profile/services/profile_service.dart';

class _FakeProfileService extends Fake implements ProfileService {
  _FakeProfileService({this.profile, this.pincodeData});

  final Map<String, dynamic>? profile;
  final Map<String, dynamic>? pincodeData;
  final List<String?> sentAreas = [];

  @override
  Future<Map<String, dynamic>?> getProfileDetails(String customerId) async => profile;

  @override
  Future<Map<String, dynamic>> checkPincode(String pincode) async =>
      {'success': true, 'data': pincodeData};

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
    sentAreas.add(area);
    return {'success': true};
  }
}

Map<String, dynamic> _profile({String area = 'Pollachi'}) => {
      'first_name': 'Asha',
      'email': 'asha@example.com',
      'dob': '1990-01-01',
      'pincode': '642002',
      'state_name': 'TAMIL NADU',
      'area': area,
      'city_name': 'COIMBATORE',
      'address': '',
    };

Future<ProfileNotifier> _loaded(_FakeProfileService service) async {
  final notifier = ProfileNotifier(service, 'cus-1');
  await notifier.fetchProfileDetails();
  return notifier;
}

Future<bool> _save(ProfileNotifier notifier, {required String pincode, String? area}) =>
    notifier.updateProfile(
      firstName: 'Asha',
      email: 'asha@example.com',
      dob: '01/01/1990',
      pincode: pincode,
      stateVal: 'TAMIL NADU',
      area: area,
      city: 'Coimbatore',
      address: '',
    );

/// Area (one of the pincode's taluks) sits between State and City on
/// Personal Details; check-pincode lists the choices as `areas`.
void main() {
  test('the stored area comes back from customer_details', () async {
    final notifier = await _loaded(_FakeProfileService(profile: _profile()));

    expect(notifier.state.user.area, 'Pollachi');
  });

  test('check-pincode hands the areas through, minus blanks', () async {
    final notifier = await _loaded(_FakeProfileService(
      profile: _profile(),
      pincodeData: {'state': 'TAMIL NADU', 'city': 'Coimbatore', 'areas': ['Kinathukadavu', ' ', 'Pollachi']},
    ));

    final result = await notifier.checkPincode('642002');

    expect(result['data']['areas'], ['Kinathukadavu', 'Pollachi']);
  });

  test('a server without the Area field gives no areas', () async {
    final notifier = await _loaded(_FakeProfileService(
      profile: _profile(),
      pincodeData: {'state': 'TAMIL NADU', 'city': 'Coimbatore'},
    ));

    final result = await notifier.checkPincode('642002');

    expect(result['data']['areas'], isEmpty);
  });

  test('a picked area is sent and kept', () async {
    final service = _FakeProfileService(profile: _profile());
    final notifier = await _loaded(service);

    expect(await _save(notifier, pincode: '642002', area: 'Kinathukadavu'), isTrue);

    expect(service.sentAreas, ['Kinathukadavu']);
    expect(notifier.state.user.area, 'Kinathukadavu');
  });

  test('no area to pick: same pincode keeps the stored one', () async {
    final service = _FakeProfileService(profile: _profile());
    final notifier = await _loaded(service);

    await _save(notifier, pincode: '642002');

    expect(service.sentAreas, [null]);
    expect(notifier.state.user.area, 'Pollachi');
  });

  test('no area to pick: a new pincode drops the old one', () async {
    final notifier = await _loaded(_FakeProfileService(profile: _profile()));

    await _save(notifier, pincode: '600001');

    expect(notifier.state.user.area, '');
  });
}
