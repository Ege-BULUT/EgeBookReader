import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Where the fold lies on one frame of a turn: unit normal [n] pointing at the free edge, axis offset
/// [t] (points on the axis satisfy dot(p, n) == t) and cylinder radius [r].
class Fold {
  const Fold(this.n, this.t, this.r);
  final Offset n;
  final double t, r;
}

double _dot(Offset a, Offset b) => a.dx * b.dx + a.dy * b.dy;

/// Keeps the finger where the paper can reach without tearing off its hinge.
Offset clampFinger(Offset f, Offset grab, double hinge, double h) {
  for (final anchor in [Offset(hinge, 0), Offset(hinge, h)]) {
    final max = (grab - anchor).distance;
    final d = f - anchor;
    if (d.distance > max) f = anchor + d / d.distance * max;
  }
  return f;
}

/// The paper point [grab] has been carried to the finger [f]. The axis is the perpendicular bisector of
/// grab and finger, moved back by half the arc the paper spends rolling over the cylinder.
Fold computeFold({
  required Offset grab,
  required Offset f,
  required double hinge,
  required double pageW,
  required double maxR,
  required double maxTilt,
}) {
  final delta = grab - f;
  final dist = delta.distance;
  var n = dist < 1e-3 ? const Offset(1, 0) : delta / dist;
  final tilt = atan2(n.dy, max(n.dx, 1e-6)).clamp(-maxTilt, maxTilt);
  n = Offset(cos(tilt), sin(tilt));
  final toEnd = (f - Offset(hinge - pageW, grab.dy)).distance;
  final r = [maxR, dist / pi, toEnd / 2].reduce(min).clamp(0.5, maxR);
  return Fold(n, (_dot(f, n) + _dot(grab, n) - pi * r) / 2, r);
}

class CurlPainter extends CustomPainter {
  CurlPainter({
    required this.shader,
    required this.fold,
    required this.hinge,
    required this.pageW,
    required this.showThrough,
    required this.paper,
    required this.front,
    required this.back,
    required this.under,
    required this.left,
    super.repaint,
  });

  final ui.FragmentShader shader;
  final Fold Function() fold;
  final double hinge, pageW;
  final bool showThrough;
  final Color paper;
  final ui.Image front, back, under, left;

  @override
  void paint(Canvas canvas, Size size) {
    final f = fold();
    final values = <double>[
      size.width, size.height, hinge, pageW, f.n.dx, f.n.dy, f.t, f.r,
      showThrough ? 1 : 0, paper.r, paper.g, paper.b,
    ];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, front);
    shader.setImageSampler(1, back);
    shader.setImageSampler(2, under);
    shader.setImageSampler(3, left);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(CurlPainter old) => true;
}

/// What the page view needs from the book for a turn starting at the current position.
class TurnPages {
  const TurnPages(this.front, this.back, this.under, this.left);
  final ui.Image front, back, under, left;
}

/// Shows the current page(s) and turns them with the finger.
class PageCurlView extends StatefulWidget {
  const PageCurlView({
    super.key,
    required this.program,
    required this.spread,
    required this.paper,
    required this.animate,
    required this.canGo,
    required this.pagesFor,
    required this.still,
    required this.onTurned,
    required this.onTap,
  });

  final ui.FragmentProgram program;
  final bool spread;
  final Color paper;

  /// False in E-ink mode and when the system asks for reduced motion: pages change at once.
  final bool animate;

  /// Whether a forward (+1) or backward (-1) turn is possible.
  final bool Function(int dir) canGo;

  /// Images for the turn that goes forward from position [from]; null while they are being rendered.
  final TurnPages? Function(int from) pagesFor;
  final Widget still;
  final void Function(int dir) onTurned;
  final void Function(Offset local, Size size) onTap;

  @override
  State<PageCurlView> createState() => PageCurlViewState();
}

