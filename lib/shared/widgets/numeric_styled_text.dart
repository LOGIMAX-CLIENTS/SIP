import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Builds a [RichText] widget that uses [GoogleFonts.lora] for numbers
/// (with their attached ₹, %, sign and separators) and
/// [GoogleFonts.playfairDisplay] for everything else.
///
/// This enforces the fintech typography rule:
///   • Numbers & financial symbols → **Lora**
///   • Text, labels, headings      → **Playfair Display**
///
/// K/T/X count as numeric only when they belong to a number, so commodity
/// purity labels like "24KT" or "24K" render entirely in the numeric font.
class NumericStyledText extends StatelessWidget {
  final String text;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle? fontStyle;
  final Color color;
  final double? height;
  final double? letterSpacing;
  final TextAlign textAlign;

  const NumericStyledText(
    this.text, {
    super.key,
    required this.fontSize,
    this.fontWeight = FontWeight.w600,
    this.fontStyle,
    this.color = Colors.black,
    this.height,
    this.letterSpacing,
    this.textAlign = TextAlign.start,
  });

  /// Runs rendered with Lora (numeric font): a number plus the symbols
  /// attached to it. Letters only count when they are part of the number —
  /// purity labels (24KT, 24K), multipliers (2x), masked digits (XXXX1234) —
  /// so the t/k/x inside ordinary words ("Oct", "debited") and punctuation
  /// not touching a digit stay in Playfair Display.
  static final _numericPattern = RegExp(
    r'(?:[Xx]{2,}\s?)?' // masked digits: XXXX1234
    r'[+\-−]?(?:₹\s?)?' // sign / currency: -₹10, ₹ 500
    r'\d(?:[\d.,:/\-−×]*\d)?' // 1,234.50  04:15  5-7  1/2
    r'(?:%|(?:[Kk][Tt]|[KkTtXx])(?![A-Za-z]))?' // 2.5%  24KT  24K  2x, not 4th
    r'|[₹%]', // a lone symbol
  );

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in _numericPattern.allMatches(text)) {
      // Text before the numeric match → Playfair Display
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: GoogleFonts.playfairDisplay(
            fontSize: fontSize,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            color: color,
            height: height,
            letterSpacing: letterSpacing,
          ),
        ));
      }
      // The numeric match → Lora
      spans.add(TextSpan(
        text: match.group(0),
        style: GoogleFonts.lora(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
        ),
      ));
      lastEnd = match.end;
    }

    // Remaining text after last match → Playfair Display
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: GoogleFonts.playfairDisplay(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
        ),
      ));
    }

    // If there are no numeric chars at all, just use Playfair Display.
    if (spans.isEmpty) {
      spans.add(TextSpan(
        text: text,
        style: GoogleFonts.playfairDisplay(
          fontSize: fontSize,
          fontWeight: fontWeight,
          fontStyle: fontStyle,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
        ),
      ));
    }

    return RichText(
      textAlign: textAlign,
      text: TextSpan(children: spans),
    );
  }
}
