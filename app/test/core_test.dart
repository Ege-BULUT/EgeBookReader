import 'dart:io';
import 'dart:math';

import 'package:egebookreader/curl.dart';
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
}
