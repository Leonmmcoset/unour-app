import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Shared timing for quick responses with a softer settling phase.
abstract final class GameMotion {
  static const settle = Curves.easeOutCubic;
  static const spring = Curves.easeOutBack;
  static const change = Curves.easeInOutCubic;

  static bool reduced(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, [int milliseconds = 320]) =>
      Duration(milliseconds: reduced(context) ? 0 : milliseconds);
}

/// Runs once for this widget's identity, rather than on each server snapshot.
class MotionEntrance extends StatefulWidget {
  final Widget child;
  final int delay;
  final Offset offset;
  final bool animate;
  const MotionEntrance({
    super.key,
    required this.child,
    this.delay = 0,
    this.offset = const Offset(0, 20),
    this.animate = true,
  });

  @override
  State<MotionEntrance> createState() => _MotionEntranceState();
}

class _MotionEntranceState extends State<MotionEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 520 + widget.delay),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (GameMotion.reduced(context) || !widget.animate) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final begin = widget.delay / (520 + widget.delay);
      final t = ((_controller.value - begin) / (1 - begin)).clamp(0.0, 1.0);
      final travel = GameMotion.spring.transform(t);
      return Opacity(
        opacity: Curves.easeOut.transform(t),
        child: Transform.translate(
          offset: widget.offset * (1 - travel),
          child: Transform.scale(scale: .96 + .04 * travel, child: child),
        ),
      );
    },
  );
}

/// Pointer feedback without taking over a child's gestures or semantics.
class PressScale extends StatefulWidget {
  final Widget child;
  const PressScale({super.key, required this.child});

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _set(true),
    onPointerUp: (_) => _set(false),
    onPointerCancel: (_) => _set(false),
    child: AnimatedScale(
      scale: _down && !GameMotion.reduced(context) ? .965 : 1,
      duration: GameMotion.duration(context, _down ? 100 : 300),
      curve: _down ? Curves.easeOut : GameMotion.spring,
      child: widget.child,
    ),
  );
}

class MotionSwitcher extends StatelessWidget {
  final Widget child;
  const MotionSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) => GameMotion.reduced(context)
      ? child
      : AnimatedSwitcher(
          duration: GameMotion.duration(context, 340),
          reverseDuration: GameMotion.duration(context, 160),
          switchInCurve: GameMotion.settle,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.center,
            children: [
              for (final old in previous)
                ExcludeSemantics(child: IgnorePointer(child: old)),
              if (current != null) current,
            ],
          ),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, .18),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: child,
        );
}

/// A finite celebration, so idle screens have no permanent animation ticker.
class RoundCelebration extends StatefulWidget {
  final Widget child;
  const RoundCelebration({super.key, required this.child});

  @override
  State<RoundCelebration> createState() => _RoundCelebrationState();
}

class _RoundCelebrationState extends State<RoundCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (GameMotion.reduced(context)) {
      _controller.value = 1;
      _started = true;
    } else if (!_started) {
      _started = true;
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: MotionEntrance(child: widget.child),
    builder: (context, child) =>
        CustomPaint(painter: _ConfettiPainter(_controller.value), child: child),
  );
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  const _ConfettiPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    if (progress == 0 || progress == 1) return;
    const colors = [
      Color(0xffee6470),
      Color(0xff568ee8),
      Color(0xff38a987),
      Color(0xffefbd4e),
    ];
    final travel = Curves.easeOutCubic.transform(progress);
    final fade = (1 - progress).clamp(0.0, 1.0);
    for (var i = 0; i < 28; i++) {
      final angle = i * math.pi * 2 / 28;
      final distance = (44 + (i % 5) * 12) * travel;
      final center = Offset(
        size.width / 2 + math.cos(angle) * distance,
        size.height / 2 + math.sin(angle) * distance + 48 * progress * progress,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle + progress * 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(-3, -2, 6, 4),
          const Radius.circular(1),
        ),
        Paint()..color = colors[i % 4].withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
