import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium_api;
import 'package:pdfrx/pdfrx.dart';
import 'package:xml/xml.dart';

/// Everything that changes how a page looks; a new value means every page is rendered again.
class PageStyle {
  const PageStyle({
    required this.paper,
    required this.ink,
    required this.fontSize,
    required this.lineHeight,
    required this.fontFamily,
    this.fontFallback = const [],
    required this.bold,
    required this.italic,
    this.margin = 26,
    this.justify = true,
    required this.grain,
    required this.actualBook,
    this.backgroundKey,
  });

  final Color paper, ink;
  final double fontSize, lineHeight;
  final String fontFamily;
  final List<String> fontFallback;
  final bool bold, italic, justify;
  final double margin;

  /// Identifies a composed custom background; null when the paper is a plain colour.
  final String? backgroundKey;

  /// Strength of the paper grain, 0 for none.
  final double grain;
  final bool actualBook;

  bool get darkPaper => paper.computeLuminance() < 0.2;

  @override
  bool operator ==(Object other) =>
      other is PageStyle &&
      other.paper == paper &&
      other.ink == ink &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.fontFamily == fontFamily &&
      other.bold == bold &&
      other.italic == italic &&
      other.grain == grain &&
      other.actualBook == actualBook &&
      other.margin == margin &&
      other.justify == justify &&
      other.backgroundKey == backgroundKey;

  @override
  int get hashCode => Object.hash(paper, ink, fontSize, lineHeight, fontFamily, bold, italic, grain, actualBook, margin, justify, backgroundKey);
}

/// A book as a list of pages that can be drawn at any size.
abstract class PageSource {
  String get title;
  int get pageCount;

  /// Lays the book out for one page of [page] logical pixels. [position] is 0..1 through the book only so
  /// long layouts can report progress later; pages are numbered from 0 afterwards.
  Future<void> prepare(Size page, PageStyle style, {void Function(double)? onProgress});

  /// Draws page [index] (ink and pictures only; the paper is already painted).
  Future<void> paint(Canvas canvas, int index, Size page, PageStyle style);

  /// A picture to use as the cover, or null.
  Future<Uint8List?> coverBytes() async => null;

  void dispose() {}
}

Future<PageSource> openBook(String path, {bool reflowPdf = false}) async {
  switch (p.extension(path).toLowerCase()) {
    case '.pdf':
      final doc = await PdfDocument.openFile(path);
      return reflowPdf ? await PdfReflowSource.create(doc, _titleOf(path)) : PdfSource(doc, _titleOf(path), path);
    case '.epub':
      return EpubSource.parse(await File(path).readAsBytes(), _titleOf(path));
    case '.cbz':
      return CbzSource.parse(await File(path).readAsBytes(), _titleOf(path));
    case '.txt':
      return TextSource(_titleOf(path), _plainBlocks(await _readText(path)), null);
    default:
      throw UnsupportedError('This format is not supported yet: ${p.extension(path)}');
  }
}

const supportedExtensions = {'.pdf', '.epub', '.cbz', '.txt'};

String _titleOf(String path) => p.basenameWithoutExtension(path).replaceAll('_', ' ');

