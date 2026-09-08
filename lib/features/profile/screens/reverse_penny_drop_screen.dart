import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/widgets/app_toast.dart';
import '../services/reverse_penny_drop_service.dart';

const _accentGreen = Color(0xFF1B882C);

final reversePennyDropServiceProvider =
    Provider((ref) => ReversePennyDropService());

class _UpiAppOption {
  final String id;
  final String displayName;
  final String badgeText;
  final Color brandColor;
  final Uri launchUri;

  const _UpiAppOption({
    required this.id,
    required this.displayName,
    required this.badgeText,
    required this.brandColor,
    required this.launchUri,
  });
}

class _UpiAppMetadata {
  final String name;
  final String badge;
  final Color brandColor;
  final List<String> schemes;

  const _UpiAppMetadata({
    required this.name,
    required this.badge,
    required this.brandColor,
    required this.schemes,
  });
}

/// Official UPI applications supported and allowed by the gateway/backend API
/// in [ios_links]. When the API returns [ios_links], we take strictly the apps
/// that the API allows and returns links for.
const Map<String, _UpiAppMetadata> _apiAllowedAppRegistry = {
  'phonepe': _UpiAppMetadata(
    name: 'PhonePe',
    badge: 'Pe',
    brandColor: Color(0xFF5F259F),
    schemes: ['phonepe://', 'ppe://'],
  ),
  'gpay': _UpiAppMetadata(
    name: 'Google Pay',
    badge: 'GPay',
    brandColor: Color(0xFF1A73E8),
    schemes: ['gpay://', 'tez://'],
  ),
  'paytm': _UpiAppMetadata(
    name: 'Paytm',
    badge: 'Paytm',
    brandColor: Color(0xFF002970),
    schemes: ['paytmmp://', 'paytm://'],
  ),
  'bhim': _UpiAppMetadata(
    name: 'BHIM UPI',
    badge: 'BHIM',
    brandColor: Color(0xFF008450),
    schemes: ['bhim://'],
  ),
  'whatsapp': _UpiAppMetadata(
    name: 'WhatsApp',
    badge: 'WA',
    brandColor: Color(0xFF25D366),
    schemes: ['whatsapp://'],
  ),
};

/// SurePass Reverse Penny Drop — an OPTIONAL extra live-control check on top
/// of an already Pennyless-verified bank account. Unlike
/// [BankPennyVerifyScreen] (Cashfree/Razorpay in-app SDK payment), this pays
/// via a UPI deep link (no SDK — SurePass's RPD product is payment-link
/// only, see backend bank_verification_surepass.py). Pops `true` if the
/// resolved payer account matched [cbankId], `false`/null otherwise.
class ReversePennyDropScreen extends ConsumerStatefulWidget {
  final String cbankId;
  const ReversePennyDropScreen({super.key, required this.cbankId});

  @override
  ConsumerState<ReversePennyDropScreen> createState() =>
      _ReversePennyDropScreenState();
}

class _ReversePennyDropScreenState extends ConsumerState<ReversePennyDropScreen> {
  bool _isProcessing = false;
  bool _paymentLaunched = false;
  String? _clientId;
  String? _paymentLink;
  // Persistent inline error — a toast alone can be missed (especially for
  // ACCOUNT_MISMATCH, which the customer needs to actually read and act on,
  // not just glance past). Cleared whenever a new attempt starts.
  String? _errorMessage;

  // Auto-poll instead of relying solely on a manual "I've Paid" tap — the
  // payment happens in an external UPI app (no in-app SDK callback like
  // BankPennyVerifyScreen has), so nothing else tells us when it settles.
  // Capped so it doesn't run forever if the customer leaves this screen
  // open; the manual button below remains available after the cap.
  static const _pollInterval = Duration(seconds: 5);
  static const _maxPollAttempts = 24; // ~2 minutes
  Timer? _pollTimer;
  int _pollAttempts = 0;

