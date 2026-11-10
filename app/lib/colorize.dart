import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'main.dart' show settings;
import 'onnx.dart';

final colorizer = Colorizer();

const _device = MethodChannel('egebookreader/volume');

/// A colorizer that can be downloaded. Files come straight from their authors' own releases.
class ColorModel {
  const ColorModel({
    required this.id,
    required this.name,
    required this.description,
    required this.sizeText,
    required this.license,
    required this.source,
    required this.url,
    required this.file,
    required this.side,
    required this.version,
  });
  final String id, name, description, sizeText, license, source, url, file, version;

  /// The model works on a square of this many pixels.
  final int side;

  bool get isManga => id == 'manga';
  bool get isZip => url.endsWith('.zip');
}

const colorModels = [
  ColorModel(
    id: 'manga',
    name: 'Manga Light Colorizer',
    description: 'Manga ve çizgi roman için eğitilmiş, en iyi sonuç bunda.',
    sizeText: '191 MB',
    license: 'CC BY-NC-SA 4.0, sharky172',
    source: 'https://huggingface.co/sharky172/manga-light-colorizer',
    url: 'https://huggingface.co/sharky172/manga-light-colorizer/resolve/main/models/v6_generator.onnx',
    file: 'manga/v6_generator.onnx',
    side: 512,
    version: 'manga1',
  ),
  ColorModel(
    id: 'ddcolor',
    name: 'DDColor',
    description: 'Fotoğraflar için eğitilmiş, siyah beyaz fotoğraflara uygun.',
    sizeText: '206 MB indirme, 228 MB yer',
    license: 'Apache-2.0',
    source: 'https://github.com/piddnad/DDColor',
    url: 'https://qaihub-public-assets.s3.us-west-2.amazonaws.com/qai-hub-models/models/ddcolor/releases/v0.66.0/ddcolor-onnx-float.zip',
    file: 'ddcolor-onnx-float/ddcolor.onnx',
    side: 256,
    version: 'ddcolor3',
  ),
];

enum JobState { none, waiting, running, done, skipped, failed }

/// A picture on a page, wherever it came from.
class PageImage {
  PageImage(this.id, this.rect, this.bytes);
  final String id;

  /// In the page's own logical coordinates.
  final ui.Rect rect;
  final Future<Uint8List> Function() bytes;
}

String contentId(Uint8List b) {
  var h = 0xcbf29ce484222325;
  for (var i = 0; i < b.length; i += 16) {
    h = (h ^ b[i]) * 0x100000001b3;
  }
  return '${b.length.toRadixString(36)}-${h.toUnsigned(64).toRadixString(36)}';
}

/// Colours one picture at a time, on a queue that rests between pictures so the phone stays cool.
class Colorizer extends ChangeNotifier {
  late Directory _models, _out;
  OnnxModel? _session;
  String? _sessionFor;

  /// Downloads under way, by model id; a null value means the size is not known.
  final downloads = <String, double?>{};
  String? error;

  /// The model in use: the chosen one if it is installed, otherwise any that is.
  ColorModel? get model {
    final chosen = colorModels.where((m) => m.id == settings.colorModelId && isInstalled(m));
    if (chosen.isNotEmpty) return chosen.first;
    final any = colorModels.where(isInstalled);
    return any.isEmpty ? null : any.first;
  }

  bool isInstalled(ColorModel m) => File(p.join(_models.path, m.file)).existsSync();

  final _queue = Queue<(PageImage, bool)>();
  final _state = <String, JobState>{};
  bool _pumping = false;

  /// Where each picture came from, for the gallery: id to title and page number.
  final _origins = <String, Map<String, dynamic>>{};

  /// Pictures the reader chose to see as they were.
  final _hidden = <String>{};
  File get _originsFile => File(p.join(_out.path, 'origins.json'));
  File get _hiddenFile => File(p.join(_out.path, 'hidden.txt'));

  /// Runs after a picture is finished, so a reader can redraw the page that shows it.
  void Function(String id)? onDone;

