import 'dart:typed_data';
import 'dart:ui';

/// The panels of a comic page in reading order, as fractions of the page (0 to 1), found by cutting the page
/// along its gutters: first across, then down each band, and so on. Empty when the page is one picture.
/// ponytail: gutters must be white or black; a page with coloured or no gutters reads as one panel.
List<Rect> findPanels(Uint8List rgba, int w, int h, {bool rtl = false}) {
  final luma = Uint8List(w * h);
  for (var i = 0; i < luma.length; i++) {
    luma[i] = (rgba[i * 4] * 299 + rgba[i * 4 + 1] * 587 + rgba[i * 4 + 2] * 114) ~/ 1000;
  }
  // The gutter colour: white or black, whichever the page's outer edge has more of.
  var white = 0, black = 0;
  void edge(int x, int y) {
    final v = luma[y * w + x];
    if (v > 215) white++;
    if (v < 40) black++;
  }

  for (var x = 0; x < w; x++) {
    edge(x, 0);
    edge(x, h - 1);
  }
  for (var y = 0; y < h; y++) {
    edge(0, y);
    edge(w - 1, y);
  }
  final dark = black > white;
  bool blank(int x, int y) => dark ? luma[y * w + x] < 40 : luma[y * w + x] > 215;
  // A line is gutter if nearly all of it is gutter colour; a stray speck or a little text does not break it.
  bool rowBlank(int y, int x0, int x1) {
    var ink = 0;
    for (var x = x0; x < x1; x++) {
      if (!blank(x, y) && ++ink > (x1 - x0) * 0.03) return false;
    }
    return true;
  }

  bool colBlank(int x, int y0, int y1) {
    var ink = 0;
    for (var y = y0; y < y1; y++) {
      if (!blank(x, y) && ++ink > (y1 - y0) * 0.03) return false;
    }
    return true;
  }

  final out = <Rect>[];
  final minGapY = (h * 0.008).ceil().clamp(2, 1 << 30), minGapX = (w * 0.008).ceil().clamp(2, 1 << 30);

  /// Bands of [from, to) between gutters at least [gap] long, by [isBlank].
  List<(int, int)> bands(int from, int to, int gap, bool Function(int) isBlank) {
    final out = <(int, int)>[];
    var start = -1, run = 0;
    for (var i = from; i < to; i++) {
      if (isBlank(i)) {
        run++;
        if (run == gap && start >= 0) {
          out.add((start, i - gap + 1));
          start = -1;
        }
      } else {
        if (start < 0) start = i;
        run = 0;
      }
    }
    if (start >= 0) out.add((start, to));
    return out;
  }

  void cut(int x0, int y0, int x1, int y1, int depth) {
    while (y0 < y1 && rowBlank(y0, x0, x1)) {
      y0++;
    }
    while (y1 > y0 && rowBlank(y1 - 1, x0, x1)) {
      y1--;
    }
    while (x0 < x1 && colBlank(x0, y0, y1)) {
      x0++;
    }
    while (x1 > x0 && colBlank(x1 - 1, y0, y1)) {
      x1--;
    }
    if (x1 - x0 < w * 0.06 || y1 - y0 < h * 0.04) return; // a speck, a page number
    if (depth < 6) {
      final rows = bands(y0, y1, minGapY, (y) => rowBlank(y, x0, x1));
      if (rows.length > 1) {
        for (final (a, b) in rows) {
          cut(x0, a, x1, b, depth + 1);
        }
        return;
      }
      final cols = bands(x0, x1, minGapX, (x) => colBlank(x, y0, y1));
      if (cols.length > 1) {
        for (final (a, b) in rtl ? cols.reversed : cols) {
          cut(a, y0, b, y1, depth + 1);
        }
        return;
      }
    }
    out.add(Rect.fromLTRB(x0 / w, y0 / h, x1 / w, y1 / h));
  }

  cut(0, 0, w, h, 0);
  return out.length < 2 || out.length > 24 ? const [] : out;
}
