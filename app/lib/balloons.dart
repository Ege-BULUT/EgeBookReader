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

const _rapid = 'https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/master/onnx/PP-OCRv5';
const _dicts = 'https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR';
const _ours = 'https://github.com/Ege-BULUT/EgeBookReader/releases/download/models-v1';

// Each pack's files: the detector or encoder first, then the recogniser or decoder, then its characters or tokenizer.
const ocrPack = ModelPack('ocr', 'PP-OCRv5 EN', 'Balonlardaki yazıyı bulur ve İngilizce yazıyı okur.', '13 MB', 'Apache-2.0, PaddlePaddle',
    'https://github.com/PaddlePaddle/PaddleOCR', [
  ('$_rapid/det/ch_PP-OCRv5_det_mobile.onnx', 'ocr/det.onnx'),
  ('$_rapid/rec/en_PP-OCRv5_rec_mobile.onnx', 'ocr/rec.onnx'),
  ('$_dicts/v3.2.0/ppocr/utils/dict/ppocrv5_en_dict.txt', 'ocr/dict.txt'),
]);
const ocrJaPack = ModelPack('ocr-ja', 'PP-OCRv5 JA', 'Japonca yazıyı okur, dikey sütunlar dahil.', '17 MB', 'Apache-2.0, PaddlePaddle',
    'https://github.com/PaddlePaddle/PaddleOCR', [
  ('$_rapid/rec/ch_PP-OCRv5_rec_mobile.onnx', 'ocr-ja/rec.onnx'),
  ('$_dicts/v3.0.0/ppocr/utils/dict/ppocrv5_dict.txt', 'ocr-ja/dict.txt'),
]);
const enTrPack = ModelPack('mt-en-tr', 'Opus-MT EN→TR', 'İngilizceden Türkçeye çevirir.', '36 MB', 'Apache-2.0, Helsinki-NLP',
    'https://huggingface.co/Helsinki-NLP/opus-mt_tiny_eng-tur', [
  ('$_ours/opus-mt-tiny-en-tr.encoder.int8.onnx', 'mt-en-tr/encoder.onnx'),
  ('$_ours/opus-mt-tiny-en-tr.decoder.int8.onnx', 'mt-en-tr/decoder.onnx'),
  ('$_ours/opus-mt-tiny-en-tr.tokenizer.json', 'mt-en-tr/tokenizer.json'),
]);
const jaEnPack = ModelPack('mt-ja-en', 'Opus-MT JA→EN', 'Japoncadan İngilizceye çevirir; Türkçeye İngilizce üzerinden.', '110 MB', 'Apache-2.0, Helsinki-NLP',
    'https://huggingface.co/Helsinki-NLP/opus-mt-ja-en', [
  ('https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/encoder_model_quantized.onnx', 'mt-ja-en/encoder.onnx'),
  ('https://huggingface.co/Xenova/opus-mt-ja-en/resolve/main/onnx/decoder_model_quantized.onnx', 'mt-ja-en/decoder.onnx'),
  ('$_ours/opus-mt-ja-en.tokenizer.json', 'mt-ja-en/tokenizer.json'),
]);

final balloonReader = BalloonReader();

const balloonPacks = [ocrPack, ocrJaPack, enTrPack, jaEnPack];

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

/// The readers for text in [from]: Japanese takes its own recogniser beside the detector.
List<ModelPack> ocrRoute(String from) => from == 'ja' ? const [ocrPack, ocrJaPack] : const [ocrPack];

/// Finds the text on a comic page, reads it and translates it, balloon by balloon, on the phone.
class BalloonReader {
  /// [models] is where the model files are; the app's own folder unless a test says otherwise.
  BalloonReader([this._models]);
  final _sessions = <String, OnnxModel>{};
  final _tokenizers = <String, Marian>{};
  final _chars = <String, List<String>>{};
  String? _models;

