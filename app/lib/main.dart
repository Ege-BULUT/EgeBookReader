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
import 'l10n.dart';
import 'onboarding.dart';
import 'motion.dart';
import 'reader.dart';
import 'settings_sheet.dart';
import 'settings.dart';
import 'shelf.dart';
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

  /// Read right to left, as manga is.
  bool rtl = false;

  bool favorite = false;

  /// Chosen by the reader or found online; [shelf] fills in the rest.
  String? category;
  final tags = <String>[];

  /// Names of the reader's own lists this book is on.
  final lists = <String>{};

  /// Looked up online already, found or not, so it is not asked again.
  bool looked = false;

  bool get isComic => comicExtensions.contains(p.extension(path).toLowerCase());

  /// The category the library files the book under.
  String get shelf => category ?? (isComic ? 'Çizgi roman' : 'Diğer');

  /// Positions as fractions of the book, so they survive a new font size or page layout.
  final List<double> bookmarks;

  double get progress => total <= 1 ? 0 : (page + 1) / total;

  Map<String, dynamic> toJson() =>
      {'path': path, 'title': title, 'cover': coverPath, 'page': page, 'total': total, 'bookmarks': bookmarks, 'colorizeStarted': colorizeStarted, 'rtl': rtl,
        'favorite': favorite, 'category': category, 'tags': tags, 'lists': lists.toList(), 'looked': looked};
  static Book fromJson(Map<String, dynamic> j) => Book(
        j['path'] as String,
        j['title'] as String,
        j['cover'] as String?,
        page: j['page'] as int,
        total: j['total'] as int,
        bookmarks: ((j['bookmarks'] as List<dynamic>?) ?? const []).map((e) => (e as num).toDouble()).toList(),
      )
        ..colorizeStarted = j['colorizeStarted'] as bool? ?? false
        ..rtl = j['rtl'] as bool? ?? false
        ..favorite = j['favorite'] as bool? ?? false
        ..category = j['category'] as String?
        ..tags.addAll(((j['tags'] as List<dynamic>?) ?? const []).cast<String>())
        ..lists.addAll(((j['lists'] as List<dynamic>?) ?? const []).cast<String>())
        ..looked = j['looked'] as bool? ?? false;
}

class Library extends ChangeNotifier {
  final books = <Book>[];

  /// The reader's own lists, in the order they were made. A list may be empty.
  final listNames = <String>[];
  late Directory _dir;
  File get _index => File(p.join(_dir.path, 'library.json'));
  File get _lists => File(p.join(_dir.path, 'lists.json'));
  static const _samples = {'Dunyanin Dilleri.epub', 'Sayfa Örneği.pdf', 'Renklendirme Denemesi.epub'};

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (_index.existsSync()) {
      final list = jsonDecode(_index.readAsStringSync()) as List<dynamic>;
      books.addAll(list.map((e) => Book.fromJson(e as Map<String, dynamic>)).where((b) => File(b.path).existsSync()));
    }
    if (_lists.existsSync()) listNames.addAll((jsonDecode(_lists.readAsStringSync()) as List<dynamic>).cast<String>());
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

  Future<void> save() async {
    await _index.writeAsString(jsonEncode(books));
    await _lists.writeAsString(jsonEncode(listNames));
  }

  bool _lookingUp = false;

  /// Finds a category and tags online for each book not looked up yet, one at a time, if the reader allows it.
  Future<void> lookUpMissing() async {
    if (_lookingUp) return;
    _lookingUp = true;
    try {
      while (settings.onlineLookup) {
        final b = books.where((b) => !b.looked && !_samples.contains(p.basename(b.path))).firstOrNull;
        if (b == null || !await lookUp(b)) break; // no internet: try again next time
      }
    } finally {
      _lookingUp = false;
    }
  }

  /// Looks [b] up online. [replace] puts the found category over one already chosen. False when it could not ask.
  Future<bool> lookUp(Book b, {bool replace = false}) async {
    final subjects = await lookUpSubjects(b.title);
    if (subjects == null) return false;
    b.looked = true;
    final found = b.isComic ? null : categoryFor(subjects);
    if (found != null && (replace || b.category == null)) b.category = found;
    for (final t in tagsFrom(subjects)) {
      if (!b.tags.contains(t)) b.tags.add(t);
    }
    changed();
    return true;
  }

