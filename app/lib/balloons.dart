import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'colorize.dart';
import 'l10n.dart';
import 'onnx.dart';

/// Text read from one speech balloon and its translation, placed on the page.
class Balloon {
  Balloon(this.rect, this.original, this.translated);

  /// As fractions of the picture, 0 to 1.
  final ui.Rect rect;
  final String original, translated;
}

/// Files downloaded together, each into the pack's own folder, through [colorizer]'s model store.
class ModelPack {
  const ModelPack(this.id, this.name, this.description, this.sizeText, this.license, this.source, this.files);
  final String id, name, description, sizeText, license, source;

  /// Download url and where it is kept, under models/.
  final List<(String, String)> files;

  List<ColorModel> get parts => [
        for (final (url, file) in files)
          ColorModel(id: id, name: name, description: description, sizeText: sizeText, license: license, source: source, url: url, file: file, side: 0, version: id),
      ];
}

// TODO(models): urls and facts filled from the validation run.
const ocrPack = ModelPack('ocr', 'PP-OCRv5', '', '', 'Apache-2.0, PaddlePaddle', 'https://github.com/PaddlePaddle/PaddleOCR', []);
const enTrPack = ModelPack('mt-en-tr', 'Opus-MT', '', '', 'CC BY 4.0, Helsinki-NLP', 'https://github.com/Helsinki-NLP/Opus-MT', []);
const jaEnPack = ModelPack('mt-ja-en', 'Opus-MT', '', '', 'CC BY 4.0, Helsinki-NLP', 'https://github.com/Helsinki-NLP/Opus-MT', []);

final balloonReader = BalloonReader();

const balloonPacks = [ocrPack, enTrPack, jaEnPack];

/// What works today, said plainly in the settings.
const balloonLimits =
    'Şimdilik İngilizce → Türkçe, Japonca → İngilizce ve Japonca → Türkçe (İngilizce üzerinden). Düz yazılı balonlarda iyi çalışır; ses efektleri, el yazısı ve süslü yazılar çoğu zaman okunmaz. Çeviri makine çevirisidir, yanlış olabilir.';

/// The language balloons are read in: the reader's choice, else the book's, else English.
String balloonLanguage(String choice, String? book) =>
    choice != 'auto' ? choice : (RegExp(r'^(ja|jp)', caseSensitive: false).hasMatch(book ?? '') ? 'ja' : 'en');

/// The translators from [from] to [to], in order: none when no translation is needed, null for a pair not offered.
/// Japanese goes to Turkish through English.
List<ModelPack>? translationRoute(String from, String to) => from == to
    ? const []
    : switch ((from, to)) {
        ('en', 'tr') => const [enTrPack],
        ('ja', 'en') => const [jaEnPack],
        ('ja', 'tr') => const [jaEnPack, enTrPack],
        _ => null,
      };

/// Finds the text on a comic page, reads it and translates it, balloon by balloon, on the phone.
class BalloonReader {
  final _sessions = <String, OnnxModel>{};
  final _tokenizers = <String, Marian>{};
  List<String>? _chars;
  String? _models;

  /// Why balloons from [from] to [to] cannot be read now, or null if they can.
  String? missing(String from, String to) {
    final route = translationRoute(from, to);
    if (route == null) return tr('Bu dil çifti henüz desteklenmiyor.');
    if (![ocrPack, ...route].every((pack) => pack.parts.every(colorizer.isInstalled))) {
      return tr('Önce Ayarlar > Görsel > Balon çevirisi bölümünden gerekli modelleri indir.');
    }
    return null;
  }

  Future<String> _path(String file) async => p.join(_models ??= p.join((await getApplicationDocumentsDirectory()).path, 'models'), file);

  Future<OnnxModel> _open(String file) async => _sessions[file] ??= await OnnxModel.open(await _path(file), threads: 2);

  /// Frees the models' memory when a book closes.
  void close() {
    for (final s in _sessions.values) {
      s.close();
    }
    _sessions.clear();
  }

