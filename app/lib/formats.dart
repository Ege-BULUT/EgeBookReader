import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html;
import 'package:xml/xml.dart';

import 'sources.dart';

/// A reflowable book parsed into blocks, whatever file it came from.
class ParsedBook extends TextSource {
  ParsedBook(super.title, super.blocks, super.lang, this._cover);
  final Uint8List? _cover;

  @override
  Future<Uint8List?> coverBytes() async => _cover;
}

String decodeWith(String? name, Uint8List bytes) {
  final n = name?.toLowerCase().replaceAll('_', '-');
  if (n == 'windows-1251' || n == 'cp1251') return decodeCp1251(bytes);
  if (n == 'windows-1252' || n == 'cp1252' || n == 'iso-8859-1' || n == 'latin1') return latin1.decode(bytes);
  return utf8.decode(bytes, allowMalformed: true);
}

/// Many Russian books are still in this encoding.
String decodeCp1251(Uint8List b) => String.fromCharCodes(b.map((c) {
      if (c < 0x80) return c;
      if (c >= 0xC0) return 0x410 + c - 0xC0;
      if (c == 0xA8) return 0x401;
      if (c == 0xB8) return 0x451;
      if (c == 0x96 || c == 0x97) return 0x2013;
      if (c == 0xAB) return 0xAB;
      if (c == 0xBB) return 0xBB;
      return 0x20;
    }));

// ---------------------------------------------------------------------------------------------------------
// Kindle: MOBI, AZW, AZW3 (PalmDoc compression; Huffman-compressed books are refused with a message)

Uint8List _palmDecompress(Uint8List input) {
  final out = BytesBuilder(copy: false);
  final buffer = Uint8List(4096 * 3);
  var o = 0;
  var i = 0;
  void put(int v) {
    if (o < buffer.length) buffer[o++] = v;
  }

  while (i < input.length) {
    final c = input[i++];
    if (c >= 1 && c <= 8) {
      for (var n = 0; n < c && i < input.length; n++) {
        put(input[i++]);
      }
    } else if (c <= 0x7f) {
      put(c);
    } else if (c >= 0xc0) {
      put(0x20);
      put(c ^ 0x80);
    } else if (i < input.length) {
      final pair = (c << 8) | input[i++];
      final distance = (pair & 0x3fff) >> 3;
      final length = (pair & 7) + 3;
      for (var n = 0; n < length && distance > 0 && o - distance >= 0; n++) {
        put(buffer[o - distance]);
      }
    }
  }
  out.add(Uint8List.sublistView(buffer, 0, o));
  return out.takeBytes();
}

/// Bytes the format appends to each text record; [flags] says which kinds are there.
int _trailing(Uint8List r, int flags) {
  var size = r.length;
  for (var bits = flags >> 1; bits != 0; bits >>= 1) {
    if (bits & 1 == 0) continue;
    var value = 0, shift = 0;
    while (size > 0) {
      final byte = r[--size];
      value |= (byte & 0x7f) << shift;
      shift += 7;
      if (byte & 0x80 != 0 || shift >= 28) break;
    }
    // The read above already stepped over the size bytes, which count within value.
    size = size + (shift ~/ 7) - value;
    if (size <= 0) return 0;
  }
  if (flags & 1 != 0 && size > 0) size -= (r[size - 1] & 3) + 1;
  return size < 0 ? 0 : size;
}

