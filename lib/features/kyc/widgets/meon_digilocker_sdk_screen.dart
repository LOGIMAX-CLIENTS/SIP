import 'package:flutter/material.dart';
import 'package:flutter_digilocker_aadhar_pan/flutter_digilocker_aadhar_pan.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/core/security/secure_logger.dart';

/// Hosts the Meon DigiLocker Flutter SDK for Aadhaar + PAN verification —
/// a THIRD Aadhaar provider path alongside [AadhaarDigilockerWebView]
/// (Cashfree webview) and `DigilockerSdkScreen` (SurePass native SDK).
///
/// Unlike SurePass's native SDK, Meon's package does not take a short-lived
/// per-session token — `DigiLockerConfig` wants the long-lived
/// `companyName` + `secretToken` merchant credentials directly. Those are
/// NOT fetched through `GatewayFactory`/`initiate_digilocker()` like the
/// other two providers (that abstraction only ever normalizes to a
/// consent_url OR a short-lived sdk_token — Meon's package fits neither
/// shape). Instead the caller must fetch them via a dedicated backend call
/// (`KycRepository.getMeonSdkConfig()` -> `kyc/meon-sdk-config`) and pass
/// them in here.
///
/// SECURITY NOTE (do not remove without re-reading): `secretToken` is a
/// permanent, shared MERCHANT credential — not scoped to this user or this
/// session. Once it reaches this screen it is resident in the app's memory
/// and process, and any single install of this app can have it extracted
/// (network capture or binary/memory inspection) — unlike SurePass's token,
/// which is short-lived and single-session, a leaked Meon secretToken lets
/// an attacker originate DigiLocker requests under this company's identity
/// indefinitely, for every user, until it's rotated backend-side. Fetching
/// it fresh from the backend (rather than hardcoding it in Dart source)
/// avoids putting it in source control / the compiled binary as a static
/// string, but does NOT eliminate this exposure — it is inherent to how
/// Meon's package is designed to be used. This was an explicit, informed
/// tradeoff (see conversation) in exchange for native in-app UX instead of
/// the WebView flow, which does not have this exposure at all.
///
/// Route: `AppRouter.meonDigilockerSdk` ('/meon-digilocker-sdk').
/// Arguments: `{'companyName': String, 'secretToken': String,
/// 'redirectUrl': String, 'panName': String?, 'panNo': String?}`.
class MeonDigilockerSdkScreen extends StatefulWidget {
  final String companyName;
  final String secretToken;
  final String redirectUrl;
  final String? panName;
  final String? panNo;

  const MeonDigilockerSdkScreen({
    super.key,
    required this.companyName,
    required this.secretToken,
    required this.redirectUrl,
    this.panName,
    this.panNo,
  });

  @override
  State<MeonDigilockerSdkScreen> createState() => _MeonDigilockerSdkScreenState();
}

class _MeonDigilockerSdkScreenState extends State<MeonDigilockerSdkScreen> {
  bool _showWidget = true;
  String? _errorMessage;

  DigiLockerConfig get _config => DigiLockerConfig(
        companyName: widget.companyName,
        secretToken: widget.secretToken,
        redirectUrl: widget.redirectUrl,
        documents: 'aadhaar,pan',
        panName: widget.panName ?? '',
        panNo: widget.panNo ?? '',
      );

  void _handleSuccess(DigiLockerResponse response) {
    SecureLogger.d('[Meon DigiLocker SDK] completed: success=${response.success}');
    if (!mounted) return;
    Navigator.pop(context, response.success);
  }

  void _handleError(String message) {
    SecureLogger.e('[Meon DigiLocker SDK] error (not shown verbatim): $message');
    if (!mounted) return;
    setState(() {
      _showWidget = false;
      _errorMessage = 'DigiLocker verification could not be completed. Please try again.';
    });
  }

  void _retry() {
    setState(() {
      _showWidget = true;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          const GradientHeader(title: 'Aadhaar Verification'),
          Expanded(
            child: _showWidget
                ? Stack(
                    children: [
                      DigiLockerWidget(
                        config: _config,
                        onSuccess: _handleSuccess,
                        onError: _handleError,
                        onClose: () {
                          if (!mounted) return;
                          Navigator.pop(context, false);
                        },
                      ),
                    ],
                  )
                : Center(
                    child: Padding(
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
                                onPressed: _retry,
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
