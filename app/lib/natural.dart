// Two small Turkish voices run straight through ONNX Runtime (lib/onnx.dart), since sherpa-onnx has no model type
// for them. The glue between their graphs is ported from their own browser demos (both Apache-2.0):
//   Antalia-2 Mini, huggingface.co/spaces/cloud0day3/antalia-mini js/tts.js: text -> cond -> 8 flow steps -> vocoder,
//     then an inverse STFT and the release's output EQ, de-esser and limiter;
//   Ahenk Cep, github.com/ozguradmin/ahenk-turkish-tts site/js/engine.js and front-native.js: text -> cond ->
//     Euler steps -> decoder in 100-frame windows.
// Both speak 48 kHz audio. The noise is torch.randn's, so a sentence sounds the same every time it is made.
import 'dart:math';
import 'dart:typed_data';

import 'onnx.dart';
import 'trnorm.dart';

const naturalRate = 48000;

final _one = Float32List(1);

/// Rounds to float32, as the JS glue's Math.fround.
double _f(double x) => (_one..[0] = x)[0];

/// torch.Generator().manual_seed(seed) followed by torch.randn calls on the CPU: mt19937, 24-bit uniforms,
/// Box-Muller over blocks of 16 in float32.
class TorchRandn {
  TorchRandn(int seed) {
    _s[0] = seed & 0xffffffff;
    for (var i = 1; i < 624; i++) {
      _s[i] = (1812433253 * (_s[i - 1] ^ (_s[i - 1] >> 30)) + i) & 0xffffffff;
    }
  }

  final _s = Uint32List(624);
  int _i = 624;

  int _next() {
    final s = _s;
    if (_i >= 624) {
      for (var k = 0; k < 624; k++) {
        final y = (s[k] & 0x80000000) | (s[(k + 1) % 624] & 0x7fffffff);
        s[k] = s[(k + 397) % 624] ^ (y >> 1) ^ (y & 1 != 0 ? 0x9908b0df : 0);
      }
      _i = 0;
    }
    var y = s[_i++];
    y ^= y >> 11;
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= y >> 18;
    return y & 0xffffffff;
  }

  /// [n] normal floats (n a multiple of 16) times [scale].
  Float32List randn(int n, [double scale = 1]) {
    final out = Float32List(n), u = Float32List(16), sc = _f(scale);
    for (var b = 0; b < n; b += 16) {
      for (var j = 0; j < 16; j++) {
        u[j] = (_next() & 0xffffff) * 5.9604644775390625e-8;
      }
      for (var j = 0; j < 8; j++) {
        final r = _f(sqrt(_f(-2 * _f(log(_f(1 - u[j]))))));
        final th = _f(2 * pi * u[j + 8]);
        out[b + j] = _f(_f(r * _f(cos(th))) * sc);
        out[b + j + 8] = _f(_f(r * _f(sin(th))) * sc);
      }
    }
    return out;
  }
}

int _roundHalfEven(double x) {
  final f = x.floorToDouble(), d = x - f;
  final i = f.toInt();
  return d > 0.5 ? i + 1 : (d < 0.5 ? i : (i.isEven ? i : i + 1));
}

// ---------------------------------------------------------------------------------------------- Antalia-2 Mini

const _antaliaSymbols = ' .,?!\'-:;abcçdefgğhıijklmnoöpqrsştuüvwxyzâîû'; // ids 3 on; 0 pad, 1 bos, 2 eos
const _hop = 512, _nFft = 2048, _space = 3;