ParsedBook parseMobi(Uint8List d, String fallbackTitle) {
  final v = ByteData.sublistView(d);
  if (d.length < 80 || String.fromCharCodes(d.sublist(60, 68)) != 'BOOKMOBI') {
    throw const FormatException('Bu dosya bir Kindle kitabı gibi görünmüyor.');
  }
  final count = v.getUint16(76);
  final offsets = [for (var i = 0; i < count; i++) v.getUint32(78 + 8 * i), d.length];
  Uint8List record(int i) => Uint8List.sublistView(d, offsets[i], offsets[i + 1]);

  final r0 = record(0);
  final h = ByteData.sublistView(r0);
  final compression = h.getUint16(0);
  final textRecords = h.getUint16(8);
  if (h.getUint16(12) != 0) throw const FormatException('Bu kitap DRM ile korunuyor, açılamıyor.');
  if (compression == 17480) throw const FormatException('Bu Kindle sıkıştırması (HUFF) henüz desteklenmiyor.');
  final headerLength = h.getUint32(20);
  final version = h.getUint32(36);
  final encoding = h.getUint32(28);
  final firstImage = h.getUint32(108);
  final flags = headerLength >= 0xE4 ? h.getUint32(0xF0) : 0;
  final nameOffset = h.getUint32(84), nameLength = h.getUint32(88);
  var title = utf8.decode(r0.sublist(nameOffset, nameOffset + nameLength), allowMalformed: true);

  String? language;
  Uint8List? cover;
  if (h.getUint32(128) & 0x40 != 0) {
    var at = 16 + headerLength;
    final total = h.getUint32(at + 8);
    at += 12;
    for (var i = 0; i < total; i++) {
      final type = h.getUint32(at), size = h.getUint32(at + 4);
      final body = r0.sublist(at + 8, at + size);
      if (type == 503) title = utf8.decode(body, allowMalformed: true);
      if (type == 524) language = utf8.decode(body, allowMalformed: true);
      if (type == 201 && body.length == 4 && firstImage + ByteData.sublistView(body).getUint32(0) < count) {
        cover = record(firstImage + ByteData.sublistView(body).getUint32(0));
      }
      at += size;
    }
  }

  final raw = BytesBuilder(copy: false);
  for (var i = 1; i <= textRecords && i < count; i++) {
    var r = record(i);
    r = Uint8List.sublistView(r, 0, _trailing(r, flags));
    raw.add(compression == 2 ? _palmDecompress(r) : r);
  }
  final bytes = raw.takeBytes();
  var text = encoding == 65001 ? utf8.decode(bytes, allowMalformed: true) : latin1.decode(bytes);

  text = text
      .replaceAll(RegExp(r'<mbp:pagebreak[^>]*>', caseSensitive: false), '<pagebreak></pagebreak>')
      .replaceAllMapped(RegExp(r'''recindex=["']?(\d+)["']?''', caseSensitive: false), (m) => 'src="rec:${m[1]}"');

  Uint8List? imageFor(String src) {
    int? index;
    if (src.startsWith('rec:')) {
      index = int.parse(src.substring(4)) - 1;
    } else {
      final m = RegExp(r'kindle:embed:([0-9A-V]+)').firstMatch(src);
      if (m != null) index = int.parse(m[1]!, radix: 32) - 1;
    }
    if (index == null || firstImage + index >= count || index < 0) return null;
    return record(firstImage + index);
  }

  // KF8 keeps each chapter as a skeleton followed by its content, so reading the flow in order gives the text in order.
  assert(version >= 1);
  final doc = html.parse(text);
  final blocks = <Block>[];
  if (doc.body != null) walkHtml(doc.body!, blocks, imageFor);
  return ParsedBook(title.isEmpty ? fallbackTitle : title, blocks, language, cover);
}

// ---------------------------------------------------------------------------------------------------------
// FictionBook

ParsedBook parseFb2(Uint8List bytes, String fallbackTitle) {
  final head = latin1.decode(bytes.sublist(0, bytes.length < 200 ? bytes.length : 200));
  final doc = XmlDocument.parse(decodeWith(RegExp(r'encoding="([^"]+)"').firstMatch(head)?[1], bytes));
  final binaries = <String, Uint8List>{};
  for (final b in doc.descendantElements.where((e) => e.localName == 'binary')) {
    try {
      binaries[b.getAttribute('id') ?? ''] = base64.decode(b.innerText.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      // one bad picture should not lose the book
    }
  }
  String? first(String name) {
    for (final e in doc.descendantElements) {
      if (e.localName == name && e.innerText.trim().isNotEmpty) return e.innerText.trim();
    }
    return null;
  }

  String href(XmlElement e) => (e.attributes.where((a) => a.localName == 'href').firstOrNull?.value ?? '').replaceFirst('#', '');
  Uint8List? cover;
  for (final c in doc.descendantElements.where((e) => e.localName == 'coverpage')) {
    final image = c.childElements.where((e) => e.localName == 'image').firstOrNull;
    if (image != null) cover = binaries[href(image)];
  }

  List<Inline> inlines(XmlNode node, {bool bold = false, bool italic = false}) {
    final out = <Inline>[];
    for (final c in node.children) {
      if (c is XmlText) {
        final t = c.value.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) out.add(Inline(t, bold: bold, italic: italic));
      } else if (c is XmlElement) {
        out.addAll(inlines(c, bold: bold || c.localName == 'strong', italic: italic || c.localName == 'emphasis'));
      }
    }
    return out;
  }

  final blocks = <Block>[];
  void walk(XmlElement e, int depth) {
    for (final c in e.childElements) {
      switch (c.localName) {
        case 'section':
          if (depth == 0 && blocks.isNotEmpty) blocks.add(PageBreak());
          walk(c, depth + 1);
        case 'title':
          for (final p in c.childElements) {
            blocks.add(TextBlock(inlines(p), heading: depth.clamp(1, 6).toInt()));
          }
        case 'subtitle':
          blocks.add(TextBlock(inlines(c), heading: 6));
        case 'p' || 'v' || 'text-author':
          blocks.add(TextBlock(inlines(c)));
        case 'poem' || 'stanza' || 'cite' || 'epigraph':
          walk(c, depth);
        case 'image':
          final image = binaries[href(c)];
          if (image != null) blocks.add(ImageBlock(image));
      }
    }
  }

  for (final body in doc.descendantElements.where((e) => e.localName == 'body')) {
    if (body.getAttribute('name') == 'notes') blocks.add(PageBreak());
    walk(body, 0);
  }
  return ParsedBook(first('book-title') ?? fallbackTitle, blocks, first('lang'), cover);
}

