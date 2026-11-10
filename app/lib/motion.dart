import 'dart:math';

import 'package:flutter/material.dart';

import 'settings.dart';

const easeEnter = Cubic(0.22, 1, 0.36, 1);

/// A small overshoot, kept for moments the finger caused: the ribbon dropping, a cover landing.
const easeSettle = Cubic(0.34, 1.4, 0.64, 1);

/// E-ink panels and people who asked the system for less motion get none.
bool motionOn(BuildContext context, Settings s) => !s.isEink && !MediaQuery.disableAnimationsOf(context);

/// The app's mark: an E whose spine and arms are drawn in, then the ribbon slides out of the spine.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, required this.size, required this.ink, required this.ribbon, this.progress = 1});
  final double size, progress;
  final Color ink, ribbon;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 38 / 46, size), painter: _LogoPainter(progress, ink, ribbon));
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t, this.ink, this.ribbon);
  final double t;
  final Color ink, ribbon;

  double _part(double from, double to, Curve curve) => curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 46);
    final p = Paint()..color = ink;
    canvas.drawRect(Rect.fromLTWH(0, 0, 8, 46 * _part(0, 0.3, easeEnter)), p);
    canvas.drawRect(Rect.fromLTWH(0, 0, 38 * _part(0.1, 0.4, easeEnter), 8), p);
    canvas.drawRect(Rect.fromLTWH(0, 38, 38 * _part(0.2, 0.5, easeEnter), 8), p);
    final out = 26 * _part(0.5, 1, easeSettle);
    if (out <= 0) return;
    canvas.save();
    canvas.clipRect(const Rect.fromLTWH(8, 0, 34, 46));
    canvas.drawPath(
      Path()
        ..moveTo(8 - 26 + out, 19)
        ..lineTo(8 + out, 19)
        ..lineTo(3 + out, 23)
        ..lineTo(8 + out, 27)
        ..lineTo(8 - 26 + out, 27)
        ..close(),
      Paint()..color = ribbon,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LogoPainter o) => o.t != t || o.ink != ink || o.ribbon != ribbon;
}

/// Fades and rises into place, later for higher [index]. Only the first six are staggered, so a long
/// list never makes anyone wait.
class Rise extends StatefulWidget {
  const Rise({super.key, required this.index, required this.enabled, required this.child});
  final int index;
  final bool enabled;
  final Widget child;
  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _v = CurvedAnimation(parent: _c, curve: easeEnter);

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      _c.value = 1;
      return;
    }
    Future<void>.delayed(Duration(milliseconds: 50 * min(widget.index, 5)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _v.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _v,
        builder: (_, child) => Opacity(
          opacity: _v.value,
          child: Transform.translate(offset: Offset(0, 10 * (1 - _v.value)), child: child),
        ),
        child: widget.child,
      );
}

/// Sinks under the finger and leans toward where it presses, like picking up a real object.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.enabled, this.onTap, this.onLongPress});
  final Widget child;
  final bool enabled;
  final VoidCallback? onTap, onLongPress;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  Offset _lean = Offset.zero;
  bool _down = false;

  void _pointer(Offset local, Size size) {
    if (!widget.enabled) return;
    setState(() {
      _down = true;
      _lean = Offset((local.dx / size.width - 0.5) * 2, (local.dy / size.height - 0.5) * 2);
    });
  }

  void _release() => setState(() {
        _down = false;
        _lean = Offset.zero;
      });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      return Listener(
        onPointerDown: (e) => _pointer(e.localPosition, box.biggest),
        onPointerMove: (e) => _pointer(e.localPosition, box.biggest),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: TweenAnimationBuilder<Offset>(
            tween: Tween(end: _lean),
            duration: Duration(milliseconds: _down ? 90 : 260),
            curve: _down ? Curves.easeOut : easeSettle,
            builder: (_, lean, child) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0014)
                ..rotateX(lean.dy * 0.1)
                ..rotateY(-lean.dx * 0.1),
              child: AnimatedScale(
                scale: _down ? 0.97 : 1,
                duration: const Duration(milliseconds: 90),
                child: child,
              ),
            ),
            child: widget.child,
          ),
        ),
      );
    });
  }
}