  Future<List<Balloon>> read(Uint8List encoded, String from, String to) async {
    final codec = await ui.instantiateImageCodec(encoded);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final image = frame.image;
    final w = image.width, h = image.height;
    final rgba = (await image.toByteData())!.buffer.asUint8List();
    // The detector sees the page at most 960 pixels on its long side, in multiples of 32.
    final s = min(1.0, 960 / max(w, h));
    final dw = max(32, (w * s / 32).round() * 32), dh = max(32, (h * s / 32).round() * 32);
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(image, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium);
    final small = await recorder.endRecording().toImage(dw, dh);
    image.dispose();
    final smallRgba = (await small.toByteData())!.buffer.asUint8List();
    small.dispose();

    final det = await _open(ocrPack.files[0].$2);
    final prob = await det.run([OnnxInput('x', await Isolate.run(() => detInput(smallRgba, dw, dh)), [1, 3, dh, dw])], 'fetch_name_0', dw * dh);
    final lines = [
      for (final r in textBoxes(prob, dw, dh)) ui.Rect.fromLTRB(r.left * w / dw, r.top * h / dh, r.right * w / dw, r.bottom * h / dh),
    ];
    if (lines.isEmpty) return const [];

    final rec = await _open(ocrPack.files[1].$2);
    final chars = _chars ??= (await File(await _path(ocrPack.files[2].$2)).readAsString()).split('\n')..removeWhere((c) => c.isEmpty);
    final classes = chars.length + 2;
    final route = translationRoute(from, to)!;
    final out = <Balloon>[];
    for (final group in groupLines(lines)) {
      final texts = <String>[];
      for (final line in group) {
        final (input, width) = lineInput(rgba, w, h, line);
        final steps = width ~/ 8;
        final probs = await rec.run([OnnxInput('x', input, [1, 3, 48, width])], 'fetch_name_0', steps * classes);
        final text = ctcDecode(probs, steps, classes, chars).trim();
        if (text.isNotEmpty) texts.add(text);
      }
      if (texts.isEmpty) continue;
      var text = joinLines(texts, vertical: group.where(isColumn).length * 2 > group.length);
      if (from == 'en') text = sentenceCase(text);
      var translated = text;
      for (final pack in route) {
        translated = await _translate(pack, translated);
      }
      final box = group.reduce((a, b) => a.expandToInclude(b));
      out.add(Balloon(ui.Rect.fromLTRB(box.left / w, box.top / h, box.right / w, box.bottom / h), text, translated));
    }
    return out;
  }

  Future<String> _translate(ModelPack pack, String text) async {
    final t = _tokenizers[pack.id] ??= Marian(jsonDecode(await File(await _path(pack.files[2].$2)).readAsString()) as Map<String, dynamic>);
    final encoder = await _open(pack.files[0].$2), decoder = await _open(pack.files[1].$2);
    final ids = t.encode(text);
    final n = ids.length;
    final mask = Int64List(n)..fillRange(0, n, 1);
    final hidden = await encoder.run([
      OnnxInput('input_ids', Int64List.fromList(ids), [1, n]),
      OnnxInput('attention_mask', mask, [1, n]),
    ], 'last_hidden_state', n * t.hidden);
    // ponytail: no key-value cache, so each step reads the whole prefix again; fine for a balloon's few words.
    final out = [t.start];
    while (out.length < min(t.maxLength, n * 3 + 10)) {
      final logits = await decoder.run([
        OnnxInput('input_ids', Int64List.fromList(out), [1, out.length]),
        OnnxInput('encoder_hidden_states', hidden, [1, n, t.hidden]),
        OnnxInput('encoder_attention_mask', mask, [1, n]),
      ], 'logits', t.vocab.length, skip: (out.length - 1) * t.vocab.length);
      final next = t.pick(logits);
      if (next == t.eos) break;
      out.add(next);
    }
    return t.decode(out.skip(1));
  }
}

