import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';

/// Hosts the Cashfree DigiLocker consent page for Aadhaar verification.
///
/// The backend's `_initiate_aadhaar_kyc()` (kyc.py) passes an https://
/// redirect_url to Cashfree (Cashfree rejects custom app schemes outright —
/// "redirect_url should start with https."), containing the path segment
/// `/kyc/digilocker-callback`. This screen matches on that path substring
/// via NavigationDelegate below and intercepts the request before the
/// WebView actually loads it — the URL never needs to resolve to a real
/// page. There is no manual fallback button; consent-page variants that
/// don't honor redirect_url will never resolve this screen.
/// The caller (the unified KYC hub) is responsible for polling the backend
/// after this screen returns `true`.
///
/// Route: `AppRouter.aadhaarVerification` ('/aadhaar-verification').
/// Arguments: `{'consentUrl': String}`.
class AadhaarDigilockerWebView extends StatefulWidget {
  final String consentUrl;

  const AadhaarDigilockerWebView({super.key, required this.consentUrl});

  @override
  State<AadhaarDigilockerWebView> createState() =>
      _AadhaarDigilockerWebViewState();
}

class _AadhaarDigilockerWebViewState extends State<AadhaarDigilockerWebView> {
  static const _callbackPathSegment = '/kyc/digilocker-callback';

  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            if (request.url.contains(_callbackPathSegment)) {
              Navigator.pop(context, true);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.consentUrl));
    _enableThirdPartyCookies();
  }

  /// DigiLocker's consent flow hands off between digilocker.gov.in and
  /// Cashfree's domain; Android's WebView blocks third-party cookies by
  /// default (this is opt-in, not automatic), which silently breaks that
  /// cross-domain session handoff and can stall the page after account
  /// selection with no visible error.
  Future<void> _enableThirdPartyCookies() async {
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      final cookieManager = WebViewCookieManager();
      if (cookieManager.platform is AndroidWebViewCookieManager) {
        await (cookieManager.platform as AndroidWebViewCookieManager)
            .setAcceptThirdPartyCookies(platform, true);
      }
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
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading) const Center(child: CircularProgressIndicator()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
