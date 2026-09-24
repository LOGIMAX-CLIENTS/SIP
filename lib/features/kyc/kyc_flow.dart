import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/features/profile/profile_controller.dart' as pc;
import 'package:startgold/routes/app_router.dart';

/// Single entry point for "the backend returned KYC_REQUIRED" across SIP,
/// Withdrawal, and Investment.
///
/// Pushes the KYC checklist (`kyc_verification_screen.dart` — PAN +
/// Aadhaar verification, plus bank-verification steps this gate doesn't
/// care about) with `popWhenIdVerified: true`, so it pops itself with
/// `true` the instant PAN and Aadhaar are both APPROVED rather than
/// leaving the user on the checklist to walk the remaining steps. Every
/// caller uses the same `await ... ; if (result) retryTheOriginalAction()`
/// shape, mirroring the pattern instant_saving_screen.dart already used for
/// PAN-only KYC — this just centralizes it so SIP/Withdrawal/Investment
/// stay consistent instead of each re-implementing the push/await.
class KycVerificationFlow {
  /// Returns true once the user has completed BOTH PAN and Aadhaar
  /// verification. Returns false if the user backs out before finishing.
  static Future<bool> start(
    BuildContext context,
    WidgetRef ref, {
    required String requestFrom,
    Map<String, dynamic>? extraData,
  }) async {
    final result = await Navigator.pushNamed(
      context,
      AppRouter.kycVerification,
      arguments: {
        'request_from': requestFrom,
        'pop_when_id_verified': true,
        ...?extraData,
      },
    );

    final completed = result == true;
    if (completed) {
      // Best-effort refresh so the Profile screen's "Verified" pill and
      // kycStatus flag reflect the verification that just completed.
      try {
        await ref.read(pc.profileProvider.notifier).fetchProfileDetails();
      } catch (_) {
        // Non-critical — the profile screen re-fetches on its own next
        // visit regardless.
      }
    }
    return completed;
  }
}
