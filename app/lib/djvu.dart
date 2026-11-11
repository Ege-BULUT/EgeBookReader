import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';

import 'colorize.dart';
import 'sources.dart';

typedef _P = Pointer<Void>;

DynamicLibrary _lib() => DynamicLibrary.open('libebr_djvu.so');

/// A DjVu book drawn by DjVuLibre (`libebr_djvu.so`, see `android/app/src/main/cpp/djvu`). Each page is a picture.
/// Work runs on helper isolates one call at a time, because calls on one document must not overlap.
// ponytail: no text layer yet, so no reading aloud, search or contents; add them from ddjvu_document_get_pagetext and _get_outline.
class DjvuSource extends PageSource {
  DjvuSource._(this.title, this._path, this._doc, this._sizes);
  @override
  final String title;
  final String _path;
  final int _doc;
  final List<Size> _sizes;
  Future<void> _queue = Future.value();

  static Future<DjvuSource> open(String path, String title) async {
    final (doc, sizes) = await Isolate.run(() {
      final lib = _lib();
      final open = lib.lookupFunction<_P Function(Pointer<Utf8>), _P Function(Pointer<Utf8>)>('ebr_djvu_open');
      final pages = lib.lookupFunction<Int Function(_P), int Function(_P)>('ebr_djvu_pages');
      final size = lib.lookupFunction<Int Function(_P, Int, Pointer<Int>), int Function(_P, int, Pointer<Int>)>('ebr_djvu_size');
      final name = path.toNativeUtf8();
      final doc = open(name);
      calloc.free(name);
      if (doc == nullptr) throw const FormatException('Bu DjVu dosyası açılamadı.');
      final out = calloc<Int>(2);
      final sizes = <(int, int)>[];
      for (var i = 0, n = pages(doc); i < n; i++) {
        // A page that cannot be measured keeps the size of the one before, so the rest of the book still opens.
        sizes.add(size(doc, i, out) == 0 ? (out[0], out[1]) : (sizes.lastOrNull ?? (1700, 2200)));
      }
      calloc.free(out);
      return (doc.address, sizes);
    });
    if (sizes.isEmpty) throw const FormatException('Bu DjVu dosyasında sayfa yok.');
    return DjvuSource._(title, path, doc, [for (final (w, h) in sizes) Size(w.toDouble(), h.toDouble())]);
  }

  Future<T> _serial<T>(Future<T> Function() job) {
    final result = _queue.then((_) => job());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Page [index] as an image [width] x [height] pixels.
  Future<ui.Image> _render(int index, int width, int height) async {
    final doc = _doc;
    final pixels = await _serial(() => Isolate.run(() {
          final render = _lib().lookupFunction<Int Function(_P, Int, Int, Int, Pointer<Uint8>), int Function(_P, int, int, int, Pointer<Uint8>)>('ebr_djvu_render');
          final buffer = calloc<Uint8>(width * height * 4);
          try {
            if (render(Pointer.fromAddress(doc), index, width, height, buffer) != 0) throw const FormatException('Bu DjVu sayfası okunamadı.');
            return Uint8List.fromList(buffer.asTypedList(width * height * 4));
          } finally {
            calloc.free(buffer);
          }
        }));
    final done = Completer<ui.Image>();
    ui.decodeImageFromPixels(pixels, width, height, ui.PixelFormat.rgba8888, done.complete);
    return done.future;
  }

  /// Pixel size for page [index] fitted into [box] logical pixels at the screen's density.
  (int, int) _pixels(int index, Size box) {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final fit = applyBoxFit(BoxFit.contain, _sizes[index], box * dpr * renderScale).destination;
    return (fit.width.round().clamp(1, 8192), fit.height.round().clamp(1, 8192));
  }

  Rect _placed(int index, Size page) => Alignment.center.inscribe(applyBoxFit(BoxFit.contain, _sizes[index], page).destination, Offset.zero & page);

  @override
  int get pageCount => _sizes.length;

  @override
  Future<void> prepare(Size page, PageStyle style, {void Function(double)? onProgress}) async {}

  @override
  Future<void> paint(Canvas canvas, int index, Size page, PageStyle style) async {
    final (w, h) = _pixels(index, page);
    final image = await _render(index, w, h);
    final src = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    await drawBookImage(canvas, image, src, _placed(index, page), style, Paint()..filterQuality = FilterQuality.medium);
    image.dispose();
  }

  Future<Uint8List> _png(int index, Size box) async {
    final (w, h) = _pixels(index, box);
    final image = await _render(index, w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  @override
  Future<List<PageImage>> imagesOn(int index, Size page) async => [
        PageImage(contentId(Uint8List.fromList(utf8.encode('$_path#$index'))), _placed(index, page), () => _png(index, page)),
      ];

  @override
  Future<Uint8List?> coverBytes() => _png(0, const Size(400, 600));

  @override
  void dispose() {
    final doc = _doc;
    _serial(() async => _lib().lookupFunction<Void Function(_P), void Function(_P)>('ebr_djvu_close')(Pointer.fromAddress(doc)));
  }
}
