// "Kendi sesim": the chosen model voice speaks, then OpenVoice v2's tone colour converter (MIT, myshell-ai/OpenVoice)
// gives it the timbre of a recorded voice. The converter was exported to ONNX by memory/research/voiceclone/
// export_onnx.py: se.onnx (22.05 kHz wave -> 256-number speaker embedding) and vc.int8.onnx (wave, source and target
// embeddings -> wave, tau 0.3, STFT inside). Both run here on an isolate of their own.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'main.dart' show device, settings;
import 'onnx.dart';
import 'settings.dart';
import 'sources.dart' show SpokenSentence;
import 'tts.dart';

const cloneRate = 22050;
const _release = 'https://github.com/Ege-BULUT/EgeBookReader/releases/download/models-v1';
const _files = {'se.onnx': '$_release/openvoice-v2-se.onnx.gz', 'vc.onnx': '$_release/openvoice-v2-vc.int8.onnx.gz'};

final cloner = Cloner();

/// Text to read aloud while recording, about 30 seconds, with most of the language's sounds.
const readAloud = {
  'tr': 'Bir kitabı sesli okumak, onu yeniden yazmak gibidir. Her cümlede durur, kelimelerin tadına bakarız. '
      'Çocukken dedemin bahçesinde, incir ağacının gölgesinde masallar dinlerdim. Güneş batarken gökyüzü '
      'turuncuya, sonra mora döner; uzaktan bir vapur düdüğü duyulurdu. Şimdi aynı masalları ben okuyorum: '
      'yavaş, sakin ve gülümseyerek. Peki sen en çok hangi hikâyeyi seversin?',
  'en': 'Reading a book aloud is a little like writing it again. We pause at every sentence and taste the words. '
      'As a child I listened to stories in my grandfather\'s garden, under the shade of a fig tree. When the sun '
      'went down, the sky turned orange, then purple, and a ferry horn sounded far away. Now I read the same stories '
      'myself: slowly, calmly, and with a smile. So which story do you love the most?',
};

/// Resamples [x] from [from] Hz to [to] Hz: a windowed-sinc filter, one table per phase of the rational ratio.
Float32List resample(Float32List x, int from, int to) {
  if (from == to) return x;
  final g = from.gcd(to), up = to ~/ g, down = from ~/ g;
  final cutoff = min(1.0, to / from) * 0.95;
  final half = (16 / cutoff).ceil(), taps = 2 * half;
  final table = Float64List(up * taps);
  for (var ph = 0; ph < up; ph++) {
    for (var j = 0; j < taps; j++) {
      final d = ph / up + half - 1 - j; // distance from the output point to input sample j
      final window = d.abs() >= half ? 0.0 : 0.5 + 0.5 * cos(pi * d / half);
      table[ph * taps + j] = (d == 0 ? cutoff : sin(pi * cutoff * d) / (pi * d)) * window;
    }
  }
  final out = Float32List(x.length * up ~/ down);
  for (var i = 0; i < out.length; i++) {
    final pos = i * down, k0 = pos ~/ up - half + 1, row = pos % up * taps;
    var acc = 0.0;
    for (var j = max(0, -k0); j < taps && k0 + j < x.length; j++) {
      acc += x[k0 + j] * table[row + j];
    }
    out[i] = acc;
  }
  return out;
}

/// Where to cut [x] into pieces of at most [most] samples: the quietest spot of each piece's second half.
List<int> cutPoints(Float32List x, {int most = 8 * cloneRate}) {
  final cuts = [0];
  while (x.length - cuts.last > most) {
    final from = cuts.last + most ~/ 2, to = cuts.last + most;
    var best = to, quietest = double.infinity;
    for (var s = from; s + 1024 <= to; s += 256) {
      var e = 0.0;
      for (var i = s; i < s + 1024; i++) {
        e += x[i] * x[i];
      }
      if (e < quietest) {
        quietest = e;
        best = s + 512;
      }
    }
    cuts.add(best);
  }
  return cuts..add(x.length);
}

