import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'l10n.dart';
import 'main.dart' show settings;
import 'natural.dart';
import 'settings.dart';
import 'sources.dart';
import 'voiceclone.dart';

final speaker = Speaker();
final voices = VoiceStore();

const languageNames = {
  'ar': 'Arapça', 'bg': 'Bulgarca', 'cs': 'Çekçe', 'da': 'Danca', 'de': 'Almanca', 'el': 'Yunanca', 'en': 'İngilizce',
  'es': 'İspanyolca', 'et': 'Estonca', 'fi': 'Fince', 'fr': 'Fransızca', 'hi': 'Hintçe', 'hr': 'Hırvatça', 'hu': 'Macarca',
  'id': 'Endonezce', 'it': 'İtalyanca', 'ja': 'Japonca', 'ko': 'Korece', 'lt': 'Litvanca', 'lv': 'Letonca', 'nl': 'Felemenkçe',
  'pl': 'Lehçe', 'pt': 'Portekizce', 'ro': 'Romence', 'ru': 'Rusça', 'sk': 'Slovakça', 'sl': 'Slovence', 'sv': 'İsveççe',
  'tr': 'Türkçe', 'uk': 'Ukraynaca', 'vi': 'Vietnamca', 'zh': 'Çince',
};

/// A voice that can be downloaded. See memory/research/tts.md for why these and not others.
class VoiceModel {
  const VoiceModel({
    required this.id,
    required this.name,
    required this.size,
    required this.languages,
    required this.voiceCount,
    required this.license,
    required this.source,
    this.women = 0,
    this.files,
  });
  final String id, name, size, license, source;
  final List<String> languages;
  final int voiceCount;

  /// How many of the voices are women's, counted from the first (Supertonic has an order of its own).
  final int women;

  /// Graphs fetched one by one (saved under the key) instead of a sherpa-onnx archive; run by lib/natural.dart.
  final Map<String, String>? files;

  String get url => 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$id.tar.bz2';
  bool get isSupertonic => id.contains('supertonic');
}

/// Supertonic's voices with the best-sounding ones first (the model's own numbers are these plus one).
const supertonicOrder = [4, 8, 9, 3, 0, 1, 2, 5, 6, 7];

/// "Kadın 2", "Erkek 1"…: voice [i] of [m] named by whether it is a woman's or a man's, counted in that group.
/// Supertonic's styles 0–4 are women and 5–9 men; Kokoro 1.1's speakers 0–57 are women and 58–102 men.
String voiceLabel(VoiceModel m, int i) {
  bool woman(int j) => m.isSupertonic ? supertonicOrder[j] < 5 : j < m.women;
  final n = [for (var j = 0; j <= i; j++) j].where((j) => woman(j) == woman(i)).length;
  return '${tr(woman(i) ? 'Kadın' : 'Erkek')} $n';
}

