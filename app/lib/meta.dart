import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_api;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

import 'formats.dart';
import 'sources.dart';

/// The facts a book can carry about itself, in the order the details sheet shows them. The names are keys for tr().
const metaFields = {
  'title': 'Kitap adı',
  'author': 'Yazar',
  'publisher': 'Yayınevi',
  'date': 'Yayım tarihi',
  'language': 'Dil',
  'isbn': 'ISBN',
  'series': 'Seri',
  'volume': 'Cilt',
  'description': 'Açıklama',
};

/// What a file or a catalogue says about a book: [fields] keyed as in [metaFields], and its subjects.
class BookMeta {
  BookMeta([Map<String, String>? fields, List<String>? subjects, this.rtl = false])
      : fields = fields ?? {},
        subjects = subjects ?? [];
  final Map<String, String> fields;
  final List<String> subjects;

  /// The comic says it reads right to left (ComicInfo's Manga "YesAndRightToLeft").
  final bool rtl;

  void put(String key, String? value) {
    final v = value?.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (v != null && v.isNotEmpty) fields.putIfAbsent(key, () => v);
  }

  void addSubjects(Iterable<String> values) {
    for (final v in values.map((v) => v.trim())) {
      if (v.isNotEmpty && !subjects.contains(v)) subjects.add(v);
    }
  }

  Map<String, dynamic> toJson() => {'fields': fields, 'subjects': subjects};
  static BookMeta fromJson(Map<String, dynamic> j) =>
      BookMeta((j['fields'] as Map<String, dynamic>).cast<String, String>(), (j['subjects'] as List<dynamic>).cast<String>());
}

/// The year of a date as books write it ("2001-05-04", "May 2001", "D:20010504"), or null.
int? yearOf(String? date) => int.tryParse(RegExp(r'(1[5-9]|20)\d\d').firstMatch(date ?? '')?[0] ?? '');

/// Reads the title, author and the rest from the book's own file. Never throws: a file that says nothing gives an empty result.
Future<BookMeta> readMeta(String path) async {
  try {
    final ext = p.extension(path).toLowerCase();
    if (ext == '.pdf') return await PdfrxEntryFunctions.instance.compute(_pdfMeta, path);
    if (ext == '.cbr' || ext == '.cb7') {
      final folder = await comicFolder(path);
      final info = folder.existsSync()
          ? folder.listSync(recursive: true).whereType<File>().where((f) => p.basename(f.path).toLowerCase() == 'comicinfo.xml').firstOrNull
          : null;
      return info == null ? BookMeta() : _comicInfo(await info.readAsString());
    }
    final bytes = await File(path).readAsBytes();
    return switch (ext) {
      '.epub' => _epub(bytes),
      '.mobi' || '.azw' || '.azw3' || '.prc' => _mobi(bytes),
      '.fb2' => _fb2(bytes),
      '.fbz' => _fb2(_firstWhere(ZipDecoder().decodeBytes(bytes), (n) => n.endsWith('.fb2')) ?? Uint8List(0)),
      '.docx' => _office(bytes, 'docProps/core.xml'),
      '.odt' => _office(bytes, 'meta.xml'),
      '.html' || '.htm' || '.xhtml' => _html(bytes),
      '.md' || '.markdown' => _markdown(utf8.decode(bytes, allowMalformed: true)),
      '.rtf' => _rtf(latin1.decode(bytes)),
      '.cbz' => _zipComic(ZipDecoder().decodeBytes(bytes)),
      '.cbt' => _zipComic(TarDecoder().decodeBytes(bytes)),
      _ => BookMeta(),
    };
  } catch (_) {
    return BookMeta();
  }
}

Uint8List? _firstWhere(Archive a, bool Function(String lowerName) test) =>
    a.files.where((f) => f.isFile && test(f.name.toLowerCase())).firstOrNull?.content;

Iterable<XmlElement> _named(XmlNode root, String name) => root.descendantElements.where((e) => e.localName == name);
String? _text(XmlNode root, String name) => _named(root, name).map((e) => e.innerText.trim()).where((t) => t.isNotEmpty).firstOrNull;

String? _isbn(Iterable<String> ids) {
  for (final id in ids) {
    final digits = id.replaceAll(RegExp(r'[^0-9Xx]'), '');
    if (digits.length == 10 || digits.length == 13) return digits;
  }
  return null;
}

String _plain(String htmlText) => html.parse(htmlText).documentElement?.text ?? htmlText;

BookMeta _epub(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final container = XmlDocument.parse(utf8.decode(_firstWhere(zip, (n) => n == 'meta-inf/container.xml')!));
  final opfPath = _named(container, 'rootfile').first.getAttribute('full-path')!.toLowerCase();
  return readOpf(utf8.decode(_firstWhere(zip, (n) => n == opfPath)!, allowMalformed: true));
}

