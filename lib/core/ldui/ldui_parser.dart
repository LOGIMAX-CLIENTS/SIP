import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

/// Lightweight LDUI (Layout-Driven UI) parser.
///
/// Recursively converts a server-sent JSON widget tree into Flutter widgets.
/// Used by the countdown-offer "Know More" bottom sheet to render
/// server-driven content without requiring app updates.
///
/// Supported widget types:
///   container, column, row, text, sizedBox, padding, flexible,
///   singleChildScrollView, align, iconButton, elevatedButton, icon,
///   image, networkImage, assetImage, card, clipRRect, center, stack
///
/// Supported action types:
///   navigateBack — pops the current route
///   navigate     — pushes a named route
class LduiParser {
  /// Parses a JSON map and returns the corresponding Flutter widget.
  ///
  /// Returns [SizedBox.shrink] for null/invalid input to fail gracefully.
  static Widget parse(Map<String, dynamic>? json, BuildContext context) {
    if (json == null) return const SizedBox.shrink();

    final type = json['type'] as String?;
    if (type == null) return const SizedBox.shrink();

    switch (type) {
      case 'container':
        return _buildContainer(json, context);
      case 'column':
        return _buildColumn(json, context);
      case 'row':
        return _buildRow(json, context);
      case 'text':
        return _buildText(json);
      case 'sizedBox':
        return _buildSizedBox(json);
      case 'padding':
        return _buildPadding(json, context);
      case 'flexible':
        return _buildFlexible(json, context);
      case 'singleChildScrollView':
        return _buildSingleChildScrollView(json, context);
      case 'align':
        return _buildAlign(json, context);
      case 'iconButton':
        return _buildIconButton(json, context);
      case 'elevatedButton':
        return _buildElevatedButton(json, context);
      case 'icon':
        return _buildIcon(json);
      case 'image':
      case 'networkImage':
        return _buildNetworkImage(json);
      case 'assetImage':
        return _buildAssetImage(json);
      case 'card':
        return _buildCard(json, context);
      case 'clipRRect':
        return _buildClipRRect(json, context);
      case 'center':
        final child = json['child'] != null
            ? parse(json['child'] as Map<String, dynamic>, context)
            : const SizedBox.shrink();
        return Center(child: child);
      case 'stack':
        return _buildStack(json, context);
      case 'expanded':
        final child = json['child'] != null
            ? parse(json['child'] as Map<String, dynamic>, context)
            : const SizedBox.shrink();
        return Expanded(child: child);
      case 'richText':
        return _buildRichText(json);
      default:
        debugPrint('[LduiParser] Unknown widget type: $type');
        return const SizedBox.shrink();
    }
  }

  // ─────────────────────────────────────────────────────────
  // Widget builders
  // ─────────────────────────────────────────────────────────

  static Widget _buildContainer(Map<String, dynamic> json, BuildContext ctx) {
    final decoration = _parseDecoration(json['decoration']);
    final color = decoration == null ? _parseColor(json['color']) : null;
    final padding = _parseEdgeInsets(json['padding']);
    final width = (json['width'] as num?)?.toDouble();
    final height = (json['height'] as num?)?.toDouble();
    final child =
        json['child'] != null ? parse(json['child'] as Map<String, dynamic>, ctx) : null;

    return Container(
      decoration: decoration,
      color: color,
      padding: padding,
      width: width?.w,
      height: height?.h,
      child: child,
    );
  }

  static Widget _buildColumn(Map<String, dynamic> json, BuildContext ctx) {
    final children = _parseChildren(json['children'], ctx);
    return Column(
      mainAxisSize: _parseMainAxisSize(json['mainAxisSize']),
      crossAxisAlignment: _parseCrossAxisAlignment(json['crossAxisAlignment']),
      mainAxisAlignment: _parseMainAxisAlignment(json['mainAxisAlignment']),
      children: children,
    );
  }

  static Widget _buildRow(Map<String, dynamic> json, BuildContext ctx) {
    final children = _parseChildren(json['children'], ctx);
    return Row(
      mainAxisAlignment: _parseMainAxisAlignment(json['mainAxisAlignment']),
      crossAxisAlignment: _parseCrossAxisAlignment(json['crossAxisAlignment']),
      children: children,
    );
  }

  static Widget _buildText(Map<String, dynamic> json) {
    final data = json['data'] as String? ?? '';
    final style = _parseTextStyle(json['style']);
    return Text(data, style: style);
  }