/// The samples and rate of a 16-bit mono WAV such as the voices make.
(Float32List, int) wavSamples(Uint8List wav) {
  final b = ByteData.sublistView(wav);
  final n = (wav.length - 44) ~/ 2;
  final x = Float32List(n);
  for (var i = 0; i < n; i++) {
    x[i] = b.getInt16(44 + i * 2, Endian.little) / 32768;
  }
  return (x, b.getUint32(24, Endian.little));
}

/// Raw 16-bit mono PCM, as the recorder writes it.
Float32List pcmSamples(Uint8List pcm) {
  final b = ByteData.sublistView(pcm);
  return Float32List.fromList([for (var i = 0; i + 1 < pcm.length; i += 2) b.getInt16(i, Endian.little) / 32768]);
}

typedef _Job = (Float32List samples, int rate, Float32List? source, Float32List? target, SendPort reply);

void _cloneMain((String, String, SendPort) start) {
  final (dir, library, ready) = start;
  final se = OnnxSession('$dir/se.onnx', threads: 2, library: library);
  final vc = OnnxSession('$dir/vc.onnx', threads: 2, library: library);
  final jobs = ReceivePort();
  ready.send(jobs.sendPort);
  jobs.listen((message) {
    final (samples, rate, source, target, reply) = message as _Job;
    try {
      reply.send(cloneWork(se, vc, samples, rate, source, target));
    } catch (e) {
      reply.send('$e');
    }
  });
}

/// The embedding of [samples] (no [source] given), or [samples] converted from [source]'s voice to [target]'s,
/// in pieces of at most 8 s: 22.05 kHz samples.
Float32List cloneWork(OnnxSession se, OnnxSession vc, Float32List samples, int rate, Float32List? source, Float32List? target) {
  var x = resample(samples, rate, cloneRate);
  if (x.length < 4096) x = Float32List(4096)..setAll(0, x); // the STFT inside needs a few frames
  if (source == null) return se.run([OnnxInput('wave', x, [1, x.length])], ['se'])['se']!.data;
  final cuts = cutPoints(x), out = BytesBuilder(copy: false);
  for (var i = 0; i + 1 < cuts.length; i++) {
    final piece = Float32List.sublistView(x, cuts[i], cuts[i + 1]);
    final padded = piece.length < 4096 ? (Float32List(4096)..setAll(0, piece)) : piece;
    final y = vc.run([
      OnnxInput('wave', padded, [1, padded.length]),
      OnnxInput('src_se', source, [1, 256, 1]),
      OnnxInput('tgt_se', target!, [1, 256, 1]),
    ], ['out'])['out']!.data;
    out.add(Float32List.fromList(y.sublist(0, min(y.length, piece.length))).buffer.asUint8List());
  }
  return out.takeBytes().buffer.asFloat32List();
}

/// A recorded voice, named by the reader.
class VoiceClone {
  VoiceClone(this.id, this.name, this.embedding);
  final String id, name;
  final Float32List embedding;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'se': embedding};
  static VoiceClone fromJson(Map<String, dynamic> j) =>
      VoiceClone(j['id'] as String, j['name'] as String, Float32List.fromList([for (final v in j['se'] as List) (v as num).toDouble()]));
}

/// The converter's files, the recorded voices, and the isolate that runs both.
class Cloner extends ChangeNotifier {
  double? progress;
  bool busy = false;
  String? error;
  SendPort? _jobs;
  Isolate? _isolate;

  Future<String> get _dir async => p.join((await getApplicationDocumentsDirectory()).path, 'voices', 'openvoice-v2');
  bool installed = false;

  Future<void> load() async => installed = File(p.join(await _dir, 'LICENSE')).existsSync();

  List<VoiceClone> get clones => [for (final j in settings.clones) VoiceClone.fromJson(j)];