/// The model text: spoken form, lower case, only the model's symbols.
String antaliaText(String raw) {
  const fold = {'’': "'", '‘': "'", '`': "'", '´': "'", '–': '-', '—': '-', '…': '.', ' ': ' ', '\t': ' ', '\n': ' '};
  var t = turkishLower(normalizeTurkish(raw));
  t = t.split('').map((c) => fold[c] ?? (_antaliaSymbols.contains(c) ? c : ' ')).join();
  return t.replaceAllMapped(RegExp(r'\s+([.,?!:;])'), (m) => m[1]!).replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<int> antaliaIds(String text) => [1, for (final c in text.split('')) if (_antaliaSymbols.contains(c)) _antaliaSymbols.indexOf(c) + 3, 2];

/// Log durations to frames per symbol: double sounds held longer, divided by speed, 1 to 60 frames.
List<int> antaliaDurations(Float32List logd, List<int> ids, double speed, {double gemStretch = 1.3}) {
  final l = ids.length, ld = Float32List.fromList(logd);
  final g = _f(log(gemStretch));
  for (var j = 2; j < l - 1; j++) {
    if (ids[j] == ids[j - 1] && ids[j] != _space) {
      ld[j] = ld[j] + g;
    } else if (ids[j - 1] == _space && ids[j] == ids[j - 2]) {
      ld[j - 1] = ld[j - 1] + g;
    }
  }
  final sp = _f(speed);
  return [for (var j = 0; j < l; j++) _roundHalfEven(_f(_f(exp(ld[j])) / sp)).clamp(1, 60)];
}

/// Frame to symbol, the frame count rounded up to even.
Int64List frameIndex(List<int> dur) {
  final cum = <int>[];
  var s = 0;
  for (final d in dur) {
    cum.add(s += d);
  }
  final t = (s / 2).ceil() * 2;
  final idx = Int64List(t);
  var j = 0;
  for (var f = 0; f < t; f++) {
    while (j < dur.length && cum[j] <= f) {
      j++;
    }
    idx[f] = min(j, dur.length - 1);
  }
  return idx;
}

final _window = Float64List.fromList([for (var i = 0; i < _nFft; i++) 0.5 - 0.5 * cos(2 * pi * i / _nFft)]);

/// torch.istft (n_fft 2048, hop 512, Hann, centred) of [re] and [im], 1025 rows of [t] frames: t * 512 samples.
Float32List istft(Float32List re, Float32List im, int t) {
  const m = _nFft ~/ 2;
  final n = _nFft + _hop * (t - 1);
  final y = Float64List(n), env = Float64List(n), zr = Float64List(m), zi = Float64List(m);
  final bits = 10;
  final rev = Int32List(m);
  for (var i = 0; i < m; i++) {
    var r = 0;
    for (var b = 0; b < bits; b++) {
      r |= ((i >> b) & 1) << (bits - 1 - b);
    }
    rev[i] = r;
  }
  final cm = Float64List.fromList([for (var i = 0; i < m ~/ 2; i++) cos(2 * pi * i / m)]);
  final sm = Float64List.fromList([for (var i = 0; i < m ~/ 2; i++) sin(2 * pi * i / m)]);
  final cn = Float64List.fromList([for (var i = 0; i < m; i++) cos(2 * pi * i / _nFft)]);
  final sn = Float64List.fromList([for (var i = 0; i < m; i++) sin(2 * pi * i / _nFft)]);
  for (var f = 0; f < t; f++) {
    // The real inverse FFT of 2048 points as one complex inverse FFT of 1024 over even and odd samples.
    for (var k = 0; k < m; k++) {
      final ar = re[k * t + f], ai = k == 0 ? 0.0 : im[k * t + f];
      final br = re[(m - k) * t + f], bi = k == 0 ? 0.0 : -im[(m - k) * t + f];
      final er = ar + br, ei = ai + bi, dr = ar - br, di = ai - bi;
      final or = dr * cn[k] - di * sn[k], oi = dr * sn[k] + di * cn[k];
      zr[k] = er - oi;
      zi[k] = ei + or;
    }
    for (var i = 0; i < m; i++) {
      final j = rev[i];
      if (j > i) {
        var x = zr[i];
        zr[i] = zr[j];
        zr[j] = x;
        x = zi[i];
        zi[i] = zi[j];
        zi[j] = x;
      }
    }
    for (var size = 2; size <= m; size <<= 1) {
      final half = size >> 1, step = m ~/ size;
      for (var start = 0; start < m; start += size) {
        for (var k = 0; k < half; k++) {
          final wr = cm[k * step], wi = sm[k * step];
          final a = start + k, b = a + half;
          final tr = zr[b] * wr - zi[b] * wi, ti = zr[b] * wi + zi[b] * wr;
          zr[b] = zr[a] - tr;
          zi[b] = zi[a] - ti;
          zr[a] += tr;
          zi[a] += ti;
        }
      }
    }
    final off = f * _hop;
    for (var k = 0; k < m; k++) {
      final i = 2 * k, w0 = _window[i], w1 = _window[i + 1];
      y[off + i] += zr[k] / _nFft * w0;
      y[off + i + 1] += zi[k] / _nFft * w1;
      env[off + i] += w0 * w0;
      env[off + i + 1] += w1 * w1;
    }
  }
  final out = Float32List(t * _hop);
  for (var i = 0; i < n - _nFft; i++) {
    final e = env[m + i];
    out[i] = y[m + i] / (e > 1e-11 ? e : 1);
  }
  return out;
}

List<double> _biquad(List<double> b, List<double> a) => [b[0] / a[0], b[1] / a[0], b[2] / a[0], a[1] / a[0], a[2] / a[0]];

List<double> _shelf(double f0, double gainDb, bool high, double q) {
  final a = pow(10, gainDb / 40).toDouble(), w0 = 2 * pi * f0 / naturalRate;
  final alpha = sin(w0) / (2 * q), c = cos(w0), s = 2 * sqrt(a) * alpha;
  return high
      ? _biquad([a * (a + 1 + (a - 1) * c + s), -2 * a * (a - 1 + (a + 1) * c), a * (a + 1 + (a - 1) * c - s)],
          [a + 1 - (a - 1) * c + s, 2 * (a - 1 - (a + 1) * c), a + 1 - (a - 1) * c - s])
      : _biquad([a * (a + 1 - (a - 1) * c + s), 2 * a * (a - 1 - (a + 1) * c), a * (a + 1 - (a - 1) * c - s)],
          [a + 1 + (a - 1) * c + s, -2 * (a - 1 + (a + 1) * c), a + 1 + (a - 1) * c - s]);
}

List<double> _peak(double f0, double gainDb, double q) {
  final a = pow(10, gainDb / 40).toDouble(), w0 = 2 * pi * f0 / naturalRate;
  final alpha = sin(w0) / (2 * q), c = cos(w0);
  return _biquad([1 + alpha * a, -2 * c, 1 - alpha * a], [1 + alpha / a, -2 * c, 1 - alpha / a]);
}

List<double> _highpass(double f0, double q) {
  final w0 = 2 * pi * f0 / naturalRate, alpha = sin(w0) / (2 * q), c = cos(w0);
  return _biquad([(1 + c) / 2, -(1 + c), (1 + c) / 2], [1 + alpha, -2 * c, 1 - alpha]);
}

/// The release's output chain at 48 kHz: EQ curve, de-esser above 5.5 kHz, +1.6 dB, soft limiter. Its state carries
/// from one chunk to the next.
class OutputChain {
  final _sections = [
    _highpass(80, 0.707), _shelf(200, -4, false, 0.707), _peak(350, -2.5, 1.2), _peak(3200, 3, 0.9), _shelf(8000, 2, true, 0.707),
  ];
  late final _state = [for (final _ in _sections) Float64List(4)];
  final _gain = pow(10, 1.6 / 20).toDouble();

  // De-esser: a 127-tap linear-phase high-pass band, turned down only while it is loud.
  static const _taps = 127, _delay = 63, _block = 96;
  final _h = () {
    const fc = 2 * 5500 / naturalRate;
    final h = Float64List(_taps);
    var sum = 0.0;
    for (var i = 0; i < _taps; i++) {
      final x = fc * (i - _delay);
      final sinc = x == 0 ? 1.0 : sin(pi * x) / (pi * x);
      h[i] = fc * sinc * (0.5 + 0.5 * cos(pi * (2 * i + 1 - _taps) / (_taps - 1)));
      sum += h[i];
    }
    for (var i = 0; i < _taps; i++) {
      h[i] = -h[i] / sum;
    }
    h[_delay] += 1;
    return h;
  }();
  var _hist = Float64List(_taps - 1);
  final _thr = pow(10, -34 / 20).toDouble();
  final _att = exp(-_block / (1.5e-3 * naturalRate)), _rel = exp(-_block / (60e-3 * naturalRate));
  double _env = 0, _deessGain = 1;

  Float64List _deess(Float64List y) {
    final n = y.length;
    if (n == 0) return y;
    final ext = Float64List(_taps - 1 + n)
      ..setAll(0, _hist)
      ..setAll(_taps - 1, y);
    final band = Float64List(n), out = Float64List(n);
    for (var i = 0; i < n; i++) {
      var acc = 0.0;
      for (var k = 0; k < _taps; k++) {
        acc += _h[k] * ext[i + _taps - 1 - k];
      }
      band[i] = acc;
    }
    for (var i = 0; i < n; i += _block) {
      final m = min(_block, n - i);
      var e = 0.0;
      for (var j = 0; j < m; j++) {
        e += band[i + j] * band[i + j];
      }
      final level = sqrt(e / m), k = level > _env ? _att : _rel;
      _env = k * _env + (1 - k) * level;
      final target = _env <= _thr ? 1.0 : pow(_thr / _env, 1 - 1 / 3).toDouble();
      final g0 = m > 1 ? _deessGain : target, step = m > 1 ? (target - g0) / m : 0.0;
      for (var j = 0; j < m; j++) {
        out[i + j] = ext[i + j + _delay] + (g0 + j * step - 1) * band[i + j];
      }
      _deessGain = target;
    }
    _hist = Float64List.sublistView(ext, n);
    return out;
  }

  Float32List process(Float32List x) {
    var y = Float64List.fromList(x);
    for (final (k, s) in _sections.indexed) {
      final st = _state[k];
      var x1 = st[0], x2 = st[1], y1 = st[2], y2 = st[3];
      for (var i = 0; i < y.length; i++) {
        final v = y[i], o = s[0] * v + s[1] * x1 + s[2] * x2 - s[3] * y1 - s[4] * y2;
        x2 = x1;
        x1 = v;
        y2 = y1;
        y1 = o;
        y[i] = o;
      }
      st.setAll(0, [x1, x2, y1, y2]);
    }
    y = _deess(y);
    final threshold = pow(10, -1 / 20).toDouble(), room = pow(10, -0.1 / 20) - threshold;
    final out = Float32List(y.length);
    for (var i = 0; i < y.length; i++) {
      final v = y[i] * _gain, a = v.abs();
      out[i] = a > threshold ? v.sign * (threshold + room * _tanh((a - threshold) / room)) : v;
    }
    return out;
  }
}

double _tanh(double x) {
  final e = exp(-2 * x.abs());
  return (1 - e) / (1 + e) * x.sign;
}

/// Sentences packed up to 300 characters; a longer one cut at commas, then at spaces. The first chunk holds the
/// first sentence and packs only up to 80 characters.
List<String> splitModelText(String text, {int maxChars = 300, int firstChars = 80}) {
  List<String> pack(List<String> pieces, int limit) {
    final out = <String>[];
    var cur = '';
    for (final p in pieces) {
      if (p.length > limit) {
        if (cur.isNotEmpty) out.add(cur);
        cur = '';
        if (p.contains(' ')) {
          out.addAll(pack(p.split(' '), limit));
        } else {
          for (var i = 0; i < p.length; i += limit) {
            out.add(p.substring(i, min(p.length, i + limit)));
          }
        }
        continue;
      }
      if (cur.isNotEmpty && cur.length + 1 + p.length > limit) {
        out.add(cur);
        cur = p;
      } else {
        cur = cur.isEmpty ? p : '$cur $p';
      }
    }
    if (cur.isNotEmpty) out.add(cur);
    return out;
  }

  final pieces = <String>[];
  for (final s in text.trim().split(RegExp(r'(?<=[.?!])\s+')).map((s) => s.trim()).where((s) => s.isNotEmpty)) {
    pieces.addAll(s.length > maxChars ? pack(s.split(RegExp(r'(?<=[,;:])\s+')).where((s) => s.isNotEmpty).toList(), maxChars) : [s]);
  }
  if (pieces.isEmpty) return [];
  var head = '', used = 0;
  for (final p in pieces) {
    if (head.isNotEmpty && head.length + 1 + p.length > firstChars) break;
    head = head.isEmpty ? p : '$head $p';
    used++;
  }
  return [head, ...pack(pieces.sublist(used), maxChars)].where((c) => RegExp(r'\p{L}', unicode: true).hasMatch(c)).toList();
}

class Antalia {
  Antalia(String dir, {String library = defaultOnnxLibrary})
      : _text = OnnxSession('$dir/text.onnx', threads: 2, library: library),
        _cond = OnnxSession('$dir/cond.onnx', threads: 2, library: library),
        _flow = OnnxSession('$dir/flow.onnx', threads: 2, library: library),
        _vocoder = OnnxSession('$dir/vocoder.onnx', threads: 2, library: library);

  final OnnxSession _text, _cond, _flow, _vocoder;
  static const steps = 8;

  Float32List _chunk(String text, TorchRandn rng, double speed) {
    final pre = 'öı'.contains(text[0]) ? 'ee, ' : '';
    const suf = ' ee.';
    final ids = antaliaIds('$pre$text$suf');
    final l = ids.length;
    final r1 = _text.run([OnnxInput('ids', Int64List.fromList(ids), [1, l])], ['h', 'logd']);
    final dur = antaliaDurations(r1['logd']!.data, ids, speed);
    final idx = frameIndex(dur);
    final t = idx.length, n = t ~/ 2;
    final r2 = _cond.run([OnnxInput('h', r1['h']!.data, [1, l, 192]), OnnxInput('idx', idx, [1, t])], ['ctok', 'cnull']);
    final ctok = OnnxInput('ctok', r2['ctok']!.data, [1, n, 192]), cnull = OnnxInput('cnull', r2['cnull']!.data, [1, n, 192]);
    var x = rng.randn(n * 256, 0.6);
    for (var i = 0; i < steps; i++) {
      x = _flow.run([
        OnnxInput('x', x, [1, n, 256]), ctok, cnull,
        OnnxInput('t', Float32List.fromList([i * (1 / steps)]), [1]),
        OnnxInput('dt', Float32List.fromList([1 / steps]), [1]),
        OnnxInput('cfg', Float32List.fromList([2.0]), [1]),
      ], ['x_next'])['x_next']!.data;
    }
    final r4 = _vocoder.run([OnnxInput('z', x, [1, n, 256])], ['re', 'im']);
    var audio = istft(r4['re']!.data, r4['im']!.data, t);
    // Keep only the frames of the text itself, without the spoken prefix and suffix.
    final nPre = pre.isEmpty ? 0 : 4, nSuf = 4;
    var cum = 0, a = 0, b = 0;
    for (var j = 0; j < l; j++) {
      cum += dur[j];
      if (j == nPre) a = cum;
      if (j == l - 2 - nSuf) b = cum;
    }
    audio = Float32List.sublistView(audio, pre.isEmpty ? 0 : a * _hop, b * _hop);
    const fade = naturalRate * 5 ~/ 1000;
    if (audio.length > 2 * fade) {
      for (var i = 0; i < fade; i++) {
        if (pre.isNotEmpty) audio[i] = audio[i] * (i == fade - 1 ? 1 : _f(i * (1 / (fade - 1))));
        final o = audio.length - fade + i;
        audio[o] = audio[o] * (i == fade - 1 ? 0 : _f(i * (-1 / (fade - 1)) + 1));
      }
    }
    return Float32List.fromList(audio);
  }

  /// [raw] said at [speed] (1 is the release's own pace, 0.95), seed 0: 48 kHz samples.
  Float32List say(String raw, {double speed = 1, int seed = 0}) {
    final chunks = splitModelText(antaliaText(raw));
    final rng = TorchRandn(seed), chain = OutputChain(), out = BytesBuilder(copy: false);
    for (final (k, c) in chunks.indexed) {
      var w = _chunk(c, rng, 0.95 * speed);
      if (k < chunks.length - 1) {
        final pause = ((RegExp(r'[.?!]$').hasMatch(c.trimRight()) ? 0.12 : 0.06) * naturalRate).floor();
        w = Float32List(w.length + pause)..setAll(0, w);
      }
      out.add(chain.process(w).buffer.asUint8List());
    }
    return out.takeBytes().buffer.asFloat32List();
  }

}

// ---------------------------------------------------------------------------------------------- Ahenk Cep

const _ahenkVocab = ['<pad>', '<unk>', ' ', '!', '"', '%', '&', "'", '(', ')', ',', '-', '.', '/', ':', ';', '?',
  'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x',
  'y', 'z', 'ç', 'ö', 'ü', 'ğ', 'ı', 'ş'];

// Letters that lose their accent (Unicode NFKD without the marks) on the way to the vocabulary.
const _plain = {
  'â': 'a', 'à': 'a', 'á': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ê': 'e', 'è': 'e', 'é': 'e', 'ë': 'e', 'î': 'i', 'ì': 'i',
  'í': 'i', 'ï': 'i', 'ô': 'o', 'ò': 'o', 'ó': 'o', 'õ': 'o', 'û': 'u', 'ù': 'u', 'ú': 'u', 'ñ': 'n', 'ý': 'y', 'ÿ': 'y',
};

/// EMA Lightning's alphabet step: lower case (I is ı), typography folded, anything outside the vocabulary a space.
String ahenkAlphabet(String text) {
  const typography = {'’': "'", '‘': "'", 'ʼ': "'", '´': "'", '`': "'", '“': '"', '”': '"', '„': '"', '«': '"', '»': '"',
    '–': '-', '—': '-', '−': '-', '…': '...'};
  final t = turkishLower(text.split('').map((c) => typography[c] ?? c).join());
  final out = t.split('').map((c) {
    final p = _plain[c] ?? c;
    return _ahenkVocab.contains(p) && p.length == 1 ? p : ' ';
  }).join();
  return out.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _finish(String piece) {
  final bare = piece.replaceFirst(RegExp('["\')]+\$'), '');
  if (bare.isNotEmpty && '.!?'.contains(bare[bare.length - 1])) return piece;
  return '${piece.replaceFirst(RegExp(r'[,;:\- ]+$'), '')}.';
}

/// EMA Lightning's chunker: pieces of at most 250 letters (10 s), cut at a sentence end, else at a clause, else at a
/// space; each with the pause that follows it.
List<(String, double)> ahenkChunks(String text, double speed) {
  final limit = min(250, (18.0 * 10.0 * speed).floor());
  final cuts = [(RegExp('[.!?]+["\')]*(?= )'), 0.25), (RegExp('[,;:](?= )'), 0.12), (RegExp(r'\S(?= )'), 0.12)];
  final pieces = <(String, double)>[];
  var rest = text.trim();
  while (rest.isNotEmpty) {
    var cut = rest.length, pause = 0.0;
    if (rest.length > limit) {
      cut = limit;
      final window = rest.substring(0, min(limit + 1, rest.length));
      for (final (re, gap) in cuts) {
        final ends = re.allMatches(window).toList();
        if (ends.isNotEmpty) {
          cut = ends.last.end;
          pause = gap;
          break;
        }
      }
    }
    final piece = rest.substring(0, cut).trim();
    rest = rest.substring(cut).trim();
    if (RegExp(r'\p{L}', unicode: true).hasMatch(piece)) pieces.add((_finish(piece), pause));
  }
  if (pieces.isNotEmpty) pieces.last = (pieces.last.$1, 0.0);
  return pieces;
}

/// Token ids, the word of every letter and where that word starts.
(List<int>, List<int>, List<int>) ahenkPiece(String text) {
  final chars = text.split('');
  final ids = [for (final c in chars) max(1, _ahenkVocab.indexOf(c))];
  var starts = [for (var i = 0; i < chars.length; i++) if (chars[i] != ' ' && (i == 0 || chars[i - 1] == ' ')) i];
  if (starts.isEmpty) starts = [0];
  final bounds = [0, ...starts.skip(1), chars.length];
  final cw = <int>[], wstart = <int>[];
  for (var w = 0; w + 1 < bounds.length; w++) {
    for (var i = bounds[w]; i < bounds[w + 1]; i++) {
      cw.add(w);
      wstart.add(bounds[w]);
    }
  }
  return (ids, cw, wstart);
}

/// Durations over speed, frames per word, and the word and in-word position of every frame.
(Float32List, Int64List, Float32List) ahenkPlan(Float32List dur, List<int> cw, double speed) {
  final l = cw.length, s = _f(speed);
  final d = Float32List(l);
  for (var i = 0; i < l; i++) {
    d[i] = dur[i] / s;
  }
  final words = cw.last + 1;
  final sums = Float32List(words);
  for (var i = 0; i < l; i++) {
    sums[cw[i]] = sums[cw[i]] + d[i];
  }
  final n = [for (var w = 0; w < words; w++) _roundHalfEven(sums[w]).clamp(1, 250)];
  final t = min(n.fold(0, (a, b) => a + b), 3000);
  final fw = Int64List(t), fp = Float32List(t);
  var k = 0;
  for (var w = 0; w < words && k < t; w++) {
    for (var j = 0; j < n[w] && k < t; j++, k++) {
      fw[k] = w;
      fp[k] = j / n[w];
    }
  }
  return (d, fw, fp);
}

class AhenkCep {
  AhenkCep(String dir, {String library = defaultOnnxLibrary})
      : _text = OnnxSession('$dir/text.onnx', threads: 2, library: library),
        _cond = OnnxSession('$dir/cond.onnx', threads: 2, library: library),
        _step = OnnxSession('$dir/step.onnx', threads: 2, library: library),
        _decoder = OnnxSession('$dir/decoder.onnx', threads: 2, library: library);

  final OnnxSession _text, _cond, _step, _decoder;
  static const steps = 16, _d = 64, _hop = 1920, _window = 100, _context = 8;

  Float32List _latents(String text, int seed, double speed) {
    final (ids, cw, wstart) = ahenkPiece(text);
    final l = ids.length;
    final r1 = _text.run([OnnxInput('ids', Int64List.fromList(ids), [1, l]), OnnxInput('style', Int64List(1), [1])], ['h', 'dur']);
    final (d, fw, fp) = ahenkPlan(r1['dur']!.data, cw, speed);
    final t = fw.length;
    final cond = _cond.run([
      OnnxInput('h', r1['h']!.data, [1, l, 224]), OnnxInput('dur', d, [1, l]),
      OnnxInput('cw', Int64List.fromList(cw), [1, l]), OnnxInput('wstart', Int64List.fromList(wstart), [1, l]),
      OnnxInput('fw', fw, [1, t]), OnnxInput('fp', fp, [1, t]),
    ], ['cond'])['cond']!.data;
    var x = TorchRandn(seed).randn(t * _d);
    for (var k = 0; k < steps; k++) {
      x = _step.run([
        OnnxInput('x', x, [1, t, _d]), OnnxInput('cond', cond, [1, t, 224]),
        OnnxInput('t', Float32List.fromList([k / steps]), [1]),
        OnnxInput('dt', Float32List.fromList([1 / steps]), [1]),
        OnnxInput('cfg', Float32List.fromList([2.0]), [1]),
      ], ['x_next'])['x_next']!.data;
    }
    return x;
  }

  /// The decoder runs on 100-frame windows with 8 frames of context on each side.
  void _decode(Float32List lat, BytesBuilder out) {
    final frames = lat.length ~/ _d;
    for (var s = 0; s < frames; s += _window) {
      final e = min(frames, s + _window), a = max(0, s - _context), b = min(frames, e + _context), len = b - a;
      final z = Float32List(_d * len);
      for (var t = 0; t < len; t++) {
        for (var c = 0; c < _d; c++) {
          z[c * len + t] = lat[(a + t) * _d + c];
        }
      }
      final audio = _decoder.run([OnnxInput('z', z, [1, _d, len])], ['audio'])['audio']!.data;
      out.add(Float32List.fromList(audio.sublist((s - a) * _hop, (e - a) * _hop)).buffer.asUint8List());
    }
  }

  Float32List say(String raw, {double speed = 1, int seed = 0}) {
    final out = BytesBuilder(copy: false);
    for (final (i, (text, pause)) in ahenkChunks(ahenkAlphabet(normalizeTurkish(raw)), speed).indexed) {
      _decode(_latents(text, (seed * 1000003 + i) & 0xffffffff, speed), out);
      if (pause > 0) out.add(Float32List((pause * naturalRate).round()).buffer.asUint8List());
    }
    return out.takeBytes().buffer.asFloat32List();
  }

}
