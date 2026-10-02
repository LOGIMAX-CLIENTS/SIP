import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/profile/utils/security_score.dart';

void main() {
  int score({bool mpin = true, required bool bio, required int timeout}) =>
      computeSecurityScore(
        mpinEnabled: mpin,
        biometricOn: bio,
        timeoutSeconds: timeout,
      ).percent;

  group('computeSecurityScore', () {
    test('biometric on with a 30s-or-shorter lock is fully protected', () {
      expect(score(bio: true, timeout: 0), 100);
      expect(score(bio: true, timeout: 30), 100);
      final full = computeSecurityScore(
          mpinEnabled: true, biometricOn: true, timeoutSeconds: 30);
      expect(full.isFull, isTrue);
      expect(full.headline, 'Fully protected');
      expect(full.message, 'All security layers are active');
      expect(full.strengthLabel, 'Strong');
    });

    test('biometric on with a longer lock is 90%', () {
      expect(score(bio: true, timeout: 31), 90);
      expect(score(bio: true, timeout: 1800), 90);
    });

    test('biometric off is 50% with a short lock, 40% otherwise', () {
      expect(score(bio: false, timeout: 0), 50);
      expect(score(bio: false, timeout: 30), 50);
      expect(score(bio: false, timeout: 31), 40);
      expect(score(bio: false, timeout: 1800), 40);
    });

    test('MPIN off is 40% whatever the lock', () {
      expect(score(mpin: false, bio: false, timeout: 0), 40);
      expect(score(mpin: false, bio: false, timeout: 1800), 40);
    });
  });
}
