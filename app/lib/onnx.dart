import 'dart:ffi';
import 'dart:io';
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

/// A named input tensor: a Float32List, or an Int64List for token ids.
class OnnxInput {
  OnnxInput(this.name, this.data, this.shape);
  final String name;
  final TypedData data;
  final List<int> shape;
}

class _Job {
  _Job(this.inputs, this.output, this.outputLength, this.skip, this.reply);
  final List<OnnxInput> inputs;
  final String output;
  final int outputLength, skip;
  final SendPort reply;
}

void _main((String, int, SendPort) start) {
  final (path, threads, ready) = start;
  // A test on a computer can point this at its own ONNX Runtime.
  final lib = DynamicLibrary.open(Platform.environment['EBR_ONNXRUNTIME'] ?? 'libonnxruntime.so');
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
  check(fn<_P Function(_P, Int32)>(_setThreads).asFunction<_P Function(_P, int)>()(options, threads));
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

  final jobs = ReceivePort();
  ready.send(jobs.sendPort);
  jobs.listen((message) {
    final job = message as _Job;
    final n = job.inputs.length;
    final names = calloc<Pointer<Utf8>>(n);
    final tensors = calloc<_P>(n);
    final outName = calloc<Pointer<Utf8>>()..value = job.output.toNativeUtf8();
    final result = calloc<_P>(), pointer = calloc<_P>();
    final buffers = <Pointer<Uint8>>[];
    final shapes = <Pointer<Int64>>[];
    try {
      for (var i = 0; i < n; i++) {
        final input = job.inputs[i];
        names[i] = input.name.toNativeUtf8();
        final bytes = input.data.buffer.asUint8List(input.data.offsetInBytes, input.data.lengthInBytes);
        final data = calloc<Uint8>(bytes.length);
        buffers.add(data);
        data.asTypedList(bytes.length).setAll(0, bytes);
        final shape = calloc<Int64>(input.shape.length);
        shapes.add(shape);
        for (var d = 0; d < input.shape.length; d++) {
          shape[d] = input.shape[d];
        }
        // ONNX element types: 1 is float, 7 is int64.
        check(createTensor(memory, data.cast(), bytes.length, shape, input.shape.length, input.data is Int64List ? 7 : 1, tensors + i));
      }
      check(run(session, nullptr, names, tensors, n, outName, 1, result));
      check(tensorData(result.value, pointer));
      job.reply.send(Float32List.fromList((pointer.value.cast<Float>() + job.skip).asTypedList(job.outputLength)));
      releaseValue(result.value);
    } catch (e) {
      job.reply.send('$e');
    } finally {
      for (var i = 0; i < buffers.length; i++) {
        if (tensors[i] != nullptr) releaseValue(tensors[i]);
        calloc.free(buffers[i]);
        calloc.free(shapes[i]);
      }
      calloc.free(names);
      calloc.free(tensors);
      calloc.free(outName);
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

  static Future<OnnxModel> open(String path, {int threads = 3}) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_main, (path, threads, ready.sendPort));
    return OnnxModel._(isolate, await ready.first as SendPort);
  }

  /// [outputLength] floats of [output], after the first [skip] of them.
  Future<Float32List> run(List<OnnxInput> inputs, String output, int outputLength, {int skip = 0}) async {
    final reply = ReceivePort();
    _jobs.send(_Job(inputs, output, outputLength, skip, reply.sendPort));
    final result = await reply.first;
    reply.close();
    if (result is String) throw StateError(result);
    return result as Float32List;
  }

  void close() => _isolate.kill(priority: Isolate.immediate);
}
