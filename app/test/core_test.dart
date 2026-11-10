import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'dart:ui' as ui;

import 'package:egebookreader/colorize.dart';
import 'package:egebookreader/curl.dart';
import 'package:egebookreader/settings.dart';
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
    final prepared = prepareColorInput(gray, w, h)!;
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

    final red = Uint8List(4 * 16);
    for (var i = 0; i < red.length; i += 4) {
      red[i] = 200;
      red[i + 3] = 255;
    }
    expect(prepareColorInput(red, 4, 4), isNull);
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
    });
  });
}
