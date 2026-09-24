import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/kyc_controller.dart';
import '../models/kyc_document.dart';
import '../widgets/kyc_step_row.dart';
import '../../profile/models/bank_account.dart';
import '../../profile/models/bank_verification_history.dart';
import '../../profile/services/bank_details_service.dart';
import '../../profile/services/bank_verification_history_service.dart';

/// Every per-step status [KycVerificationScreen] needs to render its
/// checklist, plus the top-level completed/total tally — computed once here
/// so the checklist screen and [kycProgressProvider] (used by the Profile
/// page's menu badge) can never disagree on what "3/5 done" means.
class KycStepStatuses {
  final bool panDone;
  final bool aadhaarDone;
  final bool bothIdVerified;
  // PAN + Aadhaar + a Mandatory PAN-Aadhaar Link (when active) — exactly
  // what the backend's is_kyc_complete()/kyc_status flag requires (see
  // BUSINESS_RULES.md: is_kyc_complete() covers PAN + Aadhaar + the
  // PAN-Aadhaar link). [KycVerificationScreen]'s popWhenIdVerified gate
  // MUST key off this, not bothIdVerified alone — a gated caller like
  // Auto Savings separately re-checks the backend's kycStatus after this
  // screen pops, and if that check requires the link too while this pop
  // fired on PAN+Aadhaar alone, the customer lands right back in the same
  // gate on their very next tap (see PM-STG bug: KYC gate re-triggers
  // Aadhaar verification in a loop after it was just completed).
  final bool idKycComplete;
  final KycDocumentType? panDocValue;
  final bool panSkippedInConsent;

  final KycStepStatus panStatus;
  final String panPill;
  final KycStepStatus aadhaarStatus;
  final String aadhaarPill;

  final KycStepStatus nameDobStatus;
  final String nameDobPill;
  final String nameDobSubtitle;

  final bool panAadhaarLinkMandatory;
  final KycStepStatus panAadhaarLinkStatus;
  final String panAadhaarLinkPill;
  final String panAadhaarLinkSubtitle;

  final bool panBankLinkMandatory;
  final KycStepStatus panBankLinkStatus;
  final String panBankLinkPill;
  final String panBankLinkSubtitle;

  final bool rpdMandatory;
  final KycStepStatus rpdStatus;
  final String rpdPill;
  final String rpdSubtitle;

  final KycStepStatus pennylessBavStatus;
  final String pennylessBavPill;
  final String pennylessBavSubtitle;
  final KycStepStatus bavStatus;
  final String bavPill;
  final String bavSubtitle;

  final bool digilockerActive;
  final bool aadhaarPanLinkActive;
  final bool panBankLinkActive;
  final bool rpdActive;

  final String? cbankId;
  final BavHistoryItem? latestBav;
  final RpdHistoryItem? latestRpd;

  final int completed;
  final int total;

  const KycStepStatuses({
    required this.panDone,
    required this.aadhaarDone,
    required this.bothIdVerified,
    required this.idKycComplete,
    required this.panDocValue,
    required this.panSkippedInConsent,
    required this.panStatus,
    required this.panPill,
    required this.aadhaarStatus,
    required this.aadhaarPill,
    required this.nameDobStatus,
    required this.nameDobPill,
    required this.nameDobSubtitle,
    required this.panAadhaarLinkMandatory,
    required this.panAadhaarLinkStatus,
    required this.panAadhaarLinkPill,
    required this.panAadhaarLinkSubtitle,
    required this.panBankLinkMandatory,
    required this.panBankLinkStatus,
    required this.panBankLinkPill,
    required this.panBankLinkSubtitle,
    required this.rpdMandatory,
    required this.rpdStatus,
    required this.rpdPill,
    required this.rpdSubtitle,
    required this.pennylessBavStatus,
    required this.pennylessBavPill,
    required this.pennylessBavSubtitle,
    required this.bavStatus,
    required this.bavPill,
    required this.bavSubtitle,
    required this.digilockerActive,
    required this.aadhaarPanLinkActive,
    required this.panBankLinkActive,
    required this.rpdActive,
    required this.cbankId,
    required this.latestBav,
    required this.latestRpd,
    required this.completed,
    required this.total,
  });
}

