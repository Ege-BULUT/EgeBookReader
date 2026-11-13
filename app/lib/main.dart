import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'incoming.dart';
import 'backup.dart' show logError;
import 'library_sheets.dart';
import 'l10n.dart';
import 'onboarding.dart';
import 'meta.dart';
import 'motion.dart';
import 'reader.dart';
import 'settings_sheet.dart';
import 'settings.dart';
import 'shelf.dart';
import 'sources.dart';
import 'stats.dart';
import 'tts.dart';
import 'voicing.dart';

final settings = Settings();
final library = Library();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  await fonts.load();
  await colorizer.load();
  await voices.load();
  await voicing.load();
  speaker.ready = voicing.fileFor;
  speaker.mustWait = (s) => settings.autoVoice && voicing.running && s.page >= voicing.runFrom;
  await settings.load();
  // First start on an e-ink reader (Onyx Boox, PocketBook, Kobo, Bigme, Meebook, Hisense A-series): start in the E-ink theme.
  if (!settings.onboarded) {
    final maker = await device.invokeMethod<String>('maker').catchError((_) => null) ?? '';
    if (isEinkMaker(maker)) settings.theme = PaperTheme.eink;
  }
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    logError(d.exception, d.stack);
  };
  ui.PlatformDispatcher.instance.onError = (e, stack) {
    logError(e, stack);
    return false;
  };
  await library.load();
  await stats.load();
  void flush() {
    library.flush();
    stats.flush();
  }

  AppLifecycleListener(onPause: flush, onDetach: flush, onResume: checkWatchedFolder);
  device.setMethodCallHandler((call) async {
    if (call.method != 'open') return readerCalls?.call(call);
    final a = call.arguments as Map<dynamic, dynamic>;
    openRequest.value = (a['book'] as String, a['speak'] == true);
  });
  // opened from the home-screen shelf
  if (await device.invokeMethod<Map<dynamic, dynamic>>('takeOpen') case final a?) openRequest.value = (a['book'] as String, a['speak'] == true);
  library.addListener(_pushShelf);
  _pushShelf();
  runApp(const EgeBookReaderApp());
  checkWatchedFolder();
}

const device = MethodChannel('egebookreader/volume');

/// Calls from Android meant for the open reader (volume keys, the reading notification's buttons).
Future<dynamic> Function(MethodCall)? readerCalls;

/// A book the home-screen shelf asked for, and whether to read it aloud.
final openRequest = ValueNotifier<(String, bool)?>(null);

String? _shelfSent;

/// The latest books, for the home-screen shelf.
void _pushShelf() {
  final shelf = jsonEncode([
    for (final b in library.books.take(5)) {'path': b.path, 'title': b.title, 'cover': b.cover ?? ''},
  ]);
  if (shelf == _shelfSent) return;
  _shelfSent = shelf;
  device.invokeMethod('shelf', shelf);
}

class Book {
  Book(this.path, this.title, this.coverPath, {this.page = 0, this.total = 0, List<double>? bookmarks})
      : bookmarks = bookmarks ?? [];
  final String path;
  String title;
  final String? coverPath;
  int page, total;
  bool colorizeStarted = false;

  /// Read right to left, as manga is.
  bool rtl = false;

  bool favorite = false;

  /// Chosen by the reader or found online; [shelves] fills in when there are none.
  final categories = <String>{};
  final tags = <String>[];

  /// Names of the reader's own lists this book is on.
  final lists = <String>{};

  /// Author, publisher and the rest, keyed as in [metaFields] (without the title).
  final info = <String, String>{};

  /// What Open Library said, kept so the details sheet can offer it.
  BookMeta? online;

  /// Looked up online already, found or not, so it is not asked again.
  bool looked = false;

  /// The file's own metadata has been read into [info].
  bool metaRead = false;

  /// What "Find online" searches for, when the reader changed it.
  String? query;

  /// A cover picture the reader chose, over the book's own.
  String? customCover;

  /// When the book was added and last opened, in milliseconds since the epoch; 0 if never.
  int added = 0, opened = 0;

  List<double> bookmarks;

  /// The reader's own rating, 1 to 5 stars; 0 when not rated.
  int rating = 0;

  /// How long a page of this book takes the reader, in seconds, learnt while reading; 0 until known.
  double secondsPerPage = 0;

  /// Sentences the reader marked, with their notes.
  final highlights = <Highlight>[];

  double get progress => total <= 1 ? 0 : (page + 1) / total;

  bool get isComic => comicExtensions.contains(p.extension(path).toLowerCase());

