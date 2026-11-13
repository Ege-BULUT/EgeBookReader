import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// A small door into ONNX Runtime's C API. The voices (sherpa-onnx) already ship libonnxruntime.so, and a second
// copy through a plugin cannot be loaded beside it, so the colorizer and the Turkish voices use that same library.
// Indices are positions in the OrtApi struct of ORT 1.28; the struct only ever grows at the end.
const _createEnv = 3, _createSession = 7, _run = 9, _createOptions = 10, _setThreads = 24;
const _createTensor = 49, _tensorData = 51, _dimensionsCount = 61, _dimensions = 62, _elementCount = 64;
const _typeAndShape = 65, _cpuMemory = 69, _getErrorMessage = 2, _releaseStatus = 93;
const _releaseValue = 96, _releaseTypeAndShape = 99, _releaseOptions = 100;

/// The library's file name on Android; tests point it at a desktop build.
const defaultOnnxLibrary = 'libonnxruntime.so';

final class _ApiBase extends Struct {
  external Pointer<NativeFunction<Pointer<Pointer<Void>> Function(Uint32)>> getApi;
}

typedef _P = Pointer<Void>;

/// A named input tensor: a Float32List, or an Int64List for token ids and indices.
class OnnxInput {
  OnnxInput(this.name, this.data, this.shape);
  final String name;
  final TypedData data;
  final List<int> shape;
}

/// A float output and its shape.
class OnnxOutput {
  OnnxOutput(this.data, this.shape);
  final Float32List data;
  final List<int> shape;
}

/// The C functions, bound once per isolate.
class _Ort {
  _Ort(String library) {
    final lib = DynamicLibrary.open(library);
    final base = lib.lookupFunction<Pointer<_ApiBase> Function(), Pointer<_ApiBase> Function()>('OrtGetApiBase')();
    final api = base.ref.getApi.asFunction<Pointer<Pointer<Void>> Function(int)>()(20);
    Pointer<NativeFunction<T>> fn<T extends Function>(int i) => api[i].cast();
    errorMessage = fn<Pointer<Utf8> Function(_P)>(_getErrorMessage).asFunction();
    releaseStatus = fn<Void Function(_P)>(_releaseStatus).asFunction();
    createEnv = fn<_P Function(Int32, Pointer<Utf8>, Pointer<_P>)>(_createEnv).asFunction();
    createOptions = fn<_P Function(Pointer<_P>)>(_createOptions).asFunction();
    setThreads = fn<_P Function(_P, Int32)>(_setThreads).asFunction();
    createSession = fn<_P Function(_P, Pointer<Utf8>, _P, Pointer<_P>)>(_createSession).asFunction();
    cpuMemory = fn<_P Function(Int32, Int32, Pointer<_P>)>(_cpuMemory).asFunction();
    createTensor = fn<_P Function(_P, _P, Size, Pointer<Int64>, Size, Int32, Pointer<_P>)>(_createTensor).asFunction();
    run = fn<_P Function(_P, _P, Pointer<Pointer<Utf8>>, Pointer<_P>, Size, Pointer<Pointer<Utf8>>, Size, Pointer<_P>)>(_run).asFunction();
    tensorData = fn<_P Function(_P, Pointer<_P>)>(_tensorData).asFunction();
    typeAndShape = fn<_P Function(_P, Pointer<_P>)>(_typeAndShape).asFunction();
    dimensionsCount = fn<_P Function(_P, Pointer<Size>)>(_dimensionsCount).asFunction();
    dimensions = fn<_P Function(_P, Pointer<Int64>, Size)>(_dimensions).asFunction();
    elementCount = fn<_P Function(_P, Pointer<Size>)>(_elementCount).asFunction();
    releaseTypeAndShape = fn<Void Function(_P)>(_releaseTypeAndShape).asFunction();
    releaseValue = fn<Void Function(_P)>(_releaseValue).asFunction();
    releaseOptions = fn<Void Function(_P)>(_releaseOptions).asFunction();
    final out = calloc<_P>();
    check(createEnv(3, 'ebr'.toNativeUtf8(), out));
    env = out.value;
    check(cpuMemory(1, 0, out));
    memory = out.value;
    calloc.free(out);
  }

  static _Ort? _instance;
  static _Ort of(String library) => _instance ??= _Ort(library);

  late final Pointer<Utf8> Function(_P) errorMessage;
  late final void Function(_P) releaseStatus, releaseTypeAndShape, releaseValue, releaseOptions;
  late final _P Function(int, Pointer<Utf8>, Pointer<_P>) createEnv;
  late final _P Function(Pointer<_P>) createOptions;
  late final _P Function(_P, int) setThreads;
  late final _P Function(_P, Pointer<Utf8>, _P, Pointer<_P>) createSession;
  late final _P Function(int, int, Pointer<_P>) cpuMemory;
  late final _P Function(_P, _P, int, Pointer<Int64>, int, int, Pointer<_P>) createTensor;
  late final _P Function(_P, _P, Pointer<Pointer<Utf8>>, Pointer<_P>, int, Pointer<Pointer<Utf8>>, int, Pointer<_P>) run;
  late final _P Function(_P, Pointer<_P>) tensorData, typeAndShape;
  late final _P Function(_P, Pointer<Size>) dimensionsCount, elementCount;
  late final _P Function(_P, Pointer<Int64>, int) dimensions;
  late final _P env, memory;

