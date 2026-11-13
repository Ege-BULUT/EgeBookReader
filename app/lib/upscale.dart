import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'colorize.dart';
import 'onnx.dart';
import 'sources.dart' show headerSize;

final upscaler = Upscaler();

/// Downloaded and removed like a colorizer, through [colorizer]'s model store.
const upscaleModel = ColorModel(
  id: 'upscale',
  name: 'Real-ESRGAN animevideov3',
  description: 'Düşük çözünürlüklü çizgi roman ve manga sayfalarını yapay zekâyla büyütür.',
  sizeText: '2,5 MB',
  license: 'BSD-3-Clause, Xintao Wang',
  source: 'https://github.com/xinntao/Real-ESRGAN',
  url: 'https://github.com/Ege-BULUT/EgeBookReader/releases/download/models-v1/realesr-animevideov3-x4.onnx',
  file: 'upscale/realesr-animevideov3-x4.onnx',
  side: 128,
  version: 'esr1',
);

/// The model makes every pixel into 4 by 4.
const _k = 4;

/// Tiles are this big with this much overlap, so memory stays small whatever the picture's size.
const _core = 110, _pad = 18; // 18 is the model's reach, so tiles join exactly

const _device = MethodChannel('egebookreader/volume');

/// Makes small pictures sharp at the size they are shown, one at a time in the background.
class Upscaler {
  late Directory _out, _models;
  OnnxModel? _session;
  final _queue = Queue<(PageImage, int)>();
  final _state = <String, JobState>{};
  bool _pumping = false;

  /// Runs after a picture is finished, so a reader can redraw the page that shows it.
  void Function(String id)? onDone;

  Future<void> load() async {
    final docs = await getApplicationDocumentsDirectory();
    _models = Directory(p.join(docs.path, 'models'));
    _out = Directory(p.join(docs.path, 'upscaled'));
    await _out.create(recursive: true);
  }

  bool get ready => colorizer.isInstalled(upscaleModel);
  File fileFor(String id) => File(p.join(_out.path, '$id-${upscaleModel.version}.png'));
  bool hasResult(String id) => fileFor(id).existsSync();

  /// [width] is how many pixels wide the picture shows on screen.
  void enqueue(PageImage image, int width) {
    if (!ready || _state.containsKey(image.id) || hasResult(image.id)) return;
    _state[image.id] = JobState.waiting;
    _queue.add((image, width));
    _pump();
  }

  /// Drops work nobody is waiting for any more, when a book closes.
  void clearQueue() {
    for (final j in _queue) {
      _state.remove(j.$1.id);
    }
    _queue.clear();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    while (_queue.isNotEmpty) {
      final (image, width) = _queue.removeFirst();
      while (await _device.invokeMethod<bool>('shouldRest') ?? false) {
        await Future<void>.delayed(const Duration(seconds: 20));
      }
      _state[image.id] = JobState.running;
      final clock = Stopwatch()..start();
      try {
        final done = await _upscale(await image.bytes(), width, fileFor(image.id));
        _state[image.id] = done ? JobState.done : JobState.skipped;
        if (done) onDone?.call(image.id);
      } catch (e) {
        debugPrint('upscale failed: $e');
        _state[image.id] = JobState.failed;
      }
      // Rest as long as the work took, so the phone stays cool.
      if (_queue.isNotEmpty) await Future<void>.delayed(clock.elapsed);
    }
    _pumping = false;
  }

