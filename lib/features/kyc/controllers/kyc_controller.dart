import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/core/providers/user_provider.dart';
import 'package:startgold/features/kyc/models/kyc_document.dart';
import 'package:startgold/features/kyc/repositories/kyc_repository.dart';

final kycDocumentsProvider = FutureProvider.autoDispose.family<KycDocumentsResult, String>((ref, requestFrom) async {
  final user = ref.watch(userProvider);
  if (user == null) return KycDocumentsResult(documents: [], aadhaarApproved: false);

  return ref.read(kycRepositoryProvider).getDocumentTypes(
    customerId: user.id,
    requestFrom: requestFrom,
  );
});

final kycSubmitProvider = StateNotifierProvider<KycSubmitController, AsyncValue<bool>>((ref) {
  return KycSubmitController(ref.read(kycRepositoryProvider), ref);
});

class KycSubmitController extends StateNotifier<AsyncValue<bool>> {
  final KycRepository _repository;
  final Ref _ref;

  KycSubmitController(this._repository, this._ref) : super(const AsyncValue.data(false));

  Future<void> submit({
    required String requestFrom,
    required String documentId,
    required Map<String, dynamic> fields,
  }) async {
    state = const AsyncValue.loading();
    try {
      final user = _ref.read(userProvider);
      final success = await _repository.uploadKyc(
        customerId: user!.id,
        requestFrom: requestFrom,
        documentId: documentId,
        fields: fields,
      );
      state = AsyncValue.data(success);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

// ─── Aadhaar / DigiLocker sub-flow ──────────────────────────────────────────
//
// Aadhaar is not a simple field-form submission like PAN — it's a two-step,
// poll-based flow (see KycRepository.initiateAadhaar/pollAadhaar, mirroring
// the backend's `_initiate_aadhaar_kyc` / `_check_aadhaar_kyc`). This
// notifier tracks that sub-flow's state so the unified KYC hub screen
// (kyc_screen.dart) can render the Aadhaar card independently of the PAN form.

enum AadhaarPhase {
  idle,
  initiating,
  awaitingConsent, // consent_url ready — hub should open the DigiLocker WebView
  polling,
  approved,
  expired,
  rejected,
  failed,
}

class AadhaarState {
  final AadhaarPhase phase;
  final String? verificationId;
  final String? consentUrl;
  final String? message;

  const AadhaarState({
    this.phase = AadhaarPhase.idle,
    this.verificationId,
    this.consentUrl,
    this.message,
  });

  AadhaarState copyWith({
    AadhaarPhase? phase,
    String? verificationId,
    String? consentUrl,
    String? message,
  }) {
    return AadhaarState(
      phase: phase ?? this.phase,
      verificationId: verificationId ?? this.verificationId,
      consentUrl: consentUrl ?? this.consentUrl,
      message: message ?? this.message,
    );
  }
}

final aadhaarProvider =
    StateNotifierProvider.autoDispose<AadhaarNotifier, AadhaarState>((ref) {
  return AadhaarNotifier(ref.read(kycRepositoryProvider));
});

class AadhaarNotifier extends StateNotifier<AadhaarState> {
  final KycRepository _repository;

  AadhaarNotifier(this._repository) : super(const AadhaarState());

  /// Step 1: request a DigiLocker consent session. If Aadhaar was already
  /// approved in a prior attempt, short-circuits straight to `approved`
  /// without ever calling Cashfree (see backend idempotency check).
  ///
  /// [aadhaarNumber] and [fullName] are what the user typed in on the hub
  /// screen. Both are REQUIRED by the backend (`_initiate_aadhaar_kyc`
  /// rejects the call with "Aadhaar number is required."/"Name is required
  /// for Aadhaar verification." if either is blank) — the caller must
  /// validate the form before invoking this. DigiLocker consent is still
  /// required on top of these for actual identity verification.
  Future<void> initiate(
    String requestFrom, {
    required String aadhaarNumber,
    required String fullName,
  }) async {
    state = state.copyWith(phase: AadhaarPhase.initiating, message: null);
    try {
      final data = await _repository.initiateAadhaar(
        requestFrom: requestFrom,
        aadhaarNumber: aadhaarNumber,
        fullName: fullName,
      );
      final status = (data['status'] ?? '').toString();

      if (data['is_already_approved'] == true || status == 'already approved') {
        state = state.copyWith(phase: AadhaarPhase.approved);
        return;
      }

      if (status == 'PENDING' && data['consent_url'] != null) {
        state = state.copyWith(
          phase: AadhaarPhase.awaitingConsent,
          verificationId: data['verification_id']?.toString(),
          consentUrl: data['consent_url'].toString(),
          message: data['message']?.toString(),
        );
        return;
      }

      state = state.copyWith(
        phase: AadhaarPhase.failed,
        message: data['message']?.toString() ?? 'Unable to start Aadhaar verification.',
      );
    } catch (e) {
      state = state.copyWith(phase: AadhaarPhase.failed, message: e.toString());
    }
  }

  /// Step 2: poll for the consent outcome after the user returns from the
  /// DigiLocker WebView. Retries on PENDING with a short backoff up to
  /// [maxAttempts] — DigiLocker document fetch can briefly return
  /// HTTP-202 "still processing" even after consent succeeds.
  Future<void> pollUntilTerminal(
    String requestFrom, {
    int maxAttempts = 10,
    Duration delay = const Duration(seconds: 2),
  }) async {
    final verificationId = state.verificationId;
    if (verificationId == null) {
      state = state.copyWith(
        phase: AadhaarPhase.failed,
        message: 'Aadhaar verification session missing. Please restart.',
      );
      return;
    }

    state = state.copyWith(phase: AadhaarPhase.polling, message: null);

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final data = await _repository.pollAadhaar(
          requestFrom: requestFrom,
          verificationId: verificationId,
        );
        final status = (data['status'] ?? '').toString();

        if (data['is_already_approved'] == true || status == 'already approved') {
          state = state.copyWith(phase: AadhaarPhase.approved);
          return;
        }

        switch (status) {
          case 'APPROVED':
            state = state.copyWith(phase: AadhaarPhase.approved);
            return;
          case 'EXPIRED':
            state = state.copyWith(
              phase: AadhaarPhase.expired,
              message: data['message']?.toString(),
            );
            return;
          case 'REJECTED':
            state = state.copyWith(
              phase: AadhaarPhase.rejected,
              message: data['message']?.toString(),
            );
            return;
          case 'PENDING':
            state = state.copyWith(message: data['message']?.toString());
            if (attempt < maxAttempts - 1) {
              await Future.delayed(delay);
            }
            continue;
          default:
            state = state.copyWith(
              phase: AadhaarPhase.failed,
              message: data['message']?.toString() ?? 'Unexpected status: $status',
            );
            return;
        }
      } catch (e) {
        state = state.copyWith(phase: AadhaarPhase.failed, message: e.toString());
        return;
      }
    }

    // Exhausted retries while still PENDING — not a failure, just needs the
    // user to try again shortly. verificationId is preserved so a retry
    // resumes polling instead of restarting the whole consent flow.
    state = state.copyWith(
      phase: AadhaarPhase.awaitingConsent,
      message: 'Aadhaar verification is taking longer than expected. Please try again in a moment.',
    );
  }

  /// Resets to idle so the user can restart consent after EXPIRED/REJECTED.
  void reset() => state = const AadhaarState();

  /// Seeds the card as already-approved from the server's per-document
  /// status check (`kyc/document-types`'s `aadhaar_status` — see
  /// kyc_screen.dart) — skips the form entirely, no DigiLocker round trip.
  void seedApproved() {
    if (state.phase == AadhaarPhase.idle) {
      state = state.copyWith(phase: AadhaarPhase.approved);
    }
  }
}

