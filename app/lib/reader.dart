import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'colorize.dart';
import 'curl.dart';
import 'l10n.dart';
import 'main.dart';
import 'motion.dart';
import 'zones.dart';
import 'settings.dart';
import 'settings_sheet.dart';
import 'sources.dart';
import 'tts.dart';
import 'viewer.dart';

const _volume = MethodChannel('egebookreader/volume');

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book, required this.coverRect});
  final Book book;

  /// Where the book's cover is on the library screen, for the opening and closing motion.
  final Rect? Function() coverRect;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

/// The previous look of the page, held on screen while the new one is rendered and then uncovered.
class _Ghost {
  _Ghost(this.pages, this.inset, this.spread, this.backdrop, this.circle, this.keep);
  final List<ui.Image> pages;
  final EdgeInsets inset;
  final bool spread, circle;
  final Color backdrop;
  final Map<int, ui.Image> keep;
}

class _ReaderScreenState extends State<ReaderScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 440));
  late final _swing = AnimationController(vsync: this, duration: const Duration(milliseconds: 620));
  late final _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 460));
  bool _closing = false;
  _Ghost? _ghost;
  EdgeInsets _inset = EdgeInsets.zero;
  Color _backdrop = Colors.transparent;
  bool _scrubbing = false;
  bool _autoStarted = false;
  bool _speechTurning = false;
  bool _speedOpen = false, _speedHeld = false;

  PageSource? _source;
  ui.FragmentProgram? _program;
  ui.Image? _grain;
  String? _error;

  final _curl = GlobalKey<PageCurlViewState>();
  final _scroll = ScrollController();

  int _page = 0;
  bool _menu = false;
  bool _ready = false;
  double _layoutProgress = 0;

  // What the current page images were made for.
  Size? _pageSize;
  PageStyle? _style;
  bool? _reflow;
  int _generation = 0;

  final _images = <int, ui.Image>{};
  final _pageImages = <int, List<PageImage>>{};

  /// Finer copies of the pages on screen, drawn while zoomed in.
  final _sharp = <int, ui.Image>{};
  int _sharpRun = 0;
  final _rendering = <int>{};
  ui.Image? _blank;
  ui.Image? _customBackground;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    settings.addListener(_settingsChanged);
    _volume.setMethodCallHandler(_onVolume);
    colorizer.onDone = _colorizedOne;
    colorizer.addListener(_colorizerChanged);
    speaker.addListener(_speakerChanged);
    speaker.onFinished = _speechReachedPageEnd;
    WidgetsBinding.instance.addObserver(this);
    _syncVolume();
    _volume.invokeMethod('setReading', true);
    _scroll.addListener(_onScroll);
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (motionOn(context, settings)) {
        _move.forward().whenComplete(_maybeSwing);
      } else {
        _move.value = 1;
        _swing.value = 1;
      }
    });
  }

  /// The cover swings open as soon as it has arrived and the first page is ready behind it.
  void _maybeSwing() {
    if (!mounted || _closing || !_ready || !_move.isCompleted || !_swing.isDismissed) return;
    _swing.forward().whenComplete(() {
      if (mounted && !settings.menuHintSeen) _curl.currentState?.peek();
    });
  }

  Future<void> _close() async {
    if (_closing) return;
    setState(() {
      _closing = true;
      _menu = false;
    });
    if (motionOn(context, settings)) {
      await _swing.reverse();
      await _move.reverse();
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _speakerChanged() {
    _syncVolume();
    _syncSpeechService();
    if (mounted) setState(() {});
  }

  String? _serviceState;

  /// While a book is read aloud a foreground service keeps the app alive with the screen off.
  void _syncSpeechService() {
    final state = speaker.active ? 'on-${speaker.paused}-$uiLanguage' : 'off';
    if (state == _serviceState) return;
    _serviceState = state;
    _volume.invokeMethod('speechService', {
      'active': speaker.active,
      'title': widget.book.title,
      'paused': speaker.paused,
      'labels': [tr('Duraklat'), tr('Devam et'), tr('Durdur'), tr('Sesli okuma')],
    });
  }

  bool get _onScreen => WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_ready) _renderWindow(_generation);
    } else if (_speechTurning) {
      // Animations stop when the screen does, and the voice is waiting for this page turn.
      _curl.currentState?.skipToEnd();
    }
  }

  Future<List<SpokenSentence>> _sentencesHere() async {
    final out = <SpokenSentence>[];
    for (var i = _page; i < _page + _step && i < _count; i++) {
      out.addAll(await _source!.sentencesOn(i));
    }
    return out;
  }

  Future<void> _speakFromHere() async {
    if (_menu) _toggleMenu();
    final list = await _sentencesHere();
    if (!mounted) return;
    if (list.isEmpty) {
      _speechReachedPageEnd(); // a page of pictures: nothing to say here, so move on
    } else {
      speaker.start(list);
    }
  }

  void _speechReachedPageEnd() {
    if (!mounted) return;
    if (!_canGo(1)) return speaker.stop();
    _speechTurning = true;
    if (settings.mode == TurnMode.scroll) {
      _seek(_page + 1);
      _speechTurning = false;
      _speakFromHere();
    } else if (_onScreen && _curl.currentState != null) {
      _curl.currentState!.turn(1);
    } else {
      _onTurned(1);
    }
  }

  void _colorizerChanged() {
    if (mounted) setState(() {});
  }

  /// A picture finished colouring: redraw the page it is on, which only ever changes that picture.
  Future<void> _colorizedOne(String id) async {
    if (!mounted) return;
    final generation = _generation;
    for (final entry in _pageImages.entries.toList()) {
      if (!entry.value.any((i) => i.id == id) || !_images.containsKey(entry.key)) continue;
      final img = await _renderOne(entry.key, _pageSize!, _style!);
      if (!mounted || generation != _generation) {
        img.dispose();
        return;
      }
      final old = _images[entry.key];
      setState(() => _images[entry.key] = img);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
  }

  /// Auto mode: the first pages' pictures are coloured before the book shows, the first time only,
  /// and the rest follow one by one while reading.
  Future<void> _startAutoColorize() async {
    if (settings.colorizeMode != ColorizeMode.auto || !colorizer.modelReady || _autoStarted) return;
    _autoStarted = true;
    final source = _source!, page = _pageSize!;
    final firstVisit = !widget.book.colorizeStarted;
    final first = <PageImage>[];
    var pagesWithImages = 0;
    var next = _page;
    for (; next < _count && pagesWithImages < settings.autoColorizePages; next++) {
      final images = await source.imagesOn(next, page);
      if (images.isEmpty) continue;
      pagesWithImages++;
      first.addAll(images);
      for (final image in images) {
        _firstPageOf[image.id] = next + 1;
      }
    }
    for (final image in first) {
      colorizer.enqueue(image, rest: false, title: widget.book.title, pageNumber: _pageOfImage(image));
    }
    if (firstVisit) await colorizer.whenIdle(first.map((i) => i.id));
    widget.book.colorizeStarted = true;
    library.save();
    unawaited(() async {
      for (var i = next; i < _count && mounted; i++) {
        for (final image in await source.imagesOn(i, page)) {
          colorizer.enqueue(image, title: widget.book.title, pageNumber: i + 1);
        }
      }
    }());
  }

  final _firstPageOf = <String, int>{};
  int? _pageOfImage(PageImage image) => _firstPageOf[image.id];

  Future<void> _start() async {
    try {
      _program = await ui.FragmentProgram.fromAsset('shaders/page_curl.frag');
      _grain = await _makeGrain();
      if (mounted) setState(() {});
    } catch (e) {
      _fail(e);
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    settings.removeListener(_settingsChanged);
    colorizer.removeListener(_colorizerChanged);
    speaker.removeListener(_speakerChanged);
    speaker.onFinished = null;
    speaker.stop();
    WidgetsBinding.instance.removeObserver(this);
    _volume.invokeMethod('speechService', {'active': false});
    colorizer.onDone = null;
    colorizer.clearQueue();
    _volume.setMethodCallHandler(null);
    _volume.invokeMethod('setEnabled', false);
    _volume.invokeMethod('setReading', false);
    _scroll.dispose();
    _move.dispose();
    _swing.dispose();
    _reveal.dispose();
    _dropGhost();
    library.save();
    _source?.dispose();
    for (final i in _images.values) {
      i.dispose();
    }
    _blank?.dispose();
    _customBackground?.dispose();
    _grain?.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (mounted) setState(() => _error = e is FormatException ? tr(e.message) : '$e');
  }

  void _syncVolume() => _volume.invokeMethod('setEnabled', settings.volumeKeys && !speaker.active);

  void _settingsChanged() {
    _syncVolume();
    if (mounted) setState(() {});
  }

  Future<dynamic> _onVolume(MethodCall call) async {
    if (call.method == 'speechAction') {
      switch (call.arguments as String) {
        case 'pause':
          speaker.pause();
        case 'resume':
          speaker.resume();
        case 'stop':
          speaker.stop();
      }
      return;
    }
    if (call.method != 'key') return;
    var dir = call.arguments as int;
    if (settings.invertVolume) dir = -dir;
    if (settings.mode == TurnMode.scroll) {
      final h = _scroll.position.viewportDimension;
      _scroll.animateTo(
        (_scroll.offset + dir * h * 0.85).clamp(0, _scroll.position.maxScrollExtent),
        duration: Duration(milliseconds: settings.isEink ? 1 : 280),
        curve: const Cubic(0.22, 1, 0.36, 1),
      );
    } else {
      _curl.currentState?.turn(dir);
    }
  }

  // ---- layout and page images ------------------------------------------------------------------------

  bool get _spreadActive => _spread && settings.mode != TurnMode.scroll;
  bool _spread = false;
  int get _step => _spreadActive ? 2 : 1;
  int get _count => _source?.pageCount ?? 0;

  /// Lays the book out again when the page size, the style or the reflow switch has changed.
  Future<void> _ensureLayout(Size page, PageStyle style) async {
    final reflow = settings.reflow;
    if (_pageSize == page && _style == style && _reflow == reflow) return;
    final fraction = _count > 0 ? _page / _count : (widget.book.total > 0 ? widget.book.page / widget.book.total : 0.0);
    final reopen = _source == null || _reflow != reflow;
    final paperBefore = _style?.paper;
    _pageSize = page;
    _style = style;
    _reflow = reflow;
    final generation = ++_generation;
    final old = Map.of(_images);
    _images.clear();
    _rendering.clear();
    _blank = null;
    final shown = [for (var i = _page; i < _page + _step; i++) old[i]].nonNulls.toList();
    final previous = paperBefore;
    if (old.isNotEmpty && shown.isNotEmpty && settings.mode != TurnMode.scroll && motionOn(context, settings)) {
      _dropGhost();
      _ghost = _Ghost(shown, _inset, _spreadActive, _backdrop, previous != style.paper, old);
    } else if (old.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final i in old.values) {
          i.dispose();
        }
      });
    }
    if (reopen || old.isNotEmpty) setState(() => _ready = false);

    try {
      if (reopen) {
        _source?.dispose();
        _source = null;
        _source = await openBook(widget.book.path, reflowPdf: reflow);
      }
      await _source!.prepare(page, style, onProgress: (v) {
        if (mounted && generation == _generation) setState(() => _layoutProgress = v);
      });
      if (!mounted || generation != _generation) return;
      _page = _align((fraction * _count).round().clamp(0, max(0, _count - 1)).toInt());
      if (style.backgroundKey != null) {
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final next = await composeCustomPaper(settings.custom, (page.width * dpr).ceil(), (page.height * dpr).ceil(), dpr);
        if (!mounted || generation != _generation) {
          next.dispose();
          return;
        }
        final old = _customBackground;
        _customBackground = next;
        WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
      }
      _blank = await _renderOne(-1, page, style);
      await _renderWindow(generation, first: true);
      if (!mounted || generation != _generation) return;
      await _startAutoColorize();
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
      _remember();
      if (settings.mode == TurnMode.scroll) _jumpScroll();
      _maybeSwing();
      if (_ghost != null) {
        _reveal.forward(from: 0).whenComplete(() {
          if (mounted) setState(_dropGhost);
        });
      }
    } catch (e) {
      _fail(e);
    }
  }

  void _dropGhost() {
    final g = _ghost;
    _ghost = null;
    if (g == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in g.keep.values) {
        i.dispose();
      }
    });
  }

  int _align(int page) => _spreadActive ? page - page % 2 : page;

  void _remember() {
    widget.book
      ..page = _page
      ..total = _count;
    library.save();
  }

  Future<void> _renderWindow(int generation, {bool first = false}) async {
    if (!_onScreen && !first) return; // no drawing with the screen off; it catches up on return
    final page = _pageSize!;
    final style = _style!;
    final near = <int>[
      for (var d = 0; d <= _step * 2; d++) ...[_page + d, _page + _step - 1 - d, if (d > 0) _page - d],
      _page + _step * 2 + 1,
    ].where((i) => i >= 0 && i < _count).toSet().toList();
    // On first show only what is on screen must be ready; the rest follows without blocking.
    final wait = first ? near.where((i) => i >= _page && i < _page + _step).toList() : near;
    Future<void> one(int i) async {
      if (_images.containsKey(i) || _rendering.contains(i)) return;
      _rendering.add(i);
      final img = await _renderOne(i, page, style);
      if (generation != _generation || !mounted) {
        img.dispose();
        return;
      }
      _rendering.remove(i);
      _images[i] = img;
      setState(() {});
    }

    for (final i in wait) {
      await one(i);
    }
    if (first) unawaited(Future.forEach(near, one));
    if (generation != _generation) return;
    _images.removeWhere((i, img) {
      if ((i - _page).abs() <= _step * 4) return false;
      WidgetsBinding.instance.addPostFrameCallback((_) => img.dispose());
      return true;
    });
  }

  Future<ui.Image> _renderOne(int index, Size page, PageStyle s, {double sharper = 1}) async {
    _source?.renderScale = sharper;
    final dpr = MediaQuery.devicePixelRatioOf(context) * sharper;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    final background = _customBackground;
    if (s.backgroundKey != null && background != null) {
      canvas.drawImageRect(
        background,
        Rect.fromLTWH(0, 0, background.width.toDouble(), background.height.toDouble()),
        Offset.zero & page,
        Paint(),
      );
    } else {
      canvas.drawColor(s.paper, BlendMode.src);
    }
    if (index >= 0) {
      await _source!.paint(canvas, index, page, s);
      final images = await _source!.imagesOn(index, page);
      _pageImages[index] = images;
      for (final image in images) {
        final file = colorizer.fileFor(image.id);
        if (!file.existsSync() || !colorizer.showsColor(image.id)) continue;
        // Same rectangle as the original, so colouring a picture can never move anything on the page.
        final codec = await ui.instantiateImageCodec(await file.readAsBytes(), targetWidth: (image.rect.width * dpr).ceil());
        final frame = await codec.getNextFrame();
        codec.dispose();
        final src = Rect.fromLTWH(0, 0, frame.image.width.toDouble(), frame.image.height.toDouble());
        // Over paper the original is printed with multiply, so clear it and print the colour the same way.
        final bg = _customBackground;
        if (s.backgroundKey != null && bg != null) {
          final toPx = bg.width / page.width;
          canvas.drawImageRect(bg, Rect.fromLTRB(image.rect.left * toPx, image.rect.top * toPx, image.rect.right * toPx, image.rect.bottom * toPx), image.rect, Paint());
        } else {
          canvas.drawRect(image.rect, Paint()..color = s.paper);
        }
        await drawBookImage(
          canvas,
          frame.image,
          src,
          image.rect,
          s,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..blendMode = s.darkPaper ? BlendMode.srcOver : BlendMode.multiply,
        );
        frame.image.dispose();
      }
    }
    _bakePaper(canvas, Offset.zero & page, s, index);
    final picture = recorder.endRecording();
    final image = await picture.toImage((page.width * dpr).ceil(), (page.height * dpr).ceil());
    picture.dispose();
    return image;
  }

  /// Grain, and in actual book mode the fold shadow and soft light. Baked into the page so they curl with it.
  void _bakePaper(Canvas canvas, Rect r, PageStyle s, int index) {
    final grain = _grain;
    if (grain != null && s.grain > 0) {
      canvas.drawRect(
        r,
        Paint()
          ..shader = ImageShader(grain, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage)
          ..color = Color.fromRGBO(0, 0, 0, (s.darkPaper ? 0.5 : 0.75) * s.grain)
          ..blendMode = s.darkPaper ? BlendMode.overlay : BlendMode.multiply,
      );
    }
    if (!s.actualBook) return;
    final foldAtRight = _spreadActive && index.isEven;
    final foldW = r.width * 0.16;
    final foldRect = foldAtRight
        ? Rect.fromLTWH(r.right - foldW, 0, foldW, r.height)
        : Rect.fromLTWH(0, 0, foldW, r.height);
    canvas.drawRect(
      foldRect,
      Paint()
        ..blendMode = BlendMode.multiply
        ..shader = ui.Gradient.linear(
          foldAtRight ? foldRect.centerRight : foldRect.centerLeft,
          foldAtRight ? foldRect.centerLeft : foldRect.centerRight,
          const [Color(0x66000000), Color(0x1F000000), Color(0x00000000)],
          const [0, 0.35, 1],
        ),
    );
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.topLeft,
          r.bottomRight,
          [Colors.white.withValues(alpha: s.darkPaper ? 0.05 : 0.13), Colors.white.withValues(alpha: 0)],
          const [0, 0.65],
        ),
    );
  }

  Future<ui.Image> _makeGrain() async {
    const n = 192;
    final rng = Random(7);
    final px = Uint8List(n * n * 4);
    for (var i = 0; i < px.length; i += 4) {
      final v = 214 + rng.nextInt(42);
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v - 4;
      px[i + 3] = 255;
    }
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  ui.Image? _img(int i) => (i < 0 || i >= _count) ? _blank : _images[i];

  TurnPages? _pagesFor(int from) {
    final base = _page + from * _step;
    final ui.Image? front, back, under, left;
    if (_spreadActive) {
      left = _img(base);
      front = _img(base + 1);
      back = _img(base + 2);
      under = _img(base + 3);
    } else {
      left = _blank;
      front = _img(base);
      back = front;
      under = _img(base + 1);
    }
    if (front == null || back == null || under == null || left == null) return null;
    return TurnPages(front, back, under, left);
  }

  bool _canGo(int dir) {
    if (dir == 0 || !_ready) return false;
    return dir > 0 ? _page + _step < _count : _page > 0;
  }

  void _onTurned(int dir) {
    _dropSharp();
    setState(() => _page = (_page + dir * _step).clamp(0, max(0, _count - 1)));
    _remember();
    _renderWindow(_generation);
    if (_speechTurning || speaker.active) {
      _speechTurning = false;
      _speakFromHere();
    }
  }

  Future<void> _zoomSettled(double scale) async {
    final run = ++_sharpRun;
    if (scale <= 1.3) return _dropSharp();
    final factor = min(scale, 3.0);
    for (var i = _page; i < _page + _step && i < _count; i++) {
      final img = await _renderOne(i, _pageSize!, _style!, sharper: factor);
      _source?.renderScale = 1;
      if (!mounted || run != _sharpRun) return img.dispose();
      final old = _sharp[i];
      setState(() => _sharp[i] = img);
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    }
  }

  void _dropSharp() {
    final old = _sharp.values.toList();
    _sharp.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in old) {
        i.dispose();
      }
    });
    if (mounted) setState(() {});
  }

  /// A tap on a picture opens it, unless the picture is the whole page: a comic page must keep its tap zones.
  bool _openPictureAt(Offset at, Size size) {
    final right = _spreadActive && at.dx >= size.width / 2;
    return _openPicture(right ? _page + 1 : _page, Offset(right ? at.dx - size.width / 2 : at.dx, at.dy), right ? Offset(_pageSize!.width, 0) : Offset.zero);
  }

  bool _openPicture(int index, Offset inPage, Offset pageOrigin) {
    final images = _pageImages[index] ?? const <PageImage>[];
    final page = _pageSize!;
    for (final (i, image) in images.indexed) {
      if (!image.rect.contains(inPage)) continue;
      // A picture fitted to the page (edge to edge in either direction, as comic and DjVu pages are) counts as the page.
      final fitted = image.rect.width >= page.width * 0.98 || image.rect.height >= page.height * 0.98;
      if (fitted || image.rect.width * image.rect.height > page.width * page.height * 0.7) return false;
      final shift = _inset.topLeft + pageOrigin;
      Navigator.of(context).push(PageRouteBuilder<void>(
        opaque: false,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (_, _, _) => PhotoViewer(
          closeOnBackdrop: true,
          initial: i,
          origin: () => image.rect.shift(shift),
          items: [
            for (final img in images)
              ViewerItem(id: img.id, title: widget.book.title, pageNumber: index + 1, page: img, original: img.bytes),
          ],
        ),
      ));
      return true;
    }
    return false;
  }

  void _onTap(Offset at, Size size) {
    if (_speedOpen) return setState(() => _speedOpen = false);
    if (_menu) return _toggleMenu();
    final action = settings.zones.actionAt(at, size);
    // In Tap mode the side zones are how pages turn, so they keep working over pictures.
    final zoneTurns = settings.mode == TurnMode.tap && (action == ZoneAction.prev || action == ZoneAction.next);
    if (!zoneTurns && _openPictureAt(at, size)) return;
    switch (action) {
      case ZoneAction.prev:
        _curl.currentState?.turn(-1);
      case ZoneAction.next:
        _curl.currentState?.turn(1);
      case ZoneAction.menu:
        _toggleMenu();
      case ZoneAction.bookmark:
        _toggleBookmark();
      case ZoneAction.none:
        break;
    }
  }

  void _toggleMenu() {
    if (!settings.menuHintSeen) settings.update((x) => x.menuHintSeen = true);
    setState(() => _menu = !_menu);
    _syncVolume();
  }

  double get _fraction => _count == 0 ? 0 : _page / _count;
  bool get _bookmarked => widget.book.bookmarks.any((b) => (b - _fraction).abs() < 0.5 / max(_count, 1));

  void _toggleBookmark() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_bookmarked) {
        widget.book.bookmarks.removeWhere((b) => (b - _fraction).abs() < 0.5 / max(_count, 1));
      } else {
        widget.book.bookmarks.add(_fraction);
      }
    });
    library.save();
  }

  void _seek(int page) {
    setState(() => _page = _align(page.clamp(0, max(0, _count - 1))));
    _remember();
    _renderWindow(_generation, first: true);
    if (settings.mode == TurnMode.scroll) _jumpScroll();
  }

  // ---- vertical scroll ---------------------------------------------------------------------------------

  double get _itemExtent => (_pageSize?.height ?? 1) + settings.scrollGap;

  void _jumpScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_page * _itemExtent);
    });
  }

  void _onScroll() {
    if (settings.mode != TurnMode.scroll || !_ready) return;
    final page = (_scroll.offset / _itemExtent + 0.3).floor().clamp(0, max(0, _count - 1)).toInt();
    if (page != _page) {
      _page = page;
      _remember();
      _renderWindow(_generation);
      if (_menu) setState(() {});
    }
  }

  // ---- screen --------------------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final filters = settings.bookFilters;
    final base = filters ? _tableColor(c) : c.paper;
    _backdrop = base;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Material(
          type: MaterialType.transparency,
          child: LayoutBuilder(builder: (context, box) {
            final screen = box.biggest;
            _spread = screen.width > screen.height && screen.width >= 600;
            final inset = filters ? _bookInset(screen) : EdgeInsets.zero;
            _inset = inset;
            final book = inset.deflateSize(screen);
            final scrolling = settings.mode == TurnMode.scroll;
            final page = scrolling
                ? Size(book.width, _scrollPageHeight(book))
                : (_spreadActive ? Size(book.width / 2, book.height) : book);
            if (_program != null && (_grain != null) && _error == null) {
              scheduleMicrotask(() {
                if (mounted) _ensureLayout(page, settings.pageStyle);
              });
            }
            return Stack(fit: StackFit.expand, children: [
              AnimatedBuilder(
                animation: _move,
                builder: (_, child) => Opacity(opacity: easeEnter.transform(_move.value), child: child),
                child: Stack(fit: StackFit.expand, children: [
                  ColoredBox(color: base),
                  if (filters && !scrolling)
                    CustomPaint(
                      painter: _BookBedPainter(
                        book: inset.topLeft & book,
                        spread: _spreadActive,
                        read: _count == 0 ? 0 : _page / _count,
                        edge: Color.lerp(c.paper, Colors.black, c.isDark ? 0.0 : 0.16)!,
                        line: c.isDark ? Colors.white12 : Colors.black26,
                      ),
                    ),
                  Padding(
                    padding: inset,
                    child: AnimatedOpacity(
                      opacity: _ready ? 1 : 0,
                      duration: Duration(milliseconds: _ghost != null || settings.isEink ? 1 : 200),
                      child: _error != null || !_ready || _program == null
                          ? const SizedBox.shrink()
                          : (scrolling ? _scrollView(page) : _flipView()),
                    ),
                  ),
                  if (_ghost != null) _ghostLayer(screen),
                  _menuHint(c),
                  if (_error != null) _errorView(c),
                  _chrome(c),
                  _player(c),
                  _speedPanel(c),
                  _ribbon(c, inset),
                ]),
              ),
              _coverLayer(c, screen),
            ]);
          }),
        ),
      ),
    );
  }

  Widget _ghostLayer(Size screen) {
    final g = _ghost!;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _reveal,
        builder: (_, _) {
          final v = easeEnter.transform(_reveal.value);
          Widget layer = ColoredBox(
            color: g.backdrop,
            child: Padding(
              padding: g.inset,
              child: g.spread && g.pages.length == 2
                  ? Row(children: [
                      Expanded(child: RawImage(image: g.pages[0], fit: BoxFit.fill)),
                      Expanded(child: RawImage(image: g.pages[1], fit: BoxFit.fill)),
                    ])
                  : RawImage(image: g.pages[0], fit: BoxFit.fill, width: double.infinity, height: double.infinity),
            ),
          );
          return g.circle ? ClipPath(clipper: _HoleClipper(v), child: layer) : Opacity(opacity: 1 - v, child: layer);
        },
      ),
    );
  }

  /// The cover travels from its place on the shelf to fill the screen, then swings open on its left edge.
  Widget _coverLayer(Palette c, Size screen) {
    return AnimatedBuilder(
      animation: Listenable.merge([_move, _swing]),
      builder: (_, _) {
        if (_swing.isCompleted) return const SizedBox.shrink();
        final m = easeEnter.transform(_move.value);
        final s = Curves.easeInOutCubic.transform(_swing.value);
        final from = widget.coverRect() ?? Rect.fromCenter(center: screen.center(Offset.zero), width: 120, height: 180);
        final to = _spread ? Rect.fromLTWH(screen.width / 2, 0, screen.width / 2, screen.height) : Offset.zero & screen;
        final fade = ((1 - s) / 0.25).clamp(0.0, 1.0);
        final waiting = !_ready && _move.isCompleted && _swing.isDismissed;
        return Positioned.fromRect(
          rect: Rect.lerp(from, to, m)!,
          child: IgnorePointer(
            child: Opacity(
              opacity: fade,
              child: Transform(
                alignment: Alignment.centerLeft,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0011)
                  ..rotateY(s * 1.8),
                child: Stack(fit: StackFit.expand, children: [
                  BookCover(book: widget.book, ribbon: false),
                  ColoredBox(color: Colors.black.withValues(alpha: 0.28 * s)),
                  if (waiting)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: _layoutProgress > 0 ? _layoutProgress : null,
                        minHeight: 2,
                        color: c.accent,
                        backgroundColor: Colors.transparent,
                      ),
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The bookmark: hangs from the top edge, falls with a small bounce when set.
  Widget _ribbon(Palette c, EdgeInsets inset) {
    final set = _bookmarked;
    final length = set ? 62.0 : (_menu ? 30.0 : 0.0);
    return Positioned(
      top: 0,
      right: inset.right + 18,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _menu || set ? _toggleBookmark : null,
        child: SizedBox(
          width: 44,
          height: length + 16,
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedContainer(
              duration: Duration(milliseconds: settings.isEink ? 1 : 340),
              curve: easeSettle,
              width: 14,
              height: length,
              child: CustomPaint(painter: _RibbonPainter(set ? c.accent : c.accent.withValues(alpha: 0.5))),
            ),
          ),
        ),
      ),
    );
  }

  double _scrollPageHeight(Size book) {
    final s = _source;
    final doc = s is PdfSource ? s.doc.pages.first : null;
    if (doc != null) return (book.width * doc.height / doc.width).ceilToDouble();
    if (s is CbzSource) return (book.width * 1.45).ceilToDouble();
    return book.height;
  }

  EdgeInsets _bookInset(Size s) {
    final side = max(14.0, s.shortestSide * 0.035);
    return EdgeInsets.fromLTRB(_spread ? side : 4, side * 0.7, side, side * 1.2);
  }

  Color _tableColor(Palette c) => Color.lerp(c.paper, const Color(0xFF2B211A), c.isDark ? 0.5 : 0.78)!;

  Widget _errorView(Palette c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 15, height: 1.4)),
          const SizedBox(height: 14),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Kitaplığa dön'))),
        ]),
      ),
    );
  }

  Widget _flipView() {
    final c = settings.palette;
    return PageCurlView(
      key: _curl,
      program: _program!,
      spread: _spreadActive,
      paper: c.paper,
      animate: settings.mode == TurnMode.flip && !settings.isEink && !MediaQuery.disableAnimationsOf(context),
      canGo: _canGo,
      pagesFor: _pagesFor,
      still: _still(),
      onTurned: _onTurned,
      onTap: _onTap,
      onZoomChanged: _zoomSettled,
    );
  }

  Widget _still() {
    Widget one(int i) {
      final img = _sharp[i] ?? _img(i);
      return img == null ? const SizedBox.expand() : RawImage(image: img, fit: BoxFit.fill);
    }

    Widget withBadges(int i) => Stack(fit: StackFit.expand, children: [one(i), _spokenHighlight(i), ..._badges(i)]);
    return _spreadActive
        ? Row(children: [Expanded(child: withBadges(_page)), Expanded(child: withBadges(_page + 1))])
        : withBadges(_page);
  }

  /// The sentence being read, and the word in it marked like a highlighter pen.
  /// Holding the marker and moving it takes the voice to another word.
  Widget _spokenHighlight(int index) {
    return Builder(builder: (page) {
      return ValueListenableBuilder<int>(
        valueListenable: speaker.cursor,
        builder: (_, _, _) {
          final s = speaker.current;
          final word = speaker.currentWord;
          if (s == null || s.page != index) return const SizedBox.shrink();
          final c = settings.palette;
          final eink = settings.isEink;
          void follow(Offset global) {
            final box = page.findRenderObject() as RenderBox?;
            if (box == null) return;
            final hit = speaker.map.nearest(index, box.globalToLocal(global));
            if (hit != null) speaker.scrubTo(hit.$1, hit.$2);
          }

          return Stack(fit: StackFit.expand, children: [
            IgnorePointer(child: CustomPaint(size: Size.infinite, painter: _HighlightPainter(s.boxes, c.accent))),
            if (word != null && word.boxes.isNotEmpty) ...[
              // Only a hyphenated word has more than one piece; the rest of it stays still.
              for (final extra in word.boxes.skip(1))
                Positioned.fromRect(rect: extra, child: IgnorePointer(child: CustomPaint(painter: _MarkerPainter(c, eink)))),
              TweenAnimationBuilder<Rect?>(
                tween: RectTween(end: word.boxes.first),
                duration: Duration(milliseconds: eink ? 1 : 110),
                curve: Curves.easeOut,
                builder: (_, rect, _) => Positioned.fromRect(
                  rect: rect!.inflate(14),
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      LongPressGestureRecognizer: GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                        () => LongPressGestureRecognizer(duration: const Duration(milliseconds: 170)),
                        (r) => r
                          ..onLongPressStart = (d) {
                            HapticFeedback.selectionClick();
                            speaker.beginScrub();
                            follow(d.globalPosition);
                          }
                          ..onLongPressMoveUpdate = (d) {
                            follow(d.globalPosition);
                          }
                          ..onLongPressEnd = (_) {
                            speaker.endScrub();
                          }
                          ..onLongPressCancel = speaker.endScrub,
                      ),
                    },
                    child: Padding(padding: const EdgeInsets.all(14), child: CustomPaint(painter: _MarkerPainter(c, eink))),
                  ),
                ),
              ),
            ],
          ]);
        },
      );
    });
  }

  /// A small button on each picture that can still be coloured.
  List<Widget> _badges(int index) {
    if (settings.colorizeMode == ColorizeMode.off || !colorizer.modelReady) return const [];
    final c = settings.palette;
    return [
      for (final image in _pageImages[index] ?? const <PageImage>[])
        if (colorizer.stateOf(image.id) case final state when state != JobState.skipped)
          Positioned(
            top: image.rect.top + 6,
            left: image.rect.right - 40,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                if (state == JobState.done) {
                  colorizer.setShowsColor(image.id, !colorizer.showsColor(image.id));
                } else {
                  colorizer.enqueue(image, front: true, rest: false, title: widget.book.title, pageNumber: index + 1);
                }
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.ink.withValues(alpha: 0.72), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: state == JobState.running || state == JobState.waiting
                    ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.paper))
                    : Icon(
                        state == JobState.failed
                            ? Icons.refresh
                            : (state == JobState.done && colorizer.showsColor(image.id) ? Icons.palette : Icons.palette_outlined),
                        color: c.paper,
                        size: 18,
                      ),
              ),
            ),
          ),
    ];
  }

  Widget _scrollView(Size page) {
    return GestureDetector(
      onTapUp: (d) {
        final at = d.localPosition.dy + _scroll.offset;
        final index = (at / _itemExtent).floor();
        if (index >= 0 && index < _count && _openPicture(index, Offset(d.localPosition.dx, at - index * _itemExtent), Offset(0, index * _itemExtent - _scroll.offset))) return;
        _toggleMenu();
      },
      child: ListView.builder(
        controller: _scroll,
        itemExtent: _itemExtent,
        itemCount: _count,
        itemBuilder: (context, i) {
          final img = _images[i];
          if (img == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _renderWindow(_generation));
          }
          return Padding(
            padding: EdgeInsets.only(bottom: settings.scrollGap),
            child: img == null
                ? ColoredBox(color: settings.palette.paper)
                : Stack(fit: StackFit.expand, children: [
                    RawImage(image: img, fit: BoxFit.fill, width: page.width, height: page.height),
                    _spokenHighlight(i),
                  ]),
          );
        },
      ),
    );
  }

  void _setSpeed(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded != settings.ttsSpeed) settings.update((x) => x.ttsSpeed = rounded);
  }

  /// Opens above the player when its speed button is held.
  Widget _speedPanel(Palette c) {
    final width = MediaQuery.sizeOf(context).width;
    final on = _speedOpen && speaker.active && !_menu;
    return Positioned(
      left: width * 0.05,
      width: width * 0.9,
      bottom: max(MediaQuery.paddingOf(context).bottom, 14) + 92,
      child: IgnorePointer(
        ignoring: !on,
        child: AnimatedOpacity(
          opacity: on ? 1 : 0,
          duration: Duration(milliseconds: settings.isEink ? 1 : 140),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.line)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${settings.ttsSpeed.toStringAsFixed(1)}x', style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Slider(
                value: settings.ttsSpeed.clamp(0.5, 3.0),
                min: 0.5,
                max: 3,
                divisions: 25,
                onChanged: _setSpeed,
                onChangeEnd: (_) {
                  speaker.applySpeed();
                  setState(() => _speedOpen = false);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Bar shown while reading aloud.
  Widget _player(Palette c) {
    final on = speaker.active && !_menu;
    final d = Duration(milliseconds: settings.isEink ? 1 : 260);
    final pad = MediaQuery.paddingOf(context);
    Widget button(IconData icon, VoidCallback tap, {double size = 24}) =>
        IconButton(onPressed: tap, icon: Icon(icon, color: c.ink, size: size), visualDensity: VisualDensity.compact);
    return AnimatedPositioned(
      duration: d,
      curve: easeEnter,
      left: 14,
      right: 14,
      bottom: on ? max(pad.bottom, 14) : -130,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 2),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.line)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: ValueListenableBuilder<int>(
              valueListenable: speaker.cursor,
              builder: (_, _, _) => Slider(
                value: speaker.progress,
                onChangeStart: (_) => speaker.beginScrub(),
                onChanged: speaker.scrubFraction,
                onChangeEnd: (_) => speaker.endScrub(),
              ),
            ),
          ),
          Row(children: [
          const SizedBox(width: 8),
          _SpeakingBars(color: c.accent, playing: speaker.active && !speaker.paused && !settings.isEink),
          const Spacer(),
          button(Icons.skip_previous_rounded, () => speaker.step(-1)),
          button(speaker.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, () => speaker.paused ? speaker.resume() : speaker.pause(), size: 30),
          button(Icons.skip_next_rounded, () => speaker.step(1)),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              const speeds = [0.8, 1.0, 1.2, 1.5, 2.0, 3.0];
              final next = speeds[(speeds.indexOf(settings.ttsSpeed) + 1) % speeds.length];
              settings.update((x) => x.ttsSpeed = next);
              speaker.applySpeed();
            },
            onLongPressStart: (_) {
              HapticFeedback.selectionClick();
              _speedHeld = false;
              setState(() => _speedOpen = true);
            },
            // The finger that opened the slider can carry on and move it.
            onLongPressMoveUpdate: (d) {
              _speedHeld = true;
              final width = MediaQuery.sizeOf(context).width * 0.9 - 40;
              final left = MediaQuery.sizeOf(context).width * 0.05 + 20;
              _setSpeed(0.5 + 2.5 * ((d.globalPosition.dx - left) / width).clamp(0.0, 1.0));
            },
            onLongPressEnd: (_) {
              if (!_speedHeld) return;
              speaker.applySpeed();
              setState(() => _speedOpen = false);
            },
            child: SizedBox(
              width: 44,
              height: 40,
              child: Center(child: Text('${settings.ttsSpeed}x', style: TextStyle(color: c.ink, fontSize: 13))),
            ),
          ),
          button(Icons.close_rounded, speaker.stop, size: 21),
          ]),
        ]),
      ),
    );
  }

  Widget _scrubber(Palette c, int total) {
    final value = _page.clamp(0, total - 1).toDouble();
    return LayoutBuilder(builder: (context, box) {
      const thumb = 7.0;
      final x = thumb + (box.maxWidth - thumb * 2) * value / max(total - 1, 1);
      return Stack(clipBehavior: Clip.none, alignment: Alignment.centerLeft, children: [
        Positioned.fill(
          child: IgnorePointer(child: CustomPaint(painter: _TickPainter(widget.book.bookmarks, c.accent, thumb))),
        ),
        Slider(
          value: value,
          max: (total - 1).toDouble(),
          onChangeStart: (_) => setState(() => _scrubbing = true),
          onChanged: (v) {
            final next = _align(v.round());
            if (next != _page) HapticFeedback.selectionClick();
            setState(() => _page = next);
          },
          onChangeEnd: (v) {
            setState(() => _scrubbing = false);
            _seek(v.round());
          },
        ),
        Positioned(
          left: x - 34,
          bottom: 26,
          child: IgnorePointer(
            child: AnimatedScale(
              scale: _scrubbing ? 1 : 0.7,
              duration: const Duration(milliseconds: 180),
              curve: easeSettle,
              alignment: Alignment.bottomCenter,
              child: AnimatedOpacity(
                opacity: _scrubbing ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  width: 68,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(6)),
                  child: Text('${_page + 1}',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: c.paper, fontSize: 16, fontWeight: FontWeight.w500)),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }

  /// Shown until the menu has been opened once, because nothing on a page says it exists.
  Widget _menuHint(Palette c) {
    final show = _ready && !settings.menuHintSeen;
    return IgnorePointer(
      child: Center(
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: Duration(milliseconds: settings.isEink ? 1 : 300),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(6)),
            child: Text(tr('Ayarlar için sayfanın ortasına dokun'), style: TextStyle(color: c.paper, fontSize: 14)),
          ),
        ),
      ),
    );
  }

  Widget _chrome(Palette c) {
    final eink = settings.isEink;
    final d = Duration(milliseconds: eink ? 1 : (_menu ? 220 : 140));
    const ease = Cubic(0.22, 1, 0.36, 1);
    final pad = MediaQuery.paddingOf(context);
    final total = _count;
    return Stack(children: [
      AnimatedPositioned(
        duration: d,
        curve: ease,
        top: _menu ? 0 : -10,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !_menu,
          child: AnimatedOpacity(
            opacity: _menu ? 1 : 0,
            duration: d,
            child: Container(
              color: c.paper,
              padding: EdgeInsets.fromLTRB(6, max(pad.top, 8), 12, 8),
              child: Row(children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: c.ink, size: 22),
                  onPressed: _close,
                ),
                Expanded(
                  child: Text(widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
                ),
                IconButton(
                  tooltip: tr('İçindekiler'),
                  icon: Icon(Icons.format_list_bulleted_rounded, color: c.ink, size: 22),
                  onPressed: _openContents,
                ),
                const SizedBox(width: 48), // room for the ribbon
              ]),
            ),
          ),
        ),
      ),
      AnimatedPositioned(
        duration: d,
        curve: ease,
        bottom: _menu ? 0 : -10,
        left: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: !_menu,
          child: AnimatedOpacity(
            opacity: _menu ? 1 : 0,
            duration: d,
            child: Container(
              color: c.paper,
              padding: EdgeInsets.fromLTRB(20, 10, 8, max(pad.bottom, 10)),
              child: Row(children: [
                Expanded(
                  child: total > 1 ? _scrubber(c, total) : const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),
                Text('${min(_page + 1, max(total, 1))} / $total',
                    style: TextStyle(color: c.muted, fontSize: 12, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                if (settings.ttsEnabled)
                  IconButton(
                    tooltip: tr('Sesli oku'),
                    icon: Icon(Icons.headphones_outlined, color: c.ink, size: 21),
                    onPressed: _speakFromHere,
                  ),
                TextButton.icon(
                  onPressed: _openSettings,
                  style: TextButton.styleFrom(foregroundColor: c.ink),
                  icon: const Icon(Icons.tune, size: 20),
                  label: Text(tr('Ayarlar')),
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Future<void> _openContents() async {
    final toc = await _source!.tableOfContents();
    if (!mounted) return;
    final c = settings.palette;
    final marks = [...widget.book.bookmarks]..sort();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.72,
        child: ListView(padding: const EdgeInsets.fromLTRB(8, 18, 8, 24), children: [
          if (marks.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Heading('Yer imleri')),
            for (final m in marks)
              _contentRow(context, '${tr('Sayfa')} ${(m * _count).round() + 1}', (m * _count).round(), 0, leading: Icon(Icons.bookmark, color: c.accent, size: 18)),
          ],
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8), child: Heading('İçindekiler')),
          if (toc.isEmpty)
            Padding(padding: const EdgeInsets.all(14), child: Text(tr('Bu kitapta içindekiler bilgisi yok.'), style: TextStyle(color: c.muted, fontSize: 14))),
          for (final e in toc) _contentRow(context, e.title, e.page, e.depth),
        ]),
      ),
    );
  }

  Widget _contentRow(BuildContext sheet, String title, int page, int depth, {Widget? leading}) {
    final c = settings.palette;
    final here = page >= _page && page < _page + _step;
    return InkWell(
      onTap: () {
        Navigator.pop(sheet);
        _toggleMenu();
        _seek(page);
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(14 + depth * 16.0, 11, 14, 11),
        child: Row(children: [
          if (leading != null) ...[leading, const SizedBox(width: 10)],
          Expanded(child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: here ? c.accent : c.ink, fontSize: 15))),
          Text('${page + 1}', style: TextStyle(color: c.muted, fontSize: 13)),
        ]),
      ),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.72, child: SettingsSheet(isPdf: _isPdf)),
    );
  }

  bool get _isPdf => widget.book.path.toLowerCase().endsWith('.pdf');
}

/// Three bars that move while a voice is reading.
class _SpeakingBars extends StatefulWidget {
  const _SpeakingBars({required this.color, required this.playing});
  final Color color;
  final bool playing;
  @override
  State<_SpeakingBars> createState() => _SpeakingBarsState();
}

class _SpeakingBarsState extends State<_SpeakingBars> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didUpdateWidget(_SpeakingBars old) {
    super.didUpdateWidget(old);
    if (widget.playing && !_c.isAnimating) _c.repeat();
    if (!widget.playing && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < 3; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              width: 3,
              height: 8 + 13 * (0.5 + 0.5 * sin(2 * pi * (_c.value + i * 0.28))),
              decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1.5)),
            ),
        ]),
      );
}