  void _startPolling() {
    _pollTimer?.cancel();
    _pollAttempts = 0;
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _pollAttempts++;
      if (_pollAttempts > _maxPollAttempts) {
        _stopPolling();
        return;
      }
      _checkStatus(silent: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Map<String, dynamic>? _iosLinks;

  void _resetToStart() {
    _stopPolling();
    setState(() {
      _paymentLaunched = false;
      _clientId = null;
      _paymentLink = null;
      _iosLinks = null;
      _errorMessage = null;
    });
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }

  Future<void> _startVerification() async {
    if (_isProcessing || !mounted) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });
    try {
      if (_paymentLink == null || _clientId == null) {
        debugPrint('[RPD API] Calling initiate for cbank_id: ${widget.cbankId}');
        final result = await ref
            .read(reversePennyDropServiceProvider)
            .initiate(cbankId: widget.cbankId);
        if (!mounted) return;

        _clientId = result['client_id']?.toString();
        _paymentLink = result['payment_link']?.toString();
        _iosLinks = (result['ios_links'] as Map?)?.cast<String, dynamic>();

        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
        debugPrint('[RPD API] INITIATE RESPONSE RECEIVED:');
        debugPrint('  • client_id: $_clientId');
        debugPrint('  • payment_link: $_paymentLink');
        debugPrint('  • ios_links keys: ${_iosLinks?.keys.toList()}');
        debugPrint('  • ios_links: $_iosLinks');
        debugPrint('  • raw result: $result');
        debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

        // Dedup/self-heal on the backend: a retry may find this account was
        // already fully verified by a previous attempt (webhook/earlier check
        // never made it back to us) — nothing to pay, done immediately.
        if (result['already_verified'] == true || result['verified'] == true) {
          Navigator.pop(context, true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              AppToast.show(context, 'Bank account additionally verified.', type: ToastType.success);
            }
          });
          return;
        }
      }

      if (_paymentLink == null) {
        throw Exception('Payment link not received from server.');
      }

      // Stop button spinner before opening UPI chooser sheet
      setState(() => _isProcessing = false);

