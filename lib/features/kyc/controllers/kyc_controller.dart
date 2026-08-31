import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/core/error/failures.dart';
import 'package:startgold/core/providers/user_provider.dart';
import 'package:startgold/core/security/secure_logger.dart';
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
  awaitingConsent, // consent_url ready (Cashfree) — hub should open the DigiLocker WebView
  awaitingSdk, // sdk_token ready (SurePass) — hub should launch the native DigiLocker Flutter SDK
  polling,
  // CONFIRM_NAME_UPDATE from the backend (KYC_NAME_MISMATCH_RESOLUTION) —
  // Aadhaar verified fine, but the verified name/DOB don't match the
  // profile on file. Not a failure: verificationId stays valid, and
  // AadhaarNotifier.confirmNameMismatch() resolves it without restarting
  // DigiLocker consent. See AadhaarState.aadhaarMismatchPrompt below for
  // the prompt's data.
  awaitingNameMismatchConfirm,
  approved,
  expired,
  rejected,
  failed,
}

/// Shared shape of a CONFIRM_NAME_UPDATE prompt (backend
/// `KYCService._confirm_name_update_prompt`) — identical for AADHAAR's own
/// mismatch (surfaced as AadhaarState.aadhaarMismatchPrompt, resolved via
/// AadhaarNotifier.confirmNameMismatch) and for PAN's mismatch piggybacked
/// onto an Aadhaar poll response (AadhaarState.panMismatchPrompt, resolved
/// via KycRepository.confirmPanNameMismatch using [verificationId] as
/// pan_kyc_id — PAN has no poll cycle of its own to attach a
/// verification_id to, so the backend reuses the same field name for its
/// own dedicated PAN KYC row id instead). [verifiedName]/[verifiedDob] are
/// what the document says; [profileName]/[profileDob] are what's actually
/// on file (Customer.cus_name/cus_dob) to compare against.
class NameMismatchPrompt {
  final String document; // 'AADHAAR' | 'PAN'
  final String verificationId;
  final String? verifiedName;
  final String? verifiedDob;
  final String? profileName;
  final String? profileDob;
  final String? message;

  const NameMismatchPrompt({
    required this.document,
    required this.verificationId,
    this.verifiedName,
    this.verifiedDob,
    this.profileName,
    this.profileDob,
    this.message,
  });