  void check(_P status) {
    if (status == nullptr) return;
    final message = errorMessage(status).toDartString();
    releaseStatus(status);
    throw StateError(message);
  }
}

/// One loaded graph, run synchronously on the calling isolate. Keep it off the UI isolate.
class OnnxSession {
  OnnxSession(String path, {int threads = 3, String library = defaultOnnxLibrary}) : _ort = _Ort.of(library) {
    final out = calloc<_P>();
    try {
      _ort.check(_ort.createOptions(out));
      final options = out.value;
      _ort.check(_ort.setThreads(options, threads));
      _ort.check(_ort.createSession(_ort.env, path.toNativeUtf8(), options, out));
      _ort.releaseOptions(options);
      _session = out.value;
    } finally {
      calloc.free(out);
    }
  }

  final _Ort _ort;
  late final _P _session;

  Map<String, OnnxOutput> run(List<OnnxInput> inputs, List<String> outputs) {
    final o = _ort;
    final n = inputs.length, m = outputs.length;
    final names = calloc<Pointer<Utf8>>(n), outNames = calloc<Pointer<Utf8>>(m);
    final tensors = calloc<_P>(n), results = calloc<_P>(m);
    final pointer = calloc<_P>(), info = calloc<_P>(), count = calloc<Size>();
    final owned = <Pointer>[];
    try {
      for (var i = 0; i < n; i++) {
        final input = inputs[i];
        names[i] = input.name.toNativeUtf8();
        final bytes = input.data.lengthInBytes;
        final data = calloc<Uint8>(bytes);
        owned.add(data);
        data.asTypedList(bytes).setAll(0, input.data.buffer.asUint8List(input.data.offsetInBytes, bytes));
        final shape = calloc<Int64>(input.shape.length);
        owned.add(shape);
        shape.asTypedList(input.shape.length).setAll(0, input.shape);
        final type = input.data is Int64List ? 7 : 1; // ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64 / FLOAT
        o.check(o.createTensor(o.memory, data.cast(), bytes, shape, input.shape.length, type, tensors + i));
      }
      for (var i = 0; i < m; i++) {
        outNames[i] = outputs[i].toNativeUtf8();
      }
      o.check(o.run(_session, nullptr, names, tensors, n, outNames, m, results));
      final answer = <String, OnnxOutput>{};
      for (var i = 0; i < m; i++) {
        o.check(o.typeAndShape(results[i], info));
        o.check(o.dimensionsCount(info.value, count));
        final rank = count.value;
        final dims = calloc<Int64>(rank);
        o.check(o.dimensions(info.value, dims, rank));
        final shape = List<int>.of(dims.asTypedList(rank));
        calloc.free(dims);
        o.check(o.elementCount(info.value, count));
        final length = count.value;
        o.releaseTypeAndShape(info.value);
        o.check(o.tensorData(results[i], pointer));
        answer[outputs[i]] = OnnxOutput(Float32List.fromList(pointer.value.cast<Float>().asTypedList(length)), shape);
      }
      return answer;
    } finally {
      for (var i = 0; i < n; i++) {
        if (tensors[i] != nullptr) o.releaseValue(tensors[i]);
        if (names[i] != nullptr) calloc.free(names[i]);
      }
      for (var i = 0; i < m; i++) {
        if (results[i] != nullptr) o.releaseValue(results[i]);
        if (outNames[i] != nullptr) calloc.free(outNames[i]);
      }
      owned.forEach(calloc.free);
      for (final p in [names, outNames, tensors, results, pointer, info, count]) {
        calloc.free(p);
      }
    }
  }

}

class _Job {
  _Job(this.inputs, this.output, this.reply);
  final List<OnnxInput> inputs;
  final String output;
  final SendPort reply;
}

void _main((String, int, SendPort) start) {
  final (path, threads, ready) = start;
  // A test on a computer can point this at its own ONNX Runtime.
  final session = OnnxSession(path, threads: threads, library: Platform.environment['EBR_ONNXRUNTIME'] ?? defaultOnnxLibrary);
  final jobs = ReceivePort();
  ready.send(jobs.sendPort);
  jobs.listen((message) {
    final job = message as _Job;
    try {
      job.reply.send(session.run(job.inputs, [job.output])[job.output]!.data);
    } catch (e) {
      job.reply.send('$e');
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
    _jobs.send(_Job(inputs, output, reply.sendPort));
    final result = await reply.first;
    reply.close();
    if (result is String) throw StateError(result);
    return Float32List.sublistView(result as Float32List, skip, skip + outputLength);
  }

  void close() => _isolate.kill(priority: Isolate.immediate);
}
