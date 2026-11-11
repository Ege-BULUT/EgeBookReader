import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'settings.dart';

const easeEnter = Cubic(0.22, 1, 0.36, 1);

/// A small overshoot, kept for moments the finger caused: the ribbon dropping, a cover landing.
const easeSettle = Cubic(0.34, 1.4, 0.64, 1);

/// E-ink panels and people who asked the system for less motion get none.
bool motionOn(BuildContext context, Settings s) => !s.isEink && !MediaQuery.disableAnimationsOf(context);

/// The app's mark, a calligraphic E with a bookmark ribbon. With [progress] below 1 it is part way through its
/// entrance: the letter is written in from the lower left, then the ribbon unfurls from the stem.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, required this.size, required this.ink, required this.ribbon, this.progress = 1});
  final double size, progress;
  final Color ink, ribbon;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 320 / 256, size), painter: _LogoPainter(progress, ink, ribbon));
}

// The letter E of the Ruthie typeface (Open Font License), in a 320 by 256 box.
final Path _letterE = Path()
      ..moveTo(238.05, 256.12)
      ..quadraticBezierTo(216.24, 256.12, 173.55, 240.23)
      ..quadraticBezierTo(157.35, 234, 141.3, 227.61)
      ..quadraticBezierTo(125.26, 221.23, 108.74, 215.31)
      ..quadraticBezierTo(77.59, 249.27, 39.26, 249.27)
      ..quadraticBezierTo(26.8, 249.27, 14.02, 242.41)
      ..quadraticBezierTo(0, 234.31, 0, 222.78)
      ..quadraticBezierTo(0, 207.83, 14.96, 200.35)
      ..quadraticBezierTo(26.8, 194.74, 43, 194.74)
      ..quadraticBezierTo(56.4, 194.74, 77.9, 201.29)
      ..quadraticBezierTo(90.05, 187.58, 100.02, 168.57)
      ..quadraticBezierTo(109.99, 149.56, 117.78, 125.57)
      ..quadraticBezierTo(132.11, 82.88, 135.23, 41.13)
      ..quadraticBezierTo(125.26, 39.57, 116.53, 39.1)
      ..quadraticBezierTo(107.81, 38.64, 100.64, 38.64)
      ..quadraticBezierTo(92.23, 38.64, 85.53, 39.26)
      ..quadraticBezierTo(78.83, 39.88, 73.22, 41.44)
      ..quadraticBezierTo(44.25, 49.23, 44.25, 77.27)
      ..quadraticBezierTo(44.25, 102.82, 73.53, 123.39)
      ..quadraticBezierTo(75.09, 124.01, 75.09, 124.95)
      ..quadraticBezierTo(75.09, 125.88, 73.85, 125.88)
      ..quadraticBezierTo(73.22, 125.88, 71.98, 125.26)
      ..quadraticBezierTo(32.72, 102.82, 32.72, 71.67)
      ..quadraticBezierTo(32.72, 54.22, 47.36, 43.62)
      ..quadraticBezierTo(59.2, 34.59, 78.21, 32.72)
      ..quadraticBezierTo(86.31, 31.78, 95.03, 31.78)
      ..quadraticBezierTo(103.76, 31.78, 113.73, 32.56)
      ..quadraticBezierTo(123.7, 33.34, 135.54, 34.9)
      ..quadraticBezierTo(135.85, 30.85, 136.01, 26.95)
      ..quadraticBezierTo(136.16, 23.06, 136.16, 19.32)
      ..quadraticBezierTo(136.16, 17.76, 136.16, 15.74)
      ..quadraticBezierTo(136.16, 13.71, 135.85, 10.59)
      ..quadraticBezierTo(135.54, 7.79, 135.54, 5.61)
      ..quadraticBezierTo(135.54, 3.43, 135.54, 2.18)
      ..quadraticBezierTo(135.54, 0, 136.79, 0)
      ..quadraticBezierTo(137.1, 0, 137.72, 1.56)
      ..quadraticBezierTo(140.21, 15.27, 139.59, 35.52)
      ..quadraticBezierTo(149.25, 36.77, 162.34, 39.1)
      ..quadraticBezierTo(175.42, 41.44, 191.94, 44.87)
      ..quadraticBezierTo(217.18, 12.15, 243.35, 12.15)
      ..quadraticBezierTo(266.1, 12.15, 266.1, 31.16)
      ..quadraticBezierTo(266.1, 34.59, 264.54, 34.59)
      ..quadraticBezierTo(263.29, 34.59, 263.29, 31.78)
      ..quadraticBezierTo(263.29, 24.3, 257.37, 21.19)
      ..quadraticBezierTo(252.39, 18.07, 244.91, 18.07)
      ..quadraticBezierTo(225.28, 18.07, 205.02, 47.05)
      ..quadraticBezierTo(233.07, 52.66, 252.07, 55.31)
      ..quadraticBezierTo(271.08, 57.96, 281.67, 57.96)
      ..quadraticBezierTo(293.83, 57.96, 302.55, 55.15)
      ..quadraticBezierTo(315.64, 50.48, 315.64, 41.44)
      ..quadraticBezierTo(315.64, 38.64, 314.39, 37.08)
      ..quadraticBezierTo(313.46, 34.59, 313.46, 34.27)
      ..quadraticBezierTo(313.46, 33.34, 314.39, 33.34)
      ..quadraticBezierTo(316.57, 33.34, 318.13, 38.64)
      ..quadraticBezierTo(320, 43.62, 320, 46.74)
      ..quadraticBezierTo(320, 68.24, 285.41, 68.24)
      ..quadraticBezierTo(274.82, 68.24, 253.63, 64.5)
      ..quadraticBezierTo(232.44, 60.76, 200.66, 53.9)
      ..quadraticBezierTo(196.92, 60.14, 187.26, 78.99)
      ..quadraticBezierTo(177.6, 97.84, 162.03, 129.62)
      ..quadraticBezierTo(167.95, 127.75, 177.29, 126.66)
      ..quadraticBezierTo(186.64, 125.57, 199.42, 125.57)
      ..quadraticBezierTo(234, 125.57, 254.88, 132.74)
      ..quadraticBezierTo(256.44, 133.36, 256.44, 133.98)
      ..quadraticBezierTo(256.44, 134.92, 255.19, 134.92)
      ..quadraticBezierTo(252.07, 134.92, 243.97, 133.98)
      ..quadraticBezierTo(240.23, 133.67, 237.43, 133.52)
      ..quadraticBezierTo(234.63, 133.36, 232.44, 133.36)
      ..quadraticBezierTo(220.29, 133.36, 209.07, 134.14)
      ..quadraticBezierTo(197.86, 134.92, 187.26, 137.1)
      ..quadraticBezierTo(153.3, 143.02, 153.3, 157.66)
      ..quadraticBezierTo(153.3, 159.84, 154.86, 163.58)
      ..lineTo(154.86, 164.21)
      ..quadraticBezierTo(151.43, 164.21, 148.63, 156.73)
      ..quadraticBezierTo(129.62, 191.31, 112.48, 211.26)
      ..quadraticBezierTo(128.06, 215.93, 143.64, 220.6)
      ..quadraticBezierTo(159.22, 225.28, 174.49, 229.64)
      ..quadraticBezierTo(193.5, 234.94, 209.23, 237.74)
      ..quadraticBezierTo(224.97, 240.55, 237.74, 240.55)
      ..quadraticBezierTo(254.88, 240.55, 266.41, 235.25)
      ..quadraticBezierTo(282.3, 228.08, 282.3, 214.06)
      ..quadraticBezierTo(282.3, 203.47, 272.95, 188.2)
      ..quadraticBezierTo(268.59, 180.72, 266.25, 176.98)
      ..quadraticBezierTo(263.91, 173.24, 263.91, 173.24)
      ..quadraticBezierTo(263.91, 172.93, 264.23, 172.93)
      ..quadraticBezierTo(265.47, 172.93, 267.65, 175.11)
      ..quadraticBezierTo(286.97, 191, 286.97, 213.13)
      ..quadraticBezierTo(286.97, 232.76, 272.02, 244.91)
      ..quadraticBezierTo(257.99, 256.12, 238.05, 256.12)
      ..close()
      ..moveTo(96.9, 207.21)
      ..quadraticBezierTo(111.24, 192.87, 133.36, 148.63)
      ..quadraticBezierTo(139.59, 136.16, 145.67, 123.54)
      ..quadraticBezierTo(151.74, 110.93, 158.29, 98.46)
      ..quadraticBezierTo(165.45, 84.44, 172.93, 72.44)
      ..quadraticBezierTo(180.41, 60.45, 187.26, 51.1)
      ..quadraticBezierTo(172.93, 47.67, 160.93, 45.49)
      ..quadraticBezierTo(148.94, 43.31, 139.28, 41.75)
      ..quadraticBezierTo(138.03, 62.63, 133.98, 83.97)
      ..quadraticBezierTo(129.93, 105.32, 123.08, 126.82)
      ..quadraticBezierTo(107.81, 174.49, 83.51, 203.15)
      ..close()
      ..moveTo(36.14, 243.04)
      ..quadraticBezierTo(43.31, 243.04, 51.57, 240.55)
      ..quadraticBezierTo(59.82, 238.05, 68.86, 232.76)
      ..quadraticBezierTo(86.62, 222.78, 95.03, 210.94)
      ..quadraticBezierTo(92.85, 210.32, 89.43, 209.07)
      ..quadraticBezierTo(86, 207.83, 80.7, 206.27)
      ..quadraticBezierTo(58.89, 230.26, 35.21, 230.26)
      ..quadraticBezierTo(29.29, 230.26, 29.29, 228.08)
      ..quadraticBezierTo(29.29, 226.52, 34.59, 226.52)
      ..quadraticBezierTo(54.84, 226.52, 75.09, 204.71)
      ..quadraticBezierTo(57.33, 199.1, 43.62, 199.1)
      ..quadraticBezierTo(30.54, 199.1, 20.25, 203.78)
      ..quadraticBezierTo(7.17, 209.7, 7.17, 221.54)
      ..quadraticBezierTo(7.17, 232.13, 17.14, 237.74)
      ..quadraticBezierTo(25.86, 243.04, 36.14, 243.04)
      ..close();

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t, this.ink, this.ribbon);
  final double t;
  final Color ink, ribbon;

  double _part(double from, double to, Curve curve) => curve.transform(((t - from) / (to - from)).clamp(0.0, 1.0));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.height / 256);

    // A small lift when the ribbon comes out, then back to rest.
    final lift = 1 + 0.05 * sin(pi * _part(0.42, 0.74, Curves.easeInOut));
    canvas.translate(160, 128);
    canvas.scale(lift);
    canvas.translate(-160, -128);

    // The pen moves from the lower left to the upper right.
    final written = _part(0, 0.46, Curves.easeInOutCubic);
    if (written > 0) {
      final reach = -80 + 700 * written;
      canvas.save();
      canvas.clipPath(Path()
        ..moveTo(-40, 300)
        ..lineTo(reach - 80, 300)
        ..lineTo(reach + 90, -40)
        ..lineTo(-40, -40)
        ..close());
      canvas.drawPath(_letterE, Paint()..color = ink);
      canvas.restore();
    }

    final out = 142 * _part(0.42, 0.82, easeSettle);
    if (out > 0) {
      // The ribbon unfurls: a travelling wave, pinned at the stem, that dies away as it settles.
      final amplitude = 13 * (1 - _part(0.52, 0.97, Curves.easeOut));
      double wave(double x) => amplitude * sin(x / 142 * pi * 1.7 - t * 24) * (x / 142);
      const left = 156.0, top = 124.0, height = 30.0;
      final shape = Path()..moveTo(left, top + wave(0));
      const steps = 18;
      for (var i = 1; i <= steps; i++) {
        final x = out * i / steps;
        shape.lineTo(left + x, top + wave(x));
      }
      shape.lineTo(left + out - 14 * (out / 142), top + height / 2 + wave(out));
      for (var i = steps; i >= 0; i--) {
        final x = out * i / steps;
        shape.lineTo(left + x, top + height + wave(x));
      }
      shape.close();
      canvas.drawPath(shape, Paint()..color = ribbon);
    }

    // A band of light crosses the finished letter once.
    final sheen = _part(0.82, 1, Curves.easeInOut);
    if (sheen > 0 && sheen < 1) {
      final x = -60 + 460 * sheen;
      canvas.save();
      canvas.clipPath(_letterE);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 320, 256),
        Paint()
          ..shader = ui.Gradient.linear(Offset(x - 50, 0), Offset(x + 50, 70), [
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
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _pointer(e.localPosition, box.biggest),
        onPointerMove: (e) => _pointer(e.localPosition, box.biggest),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: GestureDetector(
          // The whole box is the button, gaps between its texts too.
          behavior: HitTestBehavior.opaque,
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