/// The facts in an OPF package: the one inside an EPUB, or the metadata.opf Calibre keeps beside each book.
BookMeta readOpf(String xml) {
  final opf = XmlDocument.parse(xml);
  final m = BookMeta()
    ..put('title', _text(opf, 'title'))
    ..put('author', _named(opf, 'creator').map((e) => e.innerText.trim()).where((t) => t.isNotEmpty).join(', '))
    ..put('publisher', _text(opf, 'publisher'))
    ..put('date', _text(opf, 'date'))
    ..put('language', _text(opf, 'language'))
    ..put('isbn', _isbn(_named(opf, 'identifier').map((e) => e.innerText)))
    ..put('description', _plain(_text(opf, 'description') ?? ''))
    ..addSubjects(_named(opf, 'subject').map((e) => e.innerText));
  for (final meta in _named(opf, 'meta')) {
    if (meta.getAttribute('name') == 'calibre:series') m.put('series', meta.getAttribute('content'));
    if (meta.getAttribute('name') == 'calibre:series_index') m.put('volume', meta.getAttribute('content')?.replaceFirst(RegExp(r'\.0$'), ''));
    if (meta.getAttribute('property') == 'group-position') m.put('volume', meta.innerText);
    if (meta.getAttribute('property') == 'belongs-to-collection') m.put('series', meta.innerText);
  }
  return m;
}

BookMeta _mobi(Uint8List d) {
  final v = ByteData.sublistView(d);
  final r0 = v.getUint32(78);
  final h = ByteData.sublistView(d, r0);
  final m = BookMeta();
  if (h.getUint32(128) & 0x40 == 0) return m;
  var at = 16 + h.getUint32(20);
  final total = h.getUint32(at + 8);
  at += 12;
  final authors = <String>[];
  for (var i = 0; i < total; i++) {
    final type = h.getUint32(at), size = h.getUint32(at + 4);
    final text = utf8.decode(Uint8List.sublistView(d, r0 + at + 8, r0 + at + size), allowMalformed: true);
    switch (type) {
      case 100:
        authors.add(text);
      case 101:
        m.put('publisher', text);
      case 103:
        m.put('description', _plain(text));
      case 104:
        m.put('isbn', _isbn([text]));
      case 105:
        m.addSubjects(text.split(';'));
      case 106:
        m.put('date', text);
      case 503:
        m.put('title', text);
      case 524:
        m.put('language', text);
    }
    at += size;
  }
  return m..put('author', authors.join(', '));
}

BookMeta _fb2(Uint8List bytes) {
  final head = latin1.decode(bytes.sublist(0, bytes.length < 200 ? bytes.length : 200));
  final doc = XmlDocument.parse(decodeWith(RegExp(r'encoding="([^"]+)"').firstMatch(head)?[1], bytes));
  final info = _named(doc, 'title-info').firstOrNull ?? doc;
  final publish = _named(doc, 'publish-info').firstOrNull;
  String name(XmlElement a) => ['first-name', 'middle-name', 'last-name'].map((n) => _text(a, n)).nonNulls.join(' ');
  final m = BookMeta()
    ..put('title', _text(info, 'book-title'))
    ..put('author', _named(info, 'author').map(name).where((n) => n.isNotEmpty).join(', '))
    ..put('date', _text(info, 'date'))
    ..put('language', _text(info, 'lang'))
    ..put('description', _text(info, 'annotation'))
    ..put('series', _named(info, 'sequence').firstOrNull?.getAttribute('name'))
    ..put('volume', _named(info, 'sequence').firstOrNull?.getAttribute('number'))
    ..addSubjects(_named(info, 'genre').map((e) => e.innerText.replaceAll('_', ' ')));
  if (publish != null) {
    m
      ..put('publisher', _text(publish, 'publisher'))
      ..put('date', _text(publish, 'year'))
      ..put('isbn', _isbn([_text(publish, 'isbn') ?? '']));
  }
  return m;
}

/// DOCX keeps its facts in docProps/core.xml, ODT in meta.xml; both use Dublin Core names.
BookMeta _office(Uint8List bytes, String file) {
  final data = _firstWhere(ZipDecoder().decodeBytes(bytes), (n) => n == file.toLowerCase());
  if (data == null) return BookMeta();
  final x = XmlDocument.parse(utf8.decode(data, allowMalformed: true));
  return BookMeta()
    ..put('title', _text(x, 'title'))
    ..put('author', _text(x, 'creator') ?? _text(x, 'initial-creator'))
    ..put('date', _text(x, 'created') ?? _text(x, 'creation-date'))
    ..put('language', _text(x, 'language'))
    ..put('description', _text(x, 'description'))
    ..addSubjects([_text(x, 'subject') ?? '', ...(_text(x, 'keywords') ?? '').split(RegExp('[,;]')), ..._named(x, 'keyword').map((e) => e.innerText)]);
}