  factory NameMismatchPrompt.fromJson(Map<String, dynamic> json) {
    return NameMismatchPrompt(
      document: (json['document'] ?? '').toString(),
      verificationId: (json['verification_id'] ?? '').toString(),
      verifiedName: json['verified_name']?.toString(),
      verifiedDob: json['verified_dob']?.toString(),
      profileName: json['profile_name']?.toString(),
      profileDob: json['profile_dob']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

class AadhaarState {
  final AadhaarPhase phase;
  final String? verificationId;
  final String? consentUrl;
  // SurePass SDK-flow fields — populated instead of consentUrl when the
  // active backend gateway is SurePass (see kyc.py's initiate_digilocker
  // branch: providers report EITHER a consent_url (Cashfree) OR an
  // sdk_token+provider_client_id (SurePass), never both.
  final String? sdkToken;
  final String? providerClientId;
  final int? sdkTokenExpirySeconds;
  final String? sdkEnvironment; // "SANDBOX" | "PRODUCTION" — which base URL issued sdkToken
  final String? message;
  final String? maskedNumber;
  final String? verifiedName;
  // Same "not returned by the backend yet" caveat as KycDocumentsResult.aadhaarDob
  // (kyc_document.dart) — carried here purely so it flows into the profile
  // selection dialog once the backend adds it.
  final String? verifiedDob;
  // Populated only in AadhaarPhase.awaitingNameMismatchConfirm — see
  // NameMismatchPrompt's doc comment.
  final NameMismatchPrompt? aadhaarMismatchPrompt;
  // Populated whenever an Aadhaar poll response (APPROVED, already-approved,
  // or even REJECTED — see KYCService._pan_status_response_extras, called
  // from all three) carries pan_status: "PENDING_CONFIRMATION" alongside its
  // own status. Independent of [phase]/[aadhaarMismatchPrompt] — Aadhaar and
  // PAN mismatches are resolved through entirely separate requests (see
  // NameMismatchPrompt's doc comment) and can occur together or alone.
  final NameMismatchPrompt? panMismatchPrompt;

  const AadhaarState({
    this.phase = AadhaarPhase.idle,
    this.verificationId,
    this.consentUrl,
    this.sdkToken,
    this.providerClientId,
    this.sdkTokenExpirySeconds,
    this.sdkEnvironment,
    this.message,
    this.maskedNumber,
    this.verifiedName,
    this.verifiedDob,
    this.aadhaarMismatchPrompt,
    this.panMismatchPrompt,
  });

  AadhaarState copyWith({
    AadhaarPhase? phase,
    String? verificationId,
    String? consentUrl,
    String? sdkToken,
    String? providerClientId,
    int? sdkTokenExpirySeconds,
    String? sdkEnvironment,
    String? message,
    String? maskedNumber,
    String? verifiedName,
    String? verifiedDob,
    NameMismatchPrompt? aadhaarMismatchPrompt,
    NameMismatchPrompt? panMismatchPrompt,
  }) {
    return AadhaarState(
      phase: phase ?? this.phase,
      verificationId: verificationId ?? this.verificationId,
      consentUrl: consentUrl ?? this.consentUrl,
      sdkToken: sdkToken ?? this.sdkToken,
      providerClientId: providerClientId ?? this.providerClientId,
      sdkTokenExpirySeconds: sdkTokenExpirySeconds ?? this.sdkTokenExpirySeconds,
      sdkEnvironment: sdkEnvironment ?? this.sdkEnvironment,
      message: message ?? this.message,
      aadhaarMismatchPrompt: aadhaarMismatchPrompt ?? this.aadhaarMismatchPrompt,
      panMismatchPrompt: panMismatchPrompt ?? this.panMismatchPrompt,
      maskedNumber: maskedNumber ?? this.maskedNumber,
      verifiedName: verifiedName ?? this.verifiedName,
      verifiedDob: verifiedDob ?? this.verifiedDob,
    );
  }
}

final aadhaarProvider =
    StateNotifierProvider.autoDispose<AadhaarNotifier, AadhaarState>((ref) {
  return AadhaarNotifier(ref.read(kycRepositoryProvider), ref);
});

class AadhaarNotifier extends StateNotifier<AadhaarState> {
  final KycRepository _repository;
  final Ref _ref;
  KeepAliveLink? _keepAliveLink;

  AadhaarNotifier(this._repository, this._ref) : super(const AadhaarState());

  /// Blocks aadhaarProvider's .autoDispose teardown for the duration of the
  /// initiate -> consent/SDK sub-screen -> poll sequence. Without this, the
  /// provider can lose its listener and be disposed while the pushed
  /// sub-screen is on top — most reliably reproduced with SurePass's native
  /// DigiLocker SDK, which runs in its own Android Activity and triggers a
  /// real onPause/onResume on the host Activity — and a poll response that
  /// arrives after that silently no-ops via this notifier's own `mounted`
  /// guard, dropping CONFIRM_NAME_UPDATE/APPROVED/etc. with no error shown.
  /// Call from the widget alongside AppLifecycleObserver.suppressAppLock
  /// (same try/finally scope — see kyc_screen.dart's _runVerifyAadhaar).
  void pauseAutoDispose() {
    _keepAliveLink ??= _ref.keepAlive();
  }

  /// Releases the link acquired by [pauseAutoDispose] so the provider goes
  /// back to disposing normally once the flow ends (success, failure, or the
  /// user backing out) — must be called in every case, hence the finally
  /// block pairing at the call site.
  void resumeAutoDispose() {
    _keepAliveLink?.close();
    _keepAliveLink = null;
  }

  /// Shown to the user instead of ANY backend/provider exception, gateway
  /// error, or network failure — never the technical detail itself. That
  /// detail is only ever logged via [SecureLogger] for debugging.
  static const _temporaryIssueMessage =
      "We're currently experiencing a temporary technical service issue. "
      "Please try again later or contact your administrator.";

  /// The backend already returns a clean, user-facing message for every
  /// known Aadhaar failure path — this is a defensive fallback so that if
  /// something else ever throws a raw technical exception (e.g. a gateway
  /// error string like "CASHFREE API error: 422 — {...}", or an unhandled
  /// Dio/network exception), the Aadhaar card never displays it verbatim.
  static final _technicalErrorPattern = RegExp(
    r'API error:\s*\d{3}|status(Code)?\s*[:=]?\s*\d{3}|error code:\s*\d{3}|'
    r'DioException|SocketException|TimeoutException|HandshakeException',
    caseSensitive: false,
  );

  String _sanitizeErrorMessage(Object e) {
    // A deliberate 4xx business response (NAME_MISMATCH, REJECTED, EXPIRED,
    // PROFILE_NAME_MISMATCH, etc.) — ApiClient maps every non-2xx response
    // to a Failure, so without this check a real, backend-authored,
    // safe-to-show message (e.g. "Your profile name and/or date of birth
    // doesn't match your Aadhaar record...") was being discarded below and
    // replaced with the generic technical-issue string, regardless of the
    // real reason. Only 4xx is trusted here — a 5xx is still an
    // infrastructure fault, not a business message.
    if (e is ServerFailure && e.statusCode != null && e.statusCode! >= 400 && e.statusCode! < 500) {
      return e.message;
    }
    // Network/provider-infrastructure failures (timeouts, 5xx, connection
    // drops, SSL errors) never carry a message safe to show verbatim.
    if (e is Failure) {
      SecureLogger.e('[Aadhaar] technical error (not shown to user)', e);
      return _temporaryIssueMessage;
    }
    final raw = e.toString().replaceFirst('Exception: ', '');
    if (_technicalErrorPattern.hasMatch(raw)) {
      SecureLogger.e('[Aadhaar] technical error (not shown to user)', e);
      return _temporaryIssueMessage;
    }
    return raw;
  }

  /// `pan_confirmation` (see NameMismatchPrompt's doc comment) is only
  /// present when `data['pan_status'] == 'PENDING_CONFIRMATION'` — every
  /// other pan_status either has no such prompt or isn't relevant here.
  static NameMismatchPrompt? _extractPanMismatchPrompt(Map<String, dynamic> data) {
    if (data['pan_status'] != 'PENDING_CONFIRMATION') return null;
    final raw = data['pan_confirmation'];
    if (raw is! Map) return null;
    return NameMismatchPrompt.fromJson(Map<String, dynamic>.from(raw));
  }

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
    bool allowReverify = false,
  }) async {
    state = state.copyWith(phase: AadhaarPhase.initiating, message: null);
    try {
      final data = await _repository.initiateAadhaar(
        requestFrom: requestFrom,
        aadhaarNumber: aadhaarNumber,
        fullName: fullName,
        allowReverify: allowReverify,
      );
      // See the identical guard in pollUntilTerminal — this notifier can be
      // disposed while the request above was in flight (e.g. a 401 sends it
      // through the interceptor's refresh-and-retry detour).
      if (!mounted) return;
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

      if (status == 'PENDING' && data['sdk_token'] != null) {
        state = state.copyWith(
          phase: AadhaarPhase.awaitingSdk,
          verificationId: data['verification_id']?.toString(),
          sdkToken: data['sdk_token'].toString(),
          providerClientId: data['provider_client_id']?.toString(),
          sdkTokenExpirySeconds: data['sdk_token_expiry_seconds'] is num
              ? (data['sdk_token_expiry_seconds'] as num).toInt()
              : null,
          sdkEnvironment: data['sdk_environment']?.toString(),
          message: data['message']?.toString(),
        );
        return;
      }

      // Some providers (SurePass) can resolve the whole check synchronously
      // within the initiate call itself — no consent_url/sdk_token round
      // trip at all — so CONFIRM_NAME_UPDATE can arrive here too, not just
      // from pollUntilTerminal's matching case below. Without this branch it
      // fell into the generic `failed` case, showing the message as a plain
      // error toast instead of opening the mismatch dialog.
      if (status == 'CONFIRM_NAME_UPDATE') {
        state = state.copyWith(
          phase: AadhaarPhase.awaitingNameMismatchConfirm,
          aadhaarMismatchPrompt: NameMismatchPrompt.fromJson(data),
          message: data['message']?.toString(),
        );
        return;
      }

      state = state.copyWith(
        phase: AadhaarPhase.failed,
        message: data['message']?.toString() ?? 'Unable to start Aadhaar verification.',
      );
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(phase: AadhaarPhase.failed, message: _sanitizeErrorMessage(e));
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
        // The KYC screen (and this autoDispose notifier with it) can be torn
        // down while this await was in flight — e.g. a 401 mid-poll sends
        // the request through the interceptor's silent refresh-and-retry
        // detour, which is slow enough for the screen to unmount before it
        // resolves. Touching `state` after that throws "Bad state: Tried to
        // use AadhaarNotifier after dispose was called" instead of just
        // discarding the now-irrelevant result.
        SecureLogger.d('[KYC DEBUG] pollUntilTerminal response received, mounted=$mounted, status=${data['status']}');
        if (!mounted) return;
        final status = (data['status'] ?? '').toString();
        // Piggybacked PAN mismatch — independent of Aadhaar's own status
        // below (see panMismatchPrompt's doc comment); extracted once here
        // so every branch that can carry it picks it up the same way.
        final panMismatchPrompt = _extractPanMismatchPrompt(data);

        if (data['is_already_approved'] == true || status == 'already approved') {
          state = state.copyWith(phase: AadhaarPhase.approved, panMismatchPrompt: panMismatchPrompt);
          return;
        }

        switch (status) {
          case 'APPROVED':
            state = state.copyWith(phase: AadhaarPhase.approved, panMismatchPrompt: panMismatchPrompt);
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
              panMismatchPrompt: panMismatchPrompt,
            );
            return;
          case 'CONFIRM_NAME_UPDATE':
            state = state.copyWith(
              phase: AadhaarPhase.awaitingNameMismatchConfirm,
              aadhaarMismatchPrompt: NameMismatchPrompt.fromJson(data),
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
            SecureLogger.e('[Aadhaar] unexpected DigiLocker status (not shown to user): $status');
            state = state.copyWith(
              phase: AadhaarPhase.failed,
              message: data['message']?.toString() ?? _temporaryIssueMessage,
            );
            return;
        }
      } catch (e) {
        if (!mounted) return;
        state = state.copyWith(phase: AadhaarPhase.failed, message: _sanitizeErrorMessage(e));
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

  /// Resets to idle so the user can restart consent after EXPIRED/REJECTED,
  /// or to redo verification from the "Edit" action on an approved card.
  void reset() => state = const AadhaarState();

  /// Seeds the card as already-approved from the server's per-document
  /// status check (`kyc/document-types`'s `aadhaar_status`/`aadhaar_masked_number`/
  /// `aadhaar_name` — see kyc_screen.dart) — skips the form entirely, no
  /// DigiLocker round trip. [maskedNumber]/[name] are shown on the verified
  /// card instead of a bare "Verified" badge.
  void seedApproved({String? maskedNumber, String? name, String? dob}) {
    if (state.phase == AadhaarPhase.idle) {
      state = state.copyWith(
        phase: AadhaarPhase.approved,
        maskedNumber: maskedNumber,
        verifiedName: name,
        verifiedDob: dob,
      );
    }
  }

  /// Syncs the masked number/name shown on the verified card after a LIVE
  /// approval this session (first-time or via Edit/reverify) — unlike
  /// [seedApproved], applies regardless of current phase, since
  /// `pollUntilTerminal`'s APPROVED case only flips the phase and doesn't
  /// carry these display fields itself (see kyc_screen.dart's
  /// _checkAndHandleCompletion, which re-fetches document-types and calls
  /// this right after).
  void updateVerifiedDetails({String? maskedNumber, String? name, String? dob}) {
    state = state.copyWith(maskedNumber: maskedNumber, verifiedName: name, verifiedDob: dob);
  }

  /// Resubmits the customer's corrected name/DOB after a
  /// CONFIRM_NAME_UPDATE prompt (see pollUntilTerminal's matching case) —
  /// same verificationId, no fresh DigiLocker round trip. The backend
  /// re-validates [name]/[dob] against the Aadhaar record it already
  /// fetched (KYCService._validate_mismatch_resubmission) and, on match,
  /// applies them to the profile AND approves the row in that same call
  /// (KYCService._finalize_name_mismatch_confirmation) — no separate
  /// updateProfileName/updateProfileDob call needed here, unlike the
  /// post-completion _VerifiedDetailsDialog flow in kyc_screen.dart.
  Future<(NameMismatchOutcome, String?)> confirmNameMismatch(
    String requestFrom, {
    required String name,
    required String dob,
  }) async {
    final verificationId = state.verificationId;
    if (verificationId == null) {
      const msg = 'Aadhaar verification session missing. Please restart.';
      state = state.copyWith(phase: AadhaarPhase.failed, message: msg);
      return (NameMismatchOutcome.failed, msg);
    }
    try {
      final data = await _repository.pollAadhaar(
        requestFrom: requestFrom,
        verificationId: verificationId,
        confirmNameUpdate: true,
        name: name,
        dob: dob,
      );
      if (!mounted) return (NameMismatchOutcome.failed, null);
      final status = (data['status'] ?? '').toString();
      if (status == 'APPROVED') {
        state = state.copyWith(phase: AadhaarPhase.approved);
        return (NameMismatchOutcome.resolved, null);
      }
      // Unexpected non-APPROVED, non-thrown status — treat the same as a
      // continued mismatch (let the dialog offer a retry) rather than a
      // hard failure; the verification_id/session is still alive.
      final msg = data['message']?.toString();
      return (NameMismatchOutcome.stillMismatched, msg);
    } catch (e) {
      if (!mounted) return (NameMismatchOutcome.failed, null);
      // The common case: backend rejects with NAME_MISMATCH (still doesn't
      // match) as a thrown Exception, not a data payload — same
      // "let the customer retry" treatment as above.
      return (NameMismatchOutcome.stillMismatched, _sanitizeErrorMessage(e));
    }
  }
}

/// Outcome of [AadhaarNotifier.confirmNameMismatch].
enum NameMismatchOutcome { resolved, stillMismatched, failed }

