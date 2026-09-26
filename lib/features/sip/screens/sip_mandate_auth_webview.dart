import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/security/secure_logger.dart';
import '../../../shared/widgets/gradient_header.dart';

/// Hosts the bank's net-banking page for an eNACH mandate authorisation.
///
/// [authUrl] is the link from the Cashfree AUTH the backend raised
/// (`enach_auth_link` — POST /pg/subscriptions/pay, payment_type AUTH), so it
/// opens straight on the customer's bank login with no bank picker.
///
/// When the bank finishes, Cashfree sends the browser to the subscription's
/// return_url — `/sip/subscription-verify` (see shared/services/sip.py
/// create_scheme). This screen intercepts that navigation and pops `true`;
/// the caller then confirms the mandate status with the backend. Backing out
/// pops `false`.
///
/// Links a bank page hands to its own app (intent://, upi:// …) are opened
/// outside the WebView, which can't load them.
class SipMandateAuthWebView extends StatefulWidget {
  final String authUrl;

  const SipMandateAuthWebView({super.key, required this.authUrl});

  @override
  State<SipMandateAuthWebView> createState() => _SipMandateAuthWebViewState();
}

class _SipMandateAuthWebViewState extends State<SipMandateAuthWebView> {
  static const _returnPathSegment = '/sip/subscription-verify';

  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            if (request.url.contains(_returnPathSegment)) {
              SecureLogger.d('SIP MANDATE WEBVIEW: return_url reached');
              Navigator.pop(context, true);
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme != 'http' && uri.scheme != 'https') {
              SecureLogger.d('SIP MANDATE WEBVIEW: external link (${uri.scheme})');
              launchUrl(uri, mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
    _enableThirdPartyCookies();
  }

  /// The flow hops between Cashfree's and the bank's domains; Android's
  /// WebView blocks third-party cookies by default, which can stall that
  /// handoff with no visible error (same fix as AadhaarDigilockerWebView).
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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, false);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(
              title: 'Bank Authorisation',
              onBack: () => Navigator.pop(context, false),
            ),
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
      ),
    );
  }
}