  bool get modelReady => model != null;

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    _models = Directory(p.join(docs.path, 'models'));
    _out = Directory(p.join(docs.path, 'colorized'));
    await _out.create(recursive: true);
    if (_originsFile.existsSync()) {
      (jsonDecode(_originsFile.readAsStringSync()) as Map<String, dynamic>).forEach((k, v) => _origins[k] = v as Map<String, dynamic>);
    }
    if (_hiddenFile.existsSync()) _hidden.addAll(_hiddenFile.readAsLinesSync());
  }

  bool showsColor(String id) => !_hidden.contains(id);

  /// Switches a picture between its colours and how it was printed, everywhere it shows.
  void setShowsColor(String id, bool show) {
    show ? _hidden.remove(id) : _hidden.add(id);
    _hiddenFile.writeAsString(_hidden.join('\n'));
    notifyListeners();
    onDone?.call(id);
  }

  File originalFile(String id) => File(p.join(_out.path, 'originals', id));
  bool originalExists(String id) => originalFile(id).existsSync();
  Future<Uint8List?> originalBytes(String id) async => originalExists(id) ? originalFile(id).readAsBytes() : null;

  String titleOf(String id) => _origins[id]?['title'] as String? ?? tr('Renklendirilmiş görsel');
  int? pageOf(String id) => _origins[id]?['page'] as int?;
  String captionOf(String id) => pageOf(id) == null ? titleOf(id) : '${titleOf(id)} · ${tr('Sayfa')} ${pageOf(id)}';

  /// Raise the suffix when the model or the merge changes, so old results are made again.
  File fileFor(String id) => File(p.join(_out.path, '$id-${model?.version ?? colorModels.first.version}.png'));
  bool hasResult(String id) => fileFor(id).existsSync();

  JobState stateOf(String id) => hasResult(id) ? JobState.done : (_state[id] ?? JobState.none);

  /// Ids of everything colorized so far, newest first: the app's gallery.
  List<String> gallery() {
    final suffix = '-${model?.version ?? colorModels.first.version}.png';
    final files = _out.listSync().whereType<File>().where((f) => f.path.endsWith(suffix)).toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return [
      for (final f in files) p.basename(f.path).substring(0, p.basename(f.path).length - suffix.length),
    ];
  }

  Future<void> downloadModel(ColorModel m) async {
    if (downloads.containsKey(m.id)) return;
    error = null;
    downloads[m.id] = 0;
    notifyListeners();
    final target = File(p.join(_models.path, m.file));
    final temp = File('${target.path}.part');
    try {
      await temp.create(recursive: true);
      final client = HttpClient();
      final response = await (await client.getUrl(Uri.parse(m.url))).close();
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      final sink = temp.openWrite();
      var got = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        got += chunk.length;
        downloads[m.id] = response.contentLength > 0 ? got / response.contentLength : null;
        notifyListeners();
      }
      await sink.close();
      client.close();
      if (m.isZip) {
        final to = _models.path, from = temp.path;
        await Isolate.run(() async {
          final zip = ZipDecoder().decodeStream(InputFileStream(from));
          await extractArchiveToDisk(zip, to);
        });
      } else {
        await temp.rename(target.path);
      }
    } catch (e) {
      debugPrint('model download failed: $e');
      error = tr('Model indirilemedi. Bağlantını ve boş alanı kontrol et.');
    }
    if (temp.existsSync()) await temp.delete();
    downloads.remove(m.id);
    notifyListeners();
  }

  Future<void> removeModel(ColorModel m) async {
    _session?.close();
    _session = null;
    _sessionFor = null;
    final file = File(p.join(_models.path, m.file));
    if (file.parent.existsSync()) await file.parent.delete(recursive: true);
    notifyListeners();
  }

  /// [front] puts the picture ahead of everything waiting; a person tapped it.
  void enqueue(PageImage image, {bool front = false, bool rest = true, String? title, int? pageNumber}) {
    if (title != null) _origins[image.id] = {'title': title, 'page': pageNumber};
    final state = stateOf(image.id);
    if (!modelReady || state == JobState.done || state == JobState.skipped || state == JobState.running) return;
    if (state == JobState.waiting) {
      if (!front) return;
      _queue.removeWhere((j) => j.$1.id == image.id);
    }
    _state[image.id] = JobState.waiting;
    front ? _queue.addFirst((image, rest)) : _queue.addLast((image, rest));
    notifyListeners();
    _pump();
  }

  /// Drops work nobody is waiting for any more, when a book closes.
  void clearQueue() {
    for (final j in _queue) {
      _state.remove(j.$1.id);
    }
    _queue.clear();
  }

  Future<void> whenIdle(Iterable<String> ids) async {
    while (ids.any((id) => stateOf(id) == JobState.waiting || stateOf(id) == JobState.running)) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (_queue.isNotEmpty) {
      final (image, rest) = _queue.removeFirst();
      if (rest) await _waitForCoolDevice();
      _state[image.id] = JobState.running;
      notifyListeners();
      final clock = Stopwatch()..start();
      try {
        final encoded = await image.bytes();
        final colored = await _colorize(encoded, fileFor(image.id));
        if (colored) {
          await originalFile(image.id).create(recursive: true);
          await originalFile(image.id).writeAsBytes(encoded);
          await _originsFile.writeAsString(jsonEncode(_origins));
        }
        _state[image.id] = colored ? JobState.done : JobState.skipped;
      } catch (_) {
        _state[image.id] = JobState.failed;
      }
      notifyListeners();
      onDone?.call(image.id);
      // ponytail: fixed 50% duty cycle; tune against real thermals on a mid-range phone.
      if (rest && _queue.isNotEmpty) await Future<void>.delayed(clock.elapsed + const Duration(milliseconds: 400));
    }
    _pumping = false;
  }

  Future<void> _waitForCoolDevice() async {
    while (await _device.invokeMethod<bool>('shouldRest') ?? false) {
      await Future<void>.delayed(const Duration(seconds: 20));
    }
  }

  /// Returns false when the picture already has colour and was left alone.
  Future<bool> _colorize(Uint8List encoded, File out) async {
    final codec = await ui.instantiateImageCodec(encoded);
    final first = await codec.getNextFrame();
    codec.dispose();
    final source = first.image;
    final scale = min(1.0, 1800 / max(source.width, source.height));
    final w = (source.width * scale).round(), h = (source.height * scale).round();
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      source,
      ui.Rect.fromLTWH(0, 0, source.width.toDouble(), source.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final sized = await recorder.endRecording().toImage(w, h);
    source.dispose();
    final data = (await sized.toByteData())!.buffer.asUint8List();
    sized.dispose();

    final current = model!;
    final side = current.side, manga = current.isManga;
    final prepared = await Isolate.run(() => prepareColorInput(data, w, h, side));
    if (prepared == null) return false;

    if (_sessionFor != current.id) {
      _session?.close();
      _session = await OnnxModel.open(p.join(_models.path, current.file));
      _sessionFor = current.id;
    }
    final Float32List output;
    if (manga) {
      // Its optional SAM guide is left at zero: the generator alone gives near-identical pages, without 109 MB more.
      final luma = Float32List(side * side);
      for (var i = 0; i < luma.length; i++) {
        luma[i] = prepared.input[i] * 2 - 1;
      }
      output = await _session!.run([
        OnnxInput('L_bw', luma, [1, 1, side, side]),
        OnnxInput('sam_level0', Float32List(256 * (side ~/ 16) * (side ~/ 16)), [1, 256, side ~/ 16, side ~/ 16]),
        OnnxInput('sam_level1', Float32List(256 * (side ~/ 32) * (side ~/ 32)), [1, 256, side ~/ 32, side ~/ 32]),
        OnnxInput('wd14_embedding', Float32List(1024), const [1, 1024]),
      ], 'rgb_pred', 3 * side * side);
    } else {
      output = await _session!.run([OnnxInput('image', prepared.input, [1, 3, side, side])], 'output', 2 * side * side);
    }
    final ab = manga ? await Isolate.run(() => rgbToAb(output, side)) : output;

    final rgba = await Isolate.run(() => mergeColor(prepared, ab, w, h, protectWhites: !manga));
    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: w, height: h, pixelFormat: ui.PixelFormat.rgba8888);
    final imageCodec = await descriptor.instantiateCodec();
    final frame = await imageCodec.getNextFrame();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    imageCodec.dispose();
    descriptor.dispose();
    buffer.dispose();
    await out.writeAsBytes(png!.buffer.asUint8List());
    return true;
  }
}