/// Lines of one balloon as one text: words across lines, a hyphen at a line's end joined; columns run on.
@visibleForTesting
String joinLines(List<String> lines, {bool vertical = false}) {
  if (vertical) return lines.join();
  var s = '';
  for (final line in lines) {
    if (s.length > 1 && s.endsWith('-') && RegExp(r'[A-Za-z]').hasMatch(s[s.length - 2])) {
      s = s.substring(0, s.length - 1) + line;
    } else {
      s = s.isEmpty ? line : '$s $line';
    }
  }
  return s;
}

// ---------------------------------------------------------------------------------------------------------
// Finding text

/// The text lines in a detector's probability map ([w] by [h]): each connected patch above [thresh] whose mean is
/// at least [boxThresh], grown by [unclip] the way DBNet shrank it in training. In map pixels.
@visibleForTesting
List<ui.Rect> textBoxes(Float32List prob, int w, int h, {double thresh = 0.3, double boxThresh = 0.6, double unclip = 1.5}) {
  final seen = Uint8List(w * h);
  final out = <ui.Rect>[];
  final stack = <int>[];
  for (var start = 0; start < w * h; start++) {
    if (seen[start] != 0 || prob[start] <= thresh) continue;
    var x0 = w, y0 = h, x1 = -1, y1 = -1, count = 0;
    var sum = 0.0;
    seen[start] = 1;
    stack.add(start);
    while (stack.isNotEmpty) {
      final n = stack.removeLast();
      final x = n % w, y = n ~/ w;
      x0 = min(x0, x);
      x1 = max(x1, x);
      y0 = min(y0, y);
      y1 = max(y1, y);
      sum += prob[n];
      count++;
      for (final m in [if (x > 0) n - 1, if (x < w - 1) n + 1, if (y > 0) n - w, if (y < h - 1) n + w]) {
        if (seen[m] == 0 && prob[m] > thresh) {
          seen[m] = 1;
          stack.add(m);
        }
      }
    }
    final bw = x1 - x0 + 1.0, bh = y1 - y0 + 1.0;
    if (min(bw, bh) < 3 || sum / count < boxThresh) continue;
    final grow = bw * bh * unclip / (2 * (bw + bh));
    out.add(ui.Rect.fromLTRB(x0 - grow, y0 - grow, x1 + 1 + grow, y1 + 1 + grow).intersect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble())));
  }
  return out;
}

/// Text lines that belong together, as balloons: lines whose boxes, each grown by [grow] times its line height,
/// overlap. Each balloon's lines are in reading order: top to bottom, or for upright columns right to left.
@visibleForTesting
List<List<ui.Rect>> groupLines(List<ui.Rect> lines, {double grow = 0.6}) {
  final parent = [for (var i = 0; i < lines.length; i++) i];
  int root(int i) => parent[i] == i ? i : parent[i] = root(parent[i]);
  final grown = [for (final r in lines) r.inflate(grow * r.shortestSide)];
  for (var i = 0; i < lines.length; i++) {
    for (var j = i + 1; j < lines.length; j++) {
      if (grown[i].overlaps(grown[j])) parent[root(i)] = root(j);
    }
  }
  final groups = <int, List<ui.Rect>>{};
  for (var i = 0; i < lines.length; i++) {
    (groups[root(i)] ??= []).add(lines[i]);
  }
  return [
    for (final g in groups.values)
      g..sort(g.where(isColumn).length * 2 > g.length ? (a, b) => b.right.compareTo(a.right) : (a, b) => a.top.compareTo(b.top)),
  ];
}

/// An upright column of text, as Japanese is set; it is turned on its side before it is read.
bool isColumn(ui.Rect r) => r.height >= r.width * 1.5;

/// The detector's input: the page in planar B, G, R, normalised as PaddleOCR trained it.
@visibleForTesting
Float32List detInput(Uint8List rgba, int w, int h) {
  const mean = [0.485, 0.456, 0.406], std = [0.229, 0.224, 0.225];
  final plane = w * h;
  final out = Float32List(3 * plane);
  for (var n = 0; n < plane; n++) {
    for (var c = 0; c < 3; c++) {
      out[c * plane + n] = (rgba[n * 4 + 2 - c] / 255 - mean[c]) / std[c];
    }
  }
  return out;
}