class PageCurlViewState extends State<PageCurlView> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController.unbounded(vsync: this);
  late final ui.FragmentShader _shader = widget.program.fragmentShader();
  final _frame = ValueNotifier<int>(0);

  TurnPages? _pages;
  int _dir = 0;
  Offset _grab = Offset.zero, _finger = Offset.zero, _start = Offset.zero;
  double _maxTilt = 0;
  Offset _from = Offset.zero, _to = Offset.zero;
  bool _landing = false;
  Size _size = Size.zero;
  VelocityTracker? _tracker;

  double get _hinge => widget.spread ? _size.width / 2 : 0;
  double get _pageW => widget.spread ? _size.width / 2 : _size.width;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      if (!_landing) return;
      _finger = Offset.lerp(_from, _to, _anim.value.clamp(0.0, 1.0))!;
      _frame.value++;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _shader.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Where the finger must be for the page to be fully turned, or fully back.
  Offset get _turned => Offset(_hinge - _pageW, _grab.dy);
  Offset get _flat => _grab;

  bool _begin(int dir, Offset touch) {
    if (dir == 0 || !widget.canGo(dir)) return false;
    final pages = widget.pagesFor(dir > 0 ? 0 : -1);
    if (pages == null) return false;
    final h = _size.height;
    final band = h * 0.2;
    final corner = touch.dy < band || touch.dy > h - band;
    final y = touch.dy < band ? 0.0 : (touch.dy > h - band ? h : touch.dy);
    _grab = Offset(_hinge + _pageW, y);
    _maxTilt = corner ? 1.0 : 0.22;
    setState(() {
      _pages = pages;
      _dir = dir;
      _landing = false;
    });
    return true;
  }

  Fold _fold() => computeFold(
        grab: _grab,
        f: _finger,
        hinge: _hinge,
        pageW: _pageW,
        maxR: min(_pageW, _size.height) * 0.14,
        maxTilt: _maxTilt,
      );

  void _track(Offset touch) {
    final d = touch - _start;
    // A backward turn plays a forward turn in reverse, from the finished position.
    final raw = _dir > 0
        ? _grab + d
        : Offset(_turned.dx + d.dx * (widget.spread ? 1 : 2), _start.dy + d.dy);
    _finger = clampFinger(raw, _grab, _hinge, _size.height);
    _frame.value++;
  }

  void _land({required bool completeTurn, double velocity = 0}) {
    final toTurned = completeTurn == (_dir > 0);
    _from = _finger;
    _to = toTurned ? _turned : _flat;
    _landing = true;
    final span = max((_to - _from).distance, 1.0);
    final spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 1);
    _anim.value = 0;
    _anim
        .animateWith(_LandingSimulation(SpringSimulation(spring, 0, 1, (velocity / span).clamp(0.0, 12.0))))
        .whenComplete(() {
      if (!mounted || _dir == 0) return;
      final dir = _dir;
      if (completeTurn) {
        HapticFeedback.selectionClick();
        widget.onTurned(dir);
      }
      setState(() {
        _dir = 0;
        _pages = null;
        _landing = false;
      });
    });
  }

  /// Turns one page without a finger: tap zones and volume keys.
  void turn(int dir) {
    if (_dir != 0) return;
    if (!widget.canGo(dir)) return;
    if (!widget.animate) {
      widget.onTurned(dir);
      return;
    }
    if (!_begin(dir, Offset(0, _size.height * 0.92))) return;
    _finger = dir > 0 ? _flat : _turned;
    _land(completeTurn: true, velocity: _pageW * 1.5);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      _size = c.biggest;
      final pages = _pages;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => widget.onTap(d.localPosition, _size),
        onHorizontalDragStart: (d) {
          _start = d.localPosition;
          _tracker = VelocityTracker.withKind(d.kind ?? ui.PointerDeviceKind.touch);
        },
        onHorizontalDragUpdate: (d) {
          _tracker?.addPosition(d.sourceTimeStamp ?? Duration.zero, d.localPosition);
          if (_dir == 0 && !_anim.isAnimating) {
            final dir = d.delta.dx < 0 ? 1 : (d.delta.dx > 0 ? -1 : 0);
            if (!widget.animate) {
              if (widget.canGo(dir)) widget.onTurned(dir);
              _tracker = null;
              return;
            }
            if (_tracker == null || !_begin(dir, _start)) return;
            _finger = dir > 0 ? _flat : _turned;
          }
          if (_dir != 0 && !_landing) _track(d.localPosition);
        },
        onHorizontalDragEnd: (d) {
          if (_dir == 0 || _landing) return;
          final vx = _tracker?.getVelocity().pixelsPerSecond.dx ?? 0;
          final projected = _finger.dx + vx * 0.18;
          // On a single page the turned position is off screen, so half way is measured on the visible part.
          final middle = _dir > 0
              ? _size.width * (widget.spread ? 0.6 : 0.55)
              : (widget.spread ? _size.width * 0.4 : 0.0);
          final towardTurned = projected < middle;
          final complete = _dir > 0 ? towardTurned : !towardTurned;
          _land(completeTurn: complete, velocity: vx.abs());
        },
        child: pages == null
            ? widget.still
            : CustomPaint(
                size: Size.infinite,
                painter: CurlPainter(
                  shader: _shader,
                  fold: _fold,
                  hinge: _hinge,
                  pageW: _pageW,
                  showThrough: !widget.spread,
                  paper: widget.paper,
                  front: pages.front,
                  back: pages.back,
                  under: pages.under,
                  left: pages.left,
                  repaint: _frame,
                ),
              ),
      );
    });
  }
}

/// A critically damped spring never quite arrives, so stop it once it is within half a pixel's worth.
class _LandingSimulation extends Simulation {
  _LandingSimulation(this.inner);
  final SpringSimulation inner;
  @override
  double x(double t) => inner.x(t);
  @override
  double dx(double t) => inner.dx(t);
  @override
  bool isDone(double t) => (inner.x(t) - 1).abs() < 0.002;
}