/// Clips away a growing circle from the bottom of the screen, where the theme was just chosen.
class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper(this.t);
  final double t;

  @override
  Path getClip(Size size) {
    final center = Offset(size.width / 2, size.height * 0.8);
    final radius = Offset(size.width, size.height).distance * t;
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius));
  }

  @override
  bool shouldReclip(_HoleClipper old) => old.t != t;
}

/// A stroke of yellow highlighter: multiplied over light paper so the ink shows through it.
class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.palette, this.eink);
  final Palette palette;
  final bool eink;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = eink
        ? (Paint()..color = palette.ink.withValues(alpha: 0.28))
        : palette.isDark
            ? (Paint()..color = const Color(0x66FFE234))
            : (Paint()
              ..color = const Color(0xFFFFE94A)
              ..blendMode = BlendMode.multiply);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)), paint);
  }

  @override
  bool shouldRepaint(_MarkerPainter o) => o.palette != palette || o.eink != eink;
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter(this.boxes, this.color);
  final List<Rect> boxes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color.withValues(alpha: 0.07);
    for (final b in boxes) {
      canvas.drawRRect(RRect.fromRectAndRadius(b.inflate(1.5), const Radius.circular(3)), p);
    }
  }

  @override
  bool shouldRepaint(_HighlightPainter o) => o.boxes != boxes || o.color != color;
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final notch = min(size.height, 7.0);
    canvas.drawPath(
      Path()
        ..lineTo(size.width, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(size.width / 2, size.height - notch)
        ..lineTo(0, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter o) => o.color != color;
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.marks, this.color, this.inset);
  final List<double> marks;
  final Color color;
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    for (final m in marks) {
      final x = inset + (size.width - inset * 2) * m;
      canvas.drawRect(Rect.fromCenter(center: Offset(x, size.height / 2), width: 2, height: 10), p);
    }
  }

  @override
  bool shouldRepaint(_TickPainter o) => true;
}

/// In actual book mode: the stacked page edges at the book's sides and its shadow on the table.
class _BookBedPainter extends CustomPainter {
  _BookBedPainter({required this.book, required this.spread, required this.read, required this.edge, required this.line});
  final Rect book;
  final bool spread;
  final double read;
  final Color edge, line;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      book.inflate(2).translate(4, 7),
      Paint()
        ..color = Colors.black54
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    final linePaint = Paint()
      ..color = line
      ..strokeWidth = 0.7;
    void stack(double from, double dir, double amount) {
      final count = (amount * 9).ceil() + 1;
      final w = count * 1.5;
      final x0 = dir > 0 ? from : from - w;
      canvas.drawRect(Rect.fromLTRB(x0, book.top + 2, x0 + w, book.bottom - 1), Paint()..color = edge);
      for (var i = 0; i <= count; i++) {
        final x = from + dir * i * 1.5;
        canvas.drawLine(Offset(x, book.top + 2), Offset(x, book.bottom - 1), linePaint);
      }
    }

    stack(book.right, 1, 1 - read);
    if (spread) stack(book.left, -1, read);
  }

  @override
  bool shouldRepaint(_BookBedPainter o) => o.book != book || o.spread != spread || o.read != read || o.edge != edge;
}
