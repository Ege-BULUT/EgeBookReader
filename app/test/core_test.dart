import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:egebookreader/colorize.dart';
import 'package:egebookreader/curl.dart';
import 'package:egebookreader/formats.dart';
import 'package:egebookreader/incoming.dart';
import 'package:egebookreader/library_sheets.dart';
import 'package:egebookreader/main.dart' show Book, Highlight, sameFile, settings;
import 'package:egebookreader/panels.dart';
import 'package:egebookreader/stats.dart';
import 'package:egebookreader/meta.dart';
import 'package:egebookreader/settings.dart';
import 'package:egebookreader/shelf.dart';
import 'package:egebookreader/reader.dart' show findInSentences;
import 'package:egebookreader/tts.dart';
import 'package:egebookreader/viewer.dart';
import 'package:egebookreader/voicing.dart';
import 'package:egebookreader/l10n.dart';
import 'package:egebookreader/zones.dart';
import 'package:egebookreader/sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const w = 400.0, h = 800.0;
  const grab = Offset(w, 300);
  Fold fold(Offset f) => computeFold(grab: grab, f: f, hinge: 0, pageW: w, maxR: 50, maxTilt: 1);

  test('the grabbed paper point lands exactly under the finger', () {
    const f = Offset(120, 340);
    final x = fold(f);
    final s = f.dx * x.n.dx + f.dy * x.n.dy - x.t;
    final d = grab.dx * x.n.dx + grab.dy * x.n.dy - x.t;
    expect(s, closeTo(pi * x.r - d, 1e-6));
  });

  test('a finished turn lies flat and clear of the page', () {
    final x = fold(const Offset(-w, 300));
    expect(x.r, 0.5); // no roll left, so the landing does not pop
    expect(x.t, lessThan(0));
  });

  test('the fold normal always points at the free edge', () {
    for (final f in const [Offset(390, 10), Offset(10, 790), Offset(200, 300)]) {
      expect(fold(f).n.dx, greaterThan(0));
    }
  });

  test('the finger cannot tear the page off its hinge', () {
    final f = clampFinger(const Offset(900, -500), grab, 0, h);
    expect(f.distance, lessThanOrEqualTo(grab.distance + 1e-6));
    expect((f - const Offset(0, h)).distance, lessThanOrEqualTo((grab - const Offset(0, h)).distance + 1e-6));
  });

  test('the sample EPUB parses with its title, language tags and picture', () {
    final book = EpubSource.parse(File('assets/samples/sample.epub').readAsBytesSync(), 'x');
    expect(book.title, 'Dünyanın Dilleri');
    expect(book.lang, 'tr');
    expect(book.blocks.whereType<ImageBlock>().length, 2);
    final headings = book.blocks.whereType<TextBlock>().where((b) => b.heading == 1).toList();
    expect(headings.first.inlines.first.text, 'Türkçe');
    expect(book.blocks.whereType<TextBlock>().where((b) => b.lang == 'hi'), isNotEmpty);
  });

  testWidgets('text is laid out on pages without losing any line', (tester) async {
    await tester.runAsync(() async {
      final blocks = List.generate(60, (i) => TextBlock([Inline('Satır $i ' * 40)]));
      final book = TextSource('t', blocks, 'tr');
      const style = PageStyle(
        paper: Colors.white, ink: Colors.black, fontSize: 18, lineHeight: 1.5,
        fontFamily: 'serif', bold: false, italic: false, grain: 0, actualBook: false,
      );
      await book.prepare(const Size(360, 640), style);
      expect(book.pageCount, greaterThan(3));
      final placed = <TextPainter, double>{};
      for (final page in book.debugPages) {
        for (final p in page.whereType<PlacedText>()) {
          placed[p.painter] = (placed[p.painter] ?? 0) + (p.clipBottom - p.clipTop);
        }
      }
      expect(placed.length, 60);
      placed.forEach((painter, height) => expect(height, closeTo(painter.height, 2)));
    });
  });

  test('tap zones: the last zone drawn wins, circles stay round', () {
    const s = Size(400, 800);
    final zones = TapLayout.thirds()..add(TapZone.round(0.5, 0.5, 0.2, ZoneAction.bookmark));
    final layout = TapLayout(zones, zones);
    expect(layout.actionAt(const Offset(20, 100), s), ZoneAction.prev);
    expect(layout.actionAt(const Offset(390, 100), s), ZoneAction.next);
    expect(layout.actionAt(const Offset(200, 100), s), ZoneAction.menu);
    expect(layout.actionAt(const Offset(200, 400), s), ZoneAction.bookmark); // inside the circle, over the middle third
    expect(layout.actionAt(const Offset(200, 400 + 79), s), ZoneAction.bookmark); // radius is 0.2 of the 400 side
    expect(layout.actionAt(const Offset(200, 400 + 81), s), ZoneAction.menu);
  });

  testWidgets('text on a busy custom background reaches 4.5:1', (tester) async {
    await tester.runAsync(() async {
      // Half black, half white: no single text colour can pass without the background being softened.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
      canvas.drawRect(const Rect.fromLTWH(0, 0, 32, 64), Paint()..color = Colors.black);
      final image = await recorder.endRecording().toImage(64, 64);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('${Directory.systemTemp.createTempSync('ebr').path}/bg.png')
        ..writeAsBytesSync(png!.buffer.asUint8List());
      final c = CustomPaper(Colors.white)..image = file.path;
      await measureCustomPaper(c);
      expect(c.scrim, greaterThan(0));
      expect(c.scrim, lessThan(0.9));
    });
  });

  test('colourising changes nothing without colour, keeps paper white, leaves coloured pictures alone', () {
    const w = 40, h = 30;
    final gray = Uint8List(w * h * 4);
    for (var i = 0; i < gray.length; i += 4) {
      final v = (i ~/ 4) * 255 ~/ (w * h);
      gray[i] = gray[i + 1] = gray[i + 2] = v;
      gray[i + 3] = 255;
    }
    final prepared = prepareColorInput(gray, w, h, 256)!;
    expect(prepared.input.length, 3 * 256 * 256);

    // With no colour added, the merge must give back the picture it was given.
    final same = mergeColor(prepared, Float32List(2 * 256 * 256), w, h);
    for (var i = 0; i < gray.length; i++) {
      expect((same[i] - gray[i]).abs(), lessThanOrEqualTo(1));
    }

    // Strong colour everywhere: mid greys take it, paper-white stays white.
    final tinted = mergeColor(prepared, Float32List(2 * 256 * 256)..fillRange(0, 256 * 256, 60), w, h);
    final mid = (w * h ~/ 2) * 4, last = (w * h - 1) * 4;
    expect(tinted[mid] - tinted[mid + 1], greaterThan(40));
    expect((tinted[last] - tinted[last + 1]).abs(), lessThan(8));

    Uint8List picture(List<int> Function(int) colour) {
      final out = Uint8List(4 * 16);
      for (var i = 0; i < 16; i++) {
        out.setAll(i * 4, [...colour(i), 255]);
      }
      return out;
    }

    // Two far-apart hues: a coloured picture, left alone.
    expect(prepareColorInput(picture((i) => i.isEven ? [200, 40, 40] : [40, 60, 200]), 4, 4, 256), isNull);
    // Sepia at many strengths: one hue family, so it can still be colorized.
    expect(prepareColorInput(picture((i) => [120 + i * 8, 90 + i * 6, 50 + i * 3]), 4, 4, 256), isNotNull);
    // Nearly grey with a few coloured specks.
    expect(prepareColorInput(picture((i) => i == 0 ? [200, 40, 40] : [120, 120, 120]), 4, 4, 256), isNotNull);
  });

  testWidgets('a page is split into sentences that know where they are', (tester) async {
    await tester.runAsync(() async {
      final book = TextSource('t', [TextBlock([Inline('Birinci cümle burada. İkinci cümle nerede? Üçüncü! ' * 3)])], 'tr');
      const style = PageStyle(
        paper: Colors.white, ink: Colors.black, fontSize: 18, lineHeight: 1.5,
        fontFamily: 'serif', bold: false, italic: false, grain: 0, actualBook: false,
      );
      await book.prepare(const Size(360, 640), style);
      final sentences = await book.sentencesOn(0);
      expect(sentences.length, 9);
      expect(sentences.first.text, 'Birinci cümle burada.');
      expect(sentences[1].text, 'İkinci cümle nerede?');
      expect(sentences.first.lang, 'tr');
      expect(sentences.every((s) => s.boxes.isNotEmpty), isTrue);
      expect(sentences.first.boxes.first.top, greaterThanOrEqualTo(26));

      expect(sentences.first.words.length, 3);
      final second = sentences.first.words[1];
      expect(sentences.first.text.substring(second.start, second.end), 'cümle');
      expect(second.boxes.single.left, greaterThan(sentences.first.words[0].boxes.single.right));
      expect(second.boxes.single.height, greaterThan(0));
    });
  });

  group('speech positions', () {
    SpokenSentence sentence(String text, int page, double y) {
      final words = [
        for (final m in RegExp(r'\S+').allMatches(text))
          SpokenWord(m.start, m.end, [Rect.fromLTWH(m.start * 10.0, y, (m.end - m.start) * 10.0, 20)]),
      ];
      return SpokenSentence(text, 'tr', page, const [], words);
    }

    final map = SpeechMap([sentence('bir iki', 0, 0), sentence('üç dört beş', 0, 40), sentence('altı', 1, 0)]);

    test('progress grows through the sentences and ends at 1', () {
      expect(map.progress(0, 0), 0);
      expect(map.progress(1, 0), greaterThan(map.progress(0, 6)));
      expect(map.progress(3, 0), 1);
    });

    test('a fraction finds the word that is there, and back again', () {
      expect(map.locate(0), (0, 0));
      for (var s = 0; s < map.sentences.length; s++) {
        for (var w = 0; w < map.sentences[s].words.length; w++) {
          expect(map.locate(map.progress(s, map.sentences[s].words[w].start) + 1e-6), (s, w));
        }
      }
      expect(map.locate(1), (2, 0));
    });

    test('dragging finds the nearest word on that page and stays on its line', () {
      expect(map.nearest(0, const Offset(45, 8)), (0, 1));
      expect(map.nearest(0, const Offset(5, 48)), (1, 0));
      expect(map.nearest(0, const Offset(1000, 50)), (1, 2));
      expect(map.nearest(1, const Offset(5, 8)), (2, 0));
      expect(map.nearest(5, Offset.zero), isNull);
    });

    testWidgets('Chinese is marked character by character', (tester) async {
      await tester.runAsync(() async {
        final book = TextSource('t', [TextBlock([Inline('读书之乐。')])], 'zh');
        const style = PageStyle(
          paper: Colors.white, ink: Colors.black, fontSize: 18, lineHeight: 1.5,
          fontFamily: 'serif', bold: false, italic: false, grain: 0, actualBook: false,
        );
        await book.prepare(const Size(360, 640), style);
        expect((await book.sentencesOn(0)).single.words.length, 5);
      });
    });
  });

  test('RGB model output becomes the a and b the merge expects', () {
    final grey = rgbToAb(Float32List(3 * 4), 2); // 0 is mid grey in -1..1
    expect(grey.every((v) => v.abs() < 0.01), isTrue);
    final red = Float32List(3 * 4);
    red.fillRange(0, 4, 1);
    red.fillRange(4, 12, -1);
    final ab = rgbToAb(red, 2);
    expect(ab[0], closeTo(80, 2)); // CIELAB a of pure red
    expect(ab[4], closeTo(67, 2)); // CIELAB b of pure red
  });

  group('formats', () {
    String textOf(ParsedBook b) => b.blocks.whereType<TextBlock>().map((x) => x.inlines.map((i) => i.text).join()).join('\n');

    // Real Project Gutenberg files, kept out of the repository; the tests run when they are present.
    final fixtures = Platform.environment['EBR_FIXTURES'];
    test('MOBI and AZW3 give the whole book in reading order', () {
      for (final name in ['pp.mobi', 'pp.azw3']) {
        final b = parseMobi(File('$fixtures/$name').readAsBytesSync(), 'x');
        final text = textOf(b).toUpperCase();
        expect(b.title.toLowerCase(), contains('pride'), reason: name);
        expect(text.length, greaterThan(600000), reason: name);
        final one = text.indexOf('IT IS A TRUTH UNIVERSALLY'), last = text.lastIndexOf('DARCY, AS WELL AS ELIZABETH');
        expect(one, greaterThan(0), reason: name);
        expect(last, greaterThan(one), reason: name);
        expect(b.blocks.whereType<ImageBlock>(), isNotEmpty, reason: name);
        expect(b.lang, startsWith('en'), reason: name);
      }
    }, skip: fixtures == null);

    test('MOBI with DRM is refused in words, not with a crash', () {
      final d = File('$fixtures/alice.mobi').readAsBytesSync();
      final recordZero = ByteData.sublistView(d).getUint32(78);
      d[recordZero + 13] = 2;
      expect(() => parseMobi(d, 'x'), throwsA(isA<FormatException>()));
    }, skip: fixtures == null);

    test('FictionBook: structure, cp1251 and pictures', () {
      const xml = '''<?xml version="1.0" encoding="windows-1251"?><FictionBook xmlns:l="http://www.w3.org/1999/xlink"><description><title-info><book-title>TITLE</book-title><lang>ru</lang></title-info></description><body><section><title><p>HEAD</p></title><p>one <strong>two</strong></p><image l:href="#a"/></section></body><binary id="a" content-type="image/png">AAAA</binary></FictionBook>''';
      final bytes = Uint8List.fromList(latin1.encode(xml.replaceAll('HEAD', '\xC3\xEB\xE0\xE2\xE0')));
      final b = parseFb2(bytes, 'x');
      expect(b.title, 'TITLE');
      expect(b.lang, 'ru');
      final heading = b.blocks.first as TextBlock;
      expect(heading.heading, 1);
      expect(heading.inlines.first.text, 'Глава');
      expect((b.blocks[1] as TextBlock).inlines.last.bold, isTrue);
      expect(b.blocks.last, isA<ImageBlock>());
    });

    test('Markdown headings and emphasis', () {
      final b = parseMarkdown('# Baş\n\nbir **iki** *üç*\nsatır\n\n- madde', 't');
      expect((b.blocks[0] as TextBlock).heading, 1);
      final p = b.blocks[1] as TextBlock;
      expect(p.inlines.map((i) => i.text).join(), 'bir iki üç satır');
      expect(p.inlines[1].bold, isTrue);
      expect(p.inlines[3].italic, isTrue);
      expect((b.blocks[2] as TextBlock).inlines.single.text, 'madde');
    });

    testWidgets('comic pages keep their own sizes, so a webtoon strip is not squeezed', (tester) async {
      await tester.runAsync(() async {
        Future<Uint8List> png(int w, int h) async {
          final recorder = ui.PictureRecorder();
          Canvas(recorder);
          final image = await recorder.endRecording().toImage(w, h);
          return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        }

        final zip = Archive()
          ..addFile(ArchiveFile.bytes('1.png', await png(80, 400)))
          ..addFile(ArchiveFile.bytes('2.png', await png(60, 90)));
        final book = CbzSource.parse(Uint8List.fromList(ZipEncoder().encode(zip)), 'x');
        const style = PageStyle(
          paper: Colors.white, ink: Colors.black, fontSize: 18, lineHeight: 1.5,
          fontFamily: 'serif', bold: false, italic: false, grain: 0, actualBook: false,
        );
        await book.prepare(const Size(360, 640), style);
        expect(book.pageSizes, [const Size(80, 400), const Size(60, 90)]);
      });
    });

    test('online subjects become a category and a few tags', () {
      // Subjects as Open Library gives them for Pride and Prejudice and for Dune.
      const pride = ['Fiction', 'Love stories', 'England -- Fiction', 'Courtship -- Fiction', 'Sisters -- Fiction', 'Social classes -- Fiction', 'History'];
      expect(categoryFor(pride), 'Roman');
      expect(categoryFor(['Science fiction', 'Fiction', 'Dune (Imaginary place)']), 'Bilim kurgu');
      expect(categoryFor(['Cooking']), isNull);
      expect(tagsFrom([...pride, 'fiction']), ['Fiction', 'Love stories', 'History']);
    });

    test('a book file says who wrote it, when, and what about', () async {
      final dir = Directory.systemTemp.createTempSync('meta');
      final opf = '''<package xmlns="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata>
        <dc:title>Dune</dc:title><dc:creator>Frank Herbert</dc:creator><dc:publisher>Chilton</dc:publisher>
        <dc:date>1965-08-01</dc:date><dc:language>en</dc:language><dc:identifier>urn:isbn:978-0-441-17271-9</dc:identifier>
        <dc:subject>Science fiction</dc:subject><dc:description>&lt;p&gt;A desert planet.&lt;/p&gt;</dc:description>
        <meta name="calibre:series" content="Dune"/></metadata></package>''';
      final zip = Archive()
        ..addFile(ArchiveFile.string('META-INF/container.xml', '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>'))
        ..addFile(ArchiveFile.string('OEBPS/content.opf', opf));
      final epub = File('${dir.path}/dune.epub')..writeAsBytesSync(ZipEncoder().encode(zip));
      final m = await readMeta(epub.path);
      expect(m.fields, {
        'title': 'Dune', 'author': 'Frank Herbert', 'publisher': 'Chilton', 'date': '1965-08-01', 'language': 'en',
        'isbn': '9780441172719', 'description': 'A desert planet.', 'series': 'Dune',
      });
      expect(m.subjects, ['Science fiction']);
      final md = File('${dir.path}/n.md')..writeAsStringSync('---\ntitle: "Notlar"\nauthor: Ege\ntags: [a, b]\n---\n# x');
      final n = await readMeta(md.path);
      expect(n.fields, {'title': 'Notlar', 'author': 'Ege'});
      expect(n.subjects, ['a', 'b']);
      expect(yearOf('D:20010504'), 2001);
      dir.deleteSync(recursive: true);
    });

    test('sorting: a second tap turns the order round, and books missing the fact go last', () {
      Book book(String title, {String? author, int opened = 0}) => Book('/$title.epub', title, null)
        ..opened = opened
        ..info.addAll({'author': ?author});
      final books = [book('b', author: 'Zed', opened: 1), book('a', opened: 3), book('c', author: 'Ann', opened: 2)];
      List<String> titles(SortBy by, bool descending) => sortBooks(books, by, descending).map((b) => b.title).toList();
      expect(titles(SortBy.opened, true), ['a', 'c', 'b']);
      expect(titles(SortBy.opened, false), ['b', 'c', 'a']);
      expect(titles(SortBy.title, false), ['a', 'b', 'c']);
      expect(titles(SortBy.author, false), ['c', 'b', 'a']);
      expect(titles(SortBy.author, true), ['b', 'c', 'a']);
    });

    test('Turkish order and search: Ç after C, İ and I apart, accents found without typing them', () {
      final names = ['Zeytin', 'Çiçek', 'Cam', 'Ilık', 'İnce', 'şeker', 'Sabah', 'Éclair', 'Dağ', '9 Kapı'];
      names.sort((a, b) => sortKey(a).compareTo(sortKey(b)));
      expect(names, ['9 Kapı', 'Cam', 'Çiçek', 'Dağ', 'Éclair', 'Ilık', 'İnce', 'Sabah', 'şeker', 'Zeytin']);
      expect(foldForSearch('İSTANBUL Şef Ölçü'), 'istanbul sef olcu');
      expect(foldForSearch('ILIK'), 'ilik');
    });

    test('the same file is recognised, a different one with the same name is not', () async {
      final dir = Directory.systemTemp.createTempSync('same');
      final a = File('${dir.path}/a')..writeAsBytesSync(List.generate(3 << 20, (i) => i % 251));
      final b = File('${dir.path}/b')..writeAsBytesSync(a.readAsBytesSync());
      final c = File('${dir.path}/c')..writeAsBytesSync([...a.readAsBytesSync()]..[(3 << 20) - 5] ^= 1);
      expect(await sameFile(a, b), isTrue);
      expect(await sameFile(a, c), isFalse);
      dir.deleteSync(recursive: true);
    });

    test('RTF text, Turkish code page and unicode escapes', () {
      final b = parseRtf(Uint8List.fromList(latin1.encode(r"{\rtf1\ansi\ansicpg1254{\fonttbl{\f0 Arial;}}\f0 Ka\'f0\'fdt\par ikinci \u351? son}")), 't');
      expect((b.blocks[0] as TextBlock).inlines.single.text, 'Kağıt');
      expect((b.blocks[1] as TextBlock).inlines.single.text, 'ikinci ş son');
    });
  });

  group('page gestures', () {
    late ui.FragmentProgram program;
    var turned = <int>[];

    Future<void> pump(WidgetTester tester, {bool rtl = false}) async {
      await tester.runAsync(() async => program = await ui.FragmentProgram.fromAsset('shaders/page_curl.frag'));
      turned = [];
      await tester.pumpWidget(MaterialApp(
        home: PageCurlView(
          program: program,
          spread: false,
          rtl: rtl,
          paper: Colors.white,
          animate: false,
          canGo: (_) => true,
          pagesFor: (_) => null,
          still: const SizedBox.expand(),
          onTurned: turned.add,
          onTap: (_, _) {},
        ),
      ));
    }

    testWidgets('one finger across the page turns it once', (tester) async {
      await pump(tester);
      await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
      await tester.pump();
      expect(turned, [1]);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('right to left, a swipe toward the right turns forward', (tester) async {
      await pump(tester, rtl: true);
      await tester.dragFrom(const Offset(200, 300), const Offset(300, 0));
      await tester.pump();
      await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
      await tester.pump();
      expect(turned, [1, -1]);
    });

    testWidgets('one finger straight up and down does not turn', (tester) async {
      await pump(tester);
      await tester.dragFrom(const Offset(400, 100), const Offset(0, 300));
      await tester.pump();
      expect(turned, isEmpty);
    });

    Future<void> pinch(WidgetTester tester) async {
      final a = await tester.startGesture(const Offset(350, 300));
      final b = await tester.startGesture(const Offset(450, 300));
      await tester.pump();
      for (var i = 1; i <= 6; i++) {
        await a.moveBy(const Offset(-25, 0));
        await b.moveBy(const Offset(25, 0));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump();
    }

    testWidgets('two fingers zoom and never turn', (tester) async {
      await pump(tester);
      await pinch(tester);
      expect(turned, isEmpty);
      expect(find.textContaining('%'), findsOneWidget);
    });

    testWidgets('while zoomed, one finger moves the page instead of turning it', (tester) async {
      await pump(tester);
      await pinch(tester);
      await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
      await tester.pump();
      expect(turned, isEmpty);
      await tester.tap(find.textContaining('%'));
      await tester.pump();
      expect(find.textContaining('%'), findsNothing);
      await tester.dragFrom(const Offset(600, 300), const Offset(-300, 0));
      await tester.pump();
      expect(turned, [1]);
    });

    testWidgets('lifting one finger of a pinch does not turn the page', (tester) async {
      await pump(tester);
      final a = await tester.startGesture(const Offset(350, 300));
      final b = await tester.startGesture(const Offset(450, 300));
      await tester.pump();
      await a.moveBy(const Offset(-2, 0));
      await b.moveBy(const Offset(2, 0));
      await tester.pump();
      await b.up();
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await a.moveBy(const Offset(-40, 0));
        await tester.pump();
      }
      await a.up();
      await tester.pump();
      expect(turned, isEmpty);
    });
  });

  testWidgets('a picture in the gallery opens its book at its page, once the reader says so', (tester) async {
    var opened = 0;
    final item = ViewerItem(id: 'x', title: 'Kitap', pageNumber: 7, original: () async => null, openPage: () => opened++);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) => TextButton(onPressed: () => confirmOpenPage(context, item), child: const Text('go'))),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Kitap ·'), findsOneWidget);
    await tester.tap(find.byType(TextButton).at(1)); // Cancel
    await tester.pumpAndSettle();
    expect(opened, 0);
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).last); // Open
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  test('picture sizes come from the header; a JPEG with Exif goes to the decoder', () {
    final png = Uint8List(24)
      ..setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52])
      ..setAll(16, [0, 0, 0x03, 0x20, 0, 0, 0x2E, 0xE0]);
    expect(headerSize(png), const Size(800, 12000));
    final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 17, 8, 0x04, 0xB0, 0x02, 0x80, 3, 0, 0, 0, 0]);
    expect(headerSize(jpeg), const Size(640, 1200));
    final exif = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE1, 0, 8, ...'Exif'.codeUnits, 0, 0, 0xFF, 0xC0, 0, 17, 8, 1, 0, 1, 0, 3, 0]);
    expect(headerSize(exif), isNull);
    expect(headerSize(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('panels are found along white gutters, in reading order either way', () {
    const pw = 100, ph = 150;
    final rgba = Uint8List(pw * ph * 4)..fillRange(0, pw * ph * 4, 255);
    void box(int x0, int y0, int x1, int y1) {
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          rgba.setAll((y * pw + x) * 4, [60, 60, 60, 255]);
        }
      }
    }

    box(5, 5, 95, 60); // across the top
    box(5, 70, 45, 145); // bottom left
    box(55, 70, 95, 145); // bottom right
    Offset centre(Rect r) => Offset((r.center.dx * pw * 2).roundToDouble() / 2, (r.center.dy * ph * 2).roundToDouble() / 2);
    final ltr = findPanels(rgba, pw, ph);
    expect(ltr.map(centre).toList(), [const Offset(50, 32.5), const Offset(25, 107.5), const Offset(75, 107.5)]);
    final rtl = findPanels(rgba, pw, ph, rtl: true);
    expect(rtl.map(centre).toList(), [const Offset(50, 32.5), const Offset(75, 107.5), const Offset(25, 107.5)]);
    // One picture over the whole page: no panels.
    expect(findPanels(Uint8List(pw * ph * 4)..fillRange(0, pw * ph * 4, 90), pw, ph), isEmpty);
  });

  test('the streak counts days in a row, from yesterday while today has none', () {
    final s = ReadingStats();
    final today = DateTime(2026, 11, 12);
    for (final d in [12, 11, 10, 8]) {
      s.addTime(120, DateTime(2026, 11, d));
    }
    expect(s.streak(today), 3);
    expect(s.minutesOver(7, today), 8);
    s.seconds.remove(ReadingStats.dayOf(today));
    expect(s.streak(today), 2); // today not read yet: the run up to yesterday still counts
    s.addPage(today);
    expect(s.pages[ReadingStats.dayOf(today)], 1);
  });

  test('a highlight is found again by its text, also when a page break cuts the sentence', () {
    final h = Highlight('The quick brown fox jumps over the lazy dog.', 0.4, 0xFFF2C94C, note: 'nice');
    expect(h.matches('The quick brown fox jumps over the lazy dog.'), isTrue);
    expect(h.matches('The quick brown fox'), isTrue);
    expect(h.matches('Something else entirely.'), isFalse);
    final book = Book('/x.epub', 'x', null)..highlights.add(h);
    final back = Book.fromJson(jsonDecode(jsonEncode(book)) as Map<String, dynamic>).highlights.single;
    expect((back.text, back.at, back.color, back.note), (h.text, h.at, h.color, h.note));
  });

  test('a Calibre folder gives one book, its best format, with its opf and cover; loose books come in as they are', () {
    Incoming f(String path) => Incoming(path, () async => path);
    final found = booksAmong([
      f('Calibre/Ursula Le Guin/Earthsea (12)/Earthsea.pdf'),
      f('Calibre/Ursula Le Guin/Earthsea (12)/Earthsea.epub'),
      f('Calibre/Ursula Le Guin/Earthsea (12)/metadata.opf'),
      f('Calibre/Ursula Le Guin/Earthsea (12)/cover.jpg'),
      f('loose/a.cbz'),
      f('loose/b.txt'),
      f('loose/notes.docx.tmp'),
    ]);
    final calibre = found.singleWhere((b) => b.$1.path.startsWith('Calibre'));
    expect(calibre.$1.path, endsWith('Earthsea.epub'));
    expect(calibre.$2?.path, endsWith('metadata.opf'));
    expect(calibre.$3?.path, endsWith('cover.jpg'));
    expect(found.where((b) => b.$1.path.startsWith('loose')).map((b) => b.$1.path), ['loose/a.cbz', 'loose/b.txt']);
  });

  test('readOpf takes the series and volume Calibre writes', () {
    final m = readOpf('''<?xml version="1.0"?><package xmlns="http://www.idpf.org/2007/opf"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>A Wizard of Earthsea</dc:title><dc:creator>Ursula K. Le Guin</dc:creator>
<meta name="calibre:series" content="Earthsea"/><meta name="calibre:series_index" content="1.0"/></metadata></package>''');
    expect((m.fields['title'], m.fields['author'], m.fields['series'], m.fields['volume']), ('A Wizard of Earthsea', 'Ursula K. Le Guin', 'Earthsea', '1'));
  });

  test('automatic voicing: file names, voice labels, buffer', () {
    expect(speechKey('a'), 'af63dc4c8601ec8c'); // FNV-1a 64 of "a"
    expect(speechKey('Merhaba.'), speechKey('Merhaba.'));
    expect(speechKey('Merhaba.'), isNot(speechKey('Merhaba!')));
    final supertonic = voiceCatalog.firstWhere((m) => m.isSupertonic), kokoro = voiceCatalog.firstWhere((m) => !m.isSupertonic);
    expect([for (var i = 0; i < 4; i++) voiceLabel(supertonic, i)],
        ['${tr('Kadın')} 1', '${tr('Erkek')} 1', '${tr('Erkek')} 2', '${tr('Kadın')} 2']);
    expect((voiceLabel(kokoro, 57), voiceLabel(kokoro, 58)), ('${tr('Kadın')} 58', '${tr('Erkek')} 1'));
    settings.voicePace[supertonic.id] = [0.5, 1]; // makes faster than it speaks: the chosen pages are enough
    expect(bufferPages(supertonic, 100), settings.autoVoicePages);
    settings.voicePace[supertonic.id] = [2, 1]; // twice as slow: half of the chapter first
    expect(bufferPages(supertonic, 100), 50);
    settings.ttsSpeed = 2; // heard twice as fast: the same phone now falls behind
    settings.voicePace[supertonic.id] = [0.75, 1];
    expect(bufferPages(supertonic, 100), 34);
    settings.ttsSpeed = 1;
    settings.voicePace[supertonic.id] = [10, 1];
    expect(bufferPages(supertonic, 100), 60);
  });

  test('every interface text has an English line', () {
    final en = File('lib/l10n.dart').readAsStringSync();
    final missing = <String>{
      for (final f in Directory('lib').listSync().whereType<File>())
        for (final m in RegExp(r"\btr\('((?:[^'\\$]|\\.)*)'\)").allMatches(f.readAsStringSync()))
          if (!en.contains("'${m[1]}':") && !en.contains('"${m[1]!.replaceAll(r"\'", "'")}":')) m[1]!,
    };
    expect(missing, isEmpty);
  });

  test('search inside a book: folded, every hit, boxes of the matched words only', () {
    final words = [SpokenWord(0, 5, [const Rect.fromLTWH(0, 0, 40, 10)]), SpokenWord(6, 14, [const Rect.fromLTWH(45, 0, 60, 10)]),
        SpokenWord(15, 19, [const Rect.fromLTWH(110, 0, 50, 10)])];
    final s = SpokenSentence('Şefİn İSTANBUL şefi', 'tr', 3, [const Rect.fromLTWH(0, 0, 160, 10)], words);
    final hits = findInSentences('sef', 3, [s]);
    expect(hits.map((h) => h.match), ['Şef', 'şef']);
    expect(hits.first.page, 3);
    expect(hits.first.boxes, [const Rect.fromLTWH(0, 0, 40, 10)]);
    expect(findInSentences('istanbul', 0, [s]).single.boxes, [const Rect.fromLTWH(45, 0, 60, 10)]);
    expect(findInSentences('  ', 0, [s]), isEmpty);
    expect(foldWithMap('İı').$1, 'ii');
  });

  test('e-ink readers are recognised by their maker', () {
    expect(isEinkMaker('ONYX BOOX NoteAir3'), isTrue);
    expect(isEinkMaker('Hisense Hisense A9'), isTrue);
    expect(isEinkMaker('samsung samsung SM-S918B'), isFalse);
  });
}