/// One line of text cut from the page ([w] by [h]) for the recogniser: 48 pixels tall, as wide as its shape asks but
/// at least [minWidth], planar B, G, R from -1 to 1. An upright column is turned a quarter left first, as PaddleOCR does.
@visibleForTesting
(Float32List, int) lineInput(Uint8List rgba, int w, int h, ui.Rect box, {int minWidth = 320, int maxWidth = 1600}) {
  const height = 48;
  final x0 = box.left.round().clamp(0, w - 1), y0 = box.top.round().clamp(0, h - 1);
  final cw = max(1, box.right.round().clamp(0, w) - x0), ch = max(1, box.bottom.round().clamp(0, h) - y0);
  final turn = ch >= cw * 1.5;
  // Width and height after the turn.
  final tw = turn ? ch : cw, th = turn ? cw : ch;
  final rw = min(maxWidth, (height * tw / th).ceil()), width = max(minWidth, rw);
  final plane = height * width;
  final out = Float32List(3 * plane);
  double at(int x, int y, int c) => rgba[((y0 + y.clamp(0, ch - 1)) * w + x0 + x.clamp(0, cw - 1)) * 4 + c].toDouble();
  for (var oy = 0; oy < height; oy++) {
    final v = (oy + 0.5) * th / height - 0.5;
    for (var ox = 0; ox < rw; ox++) {
      final u = (ox + 0.5) * tw / rw - 0.5;
      // Turned a quarter left: row v, column u of the turned line is row u, column cw - 1 - v of the crop.
      final x = turn ? cw - 1 - v : u, y = turn ? u : v;
      final xf = x.floor(), yf = y.floor(), fx = x - xf, fy = y - yf;
      for (var c = 0; c < 3; c++) {
        final top = at(xf, yf, c) * (1 - fx) + at(xf + 1, yf, c) * fx;
        final bottom = at(xf, yf + 1, c) * (1 - fx) + at(xf + 1, yf + 1, c) * fx;
        out[(2 - c) * plane + oy * width + ox] = (top * (1 - fy) + bottom * fy) / 127.5 - 1;
      }
    }
  }
  return (out, width);
}

// ---------------------------------------------------------------------------------------------------------
// Reading text

/// Greedy CTC: the likeliest class at each of [steps] steps, repeats and blanks (class 0) dropped.
/// Class n is [chars][n - 1]; the class after the last character is a space.
@visibleForTesting
String ctcDecode(Float32List probs, int steps, int classes, List<String> chars) {
  final out = StringBuffer();
  var last = 0;
  for (var t = 0; t < steps; t++) {
    var best = 0;
    for (var c = 1; c < classes; c++) {
      if (probs[t * classes + c] > probs[t * classes + best]) best = c;
    }
    if (best != 0 && best != last) out.write(best - 1 < chars.length ? chars[best - 1] : ' ');
    last = best;
  }
  return out.toString();
}

/// Comic lettering is all capitals; translators read ordinary sentence case better.
@visibleForTesting
String sentenceCase(String s) {
  final letters = s.replaceAll(RegExp(r'[^A-Za-z]'), '');
  if (letters.isEmpty || letters != letters.toUpperCase()) return s;
  final lower = s.toLowerCase().replaceAllMapped(RegExp(r"\bi\b(?='|\s|$)"), (_) => 'I');
  return lower.replaceAllMapped(RegExp(r'(^|[.!?…]\s+)([a-z])'), (m) => '${m[1]}${m[2]!.toUpperCase()}');
}

// ---------------------------------------------------------------------------------------------------------
// Translating

/// A SentencePiece unigram model: pieces and their scores, segmented by Viterbi as SentencePiece does.
class Unigram {
  Unigram(this.scores) : longest = scores.keys.fold(1, (a, k) => max(a, k.length));
  final Map<String, double> scores;
  final int longest;
  late final double _unknown = scores.values.fold(0.0, min) - 10;

