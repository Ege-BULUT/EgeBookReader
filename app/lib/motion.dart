import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'settings.dart';

const easeEnter = Cubic(0.22, 1, 0.36, 1);

/// A small overshoot, kept for moments the finger caused: the ribbon dropping, a cover landing.
const easeSettle = Cubic(0.34, 1.4, 0.64, 1);

/// E-ink panels and people who asked the system for less motion get none.
bool motionOn(BuildContext context, Settings s) => !s.isEink && !MediaQuery.disableAnimationsOf(context);

/// The app's mark. With [progress] below 1 it is part way through its entrance: the spine and arms spring into place,
/// the ribbon unfurls from under the spine, light crosses the whole.
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

  // The arms end on a slant, like the edge of a page block seen from the side.
  Path _arm(double top, double length, {required bool slantDown}) {
    final slant = 3 * (length / 38).clamp(0.0, 1.0);
    return Path()
      ..moveTo(0, top)
      ..lineTo(slantDown ? length - slant : length, top)
      ..lineTo(slantDown ? length : length - slant, top + 8)
      ..lineTo(0, top + 8)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 46);

    // A small lift when the ribbon comes out, then back to rest.
    final lift = 1 + 0.05 * sin(pi * _part(0.38, 0.72, Curves.easeInOut));
    canvas.translate(19, 23);
    canvas.scale(lift);
    canvas.translate(-19, -23);

    final spine = _part(0, 0.2, easeSettle);
    final top = 38 * _part(0.1, 0.34, easeSettle);
    final bottom = 38 * _part(0.16, 0.4, easeSettle);
    final paint = Paint()..color = ink;
    final body = Path()
      ..addRect(Rect.fromCenter(center: const Offset(4, 23), width: 8, height: 46 * spine))
      ..addPath(_arm(0, top, slantDown: false), Offset.zero)
      ..addPath(_arm(38, bottom, slantDown: true), Offset.zero);

    final out = 26 * _part(0.38, 0.78, easeSettle);
    if (out > 0) {
      // The ribbon unfurls: a travelling wave, pinned at the spine, that dies away as it settles.
      final amplitude = 3.4 * (1 - _part(0.5, 0.95, Curves.easeOut));
      double wave(double x) => amplitude * sin(x / 26 * pi * 1.7 - t * 24) * (x / 26);
      final shape = Path()..moveTo(8, 19 + wave(0));
      const steps = 16;
      for (var i = 1; i <= steps; i++) {
        final x = out * i / steps;
        shape.lineTo(8 + x, 19 + wave(x));
      }
      shape.lineTo(8 + out - 5 * (out / 26), 23 + wave(out));
      for (var i = steps; i >= 0; i--) {
        final x = out * i / steps;
        shape.lineTo(8 + x, 27 + wave(x));
      }
      shape.close();
      canvas.save();
      canvas.clipRect(const Rect.fromLTWH(8, -8, 40, 62));
      canvas.drawPath(shape, Paint()..color = ribbon);
      canvas.restore();

      final fold = _part(0.68, 0.84, easeEnter);
      if (fold > 0) {
        canvas.drawPath(
          Path()
            ..moveTo(8, 27)
            ..lineTo(8 + 4 * fold, 27)
            ..lineTo(8, 27 + 3.5 * fold)
            ..close(),
          Paint()..color = Color.lerp(ribbon, const Color(0xFF000000), 0.25)!,
        );
      }
    }
    canvas.drawPath(body, paint);

    // A band of light crosses the finished mark once.
    final sheen = _part(0.8, 1, Curves.easeInOut);
    if (sheen > 0 && sheen < 1) {
      final x = -14 + 70 * sheen;
      canvas.save();
      canvas.clipPath(body);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 38, 46),
        Paint()
          ..shader = ui.Gradient.linear(Offset(x - 9, 0), Offset(x + 9, 12), [
            const Color(0x00FFFFFF),
            const Color(0x66FFFFFF),
            const Color(0x00FFFFFF),
          ], const [0, 0.5, 1]),
      );
      canvas.restore();
    }
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