Future<String> _readText(String path) async {
  final bytes = await File(path).readAsBytes();
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

// ---------------------------------------------------------------------------------------------------------
// PDF

class PdfSource extends PageSource {
  PdfSource(this.doc, this.title, this.path);
  final PdfDocument doc;
  final String path;
  final _imageBoxes = <int, Future<List<Rect>>>{};
  static ui.FragmentProgram? _darkProgram;
  @override
  final String title;
  @override
  int get pageCount => doc.pages.length;

  @override
  Future<void> prepare(Size page, PageStyle style, {void Function(double)? onProgress}) async {}

  @override
  Future<void> paint(Canvas canvas, int index, Size page, PageStyle style) async {
    final pdf = doc.pages[index];
    final scale = ui.clampDouble(
      (page.width / pdf.width) < (page.height / pdf.height) ? page.width / pdf.width : page.height / pdf.height,
      0.01,
      100,
    );
    final w = pdf.width * scale, h = pdf.height * scale;
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final rendered = await pdf.render(
      fullWidth: w * dpr,
      fullHeight: h * dpr,
      backgroundColor: 0xFFFFFFFF,
    );
    if (rendered == null) return;
    final image = await _toImage(rendered);
    rendered.dispose();
    final dst = Rect.fromLTWH((page.width - w) / 2, (page.height - h) / 2, w, h);
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    if (style.darkPaper) {
      await _paintDark(canvas, index, image, src, dst, scale, style);
    } else {
      canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium..blendMode = BlendMode.multiply);
    }
    image.dispose();
  }

  /// The page's type and drawings take the theme's colours; photographs are put back as they were, slightly dimmed.
  Future<void> _paintDark(Canvas canvas, int index, ui.Image image, Rect src, Rect dst, double scale, PageStyle s) async {
    final program = _darkProgram ??= await ui.FragmentProgram.fromAsset('shaders/page_dark.frag');
    final shader = program.fragmentShader();
    final values = [dst.left, dst.top, dst.width, dst.height, s.paper.r, s.paper.g, s.paper.b, s.ink.r, s.ink.g, s.ink.b];
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, image);
    canvas.drawRect(dst, Paint()..shader = shader);
    const dim = ColorFilter.matrix(<double>[.88, 0, 0, 0, 0, 0, .88, 0, 0, 0, 0, 0, .88, 0, 0, 0, 0, 0, 1, 0]);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = dim;
    final toPixels = image.width / dst.width;
    for (final box in await (_imageBoxes[index] ??= _findImages(index))) {
      final r = Rect.fromLTRB(box.left * scale, box.top * scale, box.right * scale, box.bottom * scale);
      final onPage = r.shift(dst.topLeft).intersect(dst);
      if (onPage.isEmpty) continue;
      canvas.drawImageRect(
        image,
        Rect.fromLTRB(
          (onPage.left - dst.left) * toPixels,
          (onPage.top - dst.top) * toPixels,
          (onPage.right - dst.left) * toPixels,
          (onPage.bottom - dst.top) * toPixels,
        ),
        onPage,
        paint,
      );
    }
  }

  Future<List<Rect>> _findImages(int index) async {
    final boxes = await PdfrxEntryFunctions.instance.compute(_imageBoxesOnWorker, (path, index, doc.pages[index].height));
    return [for (final b in boxes) Rect.fromLTRB(b[0], b[1], b[2], b[3])];
  }

  Future<ui.Image> _toImage(PdfImage img) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(img.pixels);
    final desc = ui.ImageDescriptor.raw(
      buffer,
      width: img.width,
      height: img.height,
      pixelFormat: ui.PixelFormat.bgra8888,
    );
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    return frame.image;
  }

  @override
  void dispose() => doc.dispose();
}

// Must run on PDFium's own isolate: PDFium calls back into Dart for fonts, and those callbacks belong to it.
// ponytail: top-level images on unrotated pages only; images nested in form objects still get dark-mapped.
List<List<double>> _imageBoxesOnWorker((String, int, double) job) {
  final (path, index, height) = job;
  final api = pdfium_api.getPdfium();
  return using((arena) {
    final document = api.FPDF_LoadDocument(path.toNativeUtf8(allocator: arena).cast(), ffi.nullptr);
    if (document == ffi.nullptr) return const <List<double>>[];
    final page = api.FPDF_LoadPage(document, index);
    final out = <List<double>>[];
    if (page != ffi.nullptr && api.FPDFPage_GetRotation(page) == 0) {
      final l = arena<ffi.Float>(), b = arena<ffi.Float>(), r = arena<ffi.Float>(), t = arena<ffi.Float>();
      for (var i = api.FPDFPage_CountObjects(page) - 1; i >= 0; i--) {
        final object = api.FPDFPage_GetObject(page, i);
        if (api.FPDFPageObj_GetType(object) != pdfium_api.FPDF_PAGEOBJ_IMAGE) continue;
        if (api.FPDFPageObj_GetBounds(object, l, b, r, t) != 0) {
          out.add([l.value, height - t.value, r.value, height - b.value]);
        }
      }
    }
    if (page != ffi.nullptr) api.FPDF_ClosePage(page);
    api.FPDF_CloseDocument(document);
    return out;
  });
}