bool _isActive(Map<String, dynamic>? verificationStatus, String key) {
  final entry = verificationStatus?[key];
  if (entry is Map) return entry['is_active'] != false;
  return true;
}

/// Reads `verifications[key].is_mandatory` — unlike [_isActive], absent
/// means NOT mandatory (Optional), matching the backend's own default.
bool _isMandatory(Map<String, dynamic>? verificationStatus, String key) {
  final entry = verificationStatus?[key];
  if (entry is Map) return entry['is_mandatory'] == true;
  return false;
}

/// Turns a backend status enum string ("LINKED", "NOT_LINKED") into display
/// text ("Linked", "Not Linked") — the label itself comes from the backend's
/// own value, not a second hardcoded copy in the frontend, so the two can
/// never drift the way `panAadhaarLinkPill`/`panBankLinkPill` used to.
String _formatBackendStatusLabel(String raw) {
  return raw.split('_').where((w) => w.isNotEmpty).map((w) => '${w[0]}${w.substring(1).toLowerCase()}').join(' ');
}

/// Pure derivation of every checklist step's status from the same data
/// [KycVerificationScreen] already watches. [verifyingAadhaar]/[aadhaarEditing]/
/// [retryingPanOnly] default to false for callers (like the Profile page's
/// progress badge) that aren't a live editing session — the checklist
/// screen itself passes its real in-flight state so a card doesn't flicker
/// mid-retry.
KycStepStatuses computeKycStepStatuses({
  required KycDocumentsResult docsResult,
  required AadhaarState aadhaarState,
  required Map<String, dynamic>? verificationStatus,
  required List<BankAccount>? bankAccounts,
  required List<BavHistoryItem>? bavHistory,
  required List<RpdHistoryItem>? rpdHistory,
  bool verifyingAadhaar = false,
  bool aadhaarEditing = false,
  bool retryingPanOnly = false,
}) {
  final panDoc = docsResult.documents.where(
    (d) => d.name.toUpperCase().contains('PAN') || d.code.toUpperCase().contains('PAN'),
  );
  final panDocValue = panDoc.isEmpty ? null : panDoc.first;
  final panDone = panDocValue?.alreadyUploaded ?? false;
  final panUnderReview = panDocValue?.isUnderReview ?? false;

  final aadhaarBusy = verifyingAadhaar || aadhaarState.phase == AadhaarPhase.initiating || aadhaarState.phase == AadhaarPhase.polling;
  final aadhaarDone = aadhaarState.phase == AadhaarPhase.approved ||
      (docsResult.aadhaarApproved && !aadhaarEditing && (!aadhaarBusy || retryingPanOnly));
  final aadhaarUnderReview = docsResult.aadhaarUnderReview && !aadhaarEditing;
  final aadhaarFailedPhase = aadhaarState.phase == AadhaarPhase.expired ||
      aadhaarState.phase == AadhaarPhase.rejected ||
      aadhaarState.phase == AadhaarPhase.failed;
  final panSkippedInConsent = !panDone && !aadhaarEditing && (aadhaarState.phase == AadhaarPhase.approved || docsResult.aadhaarApproved);

  final digilockerActive = _isActive(verificationStatus, 'digilocker_pan') && _isActive(verificationStatus, 'digilocker_aadhaar');
  final aadhaarPanLinkActive = _isActive(verificationStatus, 'aadhaar_pan_link');
  final panBankLinkActive = _isActive(verificationStatus, 'pan_bank_link');
  final rpdActive = _isActive(verificationStatus, 'reverse_penny_drop');

  // Step: PAN
  KycStepStatus panStatus;
  String panPill;
  if (panDone) {
    panStatus = KycStepStatus.verified;
    panPill = 'Verified';
  } else if (panUnderReview) {
    panStatus = KycStepStatus.underReview;
    panPill = 'Under Review';
  } else if (panSkippedInConsent) {
    panStatus = KycStepStatus.failed;
    panPill = 'Retry';
  } else {
    panStatus = KycStepStatus.actionable;
    panPill = 'Pending';
  }

  // Step: Aadhaar
  KycStepStatus aadhaarStatus;
  String aadhaarPill;
  if (aadhaarDone) {
    aadhaarStatus = KycStepStatus.verified;
    aadhaarPill = 'Verified';
  } else if (aadhaarUnderReview) {
    aadhaarStatus = KycStepStatus.underReview;
    aadhaarPill = 'Under Review';
  } else if (aadhaarBusy) {
    aadhaarStatus = KycStepStatus.inProgress;
    aadhaarPill = 'In Progress';
  } else if (aadhaarFailedPhase) {
    aadhaarStatus = KycStepStatus.failed;
    aadhaarPill = 'Retry';
  } else {
    aadhaarStatus = KycStepStatus.actionable;
    aadhaarPill = 'Pending';
  }

  final bothIdVerified = (panDone && aadhaarDone) || !digilockerActive;

  // Step: Name & DOB Match
  //
  // Reads the two capabilities this step is actually named after, from
  // customer_verification_status (see BUSINESS_RULES.md RULE-KYC-017).
  //
  // It used to key off `docsResult.kycConfirmed`, which is the backend's
  // `is_kyc_complete()` — the WHOLE-KYC transaction gate, covering PAN,
  // Aadhaar AND the PAN-Aadhaar link. A customer whose name/DOB matched
  // perfectly therefore still saw this step stuck on "Pending" whenever some
  // unrelated capability (in practice aadhaar_pan_link: NOT_STARTED) held
  // is_kyc_complete() at false. Confirmed live 2026-09-07:
  // profile_name_pan_name_match was MATCHED at score 100.0 while this pill
  // read Pending.
  //
  // Neither of these two capabilities is gateway-routed, so neither carries
  // is_mandatory and neither appears in is_kyc_complete() — this step is
  // display-only and must not be driven by a transaction gate.
  final persistedNameMatch =
      (verificationStatus?['profile_name_pan_name_match'] as Map?)?['status'] as String?;
  final persistedDobMatch =
      (verificationStatus?['profile_dob_pan_dob_match'] as Map?)?['status'] as String?;

  KycStepStatus nameDobStatus;
  String nameDobPill;
  String nameDobSubtitle;
  if (!bothIdVerified) {
    nameDobStatus = KycStepStatus.locked;
    nameDobPill = 'Locked';
    nameDobSubtitle = 'Unlocks once PAN and Aadhaar are verified';
  } else if (persistedNameMatch == 'MATCHED' &&
      // A document that carried no DOB never gets this row written at all
      // (Meon's PAN branch returns no DOB — see kyc.py's dob_match gate), so
      // NOT_STARTED here must not hold an otherwise-matched step back. Only
      // an explicit NOT_MATCHED should.
      persistedDobMatch != 'NOT_MATCHED') {
    nameDobStatus = KycStepStatus.verified;
    nameDobPill = 'Matched';
    nameDobSubtitle = 'PAN / Aadhaar matched with profile';
  } else if (persistedNameMatch == 'NOT_MATCHED' || persistedDobMatch == 'NOT_MATCHED') {
    // A real, recorded divergence between the profile and the verified
    // document — distinct from "never checked" below, and not something a
    // refetch can clear.
    nameDobStatus = KycStepStatus.failed;
    nameDobPill = 'Not Matched';
    nameDobSubtitle = persistedNameMatch == 'NOT_MATCHED'
        ? 'Your profile name doesn\'t match your verified PAN / Aadhaar.'
        : 'Your profile date of birth doesn\'t match your verified PAN / Aadhaar.';
  } else {
    // Neither row written yet — verification hasn't recorded the comparison.
    nameDobStatus = KycStepStatus.inProgress;
    nameDobPill = 'Pending';
    nameDobSubtitle = 'Confirm your verified details to finish this step';
  }

  // Step: PAN-Aadhaar Link
  final persistedPanAadhaarLink = (verificationStatus?['aadhaar_pan_link'] as Map?)?['status'] as String?;
  final panAadhaarLinkMandatory = _isMandatory(verificationStatus, 'aadhaar_pan_link');
  KycStepStatus panAadhaarLinkStatus;
  String panAadhaarLinkPill;
  String panAadhaarLinkSubtitle;
  if (!bothIdVerified) {
    panAadhaarLinkStatus = KycStepStatus.locked;
    panAadhaarLinkPill = 'Locked';
    panAadhaarLinkSubtitle = 'Unlocks once PAN and Aadhaar are verified';
  } else if (aadhaarState.aadhaarPanLinked == true || persistedPanAadhaarLink == 'LINKED') {
    panAadhaarLinkStatus = KycStepStatus.verified;
    // Label comes from the backend's own status string when we have one —
    // matches admin's ledger_personal.py ("LINKED") without a second
    // hardcoded copy here; falls back only when this came from the live
    // Aadhaar poll bool, which carries no status string of its own.
    panAadhaarLinkPill = persistedPanAadhaarLink != null ? _formatBackendStatusLabel(persistedPanAadhaarLink) : 'Linked';
    panAadhaarLinkSubtitle = 'Linked as per Income Tax records';
  } else if (aadhaarState.aadhaarPanLinked == false || persistedPanAadhaarLink == 'NOT_LINKED') {
    panAadhaarLinkStatus = KycStepStatus.failed;
    panAadhaarLinkPill = persistedPanAadhaarLink != null ? _formatBackendStatusLabel(persistedPanAadhaarLink) : 'Not Linked';
    panAadhaarLinkSubtitle = 'Not linked as per Income Tax records. You can retry to refresh this.';
  } else if (!panAadhaarLinkMandatory) {
    panAadhaarLinkStatus = KycStepStatus.underReview;
    panAadhaarLinkPill = 'Optional';
    panAadhaarLinkSubtitle = 'This check isn\'t required right now — you can still check it.';
  } else {
    panAadhaarLinkStatus = KycStepStatus.underReview;
    panAadhaarLinkPill = 'Pending';
    panAadhaarLinkSubtitle = 'Link status refreshes the next time you verify';
  }

  // Step: Bank Account Validation (BAV) — pennyless check specifically.
  final sortedBav = [...?bavHistory]..sort((a, b) => (b.attemptedOn ?? DateTime(0)).compareTo(a.attemptedOn ?? DateTime(0)));
  final latestBav = sortedBav.isEmpty ? null : sortedBav.first;
  final nameDobDone = nameDobStatus == KycStepStatus.verified;
  // A Mandatory prior step must actually be resolved before the next one
  // starts — an Optional (or inactive) step never blocks anything, same
  // "if mandatory" principle the PAN-Bank Link/RPD sub-items already use
  // to gate BAV's own composite status below. Previously only Name & DOB
  // Match gated this, so a customer could reach Bank Account Validation
  // with PAN-Aadhaar Link still unresolved even while it was Mandatory.
  final panAadhaarLinkSatisfiedForBav =
      !aadhaarPanLinkActive || !panAadhaarLinkMandatory || panAadhaarLinkStatus == KycStepStatus.verified;
  final idKycComplete = bothIdVerified && panAadhaarLinkSatisfiedForBav;
  KycStepStatus pennylessBavStatus;
  String pennylessBavPill;
  String pennylessBavSubtitle;
  if (!nameDobDone || !panAadhaarLinkSatisfiedForBav) {
    pennylessBavStatus = KycStepStatus.locked;
    pennylessBavPill = 'Locked';
    pennylessBavSubtitle = !nameDobDone
        ? 'Unlocks after Name & DOB Match clears'
        : 'Unlocks after PAN-Aadhaar Link is verified';
  } else if (latestBav != null && latestBav.isApproved) {
    pennylessBavStatus = KycStepStatus.verified;
    pennylessBavPill = 'Verified';
    pennylessBavSubtitle = latestBav.accountLast4 != null ? 'Account ending ${latestBav.accountLast4}' : 'Penny-less BAV verified';
  } else if (latestBav != null && latestBav.status.toLowerCase() == 'rejected') {
    pennylessBavStatus = KycStepStatus.failed;
    pennylessBavPill = 'Retry';
    pennylessBavSubtitle = 'Bank verification failed. Please try again.';
  } else {
    pennylessBavStatus = KycStepStatus.actionable;
    pennylessBavPill = 'Initiate';
    pennylessBavSubtitle = 'Penny-less — no debit from your account';
  }

  final primaryAccounts = (bankAccounts ?? const <BankAccount>[]).where((a) => a.isPrimary);
  final fallbackCbankId = primaryAccounts.isEmpty ? null : primaryAccounts.first.idBank;
  final cbankId = latestBav?.cbankId ?? fallbackCbankId;

  // PAN-Bank Link sub-item
  final persistedPanBankLink = (verificationStatus?['pan_bank_link'] as Map?)?['status'] as String?;
  final panBankLinkMandatory = _isMandatory(verificationStatus, 'pan_bank_link');
  KycStepStatus panBankLinkStatus;
  String panBankLinkPill;
  String panBankLinkSubtitle;
  if (persistedPanBankLink == 'LINKED') {
    panBankLinkStatus = KycStepStatus.verified;
    // Label comes straight from the backend's own status string — same
    // reasoning as PAN-Aadhaar Link above.
    panBankLinkPill = _formatBackendStatusLabel(persistedPanBankLink!);
    panBankLinkSubtitle = 'Your PAN is linked to this bank account';
  } else if (persistedPanBankLink == 'NOT_LINKED') {
    panBankLinkStatus = KycStepStatus.failed;
    panBankLinkPill = _formatBackendStatusLabel(persistedPanBankLink!);
    panBankLinkSubtitle = panBankLinkMandatory
        ? 'Your PAN does not appear to be linked to this bank account'
        : 'Your PAN does not appear to be linked to this bank account. (Optional — this won\'t affect your account.)';
  } else if (!panBankLinkMandatory) {
    panBankLinkStatus = KycStepStatus.underReview;
    panBankLinkPill = 'Optional';
    panBankLinkSubtitle = 'This check isn\'t required right now.';
  } else {
    panBankLinkStatus = KycStepStatus.actionable;
    panBankLinkPill = persistedPanBankLink == 'PENDING' ? 'Retry' : 'Check Now';
    panBankLinkSubtitle = 'Check whether your PAN is linked to this bank account';
  }

  // Reverse Penny Drop (RPD) sub-item
  final rpdMandatory = _isMandatory(verificationStatus, 'reverse_penny_drop');
  final sortedRpd = (rpdHistory ?? const <RpdHistoryItem>[]).where((r) => cbankId != null && r.cbankId == cbankId).toList()
    ..sort((a, b) => (b.createdOn ?? DateTime(0)).compareTo(a.createdOn ?? DateTime(0)));
  final latestRpd = sortedRpd.isEmpty ? null : sortedRpd.first;
  KycStepStatus rpdStatus;
  String rpdPill;
  String rpdSubtitle;
  if (latestRpd != null && latestRpd.status.toLowerCase() == 'success') {
    rpdStatus = KycStepStatus.verified;
    rpdPill = 'Verified';
    rpdSubtitle = 'Ownership confirmed';
  } else if (latestRpd != null && latestRpd.status.toLowerCase() == 'failed') {
    rpdStatus = KycStepStatus.failed;
    rpdPill = 'Retry';
    rpdSubtitle = latestRpd.failureReason ?? 'Additional verification failed. Please try again.';
  } else if (cbankId == null) {
    rpdStatus = KycStepStatus.locked;
    rpdPill = 'Locked';
    rpdSubtitle = 'Add a bank account to continue';
  } else {
    rpdStatus = KycStepStatus.actionable;
    rpdPill = 'Start';
    rpdSubtitle = 'Confirm ownership with a ₹1 transfer from your bank app';
  }

  // Composite Bank Account Validation status
  final panBankLinkSatisfied = !panBankLinkActive || !panBankLinkMandatory || panBankLinkStatus == KycStepStatus.verified;
  final rpdSatisfied = !rpdActive || !rpdMandatory || rpdStatus == KycStepStatus.verified;
  final KycStepStatus bavStatus;
  final String bavPill;
  final String bavSubtitle;
  if (pennylessBavStatus != KycStepStatus.verified) {
    bavStatus = pennylessBavStatus;
    bavPill = pennylessBavPill;
    bavSubtitle = pennylessBavSubtitle;
  } else if (panBankLinkSatisfied && rpdSatisfied) {
    bavStatus = KycStepStatus.verified;
    bavPill = 'Verified';
    bavSubtitle = pennylessBavSubtitle;
  } else {
    bavStatus = KycStepStatus.underReview;
    bavPill = 'In Progress';
    bavSubtitle = 'Complete the checks below to finish bank validation';
  }

  // Dynamic numbering/progress — hidden (VGR-inactive) capabilities don't
  // consume a step number or count toward the ring, and PAN-Bank
  // Link/RPD (BAV sub-items) don't factor into top-level progress at all:
  // BAV counts done as soon as BAV itself is approved.
  int total = 0;
  int completed = 0;
  void tally(KycStepStatus status) {
    total++;
    if (status == KycStepStatus.verified) completed++;
  }

  if (digilockerActive) {
    tally(panStatus);
    tally(aadhaarStatus);
  }
  tally(nameDobStatus);
  if (aadhaarPanLinkActive) {
    tally(panAadhaarLinkStatus);
  }
  tally(bavStatus);

  return KycStepStatuses(
    panDone: panDone,
    aadhaarDone: aadhaarDone,
    bothIdVerified: bothIdVerified,
    idKycComplete: idKycComplete,
    panDocValue: panDocValue,
    panSkippedInConsent: panSkippedInConsent,
    panStatus: panStatus,
    panPill: panPill,
    aadhaarStatus: aadhaarStatus,
    aadhaarPill: aadhaarPill,
    nameDobStatus: nameDobStatus,
    nameDobPill: nameDobPill,
    nameDobSubtitle: nameDobSubtitle,
    panAadhaarLinkMandatory: panAadhaarLinkMandatory,
    panAadhaarLinkStatus: panAadhaarLinkStatus,
    panAadhaarLinkPill: panAadhaarLinkPill,
    panAadhaarLinkSubtitle: panAadhaarLinkSubtitle,
    panBankLinkMandatory: panBankLinkMandatory,
    panBankLinkStatus: panBankLinkStatus,
    panBankLinkPill: panBankLinkPill,
    panBankLinkSubtitle: panBankLinkSubtitle,
    rpdMandatory: rpdMandatory,
    rpdStatus: rpdStatus,
    rpdPill: rpdPill,
    rpdSubtitle: rpdSubtitle,
    pennylessBavStatus: pennylessBavStatus,
    pennylessBavPill: pennylessBavPill,
    pennylessBavSubtitle: pennylessBavSubtitle,
    bavStatus: bavStatus,
    bavPill: bavPill,
    bavSubtitle: bavSubtitle,
    digilockerActive: digilockerActive,
    aadhaarPanLinkActive: aadhaarPanLinkActive,
    panBankLinkActive: panBankLinkActive,
    rpdActive: rpdActive,
    cbankId: cbankId,
    latestBav: latestBav,
    latestRpd: latestRpd,
    completed: completed,
    total: total,
  );
}

/// Profile page's "N/total done" badge — same underlying, already-fetched
/// providers the checklist screen watches, run through the SAME
/// [computeKycStepStatuses] so the two screens can never disagree on what
/// counts as done. Null while the core doc-types fetch hasn't resolved yet;
/// callers fall back to their existing display in that case.
final kycProgressProvider = Provider.autoDispose<({int completed, int total})?>((ref) {
  final docs = ref.watch(kycDocumentsProvider('profile')).valueOrNull;
  if (docs == null) return null;
  final aadhaarState = ref.watch(aadhaarProvider);
  final verificationStatus = ref.watch(verificationStatusProvider).valueOrNull;
  final bankAccounts = ref.watch(bankAccountsProvider).valueOrNull;
  final bavHistory = ref.watch(bavHistoryProvider).valueOrNull;
  final rpdHistory = ref.watch(rpdHistoryProvider).valueOrNull;
  final statuses = computeKycStepStatuses(
    docsResult: docs,
    aadhaarState: aadhaarState,
    verificationStatus: verificationStatus,
    bankAccounts: bankAccounts,
    bavHistory: bavHistory,
    rpdHistory: rpdHistory,
  );
  return (completed: statuses.completed, total: statuses.total);
});
