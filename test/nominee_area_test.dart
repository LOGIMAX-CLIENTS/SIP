import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/nominee/models/nominee_model.dart';

NomineeDetails _nominee({String? pincode = '642002', String? area}) =>
    NomineeDetails(
      name: 'John Doe',
      relationship: 'Father',
      relationshipId: 1,
      dob: '1970-05-15',
      mobile: '9123456780',
      pincode: pincode,
      area: area,
    );

/// Area (one of the pincode's taluks) on Nominee Details, the same field as on
/// Personal Details; check-pincode lists the choices as `areas`.
void main() {
  test('the stored area comes back from nominee/details', () {
    final nominee = NomineeDetails.fromJson({
      'name': 'John Doe',
      'relationship': 'Father',
      'dob': '15-05-1970',
      'mobile': '9123456780',
      'pincode': '642002',
      'area': 'Pollachi',
    });

    expect(nominee.area, 'Pollachi');
  });

  test('a server without the Area field gives no area', () {
    final nominee = NomineeDetails.fromJson({
      'name': 'John Doe',
      'relationship': 'Father',
      'dob': '15-05-1970',
      'mobile': '9123456780',
    });

    expect(nominee.area, isNull);
  });

  test('a picked area is sent', () {
    expect(_nominee(area: 'Kinathukadavu').toJson()['area'], 'Kinathukadavu');
  });

  test('no area to pick: nothing is sent and the server decides', () {
    expect(_nominee().toJson().containsKey('area'), isFalse);
  });

  test('copyWith carries the area', () {
    expect(_nominee(area: 'Pollachi').copyWith(name: 'Jane').area, 'Pollachi');
    expect(_nominee().copyWith(area: 'Pollachi').area, 'Pollachi');
  });
}