/// PDF text poured into the text layout. Pictures are left out for now.
class PdfReflowSource extends TextSource {
  PdfReflowSource._(this.doc, String title, List<Block> blocks) : super(title, blocks, null);
  final PdfDocument doc;

  static Future<PdfReflowSource> create(PdfDocument doc, String title) async {
    final buffer = StringBuffer();
    for (final page in doc.pages) {
      final text = await page.loadStructuredText();
      buffer.writeln(text.fullText);
      buffer.writeln();
    }
    return PdfReflowSource._(doc, title, _plainBlocks(_joinPdfLines(buffer.toString())));
  }

  @override
  void dispose() => doc.dispose();
}

/// PDF text breaks at every printed line; join lines back into paragraphs.
String _joinPdfLines(String text) {
  final paragraphs = <String>[];
  var current = '';
  void end() {
    if (current.isNotEmpty) paragraphs.add(current);
    current = '';
  }

  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) {
      end();
    } else if (current.endsWith('-')) {
      current = current.substring(0, current.length - 1) + line;
    } else {
      current = current.isEmpty ? line : '$current $line';
      if (RegExp(r'[.!?:…。！？]$').hasMatch(line) && line.length < 50) end();
    }
  }
  end();
  return paragraphs.join('\n\n');
}

List<Block> _plainBlocks(String text) => text
    .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
    .map((t) => t.trim())
    .where((t) => t.isNotEmpty)
    .map<Block>((t) => TextBlock([Inline(t.replaceAll(RegExp(r'\s*\n\s*'), ' '))]))
    .toList();

// ---------------------------------------------------------------------------------------------------------
// Text layout, shared by EPUB, TXT and reflowed PDF

class Inline {
  const Inline(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold, italic;
}

sealed class Block {}

class TextBlock extends Block {
  TextBlock(this.inlines, {this.heading = 0, this.indent = true, this.lang});
  final List<Inline> inlines;

  /// 1 to 6 for headings, 0 for body text.
  final int heading;
  final bool indent;
  final String? lang;
}

class ImageBlock extends Block {
  ImageBlock(this.bytes);
  final Uint8List bytes;
}

class PageBreak extends Block {}

sealed class Placed {}

class PlacedText extends Placed {
  PlacedText(this.painter, this.top, this.clipTop, this.clipBottom);
  final TextPainter painter;
  final double top, clipTop, clipBottom;
}

class PlacedImage extends Placed {
  PlacedImage(this.bytes, this.rect);
  final Uint8List bytes;
  final Rect rect;
}

class TextSource extends PageSource {
  TextSource(this.title, this.blocks, this.lang);
  @override
  final String title;
  final List<Block> blocks;
  final String? lang;
  List<List<Placed>> _pages = const [];
  @visibleForTesting
  List<List<Placed>> get debugPages => _pages;

  @override
  int get pageCount => _pages.length;

  static EdgeInsets _marginOf(PageStyle s) => EdgeInsets.fromLTRB(s.margin, s.margin + 8, s.margin, s.margin + 12);

