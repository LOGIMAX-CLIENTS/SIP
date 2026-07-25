import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:startgold/features/profile/profile_controller.dart' as pc;
import 'package:startgold/routes/app_router.dart';

/// Single entry point for "the backend returned KYC_REQUIRED" across SIP,
/// Withdrawal, and Investment.
///
/// Pushes the unified KYC hub (`kyc_screen.dart` — PAN form + Aadhaar
/// DigiLocker, gated on both being APPROVED) and awaits its result. Every
/// caller uses the same `await ... ; if (result) retryTheOriginalAction()`
/// shape, mirroring the pattern instant_saving_screen.dart already used for
/// PAN-only KYC — this just centralizes it so SIP/Withdrawal/Investment
/// stay consistent instead of each re-implementing the push/await.
class KycVerificationFlow {
  /// Returns true once the user has completed BOTH PAN and Aadhaar
  /// verification (the hub only pops `true` when its "Finish" button —
  /// enabled only once both are approved — is pressed). Returns false if
  /// the user backs out before finishing.
  static Future<bool> start(
    BuildContext context,
    WidgetRef ref, {
    required String requestFrom,
    Map<String, dynamic>? extraData,
  }) async {
    final result = await Navigator.pushNamed(
      context,
      AppRouter.kyc,
      arguments: {
        'request_from': requestFrom,
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