  /// The voice the reader listens in now, if it is one of theirs.
  VoiceClone? get active {
    if (!installed || settings.cloneId == null) return null;
    return clones.where((c) => c.id == settings.cloneId).firstOrNull;
  }

  Future<void> download() async {
    if (busy) return;
    busy = true;
    error = null;
    progress = 0;
    notifyListeners();
    try {
      final dir = await Directory(await _dir).create(recursive: true);
      for (final (i, MapEntry(key: name, value: url)) in _files.entries.indexed) {
        await fetchFile(url, File(p.join(dir.path, name)), (f) {
          progress = (i + f) / _files.length;
          notifyListeners();
        });
      }
      await File(p.join(dir.path, 'LICENSE')).writeAsString('OpenVoice v2 tone colour converter, MIT\nhttps://github.com/myshell-ai/OpenVoice\n');
      installed = true;
    } catch (e) {
      debugPrint('converter download failed: $e');
      error = tr('Ses dönüştürücü indirilemedi. Bağlantını ve boş alanı kontrol et.');
    }
    busy = false;
    progress = null;
    notifyListeners();
  }

  Future<void> remove() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _jobs = null;
    final d = Directory(await _dir);
    if (d.existsSync()) await d.delete(recursive: true);
    installed = false;
    settings.update((x) => x.cloneId = null);
    notifyListeners();
  }

  Future<Float32List> _run(Float32List samples, int rate, [Float32List? source, Float32List? target]) async {
    if (_jobs == null) {
      final ready = ReceivePort();
      _isolate = await Isolate.spawn(_cloneMain, (await _dir, defaultOnnxLibrary, ready.sendPort));
      _jobs = await ready.first as SendPort;
    }
    final reply = ReceivePort();
    _jobs!.send((samples, rate, source, target, reply.sendPort));
    final result = await reply.first.timeout(const Duration(minutes: 2), onTimeout: () => 'timed out');
    reply.close();
    if (result is String) throw StateError(result);
    return result as Float32List;
  }

  /// Keeps a recorded voice as its embedding only; the recording itself is not kept.
  Future<VoiceClone> add(String name, Float32List samples, int rate) async {
    final clone = VoiceClone('${DateTime.now().millisecondsSinceEpoch}', name, await _run(samples, rate));
    settings.update((x) => x.clones = [...x.clones, clone.toJson()]);
    return clone;
  }

  void delete(VoiceClone c) {
    settings.update((x) {
      x.clones = [for (final j in x.clones) if (j['id'] != c.id) j];
      if (x.cloneId == c.id) x.cloneId = null;
    });
    notifyListeners();
  }

  /// Listens in [c], or in the plain voice again with null; the voice used before is remembered.
  void choose(VoiceClone? c) {
    settings.update((x) {
      if (c != null && x.cloneId == null) {
        x.voiceBeforeClone = x.voiceSource == VoiceSource.model && voices.selected != null ? '${x.ttsModelId}|${x.ttsVoice}' : 'system';
      }
      if (c != null) x.voiceSource = VoiceSource.model;
      x.cloneId = c?.id;
    });
  }

  /// The embedding of model voice [voice] of [m], made once from a sample it speaks.
  Future<Float32List> _source(VoiceModel m, int voice) async {
    final key = '${m.id}|${speaker.sidOf(m, voice)}';
    final kept = settings.voiceEmbeddings[key];
    if (kept != null) return Float32List.fromList(kept);
    final lang = m.languages.contains(uiLanguage) ? uiLanguage : m.languages.first;
    final text = readAloud[lang] ?? readAloud['en']!;
    final (x, rate) = wavSamples(await speaker.synthesize(SpokenSentence(text, lang, 0, const []), m, voice: voice, speed: 1, cloned: false));
    final se = await _run(x, rate);
    settings.update((s) => s.voiceEmbeddings[key] = se.toList());
    return se;
  }

  /// [wav] from voice [voice] of [m], spoken again in [c]'s voice: a 22.05 kHz WAV.
  Future<Uint8List> convert(Uint8List wav, VoiceModel m, int voice, VoiceClone c) async {
    final source = await _source(m, voice);
    final (x, rate) = wavSamples(wav);
    return wavBytes(await _run(x, rate, source, c.embedding), cloneRate);
  }
}