  @override
  Future<void> prepare(Size page, PageStyle style, {void Function(double)? onProgress}) async {
    for (final old in _pages) {
      for (final placed in old) {
        if (placed is PlacedText) placed.painter.dispose();
      }
    }
    final margin = _marginOf(style);
    final width = page.width - margin.horizontal;
    final height = page.height - margin.vertical;
    final pages = <List<Placed>>[[]];
    var y = 0.0;

    void nextPage() {
      if (pages.last.isEmpty) return;
      pages.add([]);
      y = 0;
    }

    for (var i = 0; i < blocks.length; i++) {
      if (i % 40 == 0) {
        onProgress?.call(i / blocks.length);
        await Future<void>.delayed(Duration.zero); // lets the loading animation draw
      }
      switch (blocks[i]) {
        case PageBreak():
          nextPage();
        case ImageBlock(:final bytes):
          final size = await _imageSize(bytes);
          if (size == null) break;
          final scale = [width / size.width, height / size.height, 1.0 * 2].reduce((a, b) => a < b ? a : b);
          final w = size.width * scale, h = size.height * scale;
          if (y + h > height) nextPage();
          pages.last.add(PlacedImage(bytes, Rect.fromLTWH((width - w) / 2, y, w, h)));
          y += h + style.fontSize * 0.8;
        case final TextBlock b:
          final painter = _painterFor(b, style, width);
          final gapBefore = b.heading > 0 && y > 0 ? style.fontSize * 1.2 : 0.0;
          final gapAfter = b.heading > 0 ? style.fontSize * 0.7 : style.fontSize * 0.35;
          final lines = painter.computeLineMetrics();
          if (y + gapBefore + (lines.isEmpty ? 0 : lines.first.height) > height) nextPage();
          if (y > 0) y += gapBefore;

          var from = 0; // first line still to place
          var top = 0.0; // height of the lines already placed
          while (from < lines.length) {
            var fit = from;
            var used = 0.0;
            while (fit < lines.length && y + used + lines[fit].height <= height) {
              used += lines[fit].height;
              fit++;
            }
            if (fit == from) {
              if (pages.last.isEmpty) {
                // A line taller than the page: show it anyway instead of looping forever.
                used = lines[fit].height;
                fit++;
              } else {
                nextPage();
                continue;
              }
            }
            pages.last.add(PlacedText(painter, y, top, top + used));
            y += used;
            top += used;
            from = fit;
            if (from < lines.length) nextPage();
          }
          y += gapAfter;
      }
    }
    if (pages.length > 1 && pages.last.isEmpty) pages.removeLast();
    _pages = pages;
    onProgress?.call(1);
  }

  TextPainter _painterFor(TextBlock b, PageStyle s, double width) {
    final size = b.heading == 0 ? s.fontSize : s.fontSize * (1.7 - b.heading * 0.12).clamp(1.05, 1.6);
    final locale = _locale(b.lang ?? lang);
    TextStyle styleFor(Inline i) => TextStyle(
          color: s.ink,
          fontFamily: s.fontFamily,
          fontFamilyFallback: s.fontFallback,
          fontSize: size,
          height: b.heading > 0 ? 1.25 : s.lineHeight,
          fontWeight: (s.bold || i.bold || b.heading > 0) ? FontWeight.w600 : FontWeight.w400,
          fontStyle: (s.italic || i.italic) ? FontStyle.italic : FontStyle.normal,
          locale: locale,
        );
    final inlines = b.inlines;
    final painter = TextPainter(
      text: TextSpan(children: [for (final i in inlines) TextSpan(text: i.text, style: styleFor(i))]),
      textDirection: _isRtl(locale) ? TextDirection.rtl : TextDirection.ltr,
      textAlign: b.heading == 0 && s.justify ? TextAlign.justify : TextAlign.start,
      locale: locale,
    )..layout(maxWidth: width);
    return painter;
  }

  Locale? _locale(String? tag) {
    if (tag == null || tag.isEmpty) return null;
    final parts = tag.split(RegExp('[-_]'));
    return Locale(parts.first.toLowerCase(), parts.length > 1 && parts[1].length == 2 ? parts[1].toUpperCase() : null);
  }

  bool _isRtl(Locale? l) => const {'ar', 'he', 'fa', 'ur'}.contains(l?.languageCode);

  Future<Size?> _imageSize(Uint8List bytes) async {
    try {
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buffer);
      final size = Size(desc.width.toDouble(), desc.height.toDouble());
      desc.dispose();
      buffer.dispose();
      return size;
    } catch (_) {
      return null; // a broken picture must not stop the book from opening
    }
  }

