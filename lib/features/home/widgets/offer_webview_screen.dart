import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../routes/app_router.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/gradient_header.dart';

// Conditional imports — only loaded on native platforms.
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

/// Full-screen WebView page for the "Know More" offer benefits content.
///
/// - **Mobile (Android/iOS):** Renders the URL in an in-app WebView.
/// - **Web:** Opens the URL in a new browser tab (WebView not supported on web).
class OfferWebViewScreen extends StatefulWidget {
  final String url;
  final String title;

  const OfferWebViewScreen({
    super.key,
    required this.url,
    this.title = 'Offer Benefits',
  });

  @override
  State<OfferWebViewScreen> createState() => _OfferWebViewScreenState();
}

class _OfferWebViewScreenState extends State<OfferWebViewScreen> {
  WebViewController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    if (kIsWeb) {
      // On web, open URL in a new browser tab and pop back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openInBrowser();
      });
    } else {
      _initWebView();
    }
  }

  void _initWebView() {
    // Ensure the platform-specific WebView implementation is registered.
    if (defaultTargetPlatform == TargetPlatform.android) {
      WebViewPlatform.instance = AndroidWebViewPlatform();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      WebViewPlatform.instance = WebKitWebViewPlatform();
    }

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFF8EE))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            debugPrint('[OfferWebView] Error: ${error.description}');
          },
          onNavigationRequest: (request) {
            // Intercept deep links (e.g. startgold://instantSaving)
            if (request.url.startsWith('startgold://')) {
              _handleDeepLink(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterChannel',
        onMessageReceived: (message) {
          _handleDeepLink(message.message);
        },
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
    if (mounted) Navigator.pop(context);
  }

  void _handleDeepLink(String url) {
    debugPrint('[OfferWebView] Deep link: $url');
    if (url.contains('instantSaving')) {
      Navigator.pop(context);
      Navigator.pushNamed(context, '/instantSaving');
    }
  }

  @override
  Widget build(BuildContext context) {
    // On web, show a brief loading state before the browser tab opens.
    if (kIsWeb || _controller == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF8EE),
        body: Column(
          children: [
            GradientHeader(title: widget.title),
            const Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF1B882C)),
                    SizedBox(height: 16),
                    Text('Opening in browser...'),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFF8EE),
      body: Column(
        children: [
          GradientHeader(title: widget.title),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller!),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF1B882C),
                    ),
                  ),
              ],
            ),
          ),
          _buildFooterButton(),
        ],
      ),
    );
  }

  Widget _buildFooterButton() {
    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 12.h),
        decoration: const BoxDecoration(
          color: Color(0xFFFFF8EE),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Trust Badge ──
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded,
                    size: 14.sp, color: const Color(0xFF64748B)),
                SizedBox(width: 6.w),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: '100% ',
                        style: GoogleFonts.lora(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      TextSpan(
                        text: 'Secure • Trusted by Thousands',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            // ── CTA Button ──
            CustomButton(
              text: 'Start Investing',
              svgIconPath: 'assets/buttons/tick.svg',
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRouter.instantSaving);
              },
              gradient: const LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xFF1B882C), Color(0xFF003716)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B882C).withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
              textColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}
