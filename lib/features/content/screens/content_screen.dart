import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../shared/widgets/gradient_header.dart';
import '../../../shared/theme/app_theme.dart';

/// Generic content screen that renders HTML from an API response.
///
/// Used for Terms & Conditions, Refund Policy, Privacy Policy, etc.
/// The API returns `{ "data": { "content": "<p>HTML...</p>" } }`.
///
/// Typography rules (enforced via HTML pre-processing):
///   • Body / paragraphs / headings → **Playfair Display**
///   • Numerics (digits, ₹, %, symbols) → **Lora**
///     Implemented by injecting `<span style="font-family: Lora, serif;">`
///     around every numeric run before passing to HtmlWidget.
class ContentScreen extends ConsumerWidget {
  final String title;
  final AutoDisposeFutureProvider<Map<String, dynamic>> provider;

  const ContentScreen({
    super.key,
    required this.title,
    required this.provider,
  });

  // ── Numeric font injection ────────────────────────────────────────────────

  /// Characters treated as "numeric" → rendered in Lora.
  static final _numericRun = RegExp(r'[\d₹%\.,:/+×]+');

  /// HTML tag pattern — used to skip tag content when injecting spans.
  static final _htmlTag = RegExp(r'<[^>]+>');

  /// Wraps numeric sequences in a Lora font-family span.
  /// Only touches text nodes (content between HTML tags),
  /// never modifies tag attributes.
  static String _injectLoraSpans(String html) {
    final out = StringBuffer();
    int lastEnd = 0;

    for (final tag in _htmlTag.allMatches(html)) {
      // Text node between previous tag and this tag → inject spans
      final text = html.substring(lastEnd, tag.start);
      out.write(_wrapNumericsInText(text));
      // Tag itself → write unchanged
      out.write(tag.group(0));
      lastEnd = tag.end;
    }
    // Trailing text after last tag
    out.write(_wrapNumericsInText(html.substring(lastEnd)));
    return out.toString();
  }

  // ── HTML sanitiser ─────────────────────────────────────────────────────────

  /// Strips problematic inline CSS properties from the server HTML.
  /// `flutter_widget_from_html_core` does NOT process `<style>` blocks,
  /// so we must fix the inline `style=""` attributes directly.
  static String _sanitizeHtml(String html) {
    // 1. Remove text-align: justify — causes mid-word line breaks
    var result = html.replaceAll(
      RegExp(r'text-align\s*:\s*justify\s*;?', caseSensitive: false), '');

    // 2. Remove word-break: break-all / break-word — breaks words mid-letter
    result = result.replaceAll(
      RegExp(r'word-break\s*:\s*break-(all|word)\s*;?', caseSensitive: false), '');

    // 3. Remove white-space: nowrap — prevents wrapping entirely
    result = result.replaceAll(
      RegExp(r'white-space\s*:\s*nowrap\s*;?', caseSensitive: false), '');

    // 4. Decode common HTML character entities that render as raw text
    result = result
        .replaceAll('&#39;',  "'")
        .replaceAll('&#x27;', "'")
        .replaceAll('&#34;',  '"')
        .replaceAll('&#x22;', '"')
        .replaceAll('&amp;',  '&')
        .replaceAll('&lt;',   '<')
        .replaceAll('&gt;',   '>')
        .replaceAll('&nbsp;', '\u00A0')
        .replaceAll('&#8377;', '₹');

    return result;
  }

  /// Replaces each numeric run in a plain text segment with a Lora span.
  /// Rupee entity normalisation is now handled by _sanitizeHtml above.
  static String _wrapNumericsInText(String text) {
    return text.replaceAllMapped(
      _numericRun,
      (m) => '<span style="font-family: Lora, serif; font-weight: inherit;">'
          '${m.group(0)}'
          '</span>',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentAsync = ref.watch(provider);

    // Pre-load Lora so google_fonts registers it in Flutter's font system.
    // HtmlWidget resolves "font-family: Lora" through the system font registry.
    GoogleFonts.lora();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
        ),
        child: Column(
          children: [
            GradientHeader(title: title),
            Expanded(
              child: contentAsync.when(
                data: (data) {
                  final rawHtml =
                      data['content'] ?? '<p>No content available.</p>';

                  // Sanitise server HTML (strip justify/break-all inline
                  // styles, decode entities) then inject Lora font spans.
                  final processedHtml =
                      _injectLoraSpans(_sanitizeHtml(rawHtml));

                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20.w, 16.h, 20.w, 80.h),
                    child: HtmlWidget(
                      processedHtml,
                      // Base font → Playfair Display for all text.
                      // Numerics override via injected Lora spans above.
                      textStyle: GoogleFonts.playfairDisplay(
                        fontSize: 13.sp,
                        height: 1.7,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                      customStylesBuilder: (element) {
                        // h1
                        if (element.localName == 'h1') {
                          return {
                            'font-size': '18px',
                            'font-weight': '800',
                            'color': isDark ? '#FFFFFF' : '#1A1A2E',
                            'margin-top': '20px',
                            'margin-bottom': '10px',
                          };
                        }
                        // h2
                        if (element.localName == 'h2') {
                          return {
                            'font-size': '16px',
                            'font-weight': '700',
                            'color': isDark ? '#FFFFFF' : '#1A1A2E',
                            'margin-top': '18px',
                            'margin-bottom': '8px',
                          };
                        }
                        // h3
                        if (element.localName == 'h3') {
                          return {
                            'font-size': '15px',
                            'font-weight': '700',
                            'color': isDark ? '#FFFFFF' : '#1A1A2E',
                            'margin-top': '16px',
                            'margin-bottom': '6px',
                          };
                        }
                        // Bold / strong
                        if (element.localName == 'strong' ||
                            element.localName == 'b') {
                          return {
                            'font-weight': '700',
                            'color': isDark ? '#FFFFFF' : '#1A1A2E',
                          };
                        }
                        // List items
                        if (element.localName == 'li') {
                          return {
                            'margin-bottom': '6px',
                            'line-height': '1.6',
                          };
                        }
                        // Paragraphs
                        if (element.localName == 'p') {
                          return {
                            'margin-bottom': '10px',
                            'text-align': 'left',
                          };
                        }
                        return null;
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF064E3B)),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: const Color(0xFFDC2626), size: 48.sp),
                        SizedBox(height: 16.h),
                        Text(
                          'Failed to load content',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Text(
                          'Please check your connection and try again.',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 13.sp,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 20.h),
                        TextButton.icon(
                          onPressed: () => ref.invalidate(provider),
                          icon: const Icon(Icons.refresh_rounded,
                              color: Color(0xFF064E3B)),
                          label: Text(
                            'Retry',
                            style: GoogleFonts.playfairDisplay(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF064E3B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