  /// The categories the library files the book under.
  List<String> get shelves {
    final known = categories.where(categoriesOrder.containsKey).toList()..sort((a, b) => categoriesOrder[a]!.compareTo(categoriesOrder[b]!));
    return known.isNotEmpty ? known : [isComic ? 'Çizgi roman' : 'Diğer'];
  }

  String get defaultQuery => [title, info['author']].nonNulls.join(' ');

  String? get cover => customCover ?? coverPath;

  Map<String, dynamic> toJson() => {
        'path': path, 'title': title, 'cover': coverPath, 'page': page, 'total': total, 'bookmarks': bookmarks,
        'colorizeStarted': colorizeStarted, 'rtl': rtl, 'favorite': favorite, 'categories': categories.toList(), 'tags': tags,
        'lists': lists.toList(), 'info': info, 'online': online, 'looked': looked, 'metaRead': metaRead, 'query': query,
        'customCover': customCover, 'added': added, 'opened': opened, 'highlights': highlights, 'rating': rating, 'secondsPerPage': secondsPerPage,
      };
  static Book fromJson(Map<String, dynamic> j) {
    List<String> strings(String key) => ((j[key] as List<dynamic>?) ?? const []).cast<String>();
    return Book(
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
      ..categories.addAll([...strings('categories'), if (j['category'] case final String c) c])
      ..tags.addAll(strings('tags'))
      ..lists.addAll(strings('lists'))
      ..info.addAll(((j['info'] as Map<String, dynamic>?) ?? const {}).cast<String, String>())
      ..online = j['online'] == null ? null : BookMeta.fromJson(j['online'] as Map<String, dynamic>)
      ..looked = j['looked'] as bool? ?? false
      ..metaRead = j['metaRead'] as bool? ?? false
      ..query = j['query'] as String?
      ..customCover = j['customCover'] as String?
      ..added = j['added'] as int? ?? 0
      ..opened = j['opened'] as int? ?? 0
      ..rating = j['rating'] as int? ?? 0
      ..secondsPerPage = (j['secondsPerPage'] as num?)?.toDouble() ?? 0
      ..highlights.addAll(((j['highlights'] as List<dynamic>?) ?? const []).map((e) => Highlight.fromJson(e as Map<String, dynamic>)));
  }
}

/// Writes [file] through a copy beside it, so it is either the old text or the new, never a part.
void writeWhole(File file, String text) {
  final temp = File('${file.path}.new')..writeAsStringSync(text, flush: true);
  temp.renameSync(file.path);
}

/// A marked sentence. Pages move when the font or the screen changes, so it is found again by its text near where it was.
class Highlight {
  Highlight(this.text, this.at, this.color, {this.note, int? made}) : made = made ?? DateTime.now().millisecondsSinceEpoch;
  final String text;

  /// How far through the book it is, 0 to 1.
  final double at;
  int color;
  String? note;
  final int made;

  Map<String, dynamic> toJson() => {'text': text, 'at': at, 'color': color, 'note': note, 'made': made};
  static Highlight fromJson(Map<String, dynamic> j) =>
      Highlight(j['text'] as String, (j['at'] as num).toDouble(), j['color'] as int, note: j['note'] as String?, made: j['made'] as int?);

  /// Whether a sentence on a page is this one; a sentence cut by a page break counts by its part.
  bool matches(String sentence) =>
      sentence == text || (sentence.length >= 15 && text.contains(sentence)) || (text.length >= 15 && sentence.contains(text));
}

/// The highlighter colours, the first being the default.
const highlightColors = [0xFFF2C94C, 0xFF7BC67E, 0xFF6FA8DC, 0xFFE58FB0];

class Library extends ChangeNotifier {
  final books = <Book>[];

  /// Goes up with every change shown, so views can keep what they worked out until the next one.
  int revision = 0;

  @override
  void notifyListeners() {
    revision++;
    super.notifyListeners();
  }

  /// The reader's own lists, in the order they were made. A list may be empty.
  final listNames = <String>[];
  late Directory _dir;
  File get _index => File(p.join(_dir.path, 'library.json'));
  File get _lists => File(p.join(_dir.path, 'lists.json'));
  static const _samples = {'Dunyanin Dilleri.epub', 'Sayfa Örneği.pdf', 'Renklendirme Denemesi.epub'};