  /// False when the picture is already sharp enough, or too big to be worth it.
  Future<bool> _upscale(Uint8List encoded, int width, File out) async {
    final known = headerSize(encoded);
    if (known != null && (width < known.width * 1.2 || known.width * known.height > 2.5e6)) return false;
    final codec = await ui.instantiateImageCodec(encoded);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final w = frame.image.width, h = frame.image.height;
    final rgba = (await frame.image.toByteData())!.buffer.asUint8List();
    frame.image.dispose();
    final scale = min(_k.toDouble(), width / w);
    if (scale < 1.2 || w * h > 2.5e6) return false;
    final dw = (w * scale).round(), dh = (h * scale).round();
    final dst = Uint8List(dw * dh * 4);

    _session ??= await OnnxModel.open(p.join(_models.path, upscaleModel.file), threads: 2);
    for (var y = 0; y < h; y += _core) {
      for (var x = 0; x < w; x += _core) {
        final x0 = max(0, x - _pad), y0 = max(0, y - _pad);
        final tw = min(w, x + _core + _pad) - x0, th = min(h, y + _core + _pad) - y0;
        final output = await _session!.run([OnnxInput('input', tileInput(rgba, w, x0, y0, tw, th), [1, 3, th, tw])], 'output', 3 * th * _k * tw * _k);
        placeTile(output, _k, x0, y0, tw, th, x, y, min(w, x + _core), min(h, y + _core), dst, dw, scale);
      }
    }

    final buffer = await ui.ImmutableBuffer.fromUint8List(dst);
    final descriptor = ui.ImageDescriptor.raw(buffer, width: dw, height: dh, pixelFormat: ui.PixelFormat.rgba8888);
    final imageCodec = await descriptor.instantiateCodec();
    final result = await imageCodec.getNextFrame();
    final png = await result.image.toByteData(format: ui.ImageByteFormat.png);
    result.image.dispose();
    imageCodec.dispose();
    descriptor.dispose();
    buffer.dispose();
    await out.writeAsBytes(png!.buffer.asUint8List());
    return true;
  }
}

/// A [tw] by [th] tile of [rgba] (a picture [w] wide) at [x0], [y0], as the model takes it: planar RGB from 0 to 1.
@visibleForTesting
Float32List tileInput(Uint8List rgba, int w, int x0, int y0, int tw, int th) {
  final out = Float32List(3 * tw * th);
  final plane = tw * th;
  for (var y = 0; y < th; y++) {
    for (var x = 0; x < tw; x++) {
      final i = ((y0 + y) * w + x0 + x) * 4, n = y * tw + x;
      out[n] = rgba[i] / 255;
      out[plane + n] = rgba[i + 1] / 255;
      out[2 * plane + n] = rgba[i + 2] / 255;
    }
  }
  return out;
}

/// Writes the model's output for a tile ([k] times the tile at [x0], [y0]) into [dst], a picture [dw] wide at [scale]
/// times the source. Only the source box [cx0]..[cx1], [cy0]..[cy1] is written, so the overlap's seams are dropped;
/// each pixel is the average of the output pixels it covers.
@visibleForTesting
void placeTile(Float32List out, int k, int x0, int y0, int tw, int th, int cx0, int cy0, int cx1, int cy1, Uint8List dst, int dw, double scale) {
  final ow = tw * k, oh = th * k, plane = ow * oh;
  // Where each destination column starts and ends in the output, worked out once.
  final fromX = <int>[], toX = <int>[];
  final dx0 = (cx0 * scale).round(), dx1 = (cx1 * scale).round();
  for (var dx = dx0; dx < dx1; dx++) {
    final u0 = ((dx / scale - x0) * k).floor().clamp(0, ow - 1);
    fromX.add(u0);
    toX.add(max(u0 + 1, (((dx + 1) / scale - x0) * k).floor().clamp(0, ow)));
  }
  for (var dy = (cy0 * scale).round(); dy < (cy1 * scale).round(); dy++) {
    final v0 = ((dy / scale - y0) * k).floor().clamp(0, oh - 1);
    final v1 = max(v0 + 1, (((dy + 1) / scale - y0) * k).floor().clamp(0, oh));
    for (var c = 0; c < fromX.length; c++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var v = v0; v < v1; v++) {
        for (var u = fromX[c]; u < toX[c]; u++) {
          final n = v * ow + u;
          r += out[n];
          g += out[plane + n];
          b += out[2 * plane + n];
        }
      }
      final count = (v1 - v0) * (toX[c] - fromX[c]);
      final i = (dy * dw + dx0 + c) * 4;
      dst[i] = (r / count * 255).round().clamp(0, 255);
      dst[i + 1] = (g / count * 255).round().clamp(0, 255);
      dst[i + 2] = (b / count * 255).round().clamp(0, 255);
      dst[i + 3] = 255;
    }
  }
}