  /// Builds a RichText widget with multiple styled spans.
  /// JSON: {"type": "richText", "spans": [{"text": "Your ", "style": {...}}, {"text": "Rewards", "style": {...}}]}
  static Widget _buildRichText(Map<String, dynamic> json) {
    final spans = (json['spans'] as List<dynamic>?)
            ?.map((s) {
              final span = s as Map<String, dynamic>;
              return TextSpan(
                text: span['text'] as String? ?? '',
                style: _parseTextStyle(span['style']),
              );
            })
            .toList() ??
        [];
    return RichText(text: TextSpan(children: spans));
  }

  static Widget _buildSizedBox(Map<String, dynamic> json) {
    final height = (json['height'] as num?)?.toDouble();
    final width = (json['width'] as num?)?.toDouble();
    return SizedBox(
      height: height?.h,
      width: width?.w,
    );
  }

  static Widget _buildPadding(Map<String, dynamic> json, BuildContext ctx) {
    final padding = _parseEdgeInsets(json['padding']) ?? EdgeInsets.zero;
    final child =
        json['child'] != null ? parse(json['child'] as Map<String, dynamic>, ctx) : const SizedBox.shrink();
    return Padding(padding: padding, child: child);
  }

  static Widget _buildFlexible(Map<String, dynamic> json, BuildContext ctx) {
    final child =
        json['child'] != null ? parse(json['child'] as Map<String, dynamic>, ctx) : const SizedBox.shrink();
    final flex = (json['flex'] as num?)?.toInt() ?? 1;
    return Flexible(flex: flex, child: child);
  }

  static Widget _buildSingleChildScrollView(
      Map<String, dynamic> json, BuildContext ctx) {
    final padding = _parseEdgeInsets(json['padding']);
    final child =
        json['child'] != null ? parse(json['child'] as Map<String, dynamic>, ctx) : const SizedBox.shrink();
    return SingleChildScrollView(padding: padding, child: child);
  }

  static Widget _buildAlign(Map<String, dynamic> json, BuildContext ctx) {
    final alignment = _parseAlignment(json['alignment']);
    final child =
        json['child'] != null ? parse(json['child'] as Map<String, dynamic>, ctx) : const SizedBox.shrink();
    return Align(alignment: alignment, child: child);
  }

  static Widget _buildIconButton(Map<String, dynamic> json, BuildContext ctx) {
    // Check if this is a close/navigateBack button — skip it on full pages
    // (the AppBar already provides a back button)
    final onPressedJson = json['onPressed'] as Map<String, dynamic>?;
    if (onPressedJson?['actionType'] == 'navigateBack') {
      return const SizedBox.shrink();
    }

    final iconJson = json['icon'] as Map<String, dynamic>?;
    final icon = iconJson != null ? _buildIcon(iconJson) : const Icon(Icons.circle);
    final onPressed = _parseOnPressed(json['onPressed'], ctx);

    return IconButton(
      icon: icon,
      onPressed: onPressed,
      padding: EdgeInsets.all(6.r),
    );
  }

  static Widget _buildElevatedButton(
      Map<String, dynamic> json, BuildContext ctx) {
    final child =
        json['child'] != null ? parse(json['child'] as Map<String, dynamic>, ctx) : const Text('Button');
    final onPressed = _parseOnPressed(json['onPressed'], ctx);
    final styleJson = json['style'] as Map<String, dynamic>?;

    ButtonStyle? buttonStyle;
    Gradient? gradient;
    double borderRadiusValue = 12;

    if (styleJson != null) {
      final bgColor = _parseColor(styleJson['backgroundColor']);
      final fgColor = _parseColor(styleJson['foregroundColor']);
      final shapeJson = styleJson['shape'] as Map<String, dynamic>?;

      // Parse gradient if present
      final gradientJson = styleJson['gradient'] as Map<String, dynamic>?;
      if (gradientJson != null) {
        final colors = (gradientJson['colors'] as List<dynamic>?)
                ?.map((c) => _parseColor(c))
                .whereType<Color>()
                .toList() ??
            [];
        if (colors.length >= 2) {
          gradient = LinearGradient(
            begin: _parseAlignmentValue(gradientJson['begin']),
            end: _parseAlignmentValue(gradientJson['end']),
            colors: colors,
          );
        }
      }

      OutlinedBorder? shape;
      if (shapeJson != null && shapeJson['type'] == 'roundedRectangle') {
        final brJson = shapeJson['borderRadius'] as Map<String, dynamic>?;
        borderRadiusValue = (brJson?['all'] as num?)?.toDouble() ?? 12;
        shape = RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadiusValue.r),
        );
      }

