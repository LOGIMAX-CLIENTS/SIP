import 'package:flutter/material.dart';
import 'package:digilocker_flutter_sdk/digilocker_sdk.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/core/security/secure_logger.dart';

/// Hosts the SurePass DigiLocker Flutter SDK for Aadhaar verification —
/// the SurePass-provider counterpart to [AadhaarDigilockerWebView]
/// (Cashfree's webview consent flow).
///
/// The backend's `initiate_digilocker()` (SurePassVerificationGateway) hands
/// back a short-lived (~10 min) SDK token instead of a consent URL — there
/// is no webview/redirect here. This screen initializes the native
/// `digilocker_flutter_sdk` package with that token; the package itself
/// pushes its own verification/webview screens on top of this one and pops
/// them internally, then calls back via onComplete/onError. This screen
/// pops itself with `true`/`false`/null on completion — same pop-result
/// contract the webview screen uses, so `kyc_screen.dart:_onVerifyAadhaar()`
/// treats both consistently.
///
/// Route: `AppRouter.digilockerSdk` ('/digilocker-sdk').
/// Arguments: `{'sdkToken': String, 'clientId': String?, 'environment': String?}`.
class DigilockerSdkScreen extends StatefulWidget {
  final String sdkToken;
  final String? clientId;
  final String? environment; // "SANDBOX" | "PRODUCTION" — from backend's initiate_digilocker()

  const DigilockerSdkScreen({
    super.key,
    required this.sdkToken,
    this.clientId,
    this.environment,
  });

  @override
  State<DigilockerSdkScreen> createState() => _DigilockerSdkScreenState();
}

class _DigilockerSdkScreenState extends State<DigilockerSdkScreen> {
  bool _launching = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _launchSdk());
  }

  Future<void> _launchSdk() async {
    setState(() {
      _launching = true;
      _errorMessage = null;
    });

    final env = widget.environment?.toUpperCase() == 'PRODUCTION'
        ? Environment.PROD
        : Environment.SANDBOX;

    await DigilockerSdk.start(
      context,
      apiToken: widget.sdkToken,
      environment: env,
      onComplete: (VerificationResult result) {
        SecureLogger.d('[DigiLocker SDK] completed: success=${result.success}');
        if (!mounted) return;
        Navigator.pop(context, result.success);
      },
      onError: (String message) {
        SecureLogger.e('[DigiLocker SDK] error (not shown verbatim): $message');
        if (!mounted) return;
        setState(() {
          _launching = false;
          _errorMessage = 'DigiLocker verification could not be completed. Please try again.';
        });
      },
    );

    // start() returns once its internal navigation stack has unwound (user
    // completed, failed, or backed out without onComplete/onError firing —
    // e.g. hardware back from the SDK's own screen). If neither callback
    // already popped this screen, treat it as a user cancellation.
    if (mounted && _launching) {
      Navigator.pop(context, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Aadhaar Verification'),
          Expanded(
            child: Center(
              child: _launching
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _errorMessage ?? 'DigiLocker verification could not be started.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              OutlinedButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('Close'),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                onPressed: _launchSdk,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
