import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/widgets/custom_button.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';

/// Hosts the Cashfree DigiLocker consent page for Aadhaar verification.
///
/// The backend's `_initiate_aadhaar_kyc()` (kyc.py) does not pass a
/// `redirect_url` to Cashfree, so there is no app-controlled "done" URL to
/// intercept — DigiLocker's own consent UI ends the session on its side.
/// The reliable signal that the user has finished is therefore the explicit
/// "I've completed verification" action below, not URL sniffing. The caller
/// (the unified KYC hub) is responsible for polling the backend after this
/// screen returns `true`.
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
        ),
      )
      ..loadRequest(Uri.parse(widget.consentUrl));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Column(
              children: [
                Text(
                  'Complete the DigiLocker consent above, then tap below to confirm.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 13.sp,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                SizedBox(height: 12.h),
                CustomButton(
                  text: "I've completed verification",
                  svgIconPath: 'assets/buttons/tick.svg',
                  gradient: AppTheme.greenGradient,
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
