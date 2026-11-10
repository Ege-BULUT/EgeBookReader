import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'colorize.dart';
import 'fonts.dart';
import 'gallery.dart';
import 'motion.dart';
import 'reader.dart';
import 'settings.dart';
import 'sources.dart';
import 'tts.dart';

final settings = Settings();
final library = Library();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await fonts.load();
  await colorizer.load();
  await voices.load();
  await settings.load();
  await library.load();
  runApp(const EgeBookReaderApp());
}

class Book {
  Book(this.path, this.title, this.coverPath, {this.page = 0, this.total = 0, List<double>? bookmarks})
      : bookmarks = bookmarks ?? [];
  final String path, title;
  final String? coverPath;
  int page, total;
  bool colorizeStarted = false;

  /// Positions as fractions of the book, so they survive a new font size or page layout.
  final List<double> bookmarks;

  double get progress => total <= 1 ? 0 : (page + 1) / total;

  Map<String, dynamic> toJson() =>
      {'path': path, 'title': title, 'cover': coverPath, 'page': page, 'total': total, 'bookmarks': bookmarks, 'colorizeStarted': colorizeStarted};
  static Book fromJson(Map<String, dynamic> j) => Book(
        j['path'] as String,
        j['title'] as String,
        j['cover'] as String?,
        page: j['page'] as int,
        total: j['total'] as int,
        bookmarks: ((j['bookmarks'] as List<dynamic>?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      )..colorizeStarted = j['colorizeStarted'] as bool? ?? false;
}

class Library extends ChangeNotifier {
  final books = <Book>[];
  late Directory _dir;
  File get _index => File(p.join(_dir.path, 'library.json'));

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (_index.existsSync()) {
      final list = jsonDecode(_index.readAsStringSync()) as List<dynamic>;
      books.addAll(list.map((e) => Book.fromJson(e as Map<String, dynamic>)).where((b) => File(b.path).existsSync()));
    }
    // Each sample arrives once; one that was removed from the library stays removed.
    final seen = File(p.join(_dir.path, 'samples-added.txt'));
    final added = seen.existsSync() ? seen.readAsLinesSync().toSet() : <String>{};
    if (_index.existsSync() && added.isEmpty) added.addAll(const ['sample.epub', 'sample.pdf']);
    for (final (asset, name) in const [
      ('sample.epub', 'Dunyanin Dilleri.epub'),
      ('sample.pdf', 'Sayfa Örneği.pdf'),
      ('colorize.epub', 'Renklendirme Denemesi.epub'),
    ]) {
      if (added.contains(asset)) continue;
      final data = await rootBundle.load('assets/samples/$asset');
      final file = File(p.join(_dir.path, 'books', name));
      await file.create(recursive: true);
      await file.writeAsBytes(data.buffer.asUint8List());
      await _add(file.path);
      added.add(asset);
    }
    await seen.writeAsString(added.join('\n'));
    await save();
  }

  Future<void> save() => _index.writeAsString(jsonEncode(books));

  Future<void> _add(String path) async {
    final source = await openBook(path);
    final cover = await _coverFor(source, path);
    books.insert(0, Book(path, source.title, cover));
    source.dispose();
  }

  /// Copies a picked file into the app and adds it. Throws a [FormatException] the UI can show.
  Future<void> import(String from) async {
    final ext = p.extension(from).toLowerCase();
    if (!supportedExtensions.contains(ext)) throw FormatException('Bu biçim henüz desteklenmiyor: $ext');
    final to = File(p.join(_dir.path, 'books', p.basename(from)));
    await to.create(recursive: true);
    await File(from).copy(to.path);
    books.removeWhere((b) => b.path == to.path);
    await _add(to.path);
    await save();
    notifyListeners();
  }

  Future<void> remove(Book b) async {
    books.remove(b);
    await File(b.path).delete().catchError((_) => File(b.path));
    await save();
    notifyListeners();
  }

  void moveToFront(Book b) {
    if (books.remove(b)) books.insert(0, b);
    notifyListeners();
    save();
  }

  Future<String?> _coverFor(PageSource source, String path) async {
    final file = File(p.join(_dir.path, 'covers', '${p.basename(path).hashCode}.png'));
    await file.create(recursive: true);
    final bytes = await source.coverBytes();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
      return file.path;
    }
    if (source is! PdfSource) return null;
    const size = Size(360, 510);
    const style = PageStyle(
      paper: Colors.white, ink: Colors.black, fontSize: 18, lineHeight: 1.5,
      fontFamily: 'serif', bold: false, italic: false, grain: 0, actualBook: false,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
    await source.paint(canvas, 0, size, style);
    final image = await recorder.endRecording().toImage(size.width.toInt(), size.height.toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await file.writeAsBytes(png!.buffer.asUint8List());
    return file.path;
  }
}

ThemeData themeFor(Palette c) {
  final scheme = ColorScheme.fromSeed(
    seedColor: c.accent,
    brightness: c.isDark ? Brightness.dark : Brightness.light,
  ).copyWith(primary: c.accent, surface: c.paper, onSurface: c.ink, onPrimary: c.paper);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: c.paper,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.paper, modalBarrierColor: Colors.black38),
    sliderTheme: SliderThemeData(
      trackHeight: 2,
      activeTrackColor: c.accent,
      inactiveTrackColor: c.line,
      thumbColor: c.accent,
      overlayShape: SliderComponentShape.noOverlay,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    ),
  );
}