class Prepared {
  Prepared(this.input, this.lightness, this.blurred, this.side);
  final int side;
  final Float32List input;
  final Float32List lightness;

  /// Lightness averaged down to the model's size: what a region looks like from reading distance.
  final Float32List blurred;
}

double _srgbToLinear(double c) => c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
double _linearToSrgb(double c) => c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055;
double _f(double t) => t > 0.008856 ? pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
double _fInv(double t) => t > 0.206893 ? t * t * t : (t - 16 / 116) / 7.787;

/// Turns a model's RGB output (-1 to 1) into the a and b channels the merge takes, so the original lightness can stay.
@visibleForTesting
Float32List rgbToAb(Float32List rgb, int side) {
  final count = side * side;
  final out = Float32List(count * 2);
  for (var n = 0; n < count; n++) {
    final r = _srgbToLinear(((rgb[n] + 1) / 2).clamp(0.0, 1.0));
    final g = _srgbToLinear(((rgb[count + n] + 1) / 2).clamp(0.0, 1.0));
    final b = _srgbToLinear(((rgb[2 * count + n] + 1) / 2).clamp(0.0, 1.0));
    final x = _f((0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047);
    final y = _f(0.2126729 * r + 0.7151522 * g + 0.0721750 * b);
    final z = _f((0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883);
    out[n] = 500 * (x - y);
    out[count + n] = 200 * (y - z);
  }
  return out;
}

/// Lightness of every pixel, and the model's input: that lightness alone, shrunk and turned back to RGB.
/// Null if the picture already has colour.
@visibleForTesting
Prepared? prepareColorInput(Uint8List rgba, int w, int h, int side) {
  final lightness = Float32List(w * h);
  var chroma = 0.0;
  final toLinear = Float64List(256);
  for (var i = 0; i < 256; i++) {
    toLinear[i] = _srgbToLinear(i / 255);
  }
  for (var i = 0, n = 0; n < w * h; i += 4, n++) {
    final r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
    chroma += max(r, max(g, b)) - min(r, min(g, b));
    final y = 0.2126729 * toLinear[r] + 0.7151522 * toLinear[g] + 0.0721750 * toLinear[b];
    lightness[n] = 116 * _f(y) - 16;
  }
  if (chroma / (w * h) > 14) return null;

  final input = Float32List(3 * side * side);
  final small = Float32List(side * side);
  for (var y = 0; y < side; y++) {
    final y0 = y * h ~/ side, y1 = max(y0 + 1, (y + 1) * h ~/ side);
    for (var x = 0; x < side; x++) {
      final x0 = x * w ~/ side, x1 = max(x0 + 1, (x + 1) * w ~/ side);
      var sum = 0.0;
      var count = 0;
      for (var yy = y0; yy < y1; yy += max(1, (y1 - y0) ~/ 4)) {
        for (var xx = x0; xx < x1; xx += max(1, (x1 - x0) ~/ 4)) {
          sum += lightness[yy * w + xx];
          count++;
        }
      }
      small[y * side + x] = sum / count;
    }
  }
  for (var n = 0; n < small.length; n++) {
    // With a = b = 0 the colour is neutral, so all three channels are the same.
    final v = _linearToSrgb(_fInv((small[n] + 16) / 116)).clamp(0.0, 1.0);
    input[n] = v;
    input[small.length + n] = v;
    input[2 * small.length + n] = v;
  }
  return Prepared(input, lightness, small, side);
}

/// Lines and screentones stay exactly where they are, because only colour is added around the original lightness.
@visibleForTesting
Uint8List mergeColor(Prepared prepared, Float32List ab, int w, int h, {bool protectWhites = true}) {
  final lightness = prepared.lightness;
  final side = prepared.side;
  final out = Uint8List(w * h * 4);
  final aChannel = ab.buffer.asFloat32List(ab.offsetInBytes, side * side);
  final bChannel = ab.buffer.asFloat32List(ab.offsetInBytes + side * side * 4, side * side);

  double sample(Float32List c, double x, double y) {
    final x0 = x.floor().clamp(0, side - 1), y0 = y.floor().clamp(0, side - 1);
    final x1 = min(x0 + 1, side - 1), y1 = min(y0 + 1, side - 1);
    final fx = (x - x0).clamp(0.0, 1.0), fy = (y - y0).clamp(0.0, 1.0);
    final top = c[y0 * side + x0] * (1 - fx) + c[y0 * side + x1] * fx;
    final bottom = c[y1 * side + x0] * (1 - fx) + c[y1 * side + x1] * fx;
    return top * (1 - fy) + bottom * fy;
  }

  (double, double, double) labToSrgb(double l, double a, double b) {
    final fy = (l + 16) / 116;
    final x = 0.95047 * _fInv(fy + a / 500), yy = _fInv(fy), z = 1.08883 * _fInv(fy - b / 200);
    return (
      _linearToSrgb((3.2404542 * x - 1.5371385 * yy - 0.4985314 * z).clamp(0.0, 1.0)),
      _linearToSrgb((-0.9692660 * x + 1.8760108 * yy + 0.0415560 * z).clamp(0.0, 1.0)),
      _linearToSrgb((0.0556434 * x - 0.2040259 * yy + 1.0572252 * z).clamp(0.0, 1.0)),
    );
  }

  // Everything that varies slowly is worked out once on the model's grid.
  // Paper, speech bubbles and solid blacks keep no colour. Judged on the blurred lightness: a screentone is
  // only black and white dots, yet it is a mid grey to the eye and should take colour like one.
  final count = side * side;
  final keptA = Float32List(count), keptB = Float32List(count);
  final tintR = Float32List(count), tintG = Float32List(count), tintB = Float32List(count);
  for (var n = 0; n < count; n++) {
    final seen = prepared.blurred[n];
    final keep = protectWhites ? ((97 - seen) / 12).clamp(0.0, 1.0) * ((seen - 4) / 10).clamp(0.0, 1.0) : 1.0;
    final a = aChannel[n] * keep, b = bChannel[n] * keep;
    keptA[n] = a;
    keptB[n] = b;
    final tone = seen.clamp(62.0, 90.0);
    final (r, g, bl) = labToSrgb(tone, a, b);
    final (grey, _, _) = labToSrgb(tone, 0, 0);
    tintR[n] = (r / grey).clamp(0.0, 1.6);
    tintG[n] = (g / grey).clamp(0.0, 1.6);
    tintB[n] = (bl / grey).clamp(0.0, 1.6);
  }
  final greyOf = Float32List(1001);
  for (var i = 0; i <= 1000; i++) {
    greyOf[i] = labToSrgb(i / 10, 0, 0).$1;
  }

  int byte(double v) => (v * 255).round().clamp(0, 255);

  for (var y = 0, i = 0, n = 0; y < h; y++) {
    final sy = (y + 0.5) * side / h - 0.5;
    for (var x = 0; x < w; x++, i += 4, n++) {
      final sx = (x + 0.5) * side / w - 0.5;
      final l = lightness[n];
      final grey = greyOf[(l * 10).round().clamp(0, 1000)];
      // Far from its surroundings a pixel is a dot or a line: tint it like ink on coloured paper, because
      // a pure white dot has no room for colour at its own lightness.
      final printed = (((l - sample(prepared.blurred, sx, sy)).abs()) / 25).clamp(0.0, 1.0);
      var r = grey * sample(tintR, sx, sy), g = grey * sample(tintG, sx, sy), b = grey * sample(tintB, sx, sy);
      if (printed < 1) {
        final (lr, lg, lb) = labToSrgb(l, sample(keptA, sx, sy), sample(keptB, sx, sy));
        r = lr + (r - lr) * printed;
        g = lg + (g - lg) * printed;
        b = lb + (b - lb) * printed;
      }
      out[i] = byte(r);
      out[i + 1] = byte(g);
      out[i + 2] = byte(b);
      out[i + 3] = 255;
    }
  }
  return out;
}