  /// Why balloons from [from] to [to] cannot be read now, or null if they can.
  String? missing(String from, String to) {
    final route = translationRoute(from, to);
    if (route == null) return tr('Bu dil çifti henüz desteklenmiyor.');
    if (![...ocrRoute(from), ...route].every((pack) => pack.parts.every(colorizer.isInstalled))) {
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
    // The detector sees the page at most 1280 pixels on its long side, in multiples of 32.
    final s = min(1.0, 1280 / max(w, h));
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
    var lines = [
      for (final r in textBoxes(prob, dw, dh)) ui.Rect.fromLTRB(r.left * w / dw, r.top * h / dh, r.right * w / dw, r.bottom * h / dh),
    ];
    if (lines.isEmpty) return const [];
    // Thin slivers are texture, not text.
    final thickness = lines.map((r) => r.shortestSide).toList()..sort();
    lines = lines.where((r) => r.shortestSide >= thickness[thickness.length ~/ 2] * 0.5).toList();

    final reader = ocrRoute(from).last;
    final rec = await _open(reader.files[reader.files.length - 2].$2);
    final chars = _chars[reader.id] ??= await _readChars(reader.files.last.$2);
    final classes = chars.length + 2;
    final route = translationRoute(from, to)!;
    final out = <Balloon>[];
    for (final group in groupLines(lines)) {
      final texts = <String>[];
      for (final line in group) {
        final (input, width) = lineInput(rgba, w, h, line);
        final steps = width ~/ 8;
        final probs = await rec.run([OnnxInput('x', input, [1, 3, 48, width])], 'fetch_name_0', steps * classes);
        final (text, sure) = ctcDecode(probs, steps, classes, chars);
        // Unsure reads and lines with no letter or digit are drawings mistaken for text.
        if (sure >= 0.6 && RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) texts.add(text.trim());
      }
      if (texts.isEmpty) continue;
      var text = joinLines(texts, vertical: group.where(isColumn).length * 2 > group.length);
      if (from == 'en') text = sentenceCase(text);
      // Opus-MT translates one sentence at a time and quietly drops the rest.
      var parts = splitSentences(text);
      for (final pack in route) {
        parts = [for (final part in parts) await _translate(pack, part)];
      }
      final translated = parts.join(' ');
      final box = group.reduce((a, b) => a.expandToInclude(b));
      out.add(Balloon(ui.Rect.fromLTRB(box.left / w, box.top / h, box.right / w, box.bottom / h), text, translated));
    }
    return out;
  }

  Future<List<String>> _readChars(String file) async {
    final lines = (await File(await _path(file)).readAsString()).split('\n');
    if (lines.last.isEmpty) lines.removeLast(); // the file's last newline, not a character
    return lines;
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
    // It sometimes starts a sentence as if it were dialogue.
    return t.decode(out.skip(1)).replaceFirst(RegExp(r'^[-–—]\s+'), '');
  }
}

/// Lines of one balloon as one text: words across lines, a hyphen at a line's end joined; columns and Chinese or
/// Japanese lines run on without a space.
@visibleForTesting
String joinLines(List<String> lines, {bool vertical = false}) {
  if (vertical) return lines.join();
  var s = '';
  for (final line in lines.where((l) => l.isNotEmpty)) {
    if (s.length > 1 && s.endsWith('-') && RegExp(r'[A-Za-z]').hasMatch(s[s.length - 2])) {
      s = s.substring(0, s.length - 1) + line;
    } else if (s.isEmpty || s.runes.last >= 0x3000 || line.runes.first >= 0x3000) {
      s += line;
    } else {
      s = '$s $line';
    }
  }
  return s;
}

/// Sentences, cut after an end mark that a capital or a Chinese or Japanese character follows.
@visibleForTesting
List<String> splitSentences(String s) =>
    s.split(RegExp(r'(?<=[.!?。！？])\s*(?=[A-Z\u3040-\u30ff\u3400-\u9fff])')).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();

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
  double bilinear(double x, double y, int c) {
    final xf = x.floor(), yf = y.floor(), fx = x - xf, fy = y - yf;
    final top = at(xf, yf, c) * (1 - fx) + at(xf + 1, yf, c) * fx;
    final bottom = at(xf, yf + 1, c) * (1 - fx) + at(xf + 1, yf + 1, c) * fx;
    return top * (1 - fy) + bottom * fy;
  }

  // Shrinking, each pixel averages a few samples across what it covers, so thin strokes are not lost between them.
  final sx = tw / rw, sy = th / height;
  final nx = sx.ceil(), ny = sy.ceil();
  for (var oy = 0; oy < height; oy++) {
    for (var ox = 0; ox < rw; ox++) {
      for (var c = 0; c < 3; c++) {
        var sum = 0.0;
        for (var j = 0; j < ny; j++) {
          final v = oy * sy + (j + 0.5) * sy / ny - 0.5;
          for (var i = 0; i < nx; i++) {
            final u = ox * sx + (i + 0.5) * sx / nx - 0.5;
            // Turned a quarter left: row v, column u of the turned line is row u, column cw - 1 - v of the crop.
            sum += turn ? bilinear(cw - 1 - v, u, c) : bilinear(u, v, c);
          }
        }
        out[(2 - c) * plane + oy * width + ox] = sum / (nx * ny) / 127.5 - 1;
      }
    }
  }
  return (out, width);
}