  @override
  Future<void> paint(Canvas canvas, int index, Size page, PageStyle style) async {
    canvas.save();
    canvas.translate(_marginOf(style).left, _marginOf(style).top);
    for (final placed in _pages[index]) {
      switch (placed) {
        case PlacedText(:final painter, :final top, :final clipTop, :final clipBottom):
          canvas.save();
          canvas.clipRect(Rect.fromLTRB(-4, top - 1, painter.width + 4, top + clipBottom - clipTop + 1));
          painter.paint(canvas, Offset(0, top - clipTop));
          canvas.restore();
        case PlacedImage(:final bytes, :final rect):
          final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
          final codec = await ui.instantiateImageCodec(bytes, targetWidth: (rect.width * dpr).ceil());
          final frame = await codec.getNextFrame();
          codec.dispose();
          final image = frame.image;
          canvas.drawImageRect(
            image,
            Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
            rect,
            Paint()
              ..filterQuality = FilterQuality.medium
              ..blendMode = style.darkPaper ? BlendMode.srcOver : BlendMode.multiply,
          );
          image.dispose();
      }
    }
    canvas.restore();
  }
}

// ---------------------------------------------------------------------------------------------------------
// EPUB

class EpubSource extends TextSource {
  EpubSource._(super.title, super.blocks, super.lang, this._cover);
  final Uint8List? _cover;

  @override
  Future<Uint8List?> coverBytes() async => _cover;

  static EpubSource parse(Uint8List bytes, String fallbackTitle) {
    final zip = ZipDecoder().decodeBytes(bytes);
    ArchiveFile? entry(String name) {
      final wanted = Uri.decodeFull(name);
      for (final f in zip.files) {
        if (f.name == wanted) return f;
      }
      return null;
    }

    final container = entry('META-INF/container.xml');
    if (container == null) throw const FormatException('Not an EPUB: META-INF/container.xml is missing');
    if (entry('META-INF/encryption.xml') != null && _hasDrm(entry('META-INF/encryption.xml')!)) {
      throw const FormatException('This book is protected with DRM and cannot be opened.');
    }
    final opfPath = XmlDocument.parse(utf8.decode(container.content))
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path')!;
    final base = p.posix.dirname(opfPath);
    String resolve(String from, String href) =>
        p.posix.normalize(p.posix.join(from == '.' ? '' : from, href.split('#').first));

    final opf = XmlDocument.parse(utf8.decode(entry(opfPath)!.content));
    String? meta(String name) {
      for (final e in opf.descendantElements) {
        if (e.localName == name && e.innerText.trim().isNotEmpty) return e.innerText.trim();
      }
      return null;
    }

    final manifest = <String, XmlElement>{};
    for (final item in opf.descendantElements.where((e) => e.localName == 'item')) {
      manifest[item.getAttribute('id') ?? ''] = item;
    }

    Uint8List? cover;
    String? coverId;
    for (final m in opf.descendantElements.where((e) => e.localName == 'meta')) {
      if (m.getAttribute('name') == 'cover') coverId = m.getAttribute('content');
    }
    for (final item in manifest.values) {
      final isCover = (item.getAttribute('properties') ?? '').contains('cover-image') ||
          item.getAttribute('id') == coverId;
      if (isCover) {
        final f = entry(resolve(base, item.getAttribute('href')!));
        if (f != null) cover = f.content;
        break;
      }
    }

    final blocks = <Block>[];
    final lang = meta('language');
    for (final ref in opf.descendantElements.where((e) => e.localName == 'itemref')) {
      final item = manifest[ref.getAttribute('idref')];
      if (item == null) continue;
      final path = resolve(base, item.getAttribute('href')!);
      final f = entry(path);
      if (f == null) continue;
      final doc = html.parse(utf8.decode(f.content, allowMalformed: true));
      final body = doc.body;
      if (body == null) continue;
      final before = blocks.length;
      _walk(body, blocks, (href) {
        final img = entry(resolve(p.posix.dirname(path), href));
        return img?.content;
      });
      if (blocks.length > before) blocks.add(PageBreak());
    }
    if (blocks.isNotEmpty && blocks.last is PageBreak) blocks.removeLast();
    return EpubSource._(meta('title') ?? fallbackTitle, blocks, lang, cover);
  }

  /// Font obfuscation also lives in encryption.xml and is harmless; anything else is real DRM.
  static bool _hasDrm(ArchiveFile f) {
    final doc = XmlDocument.parse(utf8.decode(f.content));
    return doc.descendantElements.where((e) => e.localName == 'EncryptionMethod').any((e) {
      final alg = e.getAttribute('Algorithm') ?? '';
      return !alg.contains('obfuscation') && !alg.contains('font');
    });
  }

