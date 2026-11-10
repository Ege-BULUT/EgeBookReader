import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n.dart';
import 'main.dart' show settings;
import 'motion.dart';

enum ZoneAction { prev, next, menu, bookmark, none }

const zoneNames = {
  ZoneAction.prev: 'Önceki sayfa',
  ZoneAction.next: 'Sonraki sayfa',
  ZoneAction.menu: 'Menü',
  ZoneAction.bookmark: 'Yer imi',
  ZoneAction.none: 'Hiçbir şey',
};

/// One tap area. Rectangles use fractions of width and height; a circle's radius is a fraction of the
/// screen's short side, so it stays round after rotating.
class TapZone {
  TapZone.rect(this.x, this.y, this.w, this.h, this.action) : circle = false;
  TapZone.round(this.x, this.y, double r, this.action)
      : circle = true,
        w = r,
        h = r;

  final bool circle;
  double x, y, w, h;
  ZoneAction action;

  bool hit(Offset p, Size s) {
    if (!circle) return Rect.fromLTWH(x * s.width, y * s.height, w * s.width, h * s.height).contains(p);
    return (p - Offset(x * s.width, y * s.height)).distance <= w * s.shortestSide;
  }

  Map<String, dynamic> toJson() => {'circle': circle, 'x': x, 'y': y, 'w': w, 'h': h, 'action': action.name};

  static TapZone fromJson(Map<String, dynamic> j) {
    double n(String k) => (j[k] as num).toDouble();
    final action = ZoneAction.values.byName(j['action'] as String);
    return j['circle'] as bool ? TapZone.round(n('x'), n('y'), n('w'), action) : TapZone.rect(n('x'), n('y'), n('w'), n('h'), action);
  }
}

/// Zones are in z-order: the last one that contains the touch wins.
class TapLayout {
  TapLayout(this.portrait, this.landscape);
  factory TapLayout.standard() => TapLayout(thirds(), thirds());

  final List<TapZone> portrait, landscape;

  static List<TapZone> thirds() => [
        TapZone.rect(0, 0, 0.3, 1, ZoneAction.prev),
        TapZone.rect(0.7, 0, 0.3, 1, ZoneAction.next),
        TapZone.rect(0.3, 0, 0.4, 1, ZoneAction.menu),
      ];

  List<TapZone> of(Size s) => s.width > s.height ? landscape : portrait;

  ZoneAction actionAt(Offset p, Size s) {
    final zones = of(s);
    for (var i = zones.length - 1; i >= 0; i--) {
      if (zones[i].hit(p, s)) return zones[i].action;
    }
    return ZoneAction.none;
  }

  Map<String, dynamic> toJson() => {
        'portrait': [for (final z in portrait) z.toJson()],
        'landscape': [for (final z in landscape) z.toJson()],
      };

  static TapLayout fromJson(Map<String, dynamic> j) {
    List<TapZone> read(String k) => (j[k] as List<dynamic>).map((e) => TapZone.fromJson(e as Map<String, dynamic>)).toList();
    return TapLayout(read('portrait'), read('landscape'));
  }
}

/// Full-screen canvas the size of the reading area: drag a zone to move it, drag its handle to resize it.
class ZoneEditor extends StatefulWidget {
  const ZoneEditor({super.key});
  @override
  State<ZoneEditor> createState() => _ZoneEditorState();
}

class _ZoneEditorState extends State<ZoneEditor> {
  TapZone? _selected;

  void _changed() {
    settings.update((_) {});
    setState(() {});
  }

