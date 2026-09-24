import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:startgold/core/services/content_service.dart';
import 'package:startgold/shared/theme/app_theme.dart';
import 'package:startgold/shared/widgets/gradient_header.dart';
import 'package:startgold/shared/widgets/numeric_styled_text.dart';

/// FAQ screen.
///
/// Typography rules:
///   • Questions / labels → **Playfair Display** + **Lora** for numerics
///     (via [NumericStyledText] on the question title widget)
///   • HTML answer content → base **Playfair Display**; numeric runs
///     injected with `<span style="font-family: Lora, serif;">` so they
///     render in **Lora** inside HtmlWidget.
class FaqScreen extends ConsumerStatefulWidget {
  const FaqScreen({super.key});

  @override
  ConsumerState<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends ConsumerState<FaqScreen> {
  // ── Numeric font injection (mirrors ContentScreen) ────────────────────────

  static final _numericRun = RegExp(r'[\d₹%\.,:/+\-×]+');
  static final _htmlTag = RegExp(r'<[^>]+>');

  static String _injectLoraSpans(String html) {
    final out = StringBuffer();
    int lastEnd = 0;
    for (final tag in _htmlTag.allMatches(html)) {
      out.write(_wrapNumericsInText(html.substring(lastEnd, tag.start)));
      out.write(tag.group(0));
      lastEnd = tag.end;
    }
    out.write(_wrapNumericsInText(html.substring(lastEnd)));
    return out.toString();
  }

  static String _wrapNumericsInText(String text) {
    // Decode rupee HTML entity before pattern matching.
    final normalised = text.replaceAll('&#8377;', '₹');
    return normalised.replaceAllMapped(
      _numericRun,
      (m) =>
          '<span style="font-family: Lora, serif; font-weight: inherit;">'
          '${m.group(0)}'
          '</span>',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final faqsAsync = ref.watch(faqsProvider);

    // Pre-load Lora so google_fonts registers it in Flutter's font system.
    GoogleFonts.lora();

    return Container(
      decoration: BoxDecoration(
        gradient: isDark ? AppTheme.darkGradient : AppTheme.lightGradient,
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // ── Gradient Header ──
            const GradientHeader(title: 'FAQ'),

            // ── Body ──
            Expanded(
              child: faqsAsync.when(
                data: (faqs) {
                  if (faqs.isEmpty) {
                    return Center(
                      child: Text(
                        'No FAQs currently available.',
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 14.sp,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(20.w, 24.h, 20.w, 80.h),
                    itemCount: faqs.length,
                    itemBuilder: (context, index) {
                      final faq = faqs[index];
                      final question =
                          (faq['question'] ?? '').toString();
                      final answer =
                          (faq['answer'] ?? '').toString();
                      return _buildFaqItem(question, answer, isDark);
                    },
                  );
                },
                loading: () => const Center(
                    child: CircularProgressIndicator(
                        color: AppTheme.primaryGreen)),
                error: (e, _) => Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.w),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: const Color(0xFFDC2626), size: 48.sp),
                        SizedBox(height: 16.h),
                        // Error title — Playfair Display
                        Text(
                          'Failed to load FAQs',
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        SizedBox(height: 8.h),
                        // Body — Playfair Display
                        Text(
                          'Please check your connection and try again.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.playfairDisplay(
                            fontSize: 13.sp,
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                        SizedBox(height: 20.h),
                        TextButton.icon(
                          onPressed: () => ref.invalidate(faqsProvider),
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

  Widget _buildFaqItem(String ques, String ans, bool isDark) {
    return Container(
      margin: EdgeInsets.only(bottom: 16.h),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.05)),
      ),
      child: ExpansionTile(
        // ── Question title: NumericStyledText ensures numbers → Lora,
        //    text → Playfair Display automatically.
        title: NumericStyledText(
          ques,
          fontSize: 15.sp,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black87,
        ),
        iconColor: AppTheme.arcticBlue,
        collapsedIconColor: isDark ? Colors.white38 : Colors.black38,
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        childrenPadding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
        children: [
          // ── Answer: pre-process HTML to inject Lora spans on numerics,
          // then render via HtmlWidget. Base font → Playfair Display.
          HtmlWidget(
            _injectLoraSpans(ans),
            textStyle: GoogleFonts.playfairDisplay(
              fontSize: 14.sp,
              color: isDark ? Colors.white60 : Colors.black54,
              height: 1.6,
            ),
            customStylesBuilder: (element) {
              if (element.localName == 'strong' ||
                  element.localName == 'b') {
                return {
                  'font-weight': '700',
                  'color': isDark ? '#FFFFFF' : '#1A1A2E',
                };
              }
              if (element.localName == 'li') {
                return {'margin-bottom': '4px', 'line-height': '1.5'};
              }
              if (element.localName == 'p') {
                return {'margin-bottom': '6px'};
              }
              return null;
            },
          ),
        ],
      ),
    );
  }
}