const voiceCatalog = [
  VoiceModel(
    id: 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11',
    name: 'Supertonic 3',
    size: '122 MB',
    languages: ['tr', 'en', 'hi', 'de', 'fr', 'ru', 'ja', 'ko', 'es', 'ar', 'pt', 'it', 'nl', 'pl', 'uk', 'vi', 'id', 'sv', 'da', 'fi', 'el', 'cs', 'hu', 'ro', 'bg', 'hr', 'sk', 'sl', 'et', 'lv', 'lt'],
    voiceCount: 10,
    license: 'Kod MIT, model OpenRAIL-M',
    source: 'https://github.com/supertone-oss-archive/supertonic',
  ),
  VoiceModel(
    id: 'kokoro-int8-multi-lang-v1_1',
    name: 'Kokoro 1.1',
    size: '140 MB',
    languages: ['en', 'zh'],
    voiceCount: 103,
    women: 58,
    license: 'Apache-2.0',
    source: 'https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh',
  ),
  VoiceModel(
    id: 'antalia-2-mini-int8',
    name: 'Antalia-2 Mini',
    size: '10 MB',
    languages: ['tr'],
    voiceCount: 1,
    license: 'Apache-2.0, PatientDesk AI',
    source: 'https://huggingface.co/cloud0day3/antalia-mini',
    files: {
      'text.onnx': '$_antalia/text.int8.onnx',
      'cond.onnx': '$_antalia/cond.onnx',
      'flow.onnx': '$_antalia/flow.int8.onnx',
      'vocoder.onnx': '$_antalia/vocoder.int8.onnx',
    },
  ),
  VoiceModel(
    id: 'ahenk-cep-int8',
    name: 'Ahenk Cep',
    size: '13 MB',
    languages: ['tr'],
    voiceCount: 1,
    women: 1,
    license: 'CC BY 4.0. Atıf: Ahenk Cep, Ahenk (github.com/ozguradmin/ahenk-turkish-tts); EMA Lightning (Apache-2.0); Alania verileri, PatientDesk AI (CC BY 4.0)',
    source: 'https://huggingface.co/ozgurguler/ahenk-cep-tr',
    files: {
      'text.onnx': '$_ahenk/text.int8.onnx',
      'cond.onnx': '$_ahenk/cond.int8.onnx',
      'step.onnx': '$_ahenk/step.int8.onnx',
      'decoder.onnx': '$_ahenk/decoder.f16.onnx',
    },
  ),
];

// Pinned to the commits whose graphs were checked (memory/research/tts.md).
const _antalia = 'https://huggingface.co/spaces/cloud0day3/antalia-mini/resolve/e7e3b1e3e83db5ca4cad925cc6d2563766e763e9/models';
const _ahenk = 'https://huggingface.co/ozgurguler/ahenk-cep-tr/resolve/345c4cbb934815fa96ffd0d5061fd913237544bc/onnx';

class VoiceStore extends ChangeNotifier {
  late Directory _dir;
  final progress = <String, double?>{};
  String? error;

  Future<void> load() async {
    _dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'voices'));
    await _dir.create(recursive: true);
  }

  String dirOf(VoiceModel m) => p.join(_dir.path, m.id);
  bool installed(VoiceModel m) => File(p.join(dirOf(m), 'LICENSE')).existsSync();

  Future<void> download(VoiceModel m) async {
    if (progress.containsKey(m.id)) return;
    error = null;
    progress[m.id] = 0;
    notifyListeners();
    try {
      await (m.files != null ? _fetchFiles(m) : _fetchArchive(m));
    } catch (e) {
      debugPrint('voice download failed: $e');
      error = tr('Ses modeli indirilemedi. Bağlantını ve boş alanı kontrol et.');
    }
    progress.remove(m.id);
    notifyListeners();
  }

  Future<void> _fetchArchive(VoiceModel m) async {
    final archive = File(p.join(_dir.path, '${m.id}.tar.bz2'));
    try {
      await fetchFile(m.url, archive, (f) {
        progress[m.id] = f;
        notifyListeners();
      });
      progress[m.id] = null; // unpacking has no percentage
      notifyListeners();
      final to = _dir.path, tar = '${archive.path}.tar';
      // extractFileToDisk unpacks bzip2 through the system temp folder, which Android does not have.
      await Isolate.run(() async {
        final input = InputFileStream(archive.path);
        final output = OutputFileStream(tar);
        BZip2Decoder().decodeStream(input, output);
        await input.close();
        await output.close();
        await extractFileToDisk(tar, to);
      });
    } finally {
      if (archive.existsSync()) await archive.delete();
      final leftover = File('${archive.path}.tar');
      if (leftover.existsSync()) await leftover.delete();
    }
  }

  /// Each graph into the model's folder; the LICENSE file, written last, marks it installed.
  Future<void> _fetchFiles(VoiceModel m) async {
    final dir = await Directory(dirOf(m)).create(recursive: true);
    final files = m.files!;
    for (final (i, MapEntry(key: name, value: url)) in files.entries.indexed) {
      await fetchFile(url, File(p.join(dir.path, name)), (f) {
        progress[m.id] = (i + f) / files.length;
        notifyListeners();
      });
    }
    await File(p.join(dir.path, 'LICENSE')).writeAsString('${m.name}\n${m.license}\n${m.source}\n');
  }

  Future<void> remove(VoiceModel m) async {
    await speaker.releaseModel();
    final d = Directory(dirOf(m));
    if (d.existsSync()) await d.delete(recursive: true);
    if (settings.ttsModelId == m.id) settings.update((x) => x.ttsModelId = null);
    notifyListeners();
  }

  VoiceModel? get selected {
    for (final m in voiceCatalog) {
      if (m.id == settings.ttsModelId && installed(m)) return m;
    }
    return null;
  }
}

