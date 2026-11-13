import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:egebookreader/balloons.dart';
import 'package:egebookreader/panels.dart';
import 'package:egebookreader/upscale.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('spreads: text pairs from the first page, comics keep the cover and wide pages alone', () {
    const tall = Size(700, 1000), wide = Size(1400, 1000);
    expect(spreadStarts(5, null), [0, 2, 4]);
    expect(spreadStarts(6, List.filled(6, tall)), [0, 1, 3, 5]);
    expect(spreadStarts(7, [tall, tall, tall, wide, tall, tall, tall]), [0, 1, 3, 4, 6]);
    // A page just before a wide one has nobody to pair with.
    expect(spreadStarts(5, [tall, tall, wide, tall, tall]), [0, 1, 2, 3]);
    expect(spreadStarts(0, const []), isEmpty);
    final starts = spreadStarts(7, [tall, tall, tall, wide, tall, tall, tall]);
    expect([for (var p = 0; p < 7; p++) starts[spreadIndex(starts, p)]], [0, 1, 1, 3, 4, 4, 6]);
  });

  test('upscaling in overlapping tiles leaves no seams', () {
    // A stand-in for the model: every pixel becomes 4 by 4 of itself. Tiled and placed at 2x, the result must be
    // exactly the picture doubled, with nothing out of place where tiles meet.
    const w = 37, h = 29, core = 10, pad = 3, k = 4, scale = 2.0;
    final rng = Random(1);
    final rgba = Uint8List.fromList([for (var i = 0; i < w * h * 4; i++) i % 4 == 3 ? 255 : rng.nextInt(256)]);
    final dw = (w * scale).round(), dh = (h * scale).round();
    final dst = Uint8List(dw * dh * 4);
    for (var y = 0; y < h; y += core) {
      for (var x = 0; x < w; x += core) {
        final x0 = max(0, x - pad), y0 = max(0, y - pad);
        final tw = min(w, x + core + pad) - x0, th = min(h, y + core + pad) - y0;
        final input = tileInput(rgba, w, x0, y0, tw, th);
        final out = Float32List(3 * tw * k * th * k);
        for (var c = 0; c < 3; c++) {
          for (var v = 0; v < th * k; v++) {
            for (var u = 0; u < tw * k; u++) {
              out[c * tw * k * th * k + v * tw * k + u] = input[c * tw * th + (v ~/ k) * tw + u ~/ k];
            }
          }
        }
        placeTile(out, k, x0, y0, tw, th, x, y, min(w, x + core), min(h, y + core), dst, dw, scale);
      }
    }
    for (var y = 0; y < dh; y++) {
      for (var x = 0; x < dw; x++) {
        final from = ((y ~/ 2) * w + x ~/ 2) * 4, to = (y * dw + x) * 4;
        expect([dst[to], dst[to + 1], dst[to + 2], dst[to + 3]], [rgba[from], rgba[from + 1], rgba[from + 2], 255], reason: '$x,$y');
      }
    }
  });

  test('balloons: text boxes from a probability map, grouped into balloons in reading order', () {
    const w = 40, h = 30;
    final prob = Float32List(w * h);
    void fill(int x0, int y0, int x1, int y1, double v) {
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          prob[y * w + x] = v;
        }
      }
    }

    fill(2, 2, 20, 6, 0.9); // a line
    fill(2, 8, 16, 12, 0.9); // the line under it, same balloon
    fill(30, 20, 38, 24, 0.4); // too faint to count
    fill(30, 2, 31, 3, 0.9); // a speck
    final boxes = textBoxes(prob, w, h);
    expect(boxes.length, 2);
    expect(boxes.first.left < 2 && boxes.first.right > 20, isTrue, reason: 'grown back out');
    final groups = groupLines(boxes.reversed.toList());
    expect(groups.length, 1);
    expect(groups.first.first.top < groups.first.last.top, isTrue);
    // Japanese columns read right to left.
    final columns = groupLines([const Rect.fromLTWH(0, 0, 10, 50), const Rect.fromLTWH(12, 0, 10, 50)]);
    expect(columns.first.first.left, 12);
    expect(groupLines([const Rect.fromLTWH(0, 0, 10, 10), const Rect.fromLTWH(50, 50, 10, 10)]).length, 2);
  });

  test('balloons: CTC decoding, sentence case and SentencePiece segmentation', () {
    // Steps: a, a, blank, a, b, b -> "aab".
    final steps = [1, 1, 0, 1, 2, 2];
    final probs = Float32List(steps.length * 3);
    for (final (t, c) in steps.indexed) {
      probs[t * 3 + c] = 1;
    }
    expect(ctcDecode(probs, steps.length, 3, ['a', 'b']), ('aab', 1.0));
    expect(sentenceCase("NOT MY DAILY SALARY. MY MONTHLY SALARY. I'M FINE"), "Not my daily salary. My monthly salary. I'm fine");
    expect(sentenceCase('...and the last touch.'), '...and the last touch.');
    final spm = Unigram({'▁': -2, '▁the': -1, '▁th': -3, 'e': -2, '▁cat': -1.5, 'c': -4, 'a': -4, 't': -4, '!': -3}, unknown: -14, rules: {'！': '!', '\t': ' '});
    expect(spm.encode(' the \t cat！'), ['▁the', '▁cat', '!']);
    expect(spm.encode('the cat?¿'), ['▁the', '▁cat', '?¿'], reason: 'unknown characters in a row make one piece');
    expect(joinPieces(['▁the', '▁cat', '!']), 'the cat!');
  });

  test('balloons: a column is turned a quarter left for the recogniser, and lines are joined', () {
    // A white column 10 wide and 40 tall whose top is red: turned left, the top comes first.
    const w = 10, h = 40;
    final rgba = Uint8List(w * h * 4);
    for (var n = 0; n < w * h; n++) {
      final red = n ~/ w < 4;
      rgba.setAll(n * 4, [255, red ? 0 : 255, red ? 0 : 255, 255]);
    }
    final (input, width) = lineInput(rgba, w, h, const Rect.fromLTWH(0, 0, 10, 40));
    expect(width, 320, reason: 'padded to the narrowest line PaddleOCR reads');
    final plane = 48 * width;
    double px(int c, int x) => input[c * plane + 24 * width + x];
    expect([px(0, 2), px(1, 2), px(2, 2)], [-1, -1, 1], reason: 'blue, green, red: red at the start');
    expect([px(0, 150), px(1, 150), px(2, 150)], [1, 1, 1]);
    expect(px(0, 300), 0, reason: 'the padding');
    expect(joinLines(['PAY A LITTLE', 'MORE, BUT ROUGH-', 'LY 70%']), 'PAY A LITTLE MORE, BUT ROUGHLY 70%');
    expect(joinLines(['こんにちは', '元気'], vertical: true), 'こんにちは元気');
    expect(joinLines(['おい待て!', 'どこへ']), 'おい待て!どこへ');
    expect(splitSentences('My monthly salary is an astounding... 459 dollars!!! Not mine. おい!待て'),
        ['My monthly salary is an astounding... 459 dollars!!!', 'Not mine.', 'おい!', '待て']);
    expect(translationRoute('ja', 'tr')!.length, 2);
    expect(translationRoute('en', 'en'), isEmpty);
    expect(translationRoute('tr', 'en'), isNull);
    expect(balloonLanguage('auto', 'jpn'), 'ja');
    expect(balloonLanguage('auto', null), 'en');
  });
}