ParsedBook parseFbz(Uint8List bytes, String title) {
  final fb2 = ZipDecoder().decodeBytes(bytes).files.firstWhere((f) => f.name.toLowerCase().endsWith('.fb2'));
  return parseFb2(fb2.content, title);
}

// ---------------------------------------------------------------------------------------------------------
// Office documents, HTML, Markdown, RTF

ParsedBook parseDocx(Uint8List bytes, String title) {
  final zip = ZipDecoder().decodeBytes(bytes);
  ArchiveFile? entry(String n) => zip.files.where((f) => f.name == n).firstOrNull;
  final main = entry('word/document.xml');
  if (main == null) throw const FormatException('Bu dosya bir Word belgesi gibi görünmüyor.');
  final doc = XmlDocument.parse(utf8.decode(main.content));
  final targets = <String, String>{};
  final rels = entry('word/_rels/document.xml.rels');
  if (rels != null) {
    for (final r in XmlDocument.parse(utf8.decode(rels.content)).descendantElements.where((e) => e.localName == 'Relationship')) {
      targets[r.getAttribute('Id') ?? ''] = r.getAttribute('Target') ?? '';
    }
  }
  final blocks = <Block>[];
  for (final p in doc.descendantElements.where((e) => e.localName == 'p')) {
    final style = p.descendantElements.where((e) => e.localName == 'pStyle').firstOrNull?.attributes.where((a) => a.localName == 'val').firstOrNull?.value ?? '';
    final heading = int.tryParse(RegExp(r'[Hh]eading(\d)|Başlık(\d)').firstMatch(style)?.groups([1, 2]).nonNulls.firstOrNull ?? '') ?? 0;
    final inlines = <Inline>[];
    for (final r in p.descendantElements.where((e) => e.localName == 'r')) {
      final props = r.childElements.where((e) => e.localName == 'rPr').firstOrNull;
      final bold = props?.childElements.any((e) => e.localName == 'b') ?? false;
      final italic = props?.childElements.any((e) => e.localName == 'i') ?? false;
      final text = r.childElements.where((e) => e.localName == 't').map((e) => e.innerText).join();
      if (text.isNotEmpty) inlines.add(Inline(text, bold: bold, italic: italic));
    }
    if (inlines.isNotEmpty) blocks.add(TextBlock(inlines, heading: heading));
    for (final blip in p.descendantElements.where((e) => e.localName == 'blip')) {
      final id = blip.attributes.where((a) => a.localName == 'embed').firstOrNull?.value;
      final file = entry('word/${targets[id]}');
      if (file != null) blocks.add(ImageBlock(file.content));
    }
  }
  return ParsedBook(title, blocks, null, null);
}

ParsedBook parseOdt(Uint8List bytes, String title) {
  final zip = ZipDecoder().decodeBytes(bytes);
  final content = zip.files.where((f) => f.name == 'content.xml').firstOrNull;
  if (content == null) throw const FormatException('Bu dosya bir ODT belgesi gibi görünmüyor.');
  final blocks = <Block>[];
  for (final e in XmlDocument.parse(utf8.decode(content.content)).descendantElements) {
    if (e.localName == 'p' || e.localName == 'h') {
      final text = e.innerText.trim();
      final level = int.tryParse(e.attributes.where((a) => a.localName == 'outline-level').firstOrNull?.value ?? '') ?? 1;
      if (text.isNotEmpty) blocks.add(TextBlock([Inline(text)], heading: e.localName == 'h' ? level : 0));
    } else if (e.localName == 'image') {
      final href = e.attributes.where((a) => a.localName == 'href').firstOrNull?.value;
      final file = zip.files.where((f) => f.name == href).firstOrNull;
      if (file != null) blocks.add(ImageBlock(file.content));
    }
  }
  return ParsedBook(title, blocks, null, null);
}