  Future<void> load() async {
    _dir = await getApplicationDocumentsDirectory();
    if (_index.existsSync()) {
      try {
        final list = jsonDecode(_index.readAsStringSync()) as List<dynamic>;
        books.addAll(list.map((e) => Book.fromJson(e as Map<String, dynamic>)).where((b) => File(b.path).existsSync()));
      } on FormatException {
        // Before 0.1.9 a write cut short could leave it empty; the books themselves are found again below.
        _index.renameSync('${_index.path}.broken');
      }
      // Books from before 0.1.7 have no date added; the copy's file date is when it came in.
      for (final b in books.where((b) => b.added == 0)) {
        b.added = File(b.path).statSync().modified.millisecondsSinceEpoch;
      }
    }
    if (_lists.existsSync()) {
      try {
        listNames.addAll((jsonDecode(_lists.readAsStringSync()) as List<dynamic>).cast<String>());
      } on FormatException {
        _lists.deleteSync();
      }
    }
    // A book file the library does not list (its entry was lost) comes back, without its reading place.
    final folder = Directory(p.join(_dir.path, 'books'));
    if (folder.existsSync()) {
      final known = {for (final b in books) b.path};
      for (final f in folder.listSync().whereType<File>()) {
        if (known.contains(f.path) || !supportedExtensions.contains(p.extension(f.path).toLowerCase())) continue;
        try {
          await _add(f.path);
        } catch (_) {
          // a file that cannot be opened stays where it is
        }
      }
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

  Timer? _saving;

  /// Writes the library a moment after the last change, so a burst of changes (page turns, tag taps) is one write.
  Future<void> save() async {
    _saving?.cancel();
    _saving = Timer(const Duration(milliseconds: 600), flush);
  }

  /// Writes the library now; called when the app goes to the background. At once and whole, since the app
  /// may be closed right after: a write cut short must never leave half a file.
  Future<void> flush() async {
    _saving?.cancel();
    _saving = null;
    writeWhole(_index, jsonEncode(books));
    writeWhole(_lists, jsonEncode(listNames));
  }

  bool _filling = false;

  /// Reads each book's own metadata once, then, if the reader allows it, looks each book up online once.
  /// One book at a time, in the background; with no internet it stops and tries again next time.
  Future<void> fillIn() async {
    if (_filling) return;
    _filling = true;
    try {
      for (Book? b; (b = books.where((b) => !b.metaRead).firstOrNull) != null;) {
        await readOwnMeta(b!);
      }
      while (settings.onlineLookup) {
        final b = books.where((b) => !b.looked && !_samples.contains(p.basename(b.path))).firstOrNull;
        if (b == null || !await lookUp(b)) break;
      }
    } finally {
      _filling = false;
    }
  }

  /// Fills [b] from what its file says, without overwriting anything already there.
  Future<void> readOwnMeta(Book b) async {
    final m = await readMeta(b.path);
    b.metaRead = true;
    _take(b, m, replace: false);
    if (m.rtl) b.rtl = true;
    changed();
  }

  /// Looks [b] up online with its search text. [replace] lets what is found replace the categories. False when it could not ask.
  Future<bool> lookUp(Book b, {bool replace = false}) async {
    final found = await lookUpOnline(b.query ?? b.defaultQuery);
    if (found == null) return false;
    b.looked = true;
    b.online = found;
    _take(b, found, replace: replace);
    changed();
    return true;
  }

  /// Fills empty facts of [b] from [m], adds its tags, and files it under the category its subjects point to.
  void _take(Book b, BookMeta m, {required bool replace}) {
    for (final e in m.fields.entries) {
      if (e.key != 'title') b.info.putIfAbsent(e.key, () => e.value);
    }
    final category = b.isComic ? null : categoryFor(m.subjects);
    if (category != null && (replace || b.categories.isEmpty)) {
      if (replace) b.categories.clear();
      b.categories.add(category);
    }
    for (final t in tagsFrom(m.subjects)) {
      if (!b.tags.contains(t)) b.tags.add(t);
    }
  }

  /// Puts a picture the reader picked over the book's cover.
  Future<void> setCover(Book b, String from) async {
    await clearCover(b, notify: false);
    final to = File(p.join(_dir.path, 'covers', 'custom-${DateTime.now().millisecondsSinceEpoch}${p.extension(from)}'));
    await to.create(recursive: true);
    await File(from).copy(to.path);
    b.customCover = to.path;
    changed();
  }

  Future<void> clearCover(Book b, {bool notify = true}) async {
    final old = b.customCover;
    b.customCover = null;
    if (old != null) await File(old).delete().catchError((_) => File(old));
    if (notify) changed();
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
    books.insert(0, Book(path, source.title, cover)..added = DateTime.now().millisecondsSinceEpoch);
    source.dispose();
  }

  /// Copies a picked file into the app and adds it; false when the very same file is already in the library.
  /// A different file with the same name is kept under a new name, so no book is ever replaced.
  /// Throws a [FormatException] the UI can show.
  /// Copies a book into the library. With [opf] and [cover] (Calibre keeps them beside each book) its facts
  /// and cover come from there.
  Future<bool> import(String from, {String? opf, String? cover}) async {
    final ext = p.extension(from).toLowerCase();
    if (!supportedExtensions.contains(ext)) throw FormatException('${tr('Bu biçim henüz desteklenmiyor')}: $ext');
    final picked = File(from);
    final stem = p.basenameWithoutExtension(from);
    var to = File(p.join(_dir.path, 'books', p.basename(from)));
    for (var n = 2; to.existsSync(); n++) {
      if (await sameFile(picked, to) && books.any((b) => b.path == to.path)) return false;
      to = File(p.join(_dir.path, 'books', '$stem ($n)$ext'));
    }
    await to.create(recursive: true);
    await picked.copy(to.path);
    await _add(to.path);
    if (opf != null) {
      try {
        final m = readOpf(await File(opf).readAsString());
        final b = books.first;
        if (m.fields['title'] case final t?) b.title = t;
        _take(b, m, replace: true);
      } catch (_) {
        // a broken metadata.opf leaves what the book itself says
      }
    }
    if (cover != null) await setCover(books.first, cover);
    await save();
    notifyListeners();
    fillIn();
    return true;
  }

  /// Removes the book and everything kept for it: the file, its covers and an unpacked comic.
  Future<void> remove(Book b) async {
    books.remove(b);
    await clearCover(b, notify: false);
    final unpacked = await comicFolder(b.path); // before the file goes: its size is part of the name
    if (unpacked.existsSync()) await unpacked.delete(recursive: true);
    for (final path in [b.path, ?b.coverPath]) {
      await File(path).delete().catchError((_) => File(path));
    }
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

/// Two files with the same size and the same first and last megabyte are taken to be one book.
// ponytail: samples the ends instead of hashing everything; a full hash if two editions ever slip through.
Future<bool> sameFile(File a, File b) async {
  final size = await a.length();
  if (size != await b.length()) return false;
  Future<List<int>> part(File f, int start) async => (await f.openRead(start, min(size, start + (1 << 20))).toList()).expand((x) => x).toList();
  for (final start in {0, max(0, size - (1 << 20))}) {
    final x = await part(a, start), y = await part(b, start);
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
  }
  return true;
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
    // E-ink screens smear moving pictures: screens change at once there.
    pageTransitionsTheme: settings.isEink ? const PageTransitionsTheme(builders: {TargetPlatform.android: _AtOnce()}) : null,
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

  /// What the chip row picks: 'all', 'fav', or 'list:' followed by a list's name.
  String _filter = 'all';

  /// What the filter sheet narrows it to.
  final _more = LibraryFilter();

  /// Search text, folded; null while the search field is closed.
  String? _search;

  /// The books picked for a change to all of them at once; null when not picking.
  Set<Book>? _picking;

  void _togglePick(Book b) => setState(() {
        if (!_picking!.remove(b)) _picking!.add(b);
      });

  @override
  void initState() {
    super.initState();
    library.fillIn();
    openRequest.addListener(_openRequested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequested());
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
    openRequest.removeListener(_openRequested);
    _enter.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty) return;
    setState(() => _importing = true);
    final failed = <String>[], already = <String>[];
    for (final f in picked) {
      try {
        if (f.path != null && !await library.import(f.path!)) already.add(f.name);
      } catch (e) {
        failed.add(f.name);
      }
    }
    if (!mounted) return;
    setState(() => _importing = false);
    final notes = [
      if (failed.isNotEmpty) '${tr('Açılamadı')}: ${failed.join(', ')}',
      if (already.isNotEmpty) '${tr('Zaten kitaplıkta')}: ${already.join(', ')}',
    ];
    if (notes.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(notes.join('\n'))));
  }

  Future<void> _fromFolder() async {
    setState(() => _importing = true);
    try {
      final done = await importFolder();
      if (done != null && mounted) {
        final (added, failed) = done;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(['${tr('Eklenen kitap')}: $added', if (failed.isNotEmpty) '${tr('Açılamadı')}: ${failed.join(', ')}'].join('\n'))));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _openRequested() {
    final (path, speak) = openRequest.value ?? ('', false);
    final b = library.books.where((b) => b.path == path).firstOrNull;
    if (b == null || !mounted) return;
    openRequest.value = null;
    Navigator.of(context).popUntil((r) => r.isFirst);
    b.opened = DateTime.now().millisecondsSinceEpoch;
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(book: b, coverRect: () => null, speak: speak)))
        .then((_) => library.moveToFront(b));
  }

  void _open(Book b, GlobalKey cover) {
    Rect? rect() {
      final box = cover.currentContext?.findRenderObject() as RenderBox?;
      return box != null && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
    }

    b.opened = DateTime.now().millisecondsSinceEpoch;
    Navigator.of(context)
        .push(PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => ReaderScreen(book: b, coverRect: rect),
        ))
        .then((_) => library.moveToFront(b));
  }