  static const _blockTags = {
    'p', 'div', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'li', 'ul', 'ol', 'blockquote', 'section', 'article', 'pre',
    'table', 'tr', 'td', 'th', 'figure', 'figcaption', 'header', 'footer', 'aside', 'main', 'nav', 'dl', 'dt', 'dd',
    'center', 'tbody', 'thead',
  };

  static void _walk(dom.Element root, List<Block> out, Uint8List? Function(String) image) {
    final inlines = <Inline>[];

    void flush(dom.Element parent) {
      final text = inlines.map((i) => i.text).join();
      if (text.trim().isNotEmpty) {
        final tag = parent.localName ?? '';
        final heading = RegExp(r'^h([1-6])$').firstMatch(tag);
        out.add(TextBlock(
          _trimmed(inlines),
          heading: heading == null ? 0 : int.parse(heading.group(1)!),
          lang: parent.attributes['lang'] ?? parent.attributes['xml:lang'],
        ));
      }
      inlines.clear();
    }

    void inline(dom.Node node, bool bold, bool italic) {
      if (node is dom.Text) {
        final t = node.text.replaceAll(RegExp(r'\s+'), ' ');
        if (t.isNotEmpty) inlines.add(Inline(t, bold: bold, italic: italic));
      } else if (node is dom.Element) {
        final tag = node.localName ?? '';
        if (tag == 'br') {
          inlines.add(Inline('\n', bold: bold, italic: italic));
        } else if (tag == 'img' || tag == 'image') {
          flush(root);
          final src = node.attributes['src'] ?? node.attributes['xlink:href'] ?? node.attributes['href'];
          final bytes = src == null ? null : image(src);
          if (bytes != null) out.add(ImageBlock(bytes));
        } else if (_blockTags.contains(tag)) {
          flush(root);
          _walk(node, out, image);
        } else if (tag != 'script' && tag != 'style') {
          final b = bold || tag == 'b' || tag == 'strong';
          final i = italic || tag == 'i' || tag == 'em' || tag == 'cite';
          for (final c in node.nodes) {
            inline(c, b, i);
          }
        }
      }
    }

    for (final node in root.nodes) {
      inline(node, false, false);
    }
    flush(root);
  }

  static List<Inline> _trimmed(List<Inline> inlines) {
    final list = [...inlines];
    if (list.isNotEmpty) {
      final f = list.first;
      list[0] = Inline(f.text.trimLeft(), bold: f.bold, italic: f.italic);
      final l = list.last;
      list[list.length - 1] = Inline(l.text.trimRight(), bold: l.bold, italic: l.italic);
    }
    return list;
  }
}

// ---------------------------------------------------------------------------------------------------------
// Comics

class CbzSource extends PageSource {
  CbzSource._(this.title, this._images);
  @override
  final String title;
  final List<ArchiveFile> _images;

  @override
  int get pageCount => _images.length;

  static CbzSource parse(Uint8List bytes, String title) {
    final zip = ZipDecoder().decodeBytes(bytes);
    final images = zip.files
        .where((f) => f.isFile && RegExp(r'\.(jpe?g|png|webp|gif|bmp)$', caseSensitive: false).hasMatch(f.name))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return CbzSource._(title, images);
  }

  @override
  Future<void> prepare(Size page, PageStyle style, {void Function(double)? onProgress}) async {}

  @override
  Future<Uint8List?> coverBytes() async => _images.isEmpty ? null : _images.first.content;

  @override
  Future<void> paint(Canvas canvas, int index, Size page, PageStyle style) async {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final codec = await ui.instantiateImageCodec(_images[index].content, targetHeight: (page.height * dpr).ceil());
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    final fit = applyBoxFit(BoxFit.contain, Size(image.width.toDouble(), image.height.toDouble()), page);
    final dst = Alignment.center.inscribe(fit.destination, Offset.zero & page);
    canvas.drawImageRect(image, Offset.zero & fit.source, dst, Paint()..filterQuality = FilterQuality.medium);
    image.dispose();
  }
}