  /// Full-width forms as NFKC folds them, which is most of what SentencePiece's normaliser does to comic text.
  /// ponytail: no full NFKC table in Dart; half-width katakana and rarer folds pass through unchanged.
  static String normalize(String s) {
    final out = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0xFF01 && r <= 0xFF5E) {
        out.writeCharCode(r - 0xFEE0);
      } else if (r == 0x3000) {
        out.write(' ');
      } else if (r == 0x2026) {
        out.write('...');
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> encode(String text) {
    final s = '▁${normalize(text).replaceAll(' ', '▁')}';
    final chars = s.runes.map(String.fromCharCode).toList();
    final best = List<double>.filled(chars.length + 1, double.negativeInfinity)..[0] = 0;
    final from = List<int>.filled(chars.length + 1, 0);
    for (var i = 0; i < chars.length; i++) {
      if (best[i] == double.negativeInfinity) continue;
      final piece = StringBuffer();
      for (var j = i; j < min(chars.length, i + longest); j++) {
        piece.write(chars[j]);
        final score = scores[piece.toString()] ?? (j == i ? _unknown : null);
        if (score != null && best[i] + score > best[j + 1]) {
          best[j + 1] = best[i] + score;
          from[j + 1] = i;
        }
      }
    }
    final pieces = <String>[];
    for (var end = chars.length; end > 0; end = from[end]) {
      pieces.add(chars.sublist(from[end], end).join());
    }
    return pieces.reversed.toList();
  }
}

/// Pieces back to text: SentencePiece marks each word's start with ▁.
String joinPieces(Iterable<String> pieces) => pieces.join().replaceAll('▁', ' ').trim();

// ---------------------------------------------------------------------------------------------------------
// On the page

/// A translation in a white box over its balloon, in the largest size that fits.
class BalloonText extends StatelessWidget {
  const BalloonText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      var size = 18.0;
      for (; size > 6; size -= 0.5) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: TextStyle(fontSize: size, height: 1.1)),
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: max(1, box.maxWidth - 4));
        final fits = painter.height <= box.maxHeight - 4 && painter.width <= box.maxWidth - 4;
        painter.dispose();
        if (fits) break;
      }
      return DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(min(box.maxWidth, box.maxHeight) / 4)),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontSize: size, height: 1.1)),
          ),
        ),
      );
    });
  }
}

/// An Opus-MT model's tokenizer, from the JSON made for it: source pieces with scores, and the shared vocabulary.
class Marian {
  Marian(Map<String, dynamic> j)
      : unigram = Unigram({for (final e in j['source'] as List) (e as List)[0] as String: (e[1] as num).toDouble()}),
        vocab = (j['vocab'] as List).cast<String>(),
        eos = j['eos'] as int,
        unk = j['unk'] as int,
        pad = j['pad'] as int,
        start = j['start'] as int,
        prefix = j['prefix'] as String?,
        hidden = j['hidden'] as int,
        maxLength = j['maxLength'] as int? ?? 128;
  final Unigram unigram;
  final List<String> vocab;
  final int eos, unk, pad, start, hidden, maxLength;
  final String? prefix;
  late final Map<String, int> _ids = {for (final (i, piece) in vocab.indexed) piece: i};

  List<int> encode(String text) => [
        if (prefix != null) _ids[prefix]!,
        for (final piece in unigram.encode(text)) _ids[piece] ?? unk,
        eos,
      ];

  /// The likeliest next token; padding is never one.
  int pick(Float32List logits) {
    var best = pad == 0 ? 1 : 0;
    for (var i = 0; i < logits.length; i++) {
      if (i != pad && logits[i] > logits[best]) best = i;
    }
    return best;
  }

  String decode(Iterable<int> ids) => joinPieces([
        for (final id in ids)
          if (id != pad && id != eos && id != unk && id < vocab.length) vocab[id],
      ]);
}
