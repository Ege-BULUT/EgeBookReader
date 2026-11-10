import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// A small door into ONNX Runtime's C API. The voices (sherpa-onnx) already ship libonnxruntime.so, and a second
// copy through a plugin cannot be loaded beside it, so the colorizer uses that same library directly.
// Indices are positions in the OrtApi struct of ORT 1.28; the struct only ever grows at the end.
const _createEnv = 3, _createSession = 7, _run = 9, _createOptions = 10, _setThreads = 24;
const _createTensor = 49, _tensorData = 51, _cpuMemory = 69;
const _getErrorMessage = 2, _releaseStatus = 93, _releaseValue = 96;

final class _ApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>> getApi;
}

typedef _P = Pointer<Void>;

class _Job {
  _Job(this.input, this.shape, this.reply);
  final Float32List input;
  final List<int> shape;
  final SendPort reply;
}

void _main((String, SendPort) start) {
  final (path, ready) = start;
  final lib = DynamicLibrary.open('libonnxruntime.so');
  final base = lib.lookupFunction<Pointer<_ApiBase> Function(), Pointer<_ApiBase> Function()>('OrtGetApiBase')();
  final api = base.ref.getApi.asFunction<Pointer<Pointer<Void>> Function(int)>()(20);
  Pointer<NativeFunction<T>> fn<T extends Function>(int i) => api[i].cast();

  final errorMessage = fn<Pointer<Utf8> Function(_P)>(_getErrorMessage).asFunction<Pointer<Utf8> Function(_P)>();
  final releaseStatus = fn<Void Function(_P)>(_releaseStatus).asFunction<void Function(_P)>();
  void check(_P status) {
    if (status == nullptr) return;
    final message = errorMessage(status).toDartString();
    releaseStatus(status);
    throw StateError(message);
  }

  final out = calloc<_P>();
  check(fn<_P Function(Int32, Pointer<Utf8>, Pointer<_P>)>(_createEnv).asFunction<_P Function(int, Pointer<Utf8>, Pointer<_P>)>()(3, 'ebr'.toNativeUtf8(), out));
  final env = out.value;
  check(fn<_P Function(Pointer<_P>)>(_createOptions).asFunction<_P Function(Pointer<_P>)>()(out));
  final options = out.value;
  check(fn<_P Function(_P, Int32)>(_setThreads).asFunction<_P Function(_P, int)>()(options, 3));
  check(fn<_P Function(_P, Pointer<Utf8>, _P, Pointer<_P>)>(_createSession).asFunction<_P Function(_P, Pointer<Utf8>, _P, Pointer<_P>)>()(env, path.toNativeUtf8(), options, out));
  final session = out.value;
  check(fn<_P Function(Int32, Int32, Pointer<_P>)>(_cpuMemory).asFunction<_P Function(int, int, Pointer<_P>)>()(1, 0, out));
  final memory = out.value;

  final createTensor = fn<_P Function(_P, _P, Size, Pointer<Int64>, Size, Int32, Pointer<_P>)>(_createTensor)
      .asFunction<_P Function(_P, _P, int, Pointer<Int64>, int, int, Pointer<_P>)>();
  final run = fn<_P Function(_P, _P, Pointer<Pointer<Utf8>>, Pointer<_P>, Size, Pointer<Pointer<Utf8>>, Size, Pointer<_P>)>(_run)
      .asFunction<_P Function(_P, _P, Pointer<Pointer<Utf8>>, Pointer<_P>, int, Pointer<Pointer<Utf8>>, int, Pointer<_P>)>();
  final tensorData = fn<_P Function(_P, Pointer<_P>)>(_tensorData).asFunction<_P Function(_P, Pointer<_P>)>();
  final releaseValue = fn<Void Function(_P)>(_releaseValue).asFunction<void Function(_P)>();

  final inName = calloc<Pointer<Utf8>>()..value = 'image'.toNativeUtf8();
  final outName = calloc<Pointer<Utf8>>()..value = 'output'.toNativeUtf8();

  final jobs = ReceivePort();
  ready.send(jobs.sendPort);
  jobs.listen((message) {
    final job = message as _Job;
    final data = calloc<Float>(job.input.length);
    final shape = calloc<Int64>(job.shape.length);
    final tensor = calloc<_P>(), result = calloc<_P>(), pointer = calloc<_P>();
    try {
      data.asTypedList(job.input.length).setAll(0, job.input);
      for (var i = 0; i < job.shape.length; i++) {
        shape[i] = job.shape[i];
      }
      check(createTensor(memory, data.cast(), job.input.length * 4, shape, job.shape.length, 1, tensor));
      check(run(session, nullptr, inName, tensor, 1, outName, 1, result));
      check(tensorData(result.value, pointer));
      job.reply.send(Float32List.fromList(pointer.value.cast<Float>().asTypedList(2 * 256 * 256)));
      releaseValue(result.value);
      releaseValue(tensor.value);
    } catch (e) {
      job.reply.send('$e');
    } finally {
      calloc.free(data);
      calloc.free(shape);
      calloc.free(tensor);
      calloc.free(result);
      calloc.free(pointer);
    }
  });
}

/// One model, loaded on its own isolate so inference never touches the UI thread.
class OnnxModel {
  OnnxModel._(this._isolate, this._jobs);
  final Isolate _isolate;
  final SendPort _jobs;

  static Future<OnnxModel> open(String path) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_main, (path, ready.sendPort));
    return OnnxModel._(isolate, await ready.first as SendPort);
  }

  Future<Float32List> run(Float32List input, List<int> shape) async {
    final reply = ReceivePort();
    _jobs.send(_Job(input, shape, reply.sendPort));
    final result = await reply.first;
    reply.close();
    if (result is String) throw StateError(result);
    return result as Float32List;
  }

  void close() => _isolate.kill(priority: Isolate.immediate);
}
