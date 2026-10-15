import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';

/// iOS page transition with a back swipe that starts anywhere on the screen,
/// not just the 20px left edge Flutter's [CupertinoPageTransitionsBuilder]
/// listens on, and works in both directions. The slide animation itself is
/// the stock Cupertino one.
///
/// The gesture is only armed when [PageRoute.popGestureEnabled] is true, so
/// screens that block back with `PopScope(canPop: false)` (login, MPIN app
/// lock, success screens, payment webviews, KYC while verifying) stay blocked.
/// Horizontal scrollables, sliders and Dismissibles inside a page still win
/// their own drags — they sit deeper in the hit test and claim first.
class FullSwipePageTransitionsBuilder extends PageTransitionsBuilder {
  const FullSwipePageTransitionsBuilder();

  @override
  Duration get transitionDuration =>
      CupertinoRouteTransitionMixin.kTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.fullscreenDialog) {
      return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    return CupertinoPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      // Follow the finger linearly while a swipe is in progress.
      linearTransition: route.popGestureInProgress,
      child: _FullSwipeBackDetector<T>(route: route, child: child),
    );
  }
}

// Same constants as Flutter's own Cupertino back gesture.
const double _kMinFlingVelocity = 1.0; // Screen widths per second.
const Duration _kDroppedSwipeDuration = Duration(milliseconds: 350);

class _FullSwipeBackDetector<T> extends StatefulWidget {
  const _FullSwipeBackDetector({required this.route, required this.child});

  final PageRoute<T> route;
  final Widget child;

  @override
  State<_FullSwipeBackDetector<T>> createState() =>
      _FullSwipeBackDetectorState<T>();
}

class _FullSwipeBackDetectorState<T> extends State<_FullSwipeBackDetector<T>> {
  late final HorizontalDragGestureRecognizer _recognizer;
  NavigatorState? _navigator;

  // The route's own AnimationController. It is @protected on
  // TransitionRoute, but driving it is exactly what Flutter's built-in
  // Cupertino back gesture does too.
  AnimationController get _controller =>
      // ignore: invalid_use_of_protected_member
      widget.route.controller!;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    // Disposed mid-drag: release the navigator's user-gesture lock.
    final navigator = _navigator;
    if (navigator != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (navigator.mounted) navigator.didStopUserGesture();
      });
      _navigator = null;
    }
    super.dispose();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.route.popGestureEnabled) _recognizer.addPointer(event);
  }

  double _toLogical(double value) =>
      Directionality.of(context) == TextDirection.rtl ? -value : value;

  // A right swipe drags the page off like the stock iOS gesture. A left swipe
  // also goes back (requested for this app), but the Cupertino slide only
  // moves rightwards, so it can't follow the finger: it is tracked here and
  // pops with the normal back animation on release if it went far enough.
  double? _leftSwipeDx;

  void _handleDragStart(DragStartDetails details) {
    _leftSwipeDx = null;
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = _toLogical(details.primaryDelta!);
    if (_navigator == null && _leftSwipeDx == null) {
      // The first movement decides which kind of swipe this is.
      if (delta > 0) {
        _navigator = widget.route.navigator!..didStartUserGesture();
      } else if (delta < 0) {
        _leftSwipeDx = 0;
      } else {
        return;
      }
    }
    if (_navigator != null) {
      _controller.value -= delta / context.size!.width;
    } else {
      _leftSwipeDx = _leftSwipeDx! + delta;
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    final velocity =
        _toLogical(details.velocity.pixelsPerSecond.dx / context.size!.width);
    if (_navigator != null) {
      _finish(velocity);
    } else if (_leftSwipeDx != null) {
      final distance = -_leftSwipeDx! / context.size!.width;
      _leftSwipeDx = null;
      if (distance > 0.25 ||
          (distance > 0 && velocity <= -_kMinFlingVelocity)) {
        if (widget.route.isCurrent) widget.route.navigator?.maybePop();
      }
    }
  }

  void _handleDragCancel() {
    _leftSwipeDx = null;
    if (_navigator != null) _finish(0.0);
  }

  // Mirrors Flutter's _CupertinoBackGestureController.dragEnd.
  void _finish(double velocity) {
    final navigator = _navigator!;
    _navigator = null;
    final controller = _controller;
    const curve = Curves.fastEaseInToSlowEaseOut;
    final isCurrent = widget.route.isCurrent;

    final bool stay;
    if (!isCurrent) {
      stay = widget.route.isActive;
    } else if (velocity.abs() >= _kMinFlingVelocity) {
      stay = velocity <= 0;
    } else {
      stay = controller.value > 0.5;
    }

    if (stay) {
      controller.animateTo(1.0, duration: _kDroppedSwipeDuration, curve: curve);
    } else {
      if (isCurrent) navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(0.0,
            duration: _kDroppedSwipeDuration, curve: curve);
      }
    }

    if (controller.isAnimating) {
      // Keep the gesture "in progress" until the settle animation ends so the
      // transition curve doesn't switch mid-flight.
      late AnimationStatusListener listener;
      listener = (AnimationStatus status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}