  void _details(Book b) => showShelfSheet(context, (_) => BookSheet(book: b, newList: _newList));

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

  /// Each book's searchable text, folded once per library change instead of on every keystroke.
  final _folded = <Book, String>{};
  int _foldedAt = -1;

  String _foldedText(Book b) {
    if (_foldedAt != library.revision) {
      _folded.clear();
      _foldedAt = library.revision;
    }
    return _folded[b] ??= foldForSearch([b.title, ...b.info.values.where((v) => v.length < 200), ...b.tags].join('\n'));
  }

  bool _matches(Book b) =>
      _more.matches(b) &&
      (_search == null || _foldedText(b).contains(_search!)) &&
      switch (_filter) {
        'all' => true,
        'fav' => b.favorite,
        _ => b.lists.contains(_filter.substring(5)),
      };

  /// Quick picks: everything, favourites, and the reader's own lists.
  Widget _filters(Palette c) {
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
        chip('fav', tr('Favoriler'), icon: Icons.favorite_rounded),
        for (final l in library.listNames)
          chip('list:$l', l, icon: Icons.bookmarks_outlined, onLong: () => _listMenu(l)),
        ActionChip(
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

  /// Category sections in the chosen order, each category once.
  List<String> _sections(List<Book> books) {
    final keys = {for (final b in books) ...b.shelves}.toList()..sort((a, b) => sortKey(tr(a)).compareTo(sortKey(tr(b))));
    return settings.sortDescending ? keys.reversed.toList() : keys;
  }

  Object? _shownFor;
  List<Book> _shownBooks = const [];
  Map<String, List<Book>> _shownSections = const {};

  /// The books on show, sorted, and by category when sorted so; worked out again only when something they depend on changed.
  List<Book> _shown() {
    final s = settings;
    final key = (library.revision, s.sortBy, s.sortDescending, s.uiLanguage, _filter, _search, _more.signature);
    if (key == _shownFor) return _shownBooks;
    _shownFor = key;
    _shownBooks = sortBooks(library.books.where(_matches).toList(), s.sortBy, s.sortDescending);
    _shownSections = switch (s.sortBy) {
      SortBy.category => {
          for (final k in _sections(_shownBooks)) tr(k): sortBooks(_shownBooks.where((b) => b.shelves.contains(k)).toList(), SortBy.title, false),
        },
      // A section per series, its books by number; books in no series after them.
      SortBy.series => {
          for (final b in _shownBooks) b.info['series'] ?? tr('Seride değil'): [
            for (final x in _shownBooks)
              if ((x.info['series'] ?? tr('Seride değil')) == (b.info['series'] ?? tr('Seride değil'))) x,
          ]..sort((x, y) => volumeOf(x).compareTo(volumeOf(y))),
        },
      _ => const {},
    };
    return _shownBooks;
  }

  /// Search, how many books show, how they are ordered, grid or list, and the way to narrow them further.
  Widget _toolbar(Palette c, int shown) {
    final s = settings;
    final searching = _search != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(children: [
        IconButton(
          tooltip: tr(searching ? 'Aramayı kapat' : 'Ara'),
          onPressed: () => setState(() => _search = searching ? null : ''),
          icon: Icon(searching ? Icons.close : Icons.search, color: searching ? c.accent : c.muted, size: 22),
        ),
        Expanded(
          child: searching
              ? TextField(
                  autofocus: true,
                  style: TextStyle(color: c.ink, fontSize: 15),
                  decoration: InputDecoration(isDense: true, hintText: tr('Ad, yazar, etiket…'), suffixText: '$shown'),
                  onChanged: (v) => setState(() => _search = foldForSearch(v.trim())),
                )
              : Text('$shown ${tr('kitap')}', style: TextStyle(color: c.muted, fontSize: 13)),
        ),
        if (!searching)
          TextButton.icon(
            onPressed: () => showShelfSheet(context, (_) => const SortSheet()),
            style: TextButton.styleFrom(foregroundColor: c.ink, padding: const EdgeInsets.symmetric(horizontal: 8)),
            icon: Icon(s.sortDescending ? Icons.arrow_downward : Icons.arrow_upward, size: 16, color: c.accent),
            label: Text(tr(s.sortBy.label), style: const TextStyle(fontSize: 13)),
          ),
        IconButton(
          tooltip: tr(s.libraryList ? 'Izgara görünümü' : 'Liste görünümü'),
          onPressed: () => s.update((x) => x.libraryList = !x.libraryList),
          icon: Icon(s.libraryList ? Icons.grid_view_rounded : Icons.view_list_rounded, color: c.muted, size: 22),
        ),
        IconButton(
          tooltip: tr('Seç'),
          onPressed: () => setState(() => _picking = {}),
          icon: Icon(Icons.checklist_rounded, color: c.muted, size: 22),
        ),
        IconButton(
          tooltip: tr('Filtrele'),
          onPressed: () => showShelfSheet(context, (_) => FilterSheet(filter: _more, onChanged: () => setState(() {}))),
          icon: Badge(
            isLabelVisible: _more.count > 0,
            label: Text('${_more.count}'),
            backgroundColor: c.accent,
            child: Icon(Icons.filter_list, color: _more.count > 0 ? c.accent : c.muted, size: 22),
          ),
        ),
      ]),
    );
  }

  /// In place of the toolbar while picking: how many are picked, and what can be done to all of them.
  Widget _pickBar(Palette c, List<Book> shown) {
    final picked = _picking!;
    final all = shown.isNotEmpty && shown.every(picked.contains);
    bool? state(bool Function(Book) has) => picked.every(has) ? true : (picked.any(has) ? null : false);
    void flip(bool Function(Book) has, void Function(Book, bool) set) {
      final on = !picked.every(has);
      for (final b in picked) {
        set(b, on);
      }
      library.changed();
    }

    Widget menu(IconData icon, String tip, List<Widget> items) => MenuAnchor(
          menuChildren: items,
          builder: (context, m, _) => IconButton(
            tooltip: tr(tip),
            onPressed: picked.isEmpty ? null : () => m.isOpen ? m.close() : m.open(),
            icon: Icon(icon, color: c.ink, size: 22),
          ),
        );
    CheckboxMenuButton tick(String label, bool Function(Book) has, void Function(Book, bool) set) => CheckboxMenuButton(
          value: picked.isEmpty ? false : state(has),
          tristate: true,
          closeOnActivate: false,
          onChanged: (_) => flip(has, set),
          child: Text(label),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Row(children: [
        IconButton(
          tooltip: tr('Seçmeyi bitir'),
          onPressed: () => setState(() => _picking = null),
          icon: Icon(Icons.close, color: c.accent, size: 22),
        ),
        Expanded(child: Text('${picked.length} ${tr('seçili')}', style: TextStyle(color: c.ink, fontSize: 14))),
        TextButton(
          onPressed: () => setState(() => all ? picked.clear() : picked.addAll(shown)),
          style: TextButton.styleFrom(foregroundColor: c.accent, padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(tr(all ? 'Hiçbiri' : 'Tümü')),
        ),
        IconButton(
          tooltip: tr('Favori'),
          onPressed: picked.isEmpty ? null : () => flip((b) => b.favorite, (b, on) => b.favorite = on),
          icon: Icon(picked.isNotEmpty && picked.every((b) => b.favorite) ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: c.ink, size: 22),
        ),
        menu(Icons.bookmarks_outlined, 'Listeler', [
          for (final l in library.listNames) tick(l, (b) => b.lists.contains(l), (b, on) => on ? b.lists.add(l) : b.lists.remove(l)),
          MenuItemButton(
            leadingIcon: Icon(Icons.add, size: 18, color: c.accent),
            onPressed: () async {
              final name = await _newList();
              if (name == null) return;
              for (final b in picked) {
                b.lists.add(name);
              }
              library.changed();
            },
            child: Text(tr('Yeni liste'), style: TextStyle(color: c.accent)),
          ),
        ]),
        menu(Icons.category_outlined, 'Kategoriler', [
          for (final k in categories) tick(tr(k), (b) => b.categories.contains(k), (b, on) => on ? b.categories.add(k) : b.categories.remove(k)),
        ]),
        IconButton(
          tooltip: tr('Kitaplıktan kaldır'),
          onPressed: picked.isEmpty ? null : () => _removePicked(c),
          icon: Icon(Icons.delete_outline, color: c.ink, size: 22),
        ),
      ]),
    );
  }

  Future<void> _removePicked(Palette c) async {
    final picked = _picking!.toList();
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.paper,
        title: Text('${picked.length} ${tr('kitap kaldırılsın mı?')}', style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        content: Text(tr('Dosyaları, kapakları, notları ve okuma yerleri silinir.'), style: TextStyle(color: c.muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Vazgeç'))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Kaldır'))),
        ],
      ),
    );
    if (sure != true) return;
    for (final b in picked) {
      await library.remove(b);
    }
    if (mounted) setState(() => _picking = null);
  }

