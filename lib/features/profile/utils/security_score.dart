/// The App Security banner's protection score — a pure function of the
/// customer's current settings, so the banner and its unit test can never
/// disagree on what a given combination is worth.
///
///   Biometric ON  + Auto-Lock ≤ 30s → 100% (Fully protected)
///   Biometric ON  + Auto-Lock > 30s →  90%
///   Biometric OFF + Auto-Lock ≤ 30s →  50%
///   Biometric OFF + Auto-Lock > 30s →  40%
///   MPIN off (Auto-Lock never fires) →  40%
class SecurityScore {
  final int percent;
  final String headline;

  /// Shown under the headline — what's active, or the next step to 100%.
  final String message;

  /// One word for the strength bar's label (Strong / Good / Fair / Weak).
  final String strengthLabel;

  const SecurityScore({
    required this.percent,
    required this.headline,
    required this.message,
    required this.strengthLabel,
  });

  bool get isFull => percent == 100;
}

/// Auto-Lock at or below this (including "Immediately") counts as a short
/// lock for the score.
const int kStrongAutoLockSeconds = 30;

SecurityScore computeSecurityScore({
  required bool mpinEnabled,
  required bool biometricOn,
  required int timeoutSeconds,
}) {
  final shortLock = timeoutSeconds <= kStrongAutoLockSeconds;

  // Biometric ON forces MPIN on, so MPIN off always means biometric off too.
  if (!mpinEnabled) {
    return const SecurityScore(
      percent: 40,
      headline: 'Partially protected',
      message: 'Set up your MPIN and turn on Biometric Login.',
      strengthLabel: 'Weak',
    );
  }
  if (biometricOn && shortLock) {
    return const SecurityScore(
      percent: 100,
      headline: 'Fully protected',
      message: 'All security layers are active',
      strengthLabel: 'Strong',
    );
  }
  if (biometricOn) {
    return const SecurityScore(
      percent: 90,
      headline: 'Well protected',
      message: 'Set Auto-Lock on Exit to 30 sec or less for full protection.',
      strengthLabel: 'Good',
    );
  }
  return SecurityScore(
    percent: shortLock ? 50 : 40,
    headline: 'Partially protected',
    message: 'Turn on Biometric Login to strengthen protection.',
    strengthLabel: shortLock ? 'Fair' : 'Weak',
  );
}