/// Downloads [url] to [to] through a .part file; a .gz URL is unpacked on the way.
Future<void> fetchFile(String url, File to, void Function(double) onProgress) async {
  final client = HttpClient();
  final part = File('${to.path}.part');
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    var got = 0;
    final counted = response.map((chunk) {
      got += chunk.length;
      if (response.contentLength > 0) onProgress(got / response.contentLength);
      return chunk;
    });
    await (url.endsWith('.gz') ? counted.transform(gzip.decoder) : counted).pipe(part.openWrite());
    await part.rename(to.path);
  } finally {
    client.close();
    if (part.existsSync()) await part.delete();
  }
}

class _SynthJob {
  _SynthJob(this.text, this.sid, this.speed, this.lang, this.reply);
  final String text;
  final int sid;
  final double speed;
  final String? lang;
  final SendPort reply;
}

/// Synthesis blocks for seconds, so the model lives on an isolate of its own.
void _synthMain((VoiceModel, String, SendPort) start) {
  final (model, d, ready) = start;
  if (model.files != null) return _naturalMain(model, d, ready);
  sherpa.initBindings();
  final sherpa.OfflineTtsModelConfig config;
  if (model.isSupertonic) {
    config = sherpa.OfflineTtsModelConfig(
      numThreads: 2,
      supertonic: sherpa.OfflineTtsSupertonicModelConfig(
        durationPredictor: '$d/duration_predictor.int8.onnx',
        textEncoder: '$d/text_encoder.int8.onnx',
        vectorEstimator: '$d/vector_estimator.int8.onnx',
        vocoder: '$d/vocoder.int8.onnx',
        ttsJson: '$d/tts.json',
        unicodeIndexer: '$d/unicode_indexer.bin',
        voiceStyle: '$d/voice.bin',
      ),
    );
  } else {
    config = sherpa.OfflineTtsModelConfig(
      numThreads: 2,
      kokoro: sherpa.OfflineTtsKokoroModelConfig(
        model: '$d/model.int8.onnx',
        voices: '$d/voices.bin',
        tokens: '$d/tokens.txt',
        lexicon: '$d/lexicon-us-en.txt,$d/lexicon-zh.txt',
      ),
    );
  }
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(model: config));
  final jobs = ReceivePort();
  ready.send(jobs.sendPort);
  jobs.listen((message) {
    final job = message as _SynthJob;
    try {
      final audio = tts.generateWithConfig(
        text: job.text,
        config: sherpa.OfflineTtsGenerationConfig(
          sid: job.sid,
          speed: job.speed,
          extra: model.isSupertonic ? {'lang': job.lang ?? 'na'} : const {},
        ),
      );
      job.reply.send(wavBytes(audio.samples, audio.sampleRate));
    } catch (e) {
      job.reply.send('$e');
    }
  });
}