BookMeta _html(Uint8List bytes) {
  final doc = html.parse(utf8.decode(bytes, allowMalformed: true));
  String? meta(String name) => doc.querySelector('meta[name="$name" i]')?.attributes['content'];
  return BookMeta()
    ..put('title', doc.querySelector('title')?.text)
    ..put('author', meta('author'))
    ..put('description', meta('description'))
    ..put('language', doc.documentElement?.attributes['lang'])
    ..addSubjects((meta('keywords') ?? '').split(','));
}

/// YAML front matter: only plain "key: value" lines and one-line lists are read.
BookMeta _markdown(String text) {
  final m = BookMeta();
  final front = RegExp(r'^---\r?\n([\s\S]*?)\r?\n---').firstMatch(text);
  if (front == null) return m;
  for (final line in front[1]!.split('\n')) {
    final kv = RegExp(r'^(\w+):\s*(.*)$').firstMatch(line.trim());
    if (kv == null) continue;
    final value = kv[2]!.replaceAll(RegExp(r'''^["']|["']$'''), '');
    switch (kv[1]!.toLowerCase()) {
      case 'title' || 'author' || 'publisher' || 'date' || 'language' || 'isbn' || 'series' || 'description':
        m.put(kv[1]!.toLowerCase(), value);
      case 'tags' || 'keywords' || 'subject':
        m.addSubjects(value.replaceAll(RegExp(r'[\[\]]'), '').split(','));
    }
  }
  return m;
}

BookMeta _rtf(String text) {
  String? group(String word) => RegExp('\\{\\\\$word\\s+([^}]*)\\}').firstMatch(text)?[1];
  final year = RegExp(r'\\creatim\\yr(\d{4})').firstMatch(text)?[1];
  return BookMeta()
    ..put('title', group('title'))
    ..put('author', group('author'))
    ..put('date', year)
    ..addSubjects([group('subject') ?? '', ...(group('keywords') ?? '').split(RegExp('[,;]'))]);
}

BookMeta _zipComic(Archive a) {
  final info = _firstWhere(a, (n) => p.basename(n) == 'comicinfo.xml');
  return info == null ? BookMeta() : _comicInfo(utf8.decode(info, allowMalformed: true));
}

BookMeta _comicInfo(String xml) {
  final x = XmlDocument.parse(xml);
  final number = _text(x, 'Number');
  final series = _text(x, 'Series');
  final year = _text(x, 'Year'), month = _text(x, 'Month');
  return BookMeta(null, null, _text(x, 'Manga') == 'YesAndRightToLeft')
    ..put('title', _text(x, 'Title') ?? (series == null ? null : number == null ? series : '$series #$number'))
    ..put('series', series)
    ..put('volume', number)
    ..put('author', _text(x, 'Writer'))
    ..put('publisher', _text(x, 'Publisher'))
    ..put('date', year == null ? null : month == null ? year : '$year-${month.padLeft(2, '0')}')
    ..put('language', _text(x, 'LanguageISO'))
    ..put('description', _text(x, 'Summary'))
    ..addSubjects([...(_text(x, 'Genre') ?? '').split(','), ...(_text(x, 'Tags') ?? '').split(',')]);
}

// Must run on PDFium's own isolate, like every other PDFium call.
BookMeta _pdfMeta(String path) {
  final api = pdfium_api.getPdfium();
  return using((arena) {
    final document = api.FPDF_LoadDocument(path.toNativeUtf8(allocator: arena).cast(), ffi.nullptr);
    if (document == ffi.nullptr) return BookMeta();
    String? read(String tag) {
      final name = tag.toNativeUtf8(allocator: arena).cast<ffi.Char>();
      final length = api.FPDF_GetMetaText(document, name, ffi.nullptr, 0);
      if (length <= 2) return null;
      final buffer = arena<ffi.Uint8>(length);
      api.FPDF_GetMetaText(document, name, buffer.cast(), length);
      // UTF-16LE with a two-byte terminator.
      return String.fromCharCodes(buffer.cast<ffi.Uint16>().asTypedList(length ~/ 2 - 1));
    }

    final m = BookMeta()
      ..put('title', read('Title'))
      ..put('author', read('Author'))
      ..put('date', read('CreationDate')?.replaceFirstMapped(RegExp(r'^D:(\d{4})(\d{2})?(\d{2})?.*'), (x) => [x[1], x[2], x[3]].nonNulls.join('-')))
      ..addSubjects([read('Subject') ?? '', ...(read('Keywords') ?? '').split(RegExp('[,;]'))]);
    api.FPDF_CloseDocument(document);
    return m;
  });
}
