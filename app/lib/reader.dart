import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'curl.dart';
import 'main.dart';
import 'settings.dart';
import 'sources.dart';

const _volume = MethodChannel('egebookreader/volume');

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});
  final Book book;
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
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
  final _rendering = <int>{};
  ui.Image? _blank;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    settings.addListener(_settingsChanged);
    _volume.setMethodCallHandler(_onVolume);
    _syncVolume();
    _volume.invokeMethod('setReading', true);
    _scroll.addListener(_onScroll);
    _start();
  }

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
    _volume.setMethodCallHandler(null);
    _volume.invokeMethod('setEnabled', false);
    _volume.invokeMethod('setReading', false);
    _scroll.dispose();
    library.save();
    _source?.dispose();
    for (final i in _images.values) {
      i.dispose();
    }
    _blank?.dispose();
    _grain?.dispose();
    super.dispose();
  }

  void _fail(Object e) {
    if (mounted) setState(() => _error = e is FormatException ? e.message : '$e');
  }

  void _syncVolume() => _volume.invokeMethod('setEnabled', settings.volumeKeys && !_menu);

  void _settingsChanged() {
    _syncVolume();
    if (mounted) setState(() {});
  }

  Future<dynamic> _onVolume(MethodCall call) async {
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
    _pageSize = page;
    _style = style;
    _reflow = reflow;
    final generation = ++_generation;
    final old = Map.of(_images);
    _images.clear();
    _rendering.clear();
    _blank = null;
    if (reopen || old.isNotEmpty) setState(() => _ready = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final i in old.values) {
        i.dispose();
      }
    });

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
      _blank = await _renderOne(-1, page, style);
      await _renderWindow(generation, first: true);
      if (!mounted || generation != _generation) return;
      setState(() => _ready = true);
      _remember();
      if (settings.mode == TurnMode.scroll) _jumpScroll();
    } catch (e) {
      _fail(e);
    }
  }

  int _align(int page) => _spreadActive ? page - page % 2 : page;

  void _remember() {
    widget.book
      ..page = _page
      ..total = _count;
    library.save();
  }

  Future<void> _renderWindow(int generation, {bool first = false}) async {
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

  Future<ui.Image> _renderOne(int index, Size page, PageStyle s) async {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(dpr);
    canvas.drawColor(s.paper, BlendMode.src);
    if (index >= 0) await _source!.paint(canvas, index, page, s);
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
    setState(() => _page = (_page + dir * _step).clamp(0, max(0, _count - 1)));
    _remember();
    _renderWindow(_generation);
  }

  void _onTap(Offset at, Size size) {
    if (_menu) return _toggleMenu();
    final x = at.dx / size.width;
    if (x < 0.3) {
      _curl.currentState?.turn(-1);
    } else if (x > 0.7) {
      _curl.currentState?.turn(1);
    } else {
      _toggleMenu();
    }
  }

  void _toggleMenu() {
    setState(() => _menu = !_menu);
    _syncVolume();
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: filters ? _tableColor(c) : c.paper,
        body: LayoutBuilder(builder: (context, box) {
          final screen = box.biggest;
          _spread = screen.width > screen.height && screen.width >= 600;
          final inset = filters ? _bookInset(screen) : EdgeInsets.zero;
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
                duration: Duration(milliseconds: settings.isEink ? 1 : 260),
                child: _error != null || !_ready || _program == null
                    ? const SizedBox.shrink()
                    : (scrolling ? _scrollView(page) : _flipView()),
              ),
            ),
            if (!_ready) _loading(c),
            _chrome(c),
          ]);
        }),
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

  Widget _loading(Palette c) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 15, height: 1.4)),
            const SizedBox(height: 14),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kitaplığa dön')),
          ]),
        ),
      );
    }
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 150, height: 216, child: Hero(tag: widget.book.path, child: BookCover(book: widget.book))),
        const SizedBox(height: 22),
        SizedBox(
          width: 150,
          child: LinearProgressIndicator(
            value: _layoutProgress > 0 ? _layoutProgress : null,
            minHeight: 2,
            color: c.accent,
            backgroundColor: c.line,
          ),
        ),
      ]),
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
    );
  }

  Widget _still() {
    Widget one(int i) {
      final img = _img(i);
      return img == null ? const SizedBox.expand() : RawImage(image: img, fit: BoxFit.fill);
    }

    return _spreadActive
        ? Row(children: [Expanded(child: one(_page)), Expanded(child: one(_page + 1))])
        : one(_page);
  }

  Widget _scrollView(Size page) {
    return GestureDetector(
      onTap: _toggleMenu,
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
                : RawImage(image: img, fit: BoxFit.fill, width: page.width, height: page.height),
          );
        },
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
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(widget.book.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
                ),
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
                  child: total > 1
                      ? Slider(
                          value: _page.clamp(0, total - 1).toDouble(),
                          max: (total - 1).toDouble(),
                          onChanged: (v) => setState(() => _page = _align(v.round())),
                          onChangeEnd: (v) => _seek(v.round()),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(width: 12),
                Text('${min(_page + 1, max(total, 1))} / $total',
                    style: TextStyle(color: c.muted, fontSize: 12, fontFeatures: const [ui.FontFeature.tabularFigures()])),
                IconButton(
                  icon: Icon(Icons.tune, color: c.ink, size: 22),
                  onPressed: _openSettings,
                ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FractionallySizedBox(heightFactor: 0.72, child: _SettingsSheet(isPdf: _isPdf)),
    );
  }

  bool get _isPdf => widget.book.path.toLowerCase().endsWith('.pdf');
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

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.isPdf});
  final bool isPdf;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final c = settings.palette;
        final s = settings;
        return Theme(
          data: themeFor(c),
          child: AnimatedContainer(
            duration: Duration(milliseconds: s.isEink ? 1 : 200),
            color: c.paper,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
              children: [
                _Heading('Tema'),
                Row(children: [
                  for (final t in PaperTheme.values) ...[
                    Expanded(child: _ThemeSwatch(theme: t)),
                    if (t != PaperTheme.values.last) const SizedBox(width: 10),
                  ],
                ]),
                const SizedBox(height: 12),
                _Segmented<bool>(
                  value: s.dark,
                  options: const {false: 'Açık', true: 'Koyu'},
                  onChanged: (v) => s.update((x) => x.dark = v),
                ),
                _Heading('Yazı'),
                Row(children: [
                  _Step(icon: Icons.remove, onTap: () => s.update((x) => x.fontSize = max(12, x.fontSize - 1))),
                  Expanded(
                    child: Text('${s.fontSize.round()}',
                        textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 16)),
                  ),
                  _Step(icon: Icons.add, onTap: () => s.update((x) => x.fontSize = min(36, x.fontSize + 1))),
                ]),
                const SizedBox(height: 12),
                _Segmented<String>(
                  value: s.fontFamily,
                  options: const {'serif': 'Serif', 'sans-serif': 'Sans'},
                  onChanged: (v) => s.update((x) => x.fontFamily = v),
                ),
                _Toggle('Kalın', s.bold, (v) => s.update((x) => x.bold = v)),
                _Toggle('İtalik', s.italic, (v) => s.update((x) => x.italic = v)),
                if (isPdf) _Toggle('Reflow (PDF metnini yeniden diz)', s.reflow, (v) => s.update((x) => x.reflow = v)),
                _Heading('Sayfa çevirme'),
                _Segmented<TurnMode>(
                  value: s.mode,
                  options: const {TurnMode.flip: 'Flip', TurnMode.tap: 'Dokunma', TurnMode.scroll: 'Kaydırma'},
                  onChanged: (v) => s.update((x) => x.mode = v),
                ),
                if (s.mode == TurnMode.scroll) ...[
                  const SizedBox(height: 16),
                  Text('Sayfalar arası boşluk: ${s.scrollGap.round()} px', style: TextStyle(color: c.muted, fontSize: 13)),
                  const SizedBox(height: 10),
                  Slider(value: s.scrollGap, max: 40, onChanged: (v) => s.update((x) => x.scrollGap = v)),
                ],
                _Toggle('Ses tuşlarıyla çevir', s.volumeKeys, (v) => s.update((x) => x.volumeKeys = v)),
                _Toggle('Ses tuşlarını ters çevir', s.invertVolume, (v) => s.update((x) => x.invertVolume = v)),
                _Heading('Gerçek kitap'),
                _Toggle(
                  s.isEink ? 'Gerçek kitap modu (E-ink\'te kapalı)' : 'Gerçek kitap modu',
                  s.actualBook,
                  (v) => s.update((x) => x.actualBook = v),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 12),
        child: Text(text,
            style: TextStyle(color: settings.palette.ink, fontFamily: 'serif', fontSize: 19, fontWeight: FontWeight.w500)),
      );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.theme});
  final PaperTheme theme;
  static const _names = {
    PaperTheme.paper: 'Kağıt',
    PaperTheme.parchment: 'Parşömen',
    PaperTheme.oled: 'OLED',
    PaperTheme.eink: 'E-ink',
  };

  @override
  Widget build(BuildContext context) {
    final p = palettes[(theme, settings.dark)]!;
    final selected = settings.theme == theme;
    final c = settings.palette;
    return GestureDetector(
      onTap: () => settings.update((x) => x.theme = theme),
      child: AnimatedContainer(
        duration: Duration(milliseconds: settings.isEink ? 1 : 160),
        height: 74,
        decoration: BoxDecoration(
          color: p.paper,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c.accent : c.line, width: selected ? 1.6 : 1),
        ),
        alignment: Alignment.center,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('Aa', style: TextStyle(color: p.ink, fontFamily: 'serif', fontSize: 20)),
          const SizedBox(height: 2),
          Text(_names[theme]!, style: TextStyle(color: p.muted, fontSize: 11)),
        ]),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.value, required this.options, required this.onChanged, super.key});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final keys = options.keys.toList();
    final index = keys.indexOf(value);
    return Container(
      height: 40,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / keys.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: Duration(milliseconds: settings.isEink ? 1 : 240),
            curve: const Cubic(0.22, 1, 0.36, 1),
            left: index * w + 3,
            top: 3,
            bottom: 3,
            width: w - 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.paper,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: c.line),
              ),
            ),
          ),
          Row(children: [
            for (final k in keys)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(k),
                  child: Center(
                    child: Text(options[k]!,
                        style: TextStyle(color: k == value ? c.ink : c.muted, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: SizedBox(width: 54, height: 40, child: Icon(icon, color: c.ink, size: 20)),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(this.label, this.value, this.onChanged);
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(color: c.ink, fontSize: 15))),
        Switch(value: value, onChanged: onChanged, activeThumbColor: c.accent),
      ]),
    );
  }
}