class EgeBookReaderApp extends StatelessWidget {
  const EgeBookReaderApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'EgeBookReader',
          debugShowCheckedModeBanner: false,
          theme: themeFor(settings.palette),
          home: const LibraryScreen(),
        ),
      );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> with TickerProviderStateMixin {
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1250));
  final _headerLogo = GlobalKey();
  bool _importing = false;
  bool _introDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!motionOn(context, settings)) {
        _enter.value = 1;
        setState(() => _introDone = true);
        return;
      }
      _intro.forward().whenComplete(() {
        if (mounted) setState(() => _introDone = true);
      });
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) _enter.forward();
      });
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    setState(() => _importing = true);
    final failed = <String>[];
    for (final f in picked) {
      try {
        if (f.path != null) await library.import(f.path!);
      } catch (e) {
        failed.add(f.name);
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    if (failed.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Açılamadı: ${failed.join(', ')}')));
    }
  }

  void _open(Book b, GlobalKey cover) {
    Rect? rect() {
      final box = cover.currentContext?.findRenderObject() as RenderBox?;
      return box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    }

    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => ReaderScreen(book: b, coverRect: rect),
        ))
        .then((_) => library.moveToFront(b));
  }

  void _details(Book b) {
    final c = settings.palette;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.title, style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w500)),
              const SizedBox(height: 14),
              TextButton(
                onPressed: () {
                  library.remove(b);
                  Navigator.pop(context);
                },
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.accent),
                child: const Text('Kitaplıktan kaldır'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 150).floor().clamp(2, 8);
    return Scaffold(
      body: Stack(children: [
        SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([library, settings]),
            builder: (context, _) {
              final c = settings.palette;
              final latest = library.books.where((b) => b.total > 0).firstOrNull;
              return CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 12, 16),
                  sliver: SliverToBoxAdapter(
                    child: Row(children: [
                      Opacity(
                        opacity: _introDone ? 1 : 0,
                        child: LogoMark(key: _headerLogo, size: 26, ink: c.ink, ribbon: c.accent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Entering(
                          parent: _enter,
                          index: 0,
                          child: Text('Kitaplık',
                              style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 32, height: 1.1)),
                        ),
                      ),
                      _Entering(
                        parent: _enter,
                        index: 0,
                        child: IconButton(
                          tooltip: 'Galeri',
                          icon: Icon(Icons.photo_library_outlined, color: c.muted, size: 21),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen())),
                        ),
                      ),
                      if (_importing)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
                          ),
                        )
                      else
                        _Entering(
                          parent: _enter,
                          index: 0,
                          child: TextButton(
                            onPressed: _pick,
                            style: TextButton.styleFrom(foregroundColor: c.accent),
                            child: const Text('Kitap ekle'),
                          ),
                        ),
                    ]),
                  ),
                ),
                if (latest != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
                    sliver: SliverToBoxAdapter(
                      child: _Entering(
                        parent: _enter,
                        index: 1,
                        child: _ContinueCard(book: latest, onOpen: _open),
                      ),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 26,
                      childAspectRatio: 0.56,
                    ),
                    itemCount: library.books.length,
                    itemBuilder: (context, i) {
                      final b = library.books[i];
                      return _Entering(
                        key: ValueKey(b.path),
                        parent: _enter,
                        index: i + 2,
                        child: _BookCard(book: b, onOpen: _open, onLong: () => _details(b)),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
              );
            },
          ),
        ),
        if (!_introDone) _introOverlay(c),
      ]),
    );
  }

  /// Takes over from the system splash, which shows the same mark without its ribbon at the same place:
  /// the ribbon slides out, then the mark travels to its place in the header.
  Widget _introOverlay(Palette c) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final screen = MediaQuery.sizeOf(context);
        final t = _intro.value;
        final draw = 0.5 + 0.5 * (t / 0.55).clamp(0.0, 1.0);
        final travel = easeEnter.transform(((t - 0.6) / 0.4).clamp(0.0, 1.0));
        final box = _headerLogo.currentContext?.findRenderObject() as RenderBox?;
        final header = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : Offset.zero & const Size(21, 26);
        // 46/108 of the 288dp box Android 12+ draws its splash icon in.
        const height = 288 * 46 / 108;
        final start = Rect.fromCenter(center: screen.center(Offset.zero), width: height * 38 / 46, height: height);
        final r = Rect.lerp(start, header, travel)!;
        return Stack(children: [
          Positioned.fill(child: IgnorePointer(child: ColoredBox(color: c.paper.withValues(alpha: 1 - travel)))),
          Positioned.fromRect(
            rect: r,
            child: LogoMark(size: r.height, progress: draw, ink: c.ink, ribbon: c.accent),
          ),
        ]);
      },
    );
  }
}

