import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colorize.dart';
import 'motion.dart';
import 'main.dart' show settings;

/// One picture the viewer can show, in colour and as it was.
class ViewerItem {
  ViewerItem({required this.id, required this.caption, required this.original, this.page});
  final String id;
  final String caption;
  final Future<Uint8List?> Function() original;

  /// Enough to colour it from here, when the picture comes from an open book.
  final PageImage? page;
}

/// Full-screen picture viewer: pinch to zoom, swipe or arrows between pictures, tap to hide everything but the picture.
class PhotoViewer extends StatefulWidget {
  const PhotoViewer({super.key, required this.items, required this.initial, this.origin, this.dim = 0.8, this.closeOnBackdrop = false});
  final List<ViewerItem> items;
  final int initial;

  /// Where the picture sits on the page, so it can grow out of it and return to it.
  final Rect? Function()? origin;
  final double dim;
  final bool closeOnBackdrop;

  @override
  State<PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<PhotoViewer> with SingleTickerProviderStateMixin {
  late final _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  final _zooms = <int, TransformationController>{};
  final _originals = <String, Future<Uint8List?>>{};
  bool _chrome = true, _zoomed = false, _closing = false;

  @override
  void initState() {
    super.initState();
    colorizer.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      motionOn(context, settings) ? _enter.forward() : _enter.value = 1;
    });
  }

  @override
  void dispose() {
    colorizer.removeListener(_changed);
    _enter.dispose();
    _page.dispose();
    for (final z in _zooms.values) {
      z.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  ViewerItem get _item => widget.items[_index];

  Future<Uint8List?> _originalOf(ViewerItem item) => _originals[item.id] ??= item.original();

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    setState(() => _chrome = false);
    if (motionOn(context, settings)) await _enter.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  void _go(int by) {
    final next = _index + by;
    if (next < 0 || next >= widget.items.length) return;
    _page.animateToPage(next, duration: const Duration(milliseconds: 280), curve: easeEnter);
  }

  TransformationController _zoom(int i) => _zooms[i] ??= (TransformationController()..addListener(() {
        final zoomed = _zooms[i]!.value.getMaxScaleOnAxis() > 1.01;
        if (i == _index && zoomed != _zoomed) setState(() => _zoomed = zoomed);
      }));

  @override
  Widget build(BuildContext context) {
    final showArrows = widget.items.length > 1;
    final item = _item;
    final state = colorizer.stateOf(item.id);
    final colored = colorizer.hasResult(item.id);
    final canColor = !colored && item.page != null && colorizer.modelReady && state != JobState.skipped;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(fit: StackFit.expand, children: [
          AnimatedBuilder(
            animation: _enter,
            builder: (_, _) => ColoredBox(color: Colors.black.withValues(alpha: widget.dim * Curves.easeOut.transform(_enter.value))),
          ),
          PageView.builder(
            controller: _page,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (context, i) => _ZoomPicture(
              item: widget.items[i],
              controller: _zoom(i),
              original: _originalOf(widget.items[i]),
              enter: i == widget.initial ? _enter : null,
              origin: i == widget.initial ? widget.origin : null,
              onPicture: () => setState(() => _chrome = !_chrome),
              onBackdrop: widget.closeOnBackdrop ? _close : () => setState(() => _chrome = !_chrome),
            ),
          ),
          _bar(
            top: true,
            child: Row(children: [
              IconButton(onPressed: _close, icon: const Icon(Icons.close_rounded, color: Colors.white)),
              const Spacer(),
              if (colored && colorizer.originalExists(item.id))
                _ColorSwitch(
                  on: colorizer.showsColor(item.id),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    colorizer.setShowsColor(item.id, !colorizer.showsColor(item.id));
                  },
                )
              else if (canColor)
                TextButton.icon(
                  onPressed: state == JobState.waiting || state == JobState.running
                      ? null
                      : () => colorizer.enqueue(item.page!, front: true, rest: false, title: item.caption.split(' · ').first, pageNumber: _pageNumberOf(item)),
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: state == JobState.waiting || state == JobState.running
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.palette_outlined, size: 20),
                  label: const Text('Renklendir'),
                ),
            ]),
          ),
          if (showArrows) ...[
            _arrow(Alignment.centerLeft, Icons.chevron_left_rounded, _index > 0, () => _go(-1)),
            _arrow(Alignment.centerRight, Icons.chevron_right_rounded, _index < widget.items.length - 1, () => _go(1)),
          ],
          _bar(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: Text(
                showArrows ? '${item.caption}   ${_index + 1} / ${widget.items.length}' : item.caption,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.3),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  int? _pageNumberOf(ViewerItem item) => int.tryParse(item.caption.split('Sayfa ').last);

  Widget _bar({required bool top, required Widget child}) {
    return Positioned(
      top: top ? 0 : null,
      bottom: top ? null : 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_chrome,
        child: AnimatedOpacity(
          opacity: _chrome ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: const [Color(0x99000000), Color(0x00000000)],
              ),
            ),
            child: SafeArea(top: top, bottom: !top, child: child),
          ),
        ),
      ),
    );
  }

  Widget _arrow(Alignment side, IconData icon, bool enabled, VoidCallback onTap) {
    return Align(
      alignment: side,
      child: IgnorePointer(
        ignoring: !_chrome || !enabled,
        child: AnimatedOpacity(
          opacity: _chrome && enabled ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(onPressed: onTap, icon: Icon(icon, color: Colors.white, size: 30)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorSwitch extends StatelessWidget {
  const _ColorSwitch({required this.on, required this.onTap});
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(on ? Icons.palette : Icons.palette_outlined, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(on ? 'Renkli' : 'Orijinal', style: const TextStyle(color: Colors.white, fontSize: 13)),
          ]),
        ),
      );
}

class _ZoomPicture extends StatefulWidget {
  const _ZoomPicture({required this.item, required this.controller, required this.original, required this.enter, required this.origin, required this.onPicture, required this.onBackdrop});
  final ViewerItem item;
  final TransformationController controller;
  final Future<Uint8List?> original;
  final Animation<double>? enter;
  final Rect? Function()? origin;
  final VoidCallback onPicture, onBackdrop;
  @override
  State<_ZoomPicture> createState() => _ZoomPictureState();
}

class _ZoomPictureState extends State<_ZoomPicture> {
  Size? _natural;
  Offset? _lastTap;
  DateTime _lastTapAt = DateTime(2000);

  Rect _fit(Size box, Size image) {
    final f = applyBoxFit(BoxFit.contain, image, box);
    return Alignment.center.inscribe(f.destination, Offset.zero & box);
  }

  void _tap(TapUpDetails d, Size box) {
    final now = DateTime.now();
    final pos = d.localPosition;
    final isDouble = now.difference(_lastTapAt).inMilliseconds < 280 && _lastTap != null && (pos - _lastTap!).distance < 40;
    _lastTapAt = now;
    _lastTap = pos;
    final c = widget.controller;
    if (isDouble) {
      c.value = c.value.getMaxScaleOnAxis() > 1.01
          ? Matrix4.identity()
          : (Matrix4.identity()
            ..translateByDouble(-pos.dx * 1.5, -pos.dy * 1.5, 0, 1)
            ..scaleByDouble(2.5, 2.5, 1, 1));
      return;
    }
    final natural = _natural;
    final inv = Matrix4.inverted(c.value);
    final local = MatrixUtils.transformPoint(inv, pos);
    if (natural != null && _fit(box, natural).contains(local)) {
      widget.onPicture();
    } else {
      widget.onBackdrop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final showColor = colorizer.hasResult(widget.item.id) && colorizer.showsColor(widget.item.id);
      final file = colorizer.fileFor(widget.item.id);
      return FutureBuilder<Uint8List?>(
        future: widget.original,
        builder: (context, snapshot) {
          final ImageProvider? provider = showColor
              ? FileImage(File(file.path))
              : (snapshot.data != null ? MemoryImage(snapshot.data!) : null);
          if (provider == null) return const SizedBox.expand();
          provider.resolve(ImageConfiguration.empty).addListener(ImageStreamListener((info, _) {
            final n = Size(info.image.width.toDouble(), info.image.height.toDouble());
            if (_natural != n && mounted) WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? setState(() => _natural = n) : null);
          }));
          final picture = AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: Image(key: ValueKey(showColor), image: provider, fit: BoxFit.contain, width: size.width, height: size.height, gaplessPlayback: true),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _tap(d, size),
            child: InteractiveViewer(
              transformationController: widget.controller,
              maxScale: 6,
              child: _entering(picture, size),
            ),
          );
        },
      );
    });
  }

  /// The picture starts where it is on the page and grows to fill the screen.
  Widget _entering(Widget picture, Size size) {
    final enter = widget.enter;
    final natural = _natural;
    if (enter == null || natural == null) return picture;
    return AnimatedBuilder(
      animation: enter,
      child: picture,
      builder: (_, child) {
        final from = widget.origin?.call();
        if (from == null || enter.value >= 1) return Opacity(opacity: enter.value.clamp(0.0, 1.0), child: child);
        final fit = _fit(size, natural);
        final r = Rect.lerp(from, fit, easeEnter.transform(enter.value))!;
        final scale = r.width / fit.width;
        return Transform(
          transform: Matrix4.identity()
            ..translateByDouble(r.left - fit.left * scale, r.top - fit.top * scale, 0, 1)
            ..scaleByDouble(scale, scale, 1, 1),
          child: child,
        );
      },
    );
  }
}