// ---------------------------------------------------------------------------------------------------------
// Reading text

/// Greedy CTC: the likeliest class at each of [steps] steps, repeats and blanks (class 0) dropped, with the mean
/// probability of the characters kept.
/// Class n is [chars][n - 1]; the class after the last character is a space.
@visibleForTesting
(String, double) ctcDecode(Float32List probs, int steps, int classes, List<String> chars) {
  final out = StringBuffer();
  var last = 0, kept = 0;
  var sure = 0.0;
  for (var t = 0; t < steps; t++) {
    var best = 0;
    for (var c = 1; c < classes; c++) {
      if (probs[t * classes + c] > probs[t * classes + best]) best = c;
    }
    if (best != 0 && best != last) {
      out.write(best - 1 < chars.length ? chars[best - 1] : ' ');
      sure += probs[t * classes + best];
      kept++;
    }
    last = best;
  }
  return (out.toString(), kept == 0 ? 0.0 : sure / kept);
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

/// A SentencePiece unigram model: pieces and their scores, segmented by Viterbi exactly as SentencePiece does it.
class Unigram {
  Unigram(this.scores, {required this.unknown, this.rules = const {}})
      : longest = scores.keys.fold(1, (a, k) => max(a, k.runes.length)),
        _ruleLongest = rules.keys.fold(1, (a, k) => max(a, k.runes.length));
  final Map<String, double> scores;

  /// The score of a character no piece covers.
  final double unknown;

  /// SentencePiece's normalisation table (NFKC and its own rules), longest match first.
  final Map<String, String> rules;
  final int longest, _ruleLongest;

  /// The text as SentencePiece sees it: rules applied, spaces collapsed, each word's start marked with ▁.
  String normalize(String text) {
    final chars = text.runes.map(String.fromCharCode).toList();
    final out = StringBuffer();
    for (var i = 0; i < chars.length;) {
      var matched = false;
      for (var l = min(_ruleLongest, chars.length - i); l > 0; l--) {
        final to = rules[chars.sublist(i, i + l).join()];
        if (to != null) {
          out.write(to);
          i += l;
          matched = true;
          break;
        }
      }
      if (!matched) out.write(chars[i++]);
    }
    final words = out.toString().split(' ').where((w) => w.isNotEmpty);
    return words.isEmpty ? '' : '▁${words.join('▁')}';
  }

  List<String> encode(String text) {
    final chars = normalize(text).runes.map(String.fromCharCode).toList();
    final n = chars.length;
    // Sums in 32-bit floats, as SentencePiece adds them, so ties break the same way.
    final best = Float32List(n + 1), reached = List<bool>.filled(n + 1, false)..[0] = true;
    final from = List<int>.filled(n + 1, 0), unknownAt = List<bool>.filled(n + 1, false);
    void offer(int i, int end, double score, bool isUnknown) {
      final total = (Float32List(1)..[0] = best[i] + score)[0];
      if (!reached[end] || total > best[end]) {
        best[end] = total;
        reached[end] = true;
        from[end] = i;
        unknownAt[end] = isUnknown;
      }
    }

    for (var i = 0; i < n; i++) {
      if (!reached[i]) continue;
      var single = false;
      final piece = StringBuffer();
      for (var j = i; j < min(n, i + longest); j++) {
        piece.write(chars[j]);
        final score = scores[piece.toString()];
        if (score == null) continue;
        if (j == i) single = true;
        offer(i, j + 1, score, false);
      }
      if (!single) offer(i, i + 1, unknown, true);
    }
    final pieces = <(String, bool)>[];
    for (var end = n; end > 0; end = from[end]) {
      pieces.add((chars.sublist(from[end], end).join(), unknownAt[end]));
    }
    // Unknown characters in a row make one unknown piece.
    final out = <String>[];
    var lastUnknown = false;
    for (final (piece, isUnknown) in pieces.reversed) {
      if (isUnknown && lastUnknown) {
        out.last += piece;
      } else {
        out.add(piece);
      }
      lastUnknown = isUnknown;
    }
    return out;
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
      : unigram = Unigram(
          {
            // Only normal (1) and user-defined (4) pieces take part; control pieces such as </s> never match text.
            for (final (i, e) in (j['source'] as List).indexed)
              if ((j['sourceTypes'] as List)[i] case 1 || 4) (e as List)[0] as String: (e[1] as num).toDouble(),
          },
          unknown: (j['unkScore'] as num).toDouble(),
          rules: (j['normalize'] as Map<String, dynamic>).cast<String, String>(),
        ),
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