  /// What is new since the last version the reader saw; gone for good once closed.
  Widget _news(Palette c) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 6, 14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('$appVersion ${tr('sürümünde yeni')}', style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 18))),
            IconButton(
              tooltip: tr('Kapat'),
              icon: Icon(Icons.close, color: c.muted, size: 20),
              onPressed: () => settings.update((x) => x.seenVersion = appVersion),
            ),
          ]),
          for (final line in whatsNew)
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 4),
              child: Text('•  ${tr(line)}', style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.35)),
            ),
        ]),
      );

  /// Books added in the last two weeks, newest first, on a shelf of their own; only once the library has others too.
  List<Widget> _recent(Palette c) {
    final since = DateTime.now().subtract(const Duration(days: 14)).millisecondsSinceEpoch;
    final recent = (library.books.where((b) => b.added > since).toList()..sort((a, b) => b.added.compareTo(a.added))).take(12).toList();
    if (recent.isEmpty || recent.length == library.books.length) return const [];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
        sliver: SliverToBoxAdapter(child: Text(tr('Son eklenenler'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 19))),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: recent.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) => SizedBox(
              width: 96,
              child: _BookCard(book: recent[i], onOpen: _open, onLong: () => _details(recent[i])),
            ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
    ];
  }

  Widget _grid(List<Book> books, int columns, int from) => settings.libraryList
      ? SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: SliverList.builder(
            itemCount: books.length,
            itemBuilder: (context, i) => _Entering(
              key: ValueKey(books[i].path),
              parent: _enter,
              index: from + i,
              child: _BookRow(
                book: books[i],
                picked: _picking?.contains(books[i]),
                onOpen: _picking == null ? _open : (b, _) => _togglePick(b),
                onLong: () => _picking == null ? _details(books[i]) : _togglePick(books[i]),
              ),
            ),
          ),
        )
      : SliverPadding(
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
              child: _BookCard(
                book: b,
                picked: _picking?.contains(b),
                onOpen: _picking == null ? _open : (b, _) => _togglePick(b),
                onLong: () => _picking == null ? _details(b) : _togglePick(b),
              ),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final width = MediaQuery.sizeOf(context).width;
    final columns = (width / 150).floor().clamp(2, 8);
    return PopScope(
      canPop: _picking == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _picking = null);
      },
      child: Scaffold(
      body: Stack(children: [
        SafeArea(
          child: ListenableBuilder(
            listenable: Listenable.merge([library, settings]),
            builder: (context, _) {
              final c = settings.palette;
              final latest = library.books.where((b) => b.total > 0).firstOrNull;
              // A list that went away takes its filter with it.
              if (_filter.startsWith('list:') && !library.listNames.contains(_filter.substring(5))) _filter = 'all';
              final shown = _shown();
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
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(tr('Kitaplık'),
                                style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 32, height: 1.1)),
                          ),
                        ),
                      ),
                      _Entering(
                        parent: _enter,
                        index: 0,
                        child: IconButton(
                          tooltip: tr('Okuma istatistikleri'),
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.insights_outlined, color: c.muted, size: 21),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const StatsScreen())),
                        ),
                      ),
                      _Entering(
                        parent: _enter,
                        index: 0,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Galeri'),
                          icon: Icon(Icons.photo_library_outlined, color: c.muted, size: 21),
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GalleryScreen())),
                        ),
                      ),
                      _Entering(
                        parent: _enter,
                        index: 0,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
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
                          child: MenuAnchor(
                            builder: (_, menu, _) => TextButton(
                              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                              style: TextButton.styleFrom(foregroundColor: c.accent),
                              child: Text(tr('Kitap ekle')),
                            ),
                            menuChildren: [
                              MenuItemButton(leadingIcon: const Icon(Icons.description_outlined), onPressed: _pick, child: Text(tr('Dosya seç'))),
                              MenuItemButton(
                                  leadingIcon: const Icon(Icons.folder_open_outlined), onPressed: _fromFolder, child: Text(tr('Klasörden (Calibre da)'))),
                              MenuItemButton(
                                leadingIcon: const Icon(Icons.wifi_rounded),
                                onPressed: () => showModalBottomSheet<void>(context: context, builder: (_) => const WifiSheet()),
                                child: Text(tr('Bilgisayardan Wi-Fi ile')),
                              ),
                            ],
                          ),
                        ),
                    ]),
                  ),
                ),
                if (settings.seenVersion != appVersion)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                    sliver: SliverToBoxAdapter(child: _news(c)),
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
                  padding: const EdgeInsets.only(bottom: 14),
                  sliver: SliverToBoxAdapter(
                    child: _Entering(
                      parent: _enter,
                      index: 1,
                      child: Column(children: [_filters(c), _picking == null ? _toolbar(c, shown.length) : _pickBar(c, shown)]),
                    ),
                  ),
                ),
                if (_filter == 'all' && _search == null && _more.count == 0 && _picking == null) ..._recent(c),
                if (shown.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
                      child: Text(
                          tr(_more.count > 0
                              ? 'Bu filtrelere uyan kitap yok.'
                              : _filter == 'fav'
                                  ? 'Favori yok. Bir kitaba uzun basıp kalbe dokun.'
                                  : 'Burada kitap yok. Bir kitaba uzun basıp ekle.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.muted, fontSize: 14)),
                    ),
                  )
                else if (_shownSections.isEmpty)
                  _grid(shown, columns, 2)
                else
                  // By category: a section per category, a book in each of its categories, titles A to Z inside.
                  for (final MapEntry(key: k, value: books) in _shownSections.entries) ...[
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 14),
                      sliver: SliverToBoxAdapter(
                        child: Text(k, style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 21)),
                      ),
                    ),
                    _grid(books, columns, 2),
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
      ),
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
  const _BookCard({required this.book, required this.onOpen, required this.onLong, this.picked});
  final Book book;
  final void Function(Book, GlobalKey) onOpen;
  final VoidCallback onLong;

  /// While books are being picked: whether this one is; null otherwise.
  final bool? picked;
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
              SizedBox(key: _cover, width: double.infinity, child: _withTick(widget.picked, BookCover(book: b))),
              if (b.favorite)
                Positioned(
                  left: 6,
                  top: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: c.paper.withValues(alpha: 0.85), shape: BoxShape.circle),
                    child: Padding(padding: const EdgeInsets.all(3), child: Icon(Icons.favorite_rounded, size: 15, color: c.accent)),
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
          Text([?b.info['author'], b.total == 0 ? tr('Yeni') : '%${(b.progress * 100).round()}'].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A book as one row of the list view: cover, title, author, and how far it has been read.
class _BookRow extends StatefulWidget {
  const _BookRow({required this.book, required this.onOpen, required this.onLong, this.picked});
  final Book book;
  final void Function(Book, GlobalKey) onOpen;
  final VoidCallback onLong;

  /// While books are being picked: whether this one is; null otherwise.
  final bool? picked;
  @override
  State<_BookRow> createState() => _BookRowState();
}

class _BookRowState extends State<_BookRow> {
  final _cover = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final b = widget.book;
    return Pressable(
      enabled: motionOn(context, settings),
      onTap: () => widget.onOpen(b, _cover),
      onLongPress: widget.onLong,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(key: _cover, width: 46, height: 66, child: _withTick(widget.picked, BookCover(book: b, ribbon: false))),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(b.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 15, fontWeight: FontWeight.w500)),
                ),
                if (b.favorite) Icon(Icons.favorite_rounded, size: 15, color: c.accent),
              ]),
              if (b.info['author'] case final author?)
                Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(value: b.progress, minHeight: 2, color: c.accent, backgroundColor: c.line),
                  ),
                ),
                const SizedBox(width: 10),
                Text(b.total == 0 ? tr('Yeni') : '%${(b.progress * 100).round()}', style: TextStyle(color: c.muted, fontSize: 12)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// While books are being picked, a tick on the cover, filled for the picked ones.
Widget _withTick(bool? picked, Widget cover) {
  if (picked == null) return cover;
  final c = settings.palette;
  return Stack(fit: StackFit.expand, children: [
    cover,
    if (picked) DecoratedBox(decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(4))),
    Positioned(
      right: 3,
      bottom: 3,
      child: DecoratedBox(
        decoration: BoxDecoration(color: c.paper, shape: BoxShape.circle),
        child: Icon(picked ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: picked ? c.accent : c.muted),
      ),
    ),
  ]);
}

/// A book's cover with the bookmark ribbon that shows how far it has been read.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.ribbon = true});
  final Book book;
  final bool ribbon;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final cover = book.cover;
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
              : LayoutBuilder(
                  // Too small for the title (a list row): its first letter.
                  builder: (context, box) => box.maxWidth < 80
                      ? Center(
                          child: Text(book.title.characters.first.toUpperCase(),
                              style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 22)),
                        )
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

class _AtOnce extends PageTransitionsBuilder {
  const _AtOnce();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> a, Animation<double> b, Widget child) => child;
}
