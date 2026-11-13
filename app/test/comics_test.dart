import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

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
}