  void _add(List<TapZone> zones, {required bool circle}) {
    final z = circle ? TapZone.round(0.5, 0.5, 0.18, ZoneAction.menu) : TapZone.rect(0.3, 0.4, 0.4, 0.2, ZoneAction.menu);
    zones.add(z);
    _selected = z;
    HapticFeedback.selectionClick();
    _changed();
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final size = MediaQuery.sizeOf(context);
    final zones = settings.zones.of(size);
    if (_selected != null && !zones.contains(_selected)) _selected = null;
    final selected = _selected;
    final toolbarAtTop = selected != null && (selected.y + selected.h / 2) > 0.5;
    return Scaffold(
      backgroundColor: c.paper,
      body: Stack(fit: StackFit.expand, children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _selected = null),
        ),
        for (final z in zones) _ZoneView(zone: z, size: size, selected: z == selected, onSelect: () {
          setState(() {
            _selected = z;
            zones.remove(z);
            zones.add(z); // the chosen zone comes to the top
          });
        }, onChanged: _changed),
        AnimatedAlign(
          duration: const Duration(milliseconds: 280),
          curve: easeEnter,
          alignment: toolbarAtTop ? Alignment.topCenter : Alignment.bottomCenter,
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.line),
              ),
              child: selected == null ? _mainBar(zones) : _zoneBar(zones, selected),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _mainBar(List<TapZone> zones) {
    final c = settings.palette;
    final style = TextButton.styleFrom(foregroundColor: c.ink);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(tr('Bir alanı sürükle, köşesinden boyutlandır, dokunup işlev ata.'),
          textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 13)),
      const SizedBox(height: 4),
      Wrap(alignment: WrapAlignment.center, children: [
        TextButton(style: style, onPressed: () => _add(zones, circle: false), child: Text(tr('Dikdörtgen ekle'))),
        TextButton(style: style, onPressed: () => _add(zones, circle: true), child: Text(tr('Daire ekle'))),
        TextButton(
          style: style,
          onPressed: () {
            zones
              ..clear()
              ..addAll(TapLayout.thirds());
            _changed();
          },
          child: Text(tr('Sıfırla')),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.accent),
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Bitti')),
        ),
      ]),
    ]);
  }

  Widget _zoneBar(List<TapZone> zones, TapZone z) {
    final c = settings.palette;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 6, runSpacing: 6, alignment: WrapAlignment.center, children: [
        for (final a in ZoneAction.values)
          GestureDetector(
            onTap: () {
              z.action = a;
              HapticFeedback.selectionClick();
              _changed();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: a == z.action ? c.accent : c.paper,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: a == z.action ? c.accent : c.line),
              ),
              child: Text(tr(zoneNames[a]!), style: TextStyle(color: a == z.action ? c.paper : c.ink, fontSize: 13)),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.accent),
          onPressed: () {
            zones.remove(z);
            _changed();
          },
          child: Text(tr('Sil')),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.ink),
          onPressed: () => setState(() => _selected = null),
          child: Text(tr('Tamam')),
        ),
      ]),
    ]);
  }
}

class _ZoneView extends StatelessWidget {
  const _ZoneView({required this.zone, required this.size, required this.selected, required this.onSelect, required this.onChanged});
  final TapZone zone;
  final Size size;
  final bool selected;
  final VoidCallback onSelect, onChanged;

  Rect get _rect {
    final z = zone;
    if (z.circle) {
      return Rect.fromCircle(center: Offset(z.x * size.width, z.y * size.height), radius: z.w * size.shortestSide);
    }
    return Rect.fromLTWH(z.x * size.width, z.y * size.height, z.w * size.width, z.h * size.height);
  }

  void _move(Offset d) {
    final z = zone;
    final dx = d.dx / size.width, dy = d.dy / size.height;
    if (z.circle) {
      z.x = (z.x + dx).clamp(0.0, 1.0);
      z.y = (z.y + dy).clamp(0.0, 1.0);
    } else {
      z.x = (z.x + dx).clamp(0.0, 1 - z.w);
      z.y = (z.y + dy).clamp(0.0, 1 - z.h);
    }
    onChanged();
  }

  void _resize(Offset d) {
    final z = zone;
    if (z.circle) {
      z.w = (z.w + (d.dx + d.dy) / 2 / size.shortestSide).clamp(0.05, 0.6);
      z.h = z.w;
    } else {
      z.w = (z.w + d.dx / size.width).clamp(0.08, 1 - z.x);
      z.h = (z.h + d.dy / size.height).clamp(0.05, 1 - z.y);
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final r = _rect;
    return Positioned.fromRect(
      rect: r,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onSelect,
            onPanStart: (_) => onSelect(),
            onPanUpdate: (d) => _move(d.delta),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: zone.circle ? BoxShape.circle : BoxShape.rectangle,
                color: c.accent.withValues(alpha: selected ? 0.28 : 0.12),
                border: Border.all(color: c.accent, width: selected ? 2 : 1),
              ),
              child: Text(tr(zoneNames[zone.action]!),
                  textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w500)),
            ),
          ),
        ),
        if (selected)
          Positioned(
            right: zone.circle ? r.width * (1 - cos(pi / 4)) / 2 - 20 : -20,
            bottom: zone.circle ? r.height * (1 - sin(pi / 4)) / 2 - 20 : -20,
            child: GestureDetector(
              onPanUpdate: (d) => _resize(d.delta),
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                color: Colors.transparent,
                child: Container(width: 18, height: 18, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)),
              ),
            ),
          ),
      ]),
    );
  }
}