ParsedBook parseHtml(Uint8List bytes, String title) {
  final head = latin1.decode(bytes.sublist(0, bytes.length < 1024 ? bytes.length : 1024));
  final doc = html.parse(decodeWith(RegExp(r'charset="?([\w-]+)', caseSensitive: false).firstMatch(head)?[1], bytes));
  final blocks = <Block>[];
  if (doc.body != null) walkHtml(doc.body!, blocks, (_) => null);
  final t = doc.querySelector('title')?.text.trim();
  return ParsedBook(t == null || t.isEmpty ? title : t, blocks, doc.documentElement?.attributes['lang'], null);
}

ParsedBook parseMarkdown(String text, String title) {
  final blocks = <Block>[];
  final paragraph = <String>[];
  List<Inline> inlines(String s) {
    final out = <Inline>[];
    final marks = RegExp(r'\*\*(.+?)\*\*|\*(.+?)\*|_(.+?)_');
    var at = 0;
    for (final m in marks.allMatches(s)) {
      if (m.start > at) out.add(Inline(s.substring(at, m.start)));
      out.add(Inline(m[1] ?? m[2] ?? m[3]!, bold: m[1] != null, italic: m[1] == null));
      at = m.end;
    }
    if (at < s.length) out.add(Inline(s.substring(at)));
    return out;
  }

  void flush() {
    if (paragraph.isNotEmpty) blocks.add(TextBlock(inlines(paragraph.join(' '))));
    paragraph.clear();
  }

  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
    if (line.isEmpty) {
      flush();
    } else if (heading != null) {
      flush();
      blocks.add(TextBlock(inlines(heading[2]!), heading: heading[1]!.length));
    } else {
      paragraph.add(line.replaceFirst(RegExp(r'^([-*+]|\d+\.|>)\s+'), ''));
    }
  }
  flush();
  return ParsedBook(title, blocks, null, null);
}

ParsedBook parseRtf(Uint8List bytes, String title) {
  final s = latin1.decode(bytes);
  final page = RegExp(r'\\ansicpg(\d+)').firstMatch(s)?[1];
  final out = StringBuffer();
  final pending = <int>[];
  void flush() {
    if (pending.isEmpty) return;
    final b = Uint8List.fromList(pending);
    out.write(page == '1251' ? decodeCp1251(b) : (page == '1254' ? _cp1254(b) : latin1.decode(b)));
    pending.clear();
  }

  var i = 0, depth = 0, skipDepth = -1;
  while (i < s.length) {
    final c = s[i];
    if (c == '{') {
      depth++;
      i++;
    } else if (c == '}') {
      depth--;
      if (depth <= skipDepth) skipDepth = -1;
      i++;
    } else if (c == r'\') {
      if (i + 1 < s.length && s[i + 1] == "'" && i + 3 < s.length) {
        if (skipDepth < 0) pending.add(int.parse(s.substring(i + 2, i + 4), radix: 16));
        i += 4;
        continue;
      }
      final m = RegExp(r'\\([a-zA-Z]+)(-?\d+)? ?|\\(.)').matchAsPrefix(s, i);
      if (m == null) {
        i++;
        continue;
      }
      i = m.end;
      final word = m[1];
      if (skipDepth >= 0) continue;
      if (word == null) {
        flush();
        if (m[3] == r'\' || m[3] == '{' || m[3] == '}') out.write(m[3]);
      } else if (word == 'par' || word == 'line') {
        flush();
        out.write('\n\n');
      } else if (word == 'u') {
        flush();
        final v = int.parse(m[2] ?? '0');
        out.writeCharCode(v < 0 ? v + 65536 : v);
        if (i < s.length && s[i] == '?') i++;
      } else if (const {'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'header', 'footer'}.contains(word)) {
        skipDepth = depth - 1;
      }
    } else {
      if (skipDepth < 0 && c != '\r' && c != '\n') {
        flush();
        out.write(c);
      }
      i++;
    }
  }
  flush();
  final blocks = out.toString().split(RegExp(r'\n\s*\n')).map((t) => t.trim()).where((t) => t.isNotEmpty).map<Block>((t) => TextBlock([Inline(t)])).toList();
  return ParsedBook(title, blocks, null, null);
}

String _cp1254(Uint8List b) => String.fromCharCodes(b.map((c) => switch (c) {
      0xD0 => 0x11E,
      0xDD => 0x130,
      0xDE => 0x15E,
      0xF0 => 0x11F,
      0xFD => 0x131,
      0xFE => 0x15F,
      _ => c,
    }));