      buttonStyle = ElevatedButton.styleFrom(
        backgroundColor: gradient != null ? Colors.transparent : bgColor,
        foregroundColor: fgColor,
        shape: shape,
        minimumSize: const Size(double.infinity, 48),
        shadowColor: gradient != null ? Colors.transparent : null,
        padding: EdgeInsets.symmetric(vertical: 12.h, horizontal: 26.w),
      );
    }

    final button = ElevatedButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: child,
    );

    if (gradient != null) {
      return Container(
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(borderRadiusValue.r),
        ),
        child: button,
      );
    }

    return button;
  }

  static Widget _buildIcon(Map<String, dynamic> json) {
    final iconType = json['iconType'] as String? ?? 'circle';
    final size = (json['size'] as num?)?.toDouble() ?? 24;
    final color = _parseColor(json['color']);

    IconData iconData;
    switch (iconType) {
      case 'close':
        iconData = Icons.close;
        break;
      case 'arrow_back':
        iconData = Icons.arrow_back;
        break;
      case 'check':
        iconData = Icons.check;
        break;
      case 'info':
        iconData = Icons.info_outline;
        break;
      case 'star':
        iconData = Icons.star;
        break;
      default:
        iconData = Icons.circle;
    }

    return Icon(iconData, size: size.sp, color: color);
  }

  /// Builds a network image from a URL.
  /// JSON: {"type": "image", "url": "https://...", "width": 80, "height": 80, "fit": "contain"}
  static Widget _buildNetworkImage(Map<String, dynamic> json) {
    final url = json['url'] as String? ?? '';
    final width = (json['width'] as num?)?.toDouble();
    final height = (json['height'] as num?)?.toDouble();
    final fit = _parseBoxFit(json['fit'] as String?);
    final borderRadius = _parseBorderRadius(json['borderRadius']);

    Widget image = Image.network(
      url,
      width: width?.w,
      height: height?.h,
      fit: fit,
      errorBuilder: (_, __, ___) => SizedBox(
        width: width?.w,
        height: height?.h,
      ),
    );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius, child: image);
    }
    return image;
  }

  /// Builds an asset image from a local path.
  /// JSON: {"type": "assetImage", "asset": "assets/offer/gift.png", "width": 80, "height": 80}
  static Widget _buildAssetImage(Map<String, dynamic> json) {
    final asset = json['asset'] as String? ?? '';
    final width = (json['width'] as num?)?.toDouble();
    final height = (json['height'] as num?)?.toDouble();
    final fit = _parseBoxFit(json['fit'] as String?);

    return Image.asset(
      asset,
      width: width?.w,
      height: height?.h,
      fit: fit,
      errorBuilder: (_, __, ___) => SizedBox(
        width: width?.w,
        height: height?.h,
      ),
    );
  }

  /// Builds a Material Card.
  /// JSON: {"type": "card", "elevation": 0, "color": "#FFFFFF", "borderRadius": {"all": 16}, "child": {...}}
  static Widget _buildCard(Map<String, dynamic> json, BuildContext ctx) {
    final elevation = (json['elevation'] as num?)?.toDouble() ?? 0;
    final color = _parseColor(json['color']) ?? Colors.white;
    final borderRadius = _parseBorderRadius(json['borderRadius']);
    final child = json['child'] != null
        ? parse(json['child'] as Map<String, dynamic>, ctx)
        : const SizedBox.shrink();

    return Card(
      elevation: elevation,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? BorderRadius.circular(16.r),
      ),
      child: child,
    );
  }

  /// Builds a ClipRRect.
  /// JSON: {"type": "clipRRect", "borderRadius": {"all": 12}, "child": {...}}
  static Widget _buildClipRRect(Map<String, dynamic> json, BuildContext ctx) {
    final borderRadius = _parseBorderRadius(json['borderRadius']) ?? BorderRadius.zero;
    final child = json['child'] != null
        ? parse(json['child'] as Map<String, dynamic>, ctx)
        : const SizedBox.shrink();
    return ClipRRect(borderRadius: borderRadius, child: child);
  }

  /// Builds a Stack.
  /// JSON: {"type": "stack", "children": [...], "alignment": "center"}
  static Widget _buildStack(Map<String, dynamic> json, BuildContext ctx) {
    final children = (json['children'] as List<dynamic>?)
            ?.map((e) => parse(e as Map<String, dynamic>, ctx))
            .toList() ??
        [];
    final alignment = _parseAlignment(json['alignment'] as String?);
    return Stack(
      alignment: alignment,
      children: children,
    );
  }

  // ─────────────────────────────────────────────────────────
  // Property parsers
  // ─────────────────────────────────────────────────────────

  /// Parses an ARGB hex string (e.g. "#DE000000", "#1B882C") into a [Color].
  static Color? _parseColor(dynamic colorStr) {
    if (colorStr is! String || colorStr.isEmpty) return null;
    final hex = colorStr.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    }
    if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
    return null;
  }

  /// Parses edge insets from a JSON map with left/top/right/bottom keys.
  static EdgeInsets? _parseEdgeInsets(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    return EdgeInsets.only(
      left: ((json['left'] as num?)?.toDouble() ?? 0).w,
      top: ((json['top'] as num?)?.toDouble() ?? 0).h,
      right: ((json['right'] as num?)?.toDouble() ?? 0).w,
      bottom: ((json['bottom'] as num?)?.toDouble() ?? 0).h,
    );
  }

  /// Parses a text style from JSON properties.
  static TextStyle? _parseTextStyle(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final fontSize = (json['fontSize'] as num?)?.toDouble();
    final fontWeight = _parseFontWeight(json['fontWeight']);
    final color = _parseColor(json['color']);
    final height = (json['height'] as num?)?.toDouble();
    final fontFamily = json['fontFamily'] as String?;

    TextStyle baseStyle = TextStyle(
      fontSize: fontSize?.sp,
      fontWeight: fontWeight,
      color: color,
      height: height,
    );

    // Support Google Fonts via fontFamily
    if (fontFamily != null) {
      switch (fontFamily) {
        case 'PlayfairDisplay':
          baseStyle = GoogleFonts.playfairDisplay(textStyle: baseStyle);
          break;
        case 'Lora':
          baseStyle = GoogleFonts.lora(textStyle: baseStyle);
          break;
        case 'Poppins':
          baseStyle = GoogleFonts.poppins(textStyle: baseStyle);
          break;
        case 'Inter':
          baseStyle = GoogleFonts.inter(textStyle: baseStyle);
          break;
      }
    }

    return baseStyle;
  }

  static FontWeight? _parseFontWeight(dynamic weight) {
    if (weight is! String) return null;
    switch (weight) {
      case 'w100':
        return FontWeight.w100;
      case 'w200':
        return FontWeight.w200;
      case 'w300':
        return FontWeight.w300;
      case 'w400':
        return FontWeight.w400;
      case 'w500':
        return FontWeight.w500;
      case 'w600':
        return FontWeight.w600;
      case 'w700':
        return FontWeight.w700;
      case 'w800':
        return FontWeight.w800;
      case 'w900':
        return FontWeight.w900;
      case 'bold':
        return FontWeight.bold;
      case 'normal':
        return FontWeight.normal;
      default:
        return null;
    }
  }

  /// Parses a BoxFit string (e.g. "contain", "cover", "fill").
  static BoxFit _parseBoxFit(String? fit) {
    switch (fit) {
      case 'contain':
        return BoxFit.contain;
      case 'cover':
        return BoxFit.cover;
      case 'fill':
        return BoxFit.fill;
      case 'fitWidth':
        return BoxFit.fitWidth;
      case 'fitHeight':
        return BoxFit.fitHeight;
      case 'none':
        return BoxFit.none;
      case 'scaleDown':
        return BoxFit.scaleDown;
      default:
        return BoxFit.contain;
    }
  }

  /// Parses a BorderRadius from JSON.
  /// Supports: {"all": 12} or {"topLeft": 28, "topRight": 28, ...}
  static BorderRadius? _parseBorderRadius(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    final all = (json['all'] as num?)?.toDouble();
    if (all != null) {
      return BorderRadius.circular(all.r);
    }
    return BorderRadius.only(
      topLeft: Radius.circular(((json['topLeft'] as num?)?.toDouble() ?? 0).r),
      topRight: Radius.circular(((json['topRight'] as num?)?.toDouble() ?? 0).r),
      bottomLeft: Radius.circular(((json['bottomLeft'] as num?)?.toDouble() ?? 0).r),
      bottomRight: Radius.circular(((json['bottomRight'] as num?)?.toDouble() ?? 0).r),
    );
  }

  /// Parses a BoxDecoration from JSON (gradient, borderRadius, border).
  static BoxDecoration? _parseDecoration(dynamic json) {
    if (json is! Map<String, dynamic>) return null;

    Gradient? gradient;
    final gradientJson = json['gradient'] as Map<String, dynamic>?;
    if (gradientJson != null) {
      final colors = (gradientJson['colors'] as List<dynamic>?)
              ?.map((c) => _parseColor(c))
              .whereType<Color>()
              .toList() ??
          [];
      if (colors.length >= 2) {
        gradient = LinearGradient(
          begin: _parseAlignmentValue(gradientJson['begin']),
          end: _parseAlignmentValue(gradientJson['end']),
          colors: colors,
        );
      }
    }

    final borderRadius = _parseBorderRadius(json['borderRadius']);

    Border? border;
    final borderJson = json['border'] as Map<String, dynamic>?;
    if (borderJson != null) {
      final borderColor = _parseColor(borderJson['color']) ?? Colors.grey;
      final borderWidth = (borderJson['width'] as num?)?.toDouble() ?? 1;
      border = Border.all(color: borderColor, width: borderWidth);
    }

    final bgColor = _parseColor(json['color']);

    return BoxDecoration(
      gradient: gradient,
      color: gradient == null ? bgColor : null,
      borderRadius: borderRadius,
      border: border,
    );
  }

  static Alignment _parseAlignment(dynamic alignment) {
    if (alignment is! String) return Alignment.center;
    switch (alignment) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      case 'topRight':
        return Alignment.topRight;
      case 'centerLeft':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerRight':
        return Alignment.centerRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'bottomRight':
        return Alignment.bottomRight;
      default:
        return Alignment.center;
    }
  }

  /// Maps alignment strings to [Alignment] constants (used for gradients).
  static Alignment _parseAlignmentValue(dynamic value) {
    if (value is! String) return Alignment.center;
    switch (value) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      case 'topRight':
        return Alignment.topRight;
      case 'centerLeft':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerRight':
        return Alignment.centerRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'bottomRight':
        return Alignment.bottomRight;
      default:
        return Alignment.center;
    }
  }

  static MainAxisSize _parseMainAxisSize(dynamic value) {
    if (value == 'min') return MainAxisSize.min;
    return MainAxisSize.max;
  }

  static MainAxisAlignment _parseMainAxisAlignment(dynamic value) {
    if (value is! String) return MainAxisAlignment.start;
    switch (value) {
      case 'start':
        return MainAxisAlignment.start;
      case 'end':
        return MainAxisAlignment.end;
      case 'center':
        return MainAxisAlignment.center;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      case 'spaceAround':
        return MainAxisAlignment.spaceAround;
      case 'spaceEvenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _parseCrossAxisAlignment(dynamic value) {
    if (value is! String) return CrossAxisAlignment.center;
    switch (value) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'center':
        return CrossAxisAlignment.center;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      case 'baseline':
        return CrossAxisAlignment.baseline;
      default:
        return CrossAxisAlignment.center;
    }
  }

  /// Parses children list → List<Widget>
  static List<Widget> _parseChildren(dynamic children, BuildContext ctx) {
    if (children is! List) return [];
    return children
        .whereType<Map<String, dynamic>>()
        .map((child) => parse(child, ctx))
        .toList();
  }

  /// Parses an onPressed action from JSON and returns a VoidCallback.
  ///
  /// Supported actions:
  ///   - navigateBack: Navigator.pop(context)
  ///   - navigate: Navigator.pushNamed(context, routeName)
  static VoidCallback? _parseOnPressed(dynamic json, BuildContext ctx) {
    if (json is! Map<String, dynamic>) return null;
    final actionType = json['actionType'] as String?;

    switch (actionType) {
      case 'navigateBack':
        return () => Navigator.pop(ctx);
      case 'navigate':
        final request = json['request'] as Map<String, dynamic>?;
        final routeName = request?['routeName'] as String?;
        if (routeName != null) {
          return () {
            // Close the bottom sheet first, then navigate
            Navigator.pop(ctx);
            Navigator.pushNamed(ctx, routeName);
          };
        }
        return null;
      default:
        return null;
    }
  }
}
