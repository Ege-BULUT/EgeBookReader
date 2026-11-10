import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'reader.dart';
import 'settings.dart';
import 'sources.dart';

final settings = Settings();
final library = Library();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await settings.load();
  await library.load();
  runApp(const EgeBookReaderApp());
}

class Book {
  Book(this.path, this.title, this.coverPath, {this.page = 0, this.total = 0});
  final String path, title;
  final String? coverPath;
  int page, total;

  double get progress => total <= 1 ? 0 : (page + 1) / total;

  Map<String, dynamic> toJson() => {'path': path, 'title': title, 'cover': coverPath, 'page': page, 'total': total};
  static Book fromJson(Map<String, dynamic> j) =>
      Book(j['path'] as String, j['title'] as String, j['cover'] as String?, page: j['page'] as int, total: j['total'] as int);
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
    } else {
      for (final (asset, name) in const [('sample.epub', 'Dunyanin Dilleri.epub'), ('sample.pdf', 'Sayfa Örneği.pdf')]) {
        final data = await rootBundle.load('assets/samples/$asset');
        final file = File(p.join(_dir.path, 'books', name));
        await file.create(recursive: true);
        await file.writeAsBytes(data.buffer.asUint8List());
        await _add(file.path);
      }
      save();
    }
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

class _LibraryScreenState extends State<LibraryScreen> with SingleTickerProviderStateMixin {
  late final _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  bool _importing = false;

  @override
  void dispose() {
    _enter.dispose();
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

  void _open(Book b) {
    Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, _, _) => ReaderScreen(book: b),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
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
      body: SafeArea(
        child: ListenableBuilder(
          listenable: library,
          builder: (context, _) => CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 30, 12, 18),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    Expanded(
                      child: Text('Kitaplık',
                          style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 34, height: 1.1)),
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
                      TextButton(
                        onPressed: _pick,
                        style: TextButton.styleFrom(foregroundColor: c.accent),
                        child: const Text('Kitap ekle'),
                      ),
                  ]),
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
                    final start = (i.clamp(0, 5) * 0.08);
                    final curve = CurvedAnimation(
                      parent: _enter,
                      curve: Interval(start, (start + 0.6).clamp(0, 1), curve: const Cubic(0.22, 1, 0.36, 1)),
                    );
                    final b = library.books[i];
                    return AnimatedBuilder(
                      animation: curve,
                      builder: (_, child) => Opacity(
                        opacity: curve.value,
                        child: Transform.translate(offset: Offset(0, 12 * (1 - curve.value)), child: child),
                      ),
                      child: _BookCard(book: b, onTap: () => _open(b), onLong: () => _details(b)),
                    );
                  },
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 40)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BookCard extends StatefulWidget {
  const _BookCard({required this.book, required this.onTap, required this.onLong});
  final Book book;
  final VoidCallback onTap, onLong;
  @override
  State<_BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<_BookCard> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final b = widget.book;
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLong,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Hero(tag: b.path, child: BookCover(book: b))),
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
      ),
    );
  }
}

/// A book's cover with the bookmark ribbon that shows how far it has been read.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});
  final Book book;

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
      if (book.progress > 0)
        Positioned(
          right: 12,
          top: 0,
          child: Container(
            width: 7,
            height: 14 + 46 * book.progress,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(1.5)),
            ),
          ),
        ),
    ]);
  }
}