  void addList(String name) {
    if (name.isEmpty || listNames.contains(name)) return;
    listNames.add(name);
    changed();
  }

  void removeList(String name) {
    listNames.remove(name);
    for (final b in books) {
      b.lists.remove(name);
    }
    changed();
  }

  Future<void> _add(String path) async {
    final source = await openBook(path);
    final cover = await _coverFor(source, path);
    books.insert(0, Book(path, source.title, cover));
    source.dispose();
  }

  /// Copies a picked file into the app and adds it. Throws a [FormatException] the UI can show.
  Future<void> import(String from) async {
    final ext = p.extension(from).toLowerCase();
    if (!supportedExtensions.contains(ext)) throw FormatException('${tr('Bu biçim henüz desteklenmiyor')}: $ext');
    final to = File(p.join(_dir.path, 'books', p.basename(from)));
    await to.create(recursive: true);
    await File(from).copy(to.path);
    books.removeWhere((b) => b.path == to.path);
    await _add(to.path);
    await save();
    notifyListeners();
    lookUpMissing();
  }

  Future<void> remove(Book b) async {
    books.remove(b);
    await File(b.path).delete().catchError((_) => File(b.path));
    await save();
    notifyListeners();
  }

  /// Saves a change to one book and tells whoever shows it.
  void changed() {
    notifyListeners();
    save();
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
          home: settings.onboarded ? const LibraryScreen() : const OnboardingScreen(),
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
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 2150));
  final _headerLogo = GlobalKey();
  bool _importing = false;
  bool _introDone = false;

  /// What the grid shows: 'all', 'fav', or 'list:', 'cat:' or 'tag:' followed by a name.
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    library.lookUpMissing();
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
      Future<void>.delayed(const Duration(milliseconds: 1620), () {
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Açılamadı')}: ${failed.join(', ')}')));
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
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _BookSheet(book: b, newList: _newList),
    );
  }

  /// Asks for a name and makes a list; returns the name, or null if the reader changed their mind.
  Future<String?> _newList() async {
    final c = settings.palette;
    final field = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.paper,
        title: Text(tr('Yeni liste'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        content: TextField(
          controller: field,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: tr('Listenin adı')),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Vazgeç'))),
          TextButton(onPressed: () => Navigator.pop(context, field.text), child: Text(tr('Oluştur'))),
        ],
      ),
    );
    field.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    library.addList(trimmed);
    return trimmed;
  }

  void _settings() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const FractionallySizedBox(heightFactor: 0.72, child: SettingsSheet(isPdf: false, initialTab: 5)),
      );

  bool _matches(Book b) {
    final i = _filter.indexOf(':');
    final value = _filter.substring(i + 1);
    return switch (i < 0 ? _filter : _filter.substring(0, i)) {
      'fav' => b.favorite,
      'list' => b.lists.contains(value),
      'cat' => b.shelf == value,
      'tag' => b.tags.contains(value),
      _ => true,
    };
  }

  /// One chip for everything the grid can be narrowed to: favourites, the reader's lists, categories and tags in use.
  Widget _filters(Palette c) {
    final books = library.books;
    final cats = categories.where((k) => books.any((b) => b.shelf == k)).toList();
    final count = <String, int>{};
    for (final b in books) {
      for (final t in b.tags) {
        count[t] = (count[t] ?? 0) + 1;
      }
    }
    final tags = (count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!))).take(12);
    Widget chip(String key, String label, {IconData? icon, VoidCallback? onLong}) {
      final on = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onLongPress: onLong,
          child: ChoiceChip(
            selected: on,
            showCheckmark: false,
            avatar: icon == null ? null : Icon(icon, size: 16, color: on ? c.paper : c.muted),
            label: Text(label),
            labelStyle: TextStyle(color: on ? c.paper : c.ink, fontSize: 13),
            selectedColor: c.accent,
            backgroundColor: c.surface,
            side: BorderSide(color: on ? c.accent : c.line),
            onSelected: (_) => setState(() => _filter = on ? 'all' : key),
          ),
        ),
      );
    }

    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24), children: [
        chip('all', tr('Tümü')),
        chip('fav', tr('Favoriler'), icon: Icons.star_rounded),
        for (final l in library.listNames)
          chip('list:$l', l, icon: Icons.bookmarks_outlined, onLong: () => _listMenu(l)),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            avatar: Icon(Icons.add, size: 16, color: c.accent),
            label: Text(tr('Liste')),
            labelStyle: TextStyle(color: c.accent, fontSize: 13),
            backgroundColor: c.paper,
            side: BorderSide(color: c.line),
            onPressed: () async {
              final name = await _newList();
              if (name != null && mounted) setState(() => _filter = 'list:$name');
            },
          ),
        ),
        for (final k in cats) chip('cat:$k', tr(k)),
        for (final t in tags) chip('tag:$t', '#$t'),
      ]),
    );
  }

  void _listMenu(String name) {
    final c = settings.palette;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(tr('Listeyi silmek kitapları silmez.'), style: TextStyle(color: c.muted, fontSize: 13)),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                library.removeList(name);
                if (_filter == 'list:$name') setState(() => _filter = 'all');
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.accent),
              child: Text(tr('Listeyi sil')),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _grid(List<Book> books, int columns, int from) => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        sliver: SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 18,
            mainAxisSpacing: 26,
            childAspectRatio: 0.56,
          ),
          itemCount: books.length,
          itemBuilder: (context, i) {
            final b = books[i];
            return _Entering(
              key: ValueKey(b.path),
              parent: _enter,
              index: from + i,
              child: _BookCard(book: b, onOpen: _open, onLong: () => _details(b)),
            );
          },
        ),
      );

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
              // A list or tag that went away takes its filter with it.
              if (_filter != 'all' && _filter != 'fav' && !library.books.any(_matches) && !_filter.startsWith('list:')) _filter = 'all';
              if (_filter.startsWith('list:') && !library.listNames.contains(_filter.substring(5))) _filter = 'all';
              final shown = library.books.where(_matches).toList();
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
                          child: Text(tr('Kitaplık'),
                              style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 32, height: 1.1)),
                        ),
                      ),
                      _Entering(
                        parent: _enter,
                        index: 0,
                        child: IconButton(
                          tooltip: tr('Galeri'),
                          icon: Icon(Icons.photo_library_outlined, color: c.muted, size: 21),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen())),
                        ),
                      ),
                      _Entering(
                        parent: _enter,
                        index: 0,
                        child: IconButton(
                          tooltip: tr('Ayarlar'),
                          icon: Icon(Icons.tune_rounded, color: c.muted, size: 21),
                          onPressed: _settings,
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
                            child: Text(tr('Kitap ekle')),
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
                  padding: const EdgeInsets.only(bottom: 22),
                  sliver: SliverToBoxAdapter(child: _Entering(parent: _enter, index: 1, child: _filters(c))),
                ),
                if (shown.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
                      child: Text(tr(_filter == 'fav' ? 'Favori yok. Bir kitaba uzun basıp yıldızla.' : 'Burada kitap yok. Bir kitaba uzun basıp ekle.'),
                          textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14)),
                    ),
                  )
                else if (!settings.groupByCategory || _filter != 'all')
                  _grid(shown, columns, 2)
                else
                  for (final k in categories.where((k) => shown.any((b) => b.shelf == k))) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                      sliver: SliverToBoxAdapter(
                        child: Text(tr(k), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 21)),
                      ),
                    ),
                    _grid(shown.where((b) => b.shelf == k).toList(), columns, 2),
                    const SliverToBoxAdapter(child: SizedBox(height: 26)),
                  ],
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

  /// The mark builds itself on empty paper, then travels to its place in the header.
  Widget _introOverlay(Palette c) {
    return AnimatedBuilder(
      animation: _intro,
      builder: (context, _) {
        final screen = MediaQuery.sizeOf(context);
        final t = _intro.value;
        final draw = (t / 0.74).clamp(0.0, 1.0);
        final travel = easeEnter.transform(((t - 0.76) / 0.24).clamp(0.0, 1.0));
        final box = _headerLogo.currentContext?.findRenderObject() as RenderBox?;
        final header = box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : Offset.zero & const Size(21, 26);
        const height = 132.0;
        final start = Rect.fromCenter(center: screen.center(Offset.zero), width: height * 320 / 256, height: height);
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
              Text(tr('Okumaya devam et'), style: TextStyle(color: c.muted, fontSize: 12)),
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
              Text('${tr('Sayfa')} ${b.page + 1} / ${b.total}', style: TextStyle(color: c.muted, fontSize: 12)),
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
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              SizedBox(key: _cover, width: double.infinity, child: BookCover(book: b)),
              if (b.favorite)
                Positioned(
                  left: 6,
                  top: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: c.paper.withValues(alpha: 0.85), shape: BoxShape.circle),
                    child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.star_rounded, size: 16, color: c.accent)),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(b.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w500, height: 1.25)),
          const SizedBox(height: 2),
          Text(b.total == 0 ? tr('Yeni') : '%${(b.progress * 100).round()}',
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

/// What a long press on a book opens: favourite, category, lists, tags, looking it up online, removing it.
class _BookSheet extends StatefulWidget {
  const _BookSheet({required this.book, required this.newList});
  final Book book;
  final Future<String?> Function() newList;
  @override
  State<_BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<_BookSheet> {
  final _tag = TextEditingController();
  bool _looking = false;
  bool _offline = false;

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  void _addTag(String text) {
    final t = text.trim();
    if (t.isNotEmpty && !widget.book.tags.contains(t)) {
      widget.book.tags.add(t);
      library.changed();
    }
    _tag.clear();
  }

  Future<void> _lookUp() async {
    setState(() => _looking = true);
    final ok = await library.lookUp(widget.book, replace: true);
    if (mounted) {
      setState(() {
        _looking = false;
        _offline = !ok;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final c = settings.palette;
        final b = widget.book;
        Widget label(String text) => Padding(
              padding: const EdgeInsets.only(top: 18, bottom: 8),
              child: Text(tr(text), style: TextStyle(color: c.muted, fontSize: 13)),
            );
        Widget pick(String text, bool on, VoidCallback tap) => FilterChip(
              selected: on,
              showCheckmark: false,
              label: Text(text),
              labelStyle: TextStyle(color: on ? c.paper : c.ink, fontSize: 13),
              selectedColor: c.accent,
              backgroundColor: c.surface,
              side: BorderSide(color: on ? c.accent : c.line),
              onSelected: (_) => tap(),
            );
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: SafeArea(
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 18, 24, 12), children: [
                Row(children: [
                  Expanded(child: Text(b.title, style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w500))),
                  IconButton(
                    tooltip: tr(b.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle'),
                    icon: Icon(b.favorite ? Icons.star_rounded : Icons.star_outline_rounded, color: b.favorite ? c.accent : c.muted),
                    onPressed: () {
                      b.favorite = !b.favorite;
                      library.changed();
                    },
                  ),
                ]),
                label('Kategori'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final k in categories)
                    pick(tr(k), b.shelf == k, () {
                      b.category = k;
                      library.changed();
                    }),
                ]),
                label('Listeler'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final l in library.listNames)
                    pick(l, b.lists.contains(l), () {
                      if (!b.lists.remove(l)) b.lists.add(l);
                      library.changed();
                    }),
                  ActionChip(
                    avatar: Icon(Icons.add, size: 16, color: c.accent),
                    label: Text(tr('Yeni liste')),
                    labelStyle: TextStyle(color: c.accent, fontSize: 13),
                    backgroundColor: c.paper,
                    side: BorderSide(color: c.line),
                    onPressed: () async {
                      final name = await widget.newList();
                      if (name == null) return;
                      b.lists.add(name);
                      library.changed();
                    },
                  ),
                ]),
                label('Etiketler'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final t in b.tags)
                    InputChip(
                      label: Text(t),
                      labelStyle: TextStyle(color: c.ink, fontSize: 13),
                      backgroundColor: c.surface,
                      side: BorderSide(color: c.line),
                      deleteIconColor: c.muted,
                      onDeleted: () {
                        b.tags.remove(t);
                        library.changed();
                      },
                    ),
                ]),
                TextField(
                  controller: _tag,
                  style: TextStyle(color: c.ink, fontSize: 14),
                  decoration: InputDecoration(hintText: tr('Etiket ekle'), isDense: true),
                  onSubmitted: _addTag,
                ),
                const SizedBox(height: 14),
                Row(children: [
                  TextButton(
                    onPressed: _looking ? null : _lookUp,
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.accent),
                    child: Text(tr(_looking ? 'Aranıyor…' : 'İnternetten bul')),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      library.remove(b);
                      Navigator.pop(context);
                    },
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.muted),
                    child: Text(tr('Kitaplıktan kaldır')),
                  ),
                ]),
                if (_offline) Text(tr('İnternete ulaşılamadı.'), style: TextStyle(color: c.muted, fontSize: 13)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
