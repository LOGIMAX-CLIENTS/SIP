import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../core/security/secure_logger.dart';
import '../../../shared/widgets/gradient_header.dart';

/// Hosts Airpay's payment page for an Instant Savings purchase.
///
/// [checkoutUrl] is a page on our secure server (savings/initiate's
/// `checkout_url`) that POSTs the signed order to Airpay. When the customer
/// finishes, Airpay sends the browser to [returnUrl]; this screen closes on
/// any URL that starts with it and pops `true`. Backing out pops `false`.
/// Either way the caller asks the backend (savings/confirm-payment), which
/// checks with Airpay itself — the WebView's outcome is never trusted.
///
/// UPI app links Airpay's page hands over (upi://, intent://, tez:// …) are
/// opened outside the WebView, which can't load them.
class AirpayCheckoutWebView extends StatefulWidget {
  final String checkoutUrl;
  final String returnUrl;

  const AirpayCheckoutWebView({
    super.key,
    required this.checkoutUrl,
    required this.returnUrl,
  });

  @override
  State<AirpayCheckoutWebView> createState() => _AirpayCheckoutWebViewState();
}

class _AirpayCheckoutWebViewState extends State<AirpayCheckoutWebView> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            // Android doesn't report form POSTs to onNavigationRequest, and
            // Airpay's return is a POST — so the return is caught here too.
            if (_isReturn(url)) {
              _close(true);
              return;
            }
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onNavigationRequest: (request) {
            if (_isReturn(request.url)) {
              _close(true);
              return NavigationDecision.prevent;
            }
            final uri = Uri.tryParse(request.url);
            if (uri != null && uri.scheme != 'http' && uri.scheme != 'https') {
              _openExternally(uri);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
    _enableThirdPartyCookies();
  }

  bool _isReturn(String url) =>
      widget.returnUrl.isNotEmpty && url.startsWith(widget.returnUrl);

  void _close(bool reachedReturn) {
    if (_closed || !mounted) return;
    _closed = true;
    SecureLogger.d('AIRPAY WEBVIEW: closing (reachedReturn=$reachedReturn)');
    Navigator.pop(context, reachedReturn);
  }

  /// Hands a UPI / app link to the app it belongs to. Android `intent://`
  /// links are rebuilt from their `scheme=` part (url_launcher can't start
  /// them as they are), falling back to the link's browser_fallback_url.
  Future<void> _openExternally(Uri uri) async {
    SecureLogger.d('AIRPAY WEBVIEW: external link (${uri.scheme})');
    var target = uri;
    Uri? fallback;
    if (uri.scheme == 'intent') {
      final raw = uri.toString();
      final hash = raw.indexOf('#Intent;');
      final params = hash >= 0 ? raw.substring(hash + 8).split(';') : <String>[];
      String? scheme;
      for (final p in params) {
        if (p.startsWith('scheme=')) scheme = p.substring(7);
        if (p.startsWith('S.browser_fallback_url=')) {
          fallback = Uri.tryParse(Uri.decodeComponent(p.substring(23)));
        }
      }
      final body = (hash >= 0 ? raw.substring(0, hash) : raw).replaceFirst('intent://', '');
      if (scheme != null && scheme.isNotEmpty) {
        target = Uri.tryParse('$scheme://$body') ?? uri;
      }
    }
    try {
      final opened = await launchUrl(target, mode: LaunchMode.externalApplication);
      if (!opened && fallback != null) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      SecureLogger.e('AIRPAY WEBVIEW: could not open ${uri.scheme} link: $e');
      if (fallback != null) {
        await launchUrl(fallback, mode: LaunchMode.externalApplication);
      }
    }
  }

  /// Airpay's page and the bank's hop between domains; Android's WebView
  /// blocks third-party cookies by default, which can stall that handoff
  /// with no visible error (same fix as SipMandateAuthWebView).
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
        if (!didPop) _close(false);
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            GradientHeader(
              title: 'Payment',
              onBack: () => _close(false),
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