/// The Turkish voices of lib/natural.dart, on the same kind of isolate.
void _naturalMain(VoiceModel model, String d, SendPort ready) {
  final Float32List Function(String, {double speed}) say;
  if (model.id.startsWith('antalia')) {
    say = Antalia(d).say;
  } else {
    say = AhenkCep(d).say;
  }
  final jobs = ReceivePort();
  ready.send(jobs.sendPort);
  jobs.listen((message) {
    final job = message as _SynthJob;
    try {
      job.reply.send(wavBytes(say(job.text, speed: job.speed), naturalRate));
    } catch (e) {
      job.reply.send('$e');
    }
  });
}

/// A 16-bit mono WAV of [samples].
Uint8List wavBytes(Float32List samples, int rate) {
  final bytes = ByteData(44 + samples.length * 2);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      bytes.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 36 + samples.length * 2, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, rate, Endian.little);
  bytes.setUint32(28, rate * 2, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// Positions within one page's sentences: how far along, and which word is at a spot.
class SpeechMap {
  SpeechMap(this.sentences) {
    var sum = 0;
    for (final s in sentences) {
      _before.add(sum);
      sum += s.text.length + 1;
    }
    total = sum;
  }

  final List<SpokenSentence> sentences;
  final _before = <int>[];
  late final int total;

  double progress(int sentence, int char) {
    if (total == 0 || sentence >= sentences.length) return sentences.isEmpty ? 0 : 1;
    return ((_before[sentence] + char) / total).clamp(0.0, 1.0);
  }

  /// The last word that starts at or before [char].
  int wordAt(SpokenSentence s, int char) {
    var found = 0;
    for (var i = 0; i < s.words.length && s.words[i].start <= char; i++) {
      found = i;
    }
    return found;
  }

  /// The sentence and word at [fraction] of the page.
  (int, int) locate(double fraction) {
    final target = (fraction.clamp(0.0, 1.0) * total).floor();
    var i = sentences.length - 1;
    while (i > 0 && _before[i] > target) {
      i--;
    }
    return (i, wordAt(sentences[i], target - _before[i]));
  }

  /// The word nearest to [at] on [page]. Height counts for more, so the finger stays on its line.
  (int, int)? nearest(int page, Offset at) {
    (int, int)? best;
    var bestDistance = double.infinity;
    for (final (i, s) in sentences.indexed) {
      if (s.page != page) continue;
      for (final (w, word) in s.words.indexed) {
        for (final r in word.boxes) {
          final dx = at.dx < r.left ? r.left - at.dx : (at.dx > r.right ? at.dx - r.right : 0.0);
          final dy = at.dy < r.top ? r.top - at.dy : (at.dy > r.bottom ? at.dy - r.bottom : 0.0);
          final d = dx * dx + 9 * dy * dy;
          if (d < bestDistance) {
            bestDistance = d;
            best = (i, w);
          }
        }
      }
    }
    return best;
  }
}

/// Reads a list of sentences aloud through whichever voice is chosen, one at a time.
class Speaker extends ChangeNotifier {
  final _system = FlutterTts();
  // The reading service holds the audio focus (music ducks under the voice), so the player asks for none itself.
  final _player = AudioPlayer()
    ..setAudioContext(AudioContext(
        android: const AudioContextAndroid(contentType: AndroidContentType.speech, audioFocus: AndroidAudioFocus.none)));
  bool _systemReady = false;

  SpeechMap map = SpeechMap(const []);
  List<SpokenSentence> get sentences => map.sentences;
  int index = 0;

  /// Where the voice is inside the current sentence, in characters.
  int char = 0;
  bool active = false, paused = false, scrubbing = false;
  String? error;

  /// Automatic voicing has not made the next sentence yet: the voice waits for the reader to choose.
  bool caughtUp = false;

  /// Asked before each sentence in a voice the phone makes: a ready file, or null to make it now.
  File? Function(SpokenSentence s, VoiceModel m)? ready;

  /// True when the next sentence should wait for automatic voicing instead of being made now.
  bool Function(SpokenSentence s)? mustWait;

  /// Ticks whenever the highlighted word changes, so only the marker and the bar redraw.
  final cursor = ValueNotifier<int>(0);

  /// Called when the last sentence has been read, to turn the page.
  VoidCallback? onFinished;

  int _run = 0;
  bool _pausedBeforeScrub = false;
  int _systemBase = 0, _systemRun = -1;
  bool _gotBoundary = false;
  Isolate? _isolate;
  SendPort? _jobs;
  String? _loadedModel;
  final _audio = <String, Future<File>>{};
  int _fileNumber = 0;
  Completer<void>? _playing;

  SpokenSentence? get current => active && index < sentences.length ? sentences[index] : null;

  SpokenWord? get currentWord {
    final s = current;
    return s == null || s.words.isEmpty ? null : s.words[map.wordAt(s, char)];
  }

  double get progress => map.progress(index, char);

  void _setChar(int value) {
    final s = current;
    if (s == null) return;
    final before = map.wordAt(s, char);
    char = value.clamp(0, s.text.length);
    if (map.wordAt(s, char) != before) cursor.value++;
  }

  void start(List<SpokenSentence> list, {int from = 0}) {
    map = SpeechMap(list);
    index = from;
    char = 0;
    active = true;
    paused = false;
    caughtUp = false;
    error = null;
    _audio.clear();
    cursor.value++;
    _play();
  }

  void pause() {
    paused = true;
    _cancelSound();
    notifyListeners();
  }

  void resume() {
    paused = false;
    caughtUp = false;
    _play();
  }

  void step(int by) {
    index = (index + by).clamp(0, sentences.isEmpty ? 0 : sentences.length - 1);
    char = 0;
    paused = false;
    cursor.value++;
    _play();
  }

  void stop() {
    if (!active) return;
    active = false;
    paused = false;
    caughtUp = false;
    scrubbing = false;
    _cancelSound();
    _audio.clear();
    cursor.value++;
    notifyListeners();
  }

  /// A new speed is heard from the current word, not only from the next sentence.
  void applySpeed() {
    if (active && !paused && !scrubbing) _play();
  }

  /// The finger took hold of the bar or the marker: the voice waits until it lets go.
  void beginScrub() {
    if (scrubbing) return;
    scrubbing = true;
    _pausedBeforeScrub = paused;
    _cancelSound();
  }

  void scrubTo(int sentence, int word) {
    index = sentence;
    char = sentences[sentence].words.isEmpty ? 0 : sentences[sentence].words[word].start;
    cursor.value++;
  }

  void scrubFraction(double fraction) {
    if (sentences.isEmpty) return;
    final (s, w) = map.locate(fraction);
    scrubTo(s, w);
  }

  void endScrub() {
    if (!scrubbing) return;
    scrubbing = false;
    if (!_pausedBeforeScrub) _play();
  }

  void _cancelSound() {
    _run++;
    _system.stop();
    _player.stop();
    if (_playing?.isCompleted == false) _playing!.complete();
  }

  void _play() {
    _cancelSound();
    final run = _run;
    notifyListeners();
    unawaited(_loop(run));
  }

  Future<void> _loop(int run) async {
    try {
      while (run == _run && index < sentences.length) {
        final s = sentences[index];
        // Always from the start of a word, so a resumed voice never begins mid-syllable.
        final from = s.words.isEmpty ? 0 : s.words[map.wordAt(s, char)].start;
        final model = voices.selected;
        if (settings.voiceSource == VoiceSource.model && model != null && ready?.call(s, model) == null && (mustWait?.call(s) ?? false)) {
          caughtUp = true;
          pause();
          return;
        }
        await _speak(s, index + 1 < sentences.length ? sentences[index + 1] : null, from, run);
        if (run != _run) return;
        index++;
        char = 0;
        cursor.value++;
      }
      if (run == _run && active) onFinished?.call();
    } catch (_) {
      if (run != _run) return;
      error = tr('Seslendirme başarısız oldu. Ses ayarlarını kontrol et.');
      active = false;
      notifyListeners();
    }
  }

  Future<void> _speak(SpokenSentence s, SpokenSentence? next, int from, int run) async {
    final model = voices.selected;
    if (settings.voiceSource == VoiceSource.api && settings.apiKey.isNotEmpty) {
      final file = _audioFor(s, _fetchFromApi);
      if (next != null) unawaited(_audioFor(next, _fetchFromApi).catchError((_) => File('')));
      await _playFile(await file, s, from, run, settings.ttsSpeed);
    } else if (settings.voiceSource == VoiceSource.model && model != null) {
      final kept = ready?.call(s, model);
      final file = kept != null ? Future.value(kept) : _audioFor(s, (x) => synthesize(x, model));
      if (next != null && ready?.call(next, model) == null) unawaited(_audioFor(next, (x) => synthesize(x, model)).catchError((_) => File('')));
      // A kept file was made at 1x; one made now already has the speed in it.
      await _playFile(await file, s, from, run, kept != null ? settings.ttsSpeed : 1);
    } else {
      await _speakWithSystem(s, from, run);
    }
  }

  Future<File> _audioFor(SpokenSentence s, Future<Uint8List> Function(SpokenSentence) make) =>
      _audio['${settings.ttsVoice}|${settings.cloneId}|${settings.ttsSpeed}|${s.text}'] ??= () async {
        final bytes = await make(s);
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, 'speech-${_fileNumber++ % 8}.audio'));
        await file.writeAsBytes(bytes);
        return file;
      }();

  Future<void> _speakWithSystem(SpokenSentence s, int from, int run) async {
    if (!_systemReady) {
      await _system.awaitSpeakCompletion(true);
      _system.setProgressHandler((_, start, _, _) {
        if (_systemRun != _run) return;
        _gotBoundary = true;
        _setChar(_systemBase + start);
      });
      _systemReady = true;
    }
    if (s.lang != null) await _system.setLanguage(s.lang!);
    await _useSystemVoice(s.lang);
    await _system.setSpeechRate(0.5 * settings.ttsSpeed);
    if (run != _run) return;
    _systemBase = from;
    _systemRun = run;
    _gotBoundary = false;
    // Some voices never report where they are; then the marker walks at a typical reading pace.
    final clock = Stopwatch()..start();
    final walker = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (run == _run && !_gotBoundary) _setChar(from + (clock.elapsedMilliseconds * 0.015 * settings.ttsSpeed).floor());
    });
    try {
      await _system.speak(s.text.substring(from));
    } finally {
      walker.cancel();
    }
  }

  Future<void> _playFile(File file, SpokenSentence s, int from, int run, double rate) async {
    final done = Completer<void>();
    _playing = done;
    final finished = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    await _player.setPlaybackRate(rate);
    await _player.setSourceDeviceFile(file.path);
    var length = await _player.getDuration();
    if (run != _run) return finished.cancel();
    if (from > 0 && length != null) await _player.seek(length * (from / s.text.length));
    // The voice gives no word timings, so a word's place is its share of the sentence's letters.
    final moving = _player.onPositionChanged.listen((at) async {
      length ??= await _player.getDuration();
      final total = length?.inMilliseconds ?? 0;
      if (run == _run && total > 0) _setChar((at.inMilliseconds / total * s.text.length).floor());
    });
    await _player.resume();
    await done.future;
    await finished.cancel();
    await moving.cancel();
  }

  Future<void> releaseModel() async {
    stop();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _jobs = null;
    _loadedModel = null;
  }

  /// The phone's voices for a language, by name and locale, in a steady order.
  /// Voices that need the internet are left out; with the book's language unknown, the phone's own is used.
  Future<List<Map<String, String>>> systemVoices(String? lang) async {
    final code = (lang ?? Platform.localeName).split(RegExp('[-_]')).first.toLowerCase();
    final mine = [
      for (final v in await _system.getVoices as List)
        if ('${(v as Map)['locale']}'.toLowerCase().startsWith(code) &&
            !'${v['name']}'.contains('network') &&
            !['1', 'true'].contains('${v['network_required']}'))
          {'name': '${v['name']}', 'locale': '${v['locale']}'},
    ];
    return mine..sort((a, b) => a['name']!.compareTo(b['name']!));
  }

  Future<void> _useSystemVoice(String? lang) async {
    final chosen = settings.systemVoice?.split('|');
    if (chosen == null || chosen.length != 2) return;
    final code = (lang ?? Platform.localeName).split(RegExp('[-_]')).first.toLowerCase();
    if (!chosen[1].toLowerCase().startsWith(code)) return; // chosen for another language
    await _system.setVoice({'name': chosen[0], 'locale': chosen[1]});
  }

  final _preview = AudioPlayer();

  /// Says [text] once in a voice the reader is choosing, without touching what is being read.
  Future<void> preview(String text, String? lang, {VoiceModel? model, int voice = 0, String? systemVoice, bool cloned = true}) async {
    await _preview.stop();
    if (model == null) {
      if (lang != null) await _system.setLanguage(lang);
      final v = systemVoice?.split('|');
      if (v != null && v.length == 2) await _system.setVoice({'name': v[0], 'locale': v[1]});
      await _system.setSpeechRate(0.5 * settings.ttsSpeed);
      await _system.speak(text);
      return;
    }
    final bytes = await synthesize(SpokenSentence(text, lang, 0, const []), model, voice: voice, cloned: cloned);
    await _preview.play(BytesSource(bytes, mimeType: 'audio/wav'));
  }

  /// [s] spoken by [model], then in the reader's own voice when one is chosen, unless not [cloned].
  Future<Uint8List> synthesize(SpokenSentence s, VoiceModel model, {int? voice, double? speed, bool cloned = true}) async {
    if (_loadedModel != model.id) {
      await releaseModelKeepingSpeech();
      final ready = ReceivePort();
      _isolate = await Isolate.spawn(_synthMain, (model, voices.dirOf(model), ready.sendPort));
      _jobs = await ready.first as SendPort;
      _loadedModel = model.id;
    }
    final reply = ReceivePort();
    _jobs!.send(_SynthJob(s.text, sidOf(model, voice ?? settings.ttsVoice), speed ?? settings.ttsSpeed, _modelLanguage(s, model), reply.sendPort));
    // A model let go while this was being made never answers.
    final result = await reply.first.timeout(const Duration(minutes: 2), onTimeout: () => 'timed out');
    reply.close();
    if (result is String) throw StateError(result);
    final clone = cloned ? cloner.active : null;
    if (clone != null) return cloner.convert(result as Uint8List, model, voice ?? settings.ttsVoice, clone);
    return result as Uint8List;
  }

  Future<void> releaseModelKeepingSpeech() async {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _jobs = null;
    _loadedModel = null;
  }

  int sidOf(VoiceModel model, int voice) {
    final i = voice.clamp(0, model.voiceCount - 1);
    return model.isSupertonic ? supertonicOrder[i] : i;
  }

  String? _modelLanguage(SpokenSentence s, VoiceModel model) {
    final code = s.lang?.split(RegExp('[-_]')).first.toLowerCase();
    return code != null && model.languages.contains(code) ? code : null;
  }

  /// Any service that speaks the OpenAI-style /audio/speech request.
  Future<Uint8List> _fetchFromApi(SpokenSentence s) async {
    final uri = Uri.parse('${settings.apiBase.replaceAll(RegExp(r'/+$'), '')}/audio/speech');
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${settings.apiKey}');
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode({
        'model': settings.apiModel,
        'voice': settings.apiVoice,
        'input': s.text,
        'response_format': 'mp3',
      })));
      final response = await request.close();
      if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
      final out = BytesBuilder(copy: false);
      await for (final chunk in response) {
        out.add(chunk);
      }
      return out.takeBytes();
    } finally {
      client.close();
    }
  }
}
