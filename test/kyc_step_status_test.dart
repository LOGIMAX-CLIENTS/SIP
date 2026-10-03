import 'package:flutter_test/flutter_test.dart';
import 'package:startgold/features/kyc/controllers/kyc_controller.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/utils/kyc_step_status.dart';
import 'package:startgold/features/kyc/widgets/kyc_step_row.dart';

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

  test('a server that does not send email_verified locks nobody out', () {
    final docs = KycDocumentsResult(documents: [pan()], aadhaarApproved: false);
    expect(docs.emailVerified, isTrue);
  });
}
