import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';

/// Premium micro savings banner card — fully custom-built.
///
/// All visual elements are rendered by the widget (no background PNG),
/// eliminating any duplication. The micro.png illustration is shown
/// only on the right side via alignment cropping.
class MicroSavingsBanner extends StatefulWidget {
  final VoidCallback onSwipeComplete;

  const MicroSavingsBanner({super.key, required this.onSwipeComplete});

  @override
  State<MicroSavingsBanner> createState() => _MicroSavingsBannerState();
}

class _MicroSavingsBannerState extends State<MicroSavingsBanner>
    with TickerProviderStateMixin {
  double _dragOffset = 0;
  bool _swiped = false;

  late final AnimationController _hintController;
  late final Animation<double> _hintAnimation;

  // Chevron cascading animation
  late final AnimationController _chevronController;

  double get _trackWidth => 195.w;
  double get _thumbSize => 42.w;
  double get _maxDrag => _trackWidth - _thumbSize - 8.w;

  @override
  void initState() {
    super.initState();
    _hintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _hintAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween:
            Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 20),
    ]).animate(_hintController);
    _hintController.repeat();

    // Chevron wave — cycles 0→1 over 1200ms, each chevron staggers by 0.33
    _chevronController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _chevronController.dispose();
    _hintController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _hintController.stop();
    _hintController.value = 0;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (_swiped) return;
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dx).clamp(0.0, _maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails _) {
    if (_swiped) return;
    if (_dragOffset >= _maxDrag * 0.7) {
      setState(() {
        _swiped = true;
        _dragOffset = _maxDrag;
      });
      widget.onSwipeComplete();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _swiped = false;
            _dragOffset = 0;
          });
          _hintController.repeat();
        }
      });
    } else {
      setState(() => _dragOffset = 0);
      _hintController.repeat();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160.h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFF9D876), Color(0xFFF0A500)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF0A500).withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20.r),
        child: Stack(
          children: [
            // ── Illustration (right side only — cropped from micro.png) ──
            Positioned(
              right: -10.w,
              bottom: -10.h,
              top: 10.h,
              width: 160.w,
              child: Align(
                alignment: Alignment.centerRight,
                child: Image.asset(
                  'assets/home/micro-gold.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

            // ── Heading text (top-left) ──
            Positioned(
              left: 24.w,
              top: 16.h,
              right: 80.w,
              child: Text(
                'Micro Savings, Mega Rewards',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8B5E00),
                  height: 1.3,
                  letterSpacing: -0.3,
                ),
              ),
            ),

            // ── Interactive swipe track ──
            Positioned(
              left: 18.w,
              bottom: 58.h,
              child: _buildSwipeTrack(),
            ),

            // ── Subtitle text (below swipe bar) ──
            Positioned(
              left: 24.w,
              bottom: 12.h,
              child: Text(
                'Small steps today,\nBig rewards tomorrow.',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xCC010101),
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwipeTrack() {
    return Container(
      width: _trackWidth,
      height: 48.h,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(100.r),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // ── "Swipe >>>" label ──
          Center(
            child: Padding(
              padding: EdgeInsets.only(left: 20.w),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Swipe',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8B5E00).withValues(alpha: 0.6),
                    ),
                  ),
                  SizedBox(width: 10.w),
                  // Animated cascading chevrons
                  AnimatedBuilder(
                    animation: _chevronController,
                    builder: (_, __) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(3, (i) {
                          // Each chevron lights up in sequence:
                          // chevron 0 peaks at t=0.17, chevron 1 at t=0.50, chevron 2 at t=0.83
                          final phase = ((_chevronController.value - i * 0.33) % 1.0);
                          // Fade in for first half of its cycle, fade out for second half
                          final opacity = phase < 0.5
                              ? (phase * 2.0).clamp(0.0, 1.0)
                              : ((1.0 - phase) * 2.0).clamp(0.0, 1.0);
                          final alpha = 0.15 + (opacity * 0.65); // range: 0.15 → 0.80
                          return Icon(
                            Icons.chevron_right_rounded,
                            size: 16.sp,
                            color: const Color(0xFF8B5E00).withValues(alpha: alpha),
                          );
                        }),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // ── Draggable ₹ coin thumb ──
          AnimatedBuilder(
            animation: _hintAnimation,
            builder: (_, child) {
              final hintPx = (_dragOffset == 0 && !_swiped)
                  ? _hintAnimation.value * 20.w
                  : 0.0;
              return Positioned(
                left: 3.w + _dragOffset + hintPx,
                top: 0,
                bottom: 0,
                child: Center(child: child!),
              );
            },
            child: GestureDetector(
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                width: _thumbSize,
                height: _thumbSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFDD835), Color(0xFFF9A825)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFF9A825).withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    '₹',
                    style: GoogleFonts.lora(
                      fontSize: 18.sp,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF8B5E00),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