/// Records about 30 seconds of a voice, asks for consent, and keeps it as a voice to listen in.
class RecordVoiceSheet extends StatefulWidget {
  const RecordVoiceSheet({super.key});

  @override
  State<RecordVoiceSheet> createState() => _RecordVoiceSheetState();
}

class _RecordVoiceSheetState extends State<RecordVoiceSheet> {
  final _name = TextEditingController();
  bool recording = false, consent = false, saving = false;
  int seconds = 0;
  String? note;
  Timer? _clock;
  File? _file;

  @override
  void dispose() {
    _clock?.cancel();
    if (recording) device.invokeMethod('stopRecording');
    _file?.delete().ignore();
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _file = File(p.join((await getTemporaryDirectory()).path, 'voice-recording.pcm'));
    final ok = await device.invokeMethod<bool>('startRecording', _file!.path).catchError((_) => false);
    if (!mounted) return;
    if (ok != true) return setState(() => note = tr('Mikrofon kullanılamadı. İzin verdiğinden emin ol.'));
    setState(() {
      recording = true;
      seconds = 0;
      note = null;
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => seconds++);
      if (seconds >= 45) _stop();
    });
  }

  Future<void> _stop() async {
    _clock?.cancel();
    await device.invokeMethod('stopRecording');
    if (mounted) setState(() => recording = false);
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final x = pcmSamples(await _file!.readAsBytes());
      final clone = await cloner.add(_name.text.trim(), x, cloneRate);
      cloner.choose(clone);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('voice not kept: $e');
      if (mounted) setState(() => note = tr('Ses kaydedilemedi.'));
    }
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final ready = !recording && !saving && seconds >= 10 && consent && _name.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, max(MediaQuery.viewInsetsOf(context).bottom, MediaQuery.paddingOf(context).bottom) + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Sesini kaydet'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
          const SizedBox(height: 6),
          Text(tr('Sessiz bir yerde, telefonu ağzından bir karış uzakta tutup aşağıdaki metni rahatça oku. Yaklaşık 30 saniye yeter. Kayıt telefonda kalır; yalnızca sesin özeti saklanır.'),
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
            child: Text(readAloud[uiLanguage] ?? readAloud['en']!, style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 17, height: 1.5)),
          ),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton.icon(
              onPressed: saving ? null : (recording ? _stop : _start),
              icon: Icon(recording ? Icons.stop_rounded : Icons.mic_rounded),
              label: Text(tr(recording ? 'Durdur' : (seconds > 0 ? 'Yeniden kaydet' : 'Kayda başla'))),
              style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
            ),
            const SizedBox(width: 14),
            Text('$seconds ${tr('sn')}', style: TextStyle(color: c.ink, fontSize: 15, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note!, style: TextStyle(color: c.accent, fontSize: 13))),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: c.ink, fontSize: 15),
            decoration: InputDecoration(labelText: tr('Sesin adı (Annem, Ben…)'), isDense: true, labelStyle: TextStyle(color: c.muted)),
          ),
          CheckboxListTile(
            value: consent,
            onChanged: (v) => setState(() => consent = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: c.accent,
            title: Text(tr('Bu ses benim ya da sahibinin izni var'), style: TextStyle(color: c.ink, fontSize: 14)),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: ready ? _save : null,
              style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
              child: saving
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: c.paper))
                  : Text(tr('Sesi sakla')),
            ),
          ),
        ]),
      ),
    );
  }
}
