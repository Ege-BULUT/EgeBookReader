import 'dart:ui';

import 'package:egebookreader/panels.dart';
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
}
