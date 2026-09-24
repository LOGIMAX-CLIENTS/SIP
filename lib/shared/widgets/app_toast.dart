import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'numeric_styled_text.dart';

/// Toast type determines color palette and icon.
enum ToastType { success, error, warning, info }

/// Where the toast appears on screen.
enum ToastPosition {
  /// Bottom of screen (default). Hidden by keyboard when input is active.
  bottom,

  /// Vertically centred. Always visible even when the keyboard is open.
  center,

  /// Top of screen, below the status bar.
  top,
}

/// AppToast
///
/// Premium floating overlay toast with:
///   • fade-in + slide entry animation
///   • auto-dismiss after [duration]
///   • fade-out exit
///   • success / error / warning / info variants
///   • bottom / center / top positioning
///
/// Usage:
/// ```dart
/// // Always visible — use center when keyboard may be open
/// AppToast.show(context, 'Invalid amount', type: ToastType.error,
///               position: ToastPosition.center);
///
/// // Default bottom
/// AppToast.show(context, 'Copied!', type: ToastType.success);
/// ```
class AppToast {
  AppToast._();

  static OverlayEntry? _currentEntry;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(milliseconds: 2800),
    /// Kept for backward-compatibility. Ignored when [position] is set explicitly.
    bool showAtBottom = true,
    // Default is center — always visible even when keyboard is open.
    ToastPosition position = ToastPosition.center,
  }) {
    // Dismiss any active toast immediately
    _dismiss();

    // Dismiss keyboard so the toast is never obscured.
    // This is a no-op when the keyboard is already closed.
    FocusManager.instance.primaryFocus?.unfocus();

    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;

    // Resolve final position (legacy bool takes lower priority than enum)
    final resolvedPosition = position != ToastPosition.bottom
        ? position
        : (showAtBottom ? ToastPosition.bottom : ToastPosition.top);

    entry = OverlayEntry(
      builder: (_) => _ToastWidget(
        message: message,
        type: type,
        duration: duration,
        position: resolvedPosition,
        onDismiss: () {
          _safeRemoveEntry(entry);
          if (_currentEntry == entry) _currentEntry = null;
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  /// Safely removes an OverlayEntry, guarding against double-removal.
  /// OverlayEntry.remove() throws an assertion if called on an entry that
  /// is not currently mounted in the overlay. This happens when:
  ///   - Auto-dismiss timer fires after _dismiss() already removed it
  ///   - Navigation popped the route that owned the overlay context
  static void _safeRemoveEntry(OverlayEntry entry) {
    try {
      if (entry.mounted) {
        entry.remove();
      }
    } catch (_) {
      // Swallow — entry was already removed by another path.
    }
  }

  static void _dismiss() {
    final entry = _currentEntry;
    _currentEntry = null;
    if (entry != null) {
      _safeRemoveEntry(entry);
    }
  }

  /// Dismiss whatever toast is currently showing, if any — before its own
  /// auto-dismiss [duration] elapses. Needed because a toast lives on the
  /// ROOT overlay (see [show]'s `rootOverlay: true`), independent of route
  /// navigation: a warning shown just before an authoritative result
  /// arrives (e.g. a "payment status unclear" fallback that fires while a
  /// slower confirm call is still in flight) would otherwise keep floating
  /// on top of whatever screen is navigated to next for the rest of its
  /// ~2.8s lifetime, even after that screen shows the real, contradicting
  /// outcome. Call this right before navigating away once the authoritative
  /// result is known, so a since-superseded toast can't outlive it.
  static void dismiss() => _dismiss();
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final ToastPosition position;
  final VoidCallback onDismiss;

  const _ToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.position,
    required this.onDismiss,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      reverseDuration: const Duration(milliseconds: 280),
    );

    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

    // Slide direction depends on position
    final slideBegin = switch (widget.position) {
      ToastPosition.bottom => const Offset(0, 0.35),
      ToastPosition.top => const Offset(0, -0.35),
      ToastPosition.center => const Offset(0, 0.15),
    };

    _slide = Tween<Offset>(
      begin: slideBegin,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();

    // Auto-dismiss after duration
    Future.delayed(widget.duration, () async {
      if (mounted) {
        await _controller.reverse();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  _ToastStyle get _style => _resolveStyle(widget.type);

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPad = mediaQuery.padding.bottom;
    final topPad = mediaQuery.padding.top;

    Widget positionedToast;

    // Material must be INSIDE Positioned, not wrapping it.
    // Positioned only works as a direct child of a Stack ancestor
    // (the Overlay uses a Stack-like layout internally).
    Widget materialAnimated() => Material(
          color: Colors.transparent,
          child: _buildAnimated(),
        );

    switch (widget.position) {
      case ToastPosition.bottom:
        positionedToast = Positioned(
          left: 20.w,
          right: 20.w,
          bottom: bottomPad + 24.h,
          child: materialAnimated(),
        );
      case ToastPosition.top:
        positionedToast = Positioned(
          left: 20.w,
          right: 20.w,
          top: topPad + 12.h,
          child: materialAnimated(),
        );
      case ToastPosition.center:
        // Use Align so the toast sits in the true visual centre regardless
        // of keyboard inset — the overlay ignores the IME inset.
        positionedToast = Positioned.fill(
          child: Align(
            alignment: const Alignment(0, -0.2), // slightly above centre
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: materialAnimated(),
            ),
          ),
        );
    }

    return positionedToast;
  }

  Widget _buildAnimated() {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: _buildCard(),
      ),
    );
  }

  Widget _buildCard() {
    return Container(
      constraints: BoxConstraints(maxWidth: 480.w),
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: _style.background,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: _style.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _style.shadow,
            blurRadius: 28,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon pill
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: _style.iconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(_style.icon, color: _style.iconColor, size: 18.sp),
          ),
          SizedBox(width: 12.w),
          // Message
          Flexible(
            child: NumericStyledText(
              widget.message,
              fontSize: 13.5.sp,
              fontWeight: FontWeight.w500,
              color: _style.textColor,
            ),
          ),
        ],
      ),
    );
  }

  _ToastStyle _resolveStyle(ToastType type) {
    switch (type) {
      case ToastType.success:
        return _ToastStyle(
          background: const Color(0xFFF0FDF4),
          border: const Color(0xFFBBF7D0),
          shadow: const Color(0xFF16A34A).withValues(alpha: 0.18),
          iconBackground: const Color(0xFFDCFCE7),
          iconColor: const Color(0xFF16A34A),
          icon: Icons.check_circle_rounded,
          textColor: const Color(0xFF14532D),
        );
      case ToastType.error:
        return _ToastStyle(
          background: const Color(0xFFFFF1F2),
          border: const Color(0xFFFECDD3),
          shadow: const Color(0xFFDC2626).withValues(alpha: 0.18),
          iconBackground: const Color(0xFFFFE4E6),
          iconColor: const Color(0xFFDC2626),
          icon: Icons.error_rounded,
          textColor: const Color(0xFF7F1D1D),
        );
      case ToastType.warning:
        return _ToastStyle(
          background: const Color(0xFFFFFBEB),
          border: const Color(0xFFFDE68A),
          shadow: const Color(0xFFD97706).withValues(alpha: 0.18),
          iconBackground: const Color(0xFFFEF3C7),
          iconColor: const Color(0xFFD97706),
          icon: Icons.warning_amber_rounded,
          textColor: const Color(0xFF78350F),
        );
      case ToastType.info:
        return _ToastStyle(
          background: const Color(0xFFEFF6FF),
          border: const Color(0xFFBFDBFE),
          shadow: const Color(0xFF2563EB).withValues(alpha: 0.18),
          iconBackground: const Color(0xFFDBEAFE),
          iconColor: const Color(0xFF2563EB),
          icon: Icons.info_rounded,
          textColor: const Color(0xFF1E3A5F),
        );
    }
  }
}

class _ToastStyle {
  final Color background;
  final Color border;
  final Color shadow;
  final Color iconBackground;
  final Color iconColor;
  final IconData icon;
  final Color textColor;

  const _ToastStyle({
    required this.background,
    required this.border,
    required this.shadow,
    required this.iconBackground,
    required this.iconColor,
    required this.icon,
    required this.textColor,
  });
}