/// Places a library item on the shared entrance timeline.
class _Entering extends StatelessWidget {
  const _Entering({super.key, required this.parent, required this.index, required this.child});
  final AnimationController parent;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = index.clamp(0, 5) * 0.08;
    final interval = Interval(start, (start + 0.6).clamp(0, 1), curve: easeEnter);
    return AnimatedBuilder(
      animation: parent,
      builder: (_, child) {
        final v = interval.transform(parent.value);
        return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 12 * (1 - v)), child: child));
      },
      child: child,
    );
  }
}

/// The book being read, first and larger, so going back to it is one tap.
class _ContinueCard extends StatefulWidget {
  const _ContinueCard({required this.book, required this.onOpen});
  final Book book;
  final void Function(Book, GlobalKey) onOpen;
  @override
  State<_ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<_ContinueCard> {
  final _cover = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final b = widget.book;
    return Pressable(
      enabled: motionOn(context, settings),
      onTap: () => widget.onOpen(b, _cover),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          SizedBox(key: _cover, width: 62, height: 90, child: BookCover(book: b)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Okumaya devam et', style: TextStyle(color: c.muted, fontSize: 12)),
              const SizedBox(height: 4),
              Text(b.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 18, height: 1.2)),
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(end: b.progress),
                duration: const Duration(milliseconds: 700),
                curve: easeEnter,
                builder: (_, v, _) => ClipRRect(
                  borderRadius: BorderRadius.circular(1),
                  child: LinearProgressIndicator(value: v, minHeight: 2, color: c.accent, backgroundColor: c.line),
                ),
              ),
              const SizedBox(height: 6),
              Text('Sayfa ${b.page + 1} / ${b.total}', style: TextStyle(color: c.muted, fontSize: 12)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _BookCard extends StatefulWidget {
  const _BookCard({required this.book, required this.onOpen, required this.onLong});
  final Book book;
  final void Function(Book, GlobalKey) onOpen;
  final VoidCallback onLong;
  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  final _cover = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final b = widget.book;
    return Pressable(
      enabled: motionOn(context, settings),
      onTap: () => widget.onOpen(b, _cover),
      onLongPress: widget.onLong,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: SizedBox(key: _cover, width: double.infinity, child: BookCover(book: b))),
          const SizedBox(height: 10),
          Text(b.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25)),
          const SizedBox(height: 2),
          Text(b.total == 0 ? 'Yeni' : '%${(b.progress * 100).round()}',
              style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A book's cover with the bookmark ribbon that shows how far it has been read.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.ribbon = true});
  final Book book;
  final bool ribbon;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final cover = book.coverPath;
    return Stack(fit: StackFit.expand, children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.line),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: cover != null && File(cover).existsSync()
              ? Image.file(File(cover), fit: BoxFit.cover, gaplessPlayback: true)
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      type: MaterialType.transparency,
                      child: Text(book.title,
                          style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 16, height: 1.25)),
                    ),
                  ),
                ),
        ),
      ),
      if (ribbon && book.progress > 0)
        Positioned(
          right: 12,
          top: 0,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: book.progress),
            duration: const Duration(milliseconds: 800),
            curve: easeSettle,
            builder: (_, v, _) => Container(
              width: 7,
              height: 14 + 46 * v,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(1.5)),
              ),
            ),
          ),
        ),
    ]);
  }
}