      final launched = await _handlePaymentLaunch(
        genericUpiLink: _paymentLink!,
        iosLinks: _iosLinks,
      );
      if (mounted) {
        if (launched) {
          setState(() => _paymentLaunched = true);
          _startPolling();
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (mounted && _isProcessing) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<bool> _handlePaymentLaunch({
    required String genericUpiLink,
    Map<String, dynamic>? iosLinks,
  }) async {
    if (Platform.isIOS) {
      final installedApps = await _detectInstalledUpiApps(
        genericUpiLink: genericUpiLink,
        iosLinks: iosLinks,
      );

      if (!mounted) return false;

      if (installedApps.isNotEmpty) {
        final selectedUri = await _showUpiAppPickerSheet(
          context: context,
          apps: installedApps,
          genericUpiLink: genericUpiLink,
        );
        if (selectedUri != null) {
          return launchUrl(selectedUri, mode: LaunchMode.externalApplication);
        }
        return false;
      }

      // Fallback if no specific app scheme matched:
      final genericUri = Uri.tryParse(genericUpiLink);
      if (genericUri != null && await canLaunchUrl(genericUri)) {
        return launchUrl(genericUri, mode: LaunchMode.externalApplication);
      }

      // If generic cannot be launched, show picker sheet with Copy UPI VPA option
      if (mounted) {
        final selectedUri = await _showUpiAppPickerSheet(
          context: context,
          apps: const [],
          genericUpiLink: genericUpiLink,
        );
        if (selectedUri != null) {
          return launchUrl(selectedUri, mode: LaunchMode.externalApplication);
        }
      }
      return false;
    }

    // Android resolves generic "upi://" scheme against installed apps via system chooser
    final genericUri = Uri.parse(genericUpiLink);
    if (await canLaunchUrl(genericUri)) {
      return launchUrl(genericUri, mode: LaunchMode.externalApplication);
    }
    return false;
  }

  Future<List<_UpiAppOption>> _detectInstalledUpiApps({
    required String genericUpiLink,
    Map<String, dynamic>? iosLinks,
  }) async {
    final parsed = Uri.tryParse(genericUpiLink);
    final query = parsed?.query ?? '';

    // Take ONLY the applications allowed/provided via the API in ios_links.
    // If ios_links is provided by API (e.g. {'phonepe': '...', 'gpay': '...', ...}),
    // we use strictly the keys present in ios_links.
    // If ios_links is null or empty, we fallback to the known API-supported applications.
    final allowedKeys = (iosLinks != null && iosLinks.isNotEmpty)
        ? iosLinks.keys.map((k) => k.toLowerCase().trim()).toList()
        : _apiAllowedAppRegistry.keys.toList();

    debugPrint('[RPD APPS] Applications allowed via API ios_links: $allowedKeys');

    final List<_UpiAppOption> detectedApps = [];

    for (final key in allowedKeys) {
      final meta = _apiAllowedAppRegistry[key] ??
          _UpiAppMetadata(
            name: key.toUpperCase(),
            badge: key.length > 4 ? key.substring(0, 4).toUpperCase() : key.toUpperCase(),
            brandColor: const Color(0xFF1A73E8),
            schemes: ['$key://'],
          );

      // Check if API provided a direct deep link for this app in ios_links
      final apiRawLink = iosLinks?[key]?.toString() ??
          iosLinks?[meta.name.toLowerCase()]?.toString();

      final List<Uri> testUris = [];

      // 1. If API returned a direct link for this app, test it first
      if (apiRawLink != null && apiRawLink.isNotEmpty) {
        final parsedApiUri = Uri.tryParse(apiRawLink);
        if (parsedApiUri != null) {
          testUris.add(parsedApiUri);
        }
      }

      // 2. Add known schemes to test if app is installed
      for (final scheme in meta.schemes) {
        final uri = Uri.tryParse(scheme);
        if (uri != null) {
          testUris.add(uri);
        }
        final cleanScheme = scheme.replaceAll('://', '');
        if (query.isNotEmpty) {
          final queryUri = Uri.tryParse('$cleanScheme://upi/pay?$query');
          if (queryUri != null) {
            testUris.add(queryUri);
          }
        }
      }

      Uri? resolvedLaunchUri;
      for (final uri in testUris) {
        try {
          if (await canLaunchUrl(uri)) {
            // Prioritize the exact link from API ios_links
            if (apiRawLink != null && apiRawLink.isNotEmpty) {
              resolvedLaunchUri = Uri.tryParse(apiRawLink);
            } else if (query.isNotEmpty) {
              final cleanScheme = meta.schemes.first.replaceAll('://', '');
              resolvedLaunchUri = Uri.tryParse('$cleanScheme://upi/pay?$query');
            } else {
              resolvedLaunchUri = uri;
            }
            break;
          }
        } catch (_) {}
      }

      if (resolvedLaunchUri != null) {
        detectedApps.add(
          _UpiAppOption(
            id: key,
            displayName: meta.name,
            badgeText: meta.badge,
            brandColor: meta.brandColor,
            launchUri: resolvedLaunchUri,
          ),
        );
        debugPrint('[RPD APPS] Allowed app is installed: ${meta.name} ($key) -> $resolvedLaunchUri');
      } else {
        debugPrint('[RPD APPS] Allowed app is NOT installed: ${meta.name} ($key)');
      }
    }

    return detectedApps;
  }

  Future<Uri?> _showUpiAppPickerSheet({
    required BuildContext context,
    required List<_UpiAppOption> apps,
    required String genericUpiLink,
  }) async {
    final parsed = Uri.tryParse(genericUpiLink);
    final upiId = parsed?.queryParameters['pa'] ?? '';

    return showModalBottomSheet<Uri>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
        final subTextColor = isDark ? Colors.white60 : Colors.black54;

        return Container(
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          ),
          padding: EdgeInsets.fromLTRB(20.w, 12.h, 20.w, 24.h),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40.w,
                    height: 4.h,
                    margin: EdgeInsets.only(bottom: 16.h),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(2.r),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Choose UPI App',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: 4.h),
                        Text(
                          'Pay ₹1 from your bank account to verify',
                          style: TextStyle(
                            fontSize: 12.sp,
                            color: subTextColor,
                          ),
                        ),
                      ],
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(sheetContext),
                      child: Container(
                        padding: EdgeInsets.all(6.w),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                        ),
                        child: Icon(Icons.close, size: 18.sp, color: subTextColor),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 20.h),
                if (apps.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: Center(
                      child: Text(
                        'No allowed UPI apps detected directly on this device. You can copy the UPI VPA below to pay ₹1 from any UPI app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: subTextColor,
                        ),
                      ),
                    ),
                  )
                else
                  ...apps.map((app) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14.r),
                        onTap: () => Navigator.pop(sheetContext, app.launchUri),
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF8F9FA),
                            borderRadius: BorderRadius.circular(14.r),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44.w,
                                height: 44.w,
                                decoration: BoxDecoration(
                                  color: app.brandColor,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: app.brandColor.withValues(alpha: 0.3),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    app.badgeText,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: app.badgeText.length > 4 ? 10.sp : 13.sp,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 14.w),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      app.displayName,
                                      style: TextStyle(
                                        fontSize: 15.sp,
                                        fontWeight: FontWeight.w600,
                                        color: textColor,
                                      ),
                                    ),
                                    SizedBox(height: 2.h),
                                    Text(
                                      'Installed on this iPhone',
                                      style: TextStyle(
                                        fontSize: 11.sp,
                                        color: subTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.arrow_forward_ios_rounded, size: 14.sp, color: subTextColor),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                SizedBox(height: 8.h),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      final textToCopy = upiId.isNotEmpty ? upiId : genericUpiLink;
                      Clipboard.setData(ClipboardData(text: textToCopy));
                      Navigator.pop(sheetContext);
                      AppToast.show(context, 'UPI details copied to clipboard.', type: ToastType.info);
                    },
                    icon: Icon(Icons.copy_rounded, size: 14.sp, color: _accentGreen),
                    label: Text(
                      upiId.isNotEmpty ? 'Copy UPI VPA ($upiId)' : 'Copy UPI Link',
                      style: TextStyle(fontSize: 12.sp, color: _accentGreen, fontWeight: FontWeight.w500),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// [silent] = true for background auto-polls: suppresses the "still
  /// pending" toast (would otherwise spam every [_pollInterval]) and never
  /// touches [_isProcessing] (so the manual button's spinner isn't driven by
  /// background polling). Terminal outcomes (verified / FAILED /
  /// ACCOUNT_MISMATCH) are always surfaced and always stop the poll timer,
  /// silent or not.
  Future<void> _checkStatus({bool silent = false}) async {
    if (_clientId == null || !mounted) return;
    if (!silent) {
      if (_isProcessing) return;
      setState(() {
        _isProcessing = true;
        _errorMessage = null; // clear any stale banner before this re-check
      });
    }
    try {
      final result = await ref
          .read(reversePennyDropServiceProvider)
          .status(clientId: _clientId!);
      if (!mounted) return;

      final status = result['status']?.toString() ?? '';
      if (result['verified'] == true) {
        _stopPolling();
        Navigator.pop(context, true);
        // Deferred to the next frame — see the sibling case above.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            AppToast.show(context, 'Bank account additionally verified.', type: ToastType.success);
          }
        });
        return;
      }

      if (status == 'PENDING') {
        if (!silent) {
          AppToast.show(
            context,
            'Payment not received yet. Please complete the ₹1 payment and try again.',
            type: ToastType.error,
          );
        }
        return; // Not terminal — keep polling.
      }

      // Terminal failure — always surfaced (toast + persistent banner) and
      // always stops polling, silent or not.
      _stopPolling();
      final message = switch (status) {
        'ACCOUNT_MISMATCH' =>
          'The ₹1 payment came from a different account than the one being verified.',
        'FAILED' => 'Verification failed. Please try again.',
        _ => result['message']?.toString() ?? 'Verification pending.',
      };
      if (mounted) setState(() => _errorMessage = message);
      AppToast.show(context, message, type: ToastType.error);
    } catch (e) {
      if (!silent && mounted) {
        AppToast.show(context, e.toString().replaceFirst('Exception: ', ''), type: ToastType.error);
      }
    } finally {
      if (!silent && mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          GradientHeader(
            title: 'Verify Bank Account',
            trailing: (_paymentLaunched && _errorMessage == null)
                ? IconButton(
                    icon: Icon(Icons.refresh_rounded, color: Colors.white, size: 22.sp),
                    onPressed: _isProcessing ? null : _checkStatus,
                    tooltip: 'Refresh status',
                  )
                : null,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/home/rpd.png', width: 180.w, height: 180.w),
                  SizedBox(height: 16.h),
                  Text(
                    'Our KYC partners will securely verify your bank account by '
                    'charging ₹1. This amount is refunded instantly once the '
                    'verification is completed.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 14.sp,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    SizedBox(height: 16.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10.r),
                        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 18.sp, color: Colors.red.shade400),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 12.sp,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  SizedBox(height: 32.h),
                  if (_errorMessage != null) ...[
                    Text(
                      'Please retry with the correct bank account.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.playfairDisplay(fontSize: 13.sp, color: isDark ? Colors.white54 : Colors.black54),
                    ),
                    SizedBox(height: 16.h),
                    ElevatedButton(
                      onPressed: _resetToStart,
                      style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
                      child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                    ),
                  ] else ...[
                    ElevatedButton(
                      onPressed: _isProcessing ? null : _startVerification,
                      style: ElevatedButton.styleFrom(backgroundColor: _accentGreen),
                      child: _isProcessing
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Text(
                              _paymentLaunched ? 'Choose UPI App / Pay ₹1' : 'Proceed to Verify',
                              style: TextStyle(color: Colors.white, fontSize: 17.sp),
                            ),
                    ),
                    if (_paymentLaunched) ...[
                      SizedBox(height: 12.h),
                      Text(
                        'A ₹1 verification request is active. Tap above to select or re-open your UPI app, then return here to complete verification.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.playfairDisplay(fontSize: 12.sp, color: isDark ? Colors.white54 : Colors.black54),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
