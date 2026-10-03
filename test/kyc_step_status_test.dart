import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/core/providers/user_provider.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';
import 'package:startgold/features/kyc/utils/kyc_step_status.dart';
import 'package:startgold/features/kyc/widgets/kyc_step_row.dart';
import 'package:startgold/features/profile/services/profile_service.dart';

/// document-types as served before the E-mail step: no email/email_verified.
class _OldServerRepository extends Fake implements KycRepository {
  @override
  Future<KycDocumentsResult> getDocumentTypes({required String customerId, required String requestFrom}) async =>
      KycDocumentsResult(documents: [], aadhaarApproved: false);
}

class _FakeProfileService extends Fake implements ProfileService {
  _FakeProfileService(this.profile);
  final Map<String, dynamic>? profile;

  @override
  Future<Map<String, dynamic>?> getProfileDetails(String customerId) async => profile;
}

/// E-mail Verification is step 1 of the KYC checklist (RULE-KYC-022).
void main() {
  KycDocumentType pan({bool done = false}) => KycDocumentType(
        id: '1',
        name: 'PAN',
        code: 'PAN',
        mandatory: true,
        fields: const [],
        images: KycImagesRequirement(front: false, back: false),
        alreadyUploaded: done,
      );

  KycStepStatuses compute({
    bool emailVerified = true,
    bool panDone = false,
    bool aadhaarApproved = false,
    AadhaarPhase phase = AadhaarPhase.idle,
    Map<String, dynamic>? verificationStatus,
  }) {
    return computeKycStepStatuses(
      docsResult: KycDocumentsResult(
        documents: [pan(done: panDone)],
        aadhaarApproved: aadhaarApproved,
        email: 'asha@example.com',
        emailVerified: emailVerified,
      ),
      aadhaarState: AadhaarState(phase: phase),
      verificationStatus: verificationStatus,
      bankAccounts: null,
      bavHistory: null,
      rpdHistory: null,
    );
  }

  test('an unverified e-mail locks PAN and Aadhaar that have not started', () {
    final s = compute(emailVerified: false);

    expect(s.emailStatus, KycStepStatus.actionable);
    expect(s.emailPill, 'Pending');
    expect(s.panStatus, KycStepStatus.locked);
    expect(s.aadhaarStatus, KycStepStatus.locked);
    expect(s.completed, 0);
  });

  test('a verified e-mail counts as the first step done', () {
    final s = compute();

    expect(s.emailStatus, KycStepStatus.verified);
    expect(s.panStatus, KycStepStatus.actionable);
    expect(s.aadhaarStatus, KycStepStatus.actionable);
    expect(s.completed, 1);
    // E-mail, PAN, Aadhaar, Name & DOB, PAN-Aadhaar Link, Bank.
    expect(s.total, 6);
  });

  test('progress already made is kept while the e-mail is unverified', () {
    final s = compute(emailVerified: false, panDone: true, aadhaarApproved: true);

    expect(s.panStatus, KycStepStatus.verified);
    expect(s.aadhaarStatus, KycStepStatus.verified);
    expect(s.emailStatus, KycStepStatus.actionable);
    expect(s.completed, 2);
  });

  test('an Aadhaar check under way is not locked', () {
    final s = compute(emailVerified: false, phase: AadhaarPhase.polling);
    expect(s.aadhaarStatus, KycStepStatus.inProgress);
  });

  test('a Retry is locked too — the server refuses to start one', () {
    final s = compute(emailVerified: false, phase: AadhaarPhase.failed);
    expect(s.aadhaarStatus, KycStepStatus.locked);
  });

  test('the bank step does not wait on the e-mail', () {
    final withEmail = compute(panDone: true, aadhaarApproved: true);
    final withoutEmail = compute(emailVerified: false, panDone: true, aadhaarApproved: true);

    expect(withoutEmail.bavStatus, withEmail.bavStatus);
    expect(withoutEmail.idKycComplete, withEmail.idKycComplete);
  });

  test('the e-mail step is counted even when DigiLocker is switched off', () {
    final s = compute(verificationStatus: {
      'digilocker_pan': {'is_active': false},
      'digilocker_aadhaar': {'is_active': false},
    });
    // E-mail, Name & DOB, PAN-Aadhaar Link, Bank.
    expect(s.total, 4);
  });

  test('an unknown e-mail status is never shown as verified', () {
    final s = computeKycStepStatuses(
      docsResult: KycDocumentsResult(documents: [pan()], aadhaarApproved: false),
      aadhaarState: const AadhaarState(),
      verificationStatus: null,
      bankAccounts: null,
      bavHistory: null,
      rpdHistory: null,
    );
    expect(s.emailStatus, KycStepStatus.actionable);
  });

  group('a server that does not report the e-mail step', () {
    ProviderContainer container({required Map<String, dynamic>? profile}) {
      final c = ProviderContainer(overrides: [
        userProvider.overrideWithValue(UserProfile(id: 'cus-1', name: 'Gokul', mobile: '9876543210')),
        kycRepositoryProvider.overrideWithValue(_OldServerRepository()),
        profileServiceProvider.overrideWithValue(_FakeProfileService(profile)),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('takes it from the profile — unverified', () async {
      final c = container(profile: {'email': 'gokul@logimaxindia.com', 'email_verified': false});
      final docs = await c.read(kycDocumentsProvider('profile').future);
      expect(docs.email, 'gokul@logimaxindia.com');
      expect(docs.emailVerified, isFalse);
    });

    test('takes it from the profile — verified', () async {
      final c = container(profile: {'email': 'gokul@logimaxindia.com', 'email_verified': true});
      final docs = await c.read(kycDocumentsProvider('profile').future);
      expect(docs.emailVerified, isTrue);
    });

    test('reads unverified when the profile cannot be fetched either', () async {
      final c = container(profile: null);
      final docs = await c.read(kycDocumentsProvider('profile').future);
      expect(docs.emailVerified, isFalse);
    });
  });
}
