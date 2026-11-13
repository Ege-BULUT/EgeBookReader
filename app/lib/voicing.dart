import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'main.dart' show device, settings;
import 'settings.dart';
import 'sources.dart' show SpokenSentence;
import 'tts.dart';

final voicing = Voicing();

/// FNV-1a over 64 bits: the same name for the same sentence from one run of the app to the next.
String speechKey(String text) {
  var h = 0xcbf29ce484222325;
  for (final b in utf8.encode(text)) {
    h ^= b;
    h *= 0x100000001b3;
  }
  String hex(int v) => v.toRadixString(16).padLeft(8, '0');
  return hex(h >>> 32) + hex(h & 0xffffffff); // an int is signed: written in two halves
}

/// "4 dk", "1 sa 12 dk", "40 sn".
String spanOf(double seconds) {
  final m = (seconds / 60).round();
  if (seconds < 60) return '${max(1, seconds.round())} ${tr('sn')}';
  return m < 60 ? '$m ${tr('dk')}' : '${m ~/ 60} ${tr('sa')} ${m % 60} ${tr('dk')}';
}

/// Automatic voicing: sentences are voiced ahead of the listener by the phone's own voice and kept as small AAC files,
/// so a phone that speaks slower than it reads still reads without gaps.
class Voicing extends ChangeNotifier {
  Directory? _dir;
  static const limit = 500 << 20;
  int bytes = 0;

  bool running = false;

  /// The pages of the stage being voiced, [from] to [to] (not included), and the one being made now.
  int from = 0, to = 0, page = 0;

  /// The first page of the whole run; a sentence before it is not waited for.
  int runFrom = 0;

  /// Characters of this stage done and in all.
  int done = 0, total = 0;
  int _run = 0, _learned = 0;

  Future<void> load() async {
    _dir = await Directory(p.join((await getApplicationCacheDirectory()).path, 'voiced')).create(recursive: true);
    bytes = [for (final f in _dir!.listSync().whereType<File>()) f.lengthSync()].fold(0, (a, b) => a + b);
  }

  String _key(SpokenSentence s, VoiceModel m) =>
      speechKey('${m.id}|${speaker.sidOf(m, settings.ttsVoice)}|${s.lang}|${s.text}'); // made at 1x, sped up as it plays

  /// The kept voicing of [s], if it has been made.
  File? fileFor(SpokenSentence s, VoiceModel m) {
    if (_dir == null) return null;
    final f = File(p.join(_dir!.path, _key(s, m)));
    return f.existsSync() ? f : null;
  }

  double get fraction => total == 0 ? 0 : (done / total).clamp(0.0, 1.0);

  /// "%42.17 · 63/100"
  String get label => '%${(fraction * 100).toStringAsFixed(2)} · ${page - from}/${to - from}';

  /// Seconds it takes this phone to make, and to say at 1x, one character in [m]; null until measured.
  List<double>? paceOf(VoiceModel m) => settings.voicePace[m.id];

  /// Voices pages [from] to [to] of a book. Those before [hurryUntil] go at full speed, since someone waits for
  /// them; the future completes once they are ready (false when stopped first). The rest go gently.
  Future<bool> start(int from, int to, Future<List<SpokenSentence>> Function(int) sentencesOn, {int? hurryUntil}) {
    final run = ++_run;
    final first = Completer<bool>();
    unawaited(_go(run, from, min(hurryUntil ?? from, to), to, sentencesOn, first));
    return first.future;
  }

  void cancel() {
    _run++;
    if (!running) return;
    running = false;
    notifyListeners();
  }

  Future<void> _go(int run, int from, int hurryUntil, int to, Future<List<SpokenSentence>> Function(int) sentencesOn, Completer<bool> first) async {
    running = true;
    runFrom = from;
    try {
      for (final (a, b, hurry) in [(from, hurryUntil, true), (hurryUntil, to, false)]) {
        if (a >= b) continue;
        this.from = a;
        this.to = b;
        page = a;
        done = total = 0;
        notifyListeners();
        for (var i = a; i < b; i++) {
          if (run != _run) return;
          total += (await sentencesOn(i)).fold(0, (n, s) => n + s.text.length);
        }
        for (var i = a; i < b; i++) {
          page = i;
          for (final s in await sentencesOn(i)) {
            final model = voices.selected;
            if (run != _run || model == null || settings.voiceSource != VoiceSource.model) return;
            if (fileFor(s, model) == null) await _make(s, model, gentle: !hurry);
            done += s.text.length;
            notifyListeners();
          }
        }
        page = b;
        if (hurry && !first.isCompleted) first.complete(true);
      }
    } catch (e) {
      debugPrint('voicing stopped: $e');
    } finally {
      if (!first.isCompleted) first.complete(run == _run);
      if (run == _run) {
        running = false;
        notifyListeners();
      }
    }
  }

  /// Voices one sentence now and keeps it; also how the phone's speed is first measured.
  Future<void> make(SpokenSentence s, VoiceModel m) async {
    if (fileFor(s, m) == null) await _make(s, m, gentle: false);
  }

  Future<void> _make(SpokenSentence s, VoiceModel m, {required bool gentle}) async {
    final clock = Stopwatch()..start();
    final wav = await speaker.synthesize(s, m, speed: 1);
    final made = clock.elapsedMicroseconds / 1e6;
    final rate = ByteData.sublistView(wav).getUint32(24, Endian.little);
    _learn(m, made / max(1, s.text.length), (wav.length - 44) / 2 / rate / max(1, s.text.length));
    final out = File(p.join(_dir!.path, _key(s, m)));
    final raw = File('${out.path}.wav'), packed = File('${out.path}.m4a');
    await raw.writeAsBytes(wav);
    try {
      // About a tenth of the space of the voice's own WAV.
      await device.invokeMethod('encodeAac', {'from': raw.path, 'to': packed.path});
      await packed.rename(out.path);
      await raw.delete();
    } on Exception {
      if (packed.existsSync()) await packed.delete();
      await raw.rename(out.path);
    }
    bytes += await out.length();
    if (bytes > limit) await _trim();
    if (gentle) {
      // Leave the phone room: rest a third as long as the work took, twice as long when it runs warm.
      final warm = await device.invokeMethod<int>('thermal').then((t) => (t ?? 0) >= 2, onError: (_) => false);
      await Future<void>.delayed(clock.elapsed * (warm ? 2 : 0.3));
    }
  }

  void _learn(VoiceModel m, double make, double lasts) {
    final old = settings.voicePace[m.id];
    settings.voicePace[m.id] = old == null ? [make, lasts] : [old[0] * 0.8 + make * 0.2, old[1] * 0.8 + lasts * 0.2];
    if (_learned++ % 20 == 0) settings.update((_) {}); // saved now and then, not after every sentence
  }

  /// Over the limit, the oldest files go first: those are the pages already heard.
  Future<void> _trim() async {
    final files = [for (final f in _dir!.listSync().whereType<File>()) (f, f.statSync())]
      ..sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    var size = files.fold(0, (n, f) => n + f.$2.size);
    for (final (f, st) in files) {
      if (size < limit * 0.8) break;
      size -= st.size;
      await f.delete();
    }
    bytes = size;
    notifyListeners();
  }

  Future<void> clear() async {
    cancel();
    if (_dir != null && _dir!.existsSync()) {
      await _dir!.delete(recursive: true);
      await _dir!.create();
    }
    bytes = 0;
    notifyListeners();
  }
}

/// Pages to voice before reading starts: the reader's choice, or more if this phone is too slow to reach the end
/// of the chapter without a stop. With making taking g seconds a page and hearing it l, N pages need N·(1 − l/g).
int bufferPages(VoiceModel m, int pagesToChapterEnd) {
  final pace = voicing.paceOf(m);
  var b = settings.autoVoicePages;
  final listen = pace == null ? 0 : pace[1] / settings.ttsSpeed; // measured at 1x
  if (pace != null && pace[0] > listen) b = max(b, (pagesToChapterEnd * (1 - listen / pace[0])).ceil());
  return min(b, 60); // ponytail: an hour-long chapter on a very slow phone still waits for 60 pages only
}

/// The card shown while the first pages are being voiced.
class VoicingProgress extends StatelessWidget {
  const VoicingProgress({super.key, required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return ListenableBuilder(
      listenable: voicing,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 6),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.line)),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tr('Ses hazırlanıyor'), style: TextStyle(color: c.ink, fontSize: 15))),
            Text(voicing.label, style: TextStyle(color: c.muted, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: voicing.fraction, minHeight: 3, color: c.accent, backgroundColor: c.line),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onCancel, style: TextButton.styleFrom(foregroundColor: c.muted), child: Text(tr('Vazgeç'))),
          ),
        ]),
      ),
    );
  }
}

/// Voice a stretch of the book ahead: two-handled slider, words and time it will take on this phone, then progress.
class RangeVoicingSheet extends StatefulWidget {
  const RangeVoicingSheet({super.key, required this.count, required this.page, required this.sentencesOn});
  final int count, page;
  final Future<List<SpokenSentence>> Function(int) sentencesOn;

  @override
  State<RangeVoicingSheet> createState() => _RangeVoicingSheetState();
}

class _RangeVoicingSheetState extends State<RangeVoicingSheet> {
  late var range = RangeValues(widget.page + 1.0, min(widget.count, widget.page + 50).toDouble());
  int? words, chars;
  int _counting = 0;

  @override
  void initState() {
    super.initState();
    voicing.addListener(_changed);
    _count();
  }

  @override
  void dispose() {
    voicing.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _count() async {
    final run = ++_counting;
    setState(() => words = chars = null);
    var w = 0, n = 0;
    SpokenSentence? first;
    for (var i = range.start.round() - 1; i < range.end.round(); i++) {
      for (final s in await widget.sentencesOn(i)) {
        first ??= s;
        w += s.words.length;
        n += s.text.length;
      }
      if (run != _counting || !mounted) return;
    }
    // Not measured on this phone yet: one sentence tells.
    final model = voices.selected;
    if (model != null && first != null && voicing.paceOf(model) == null) await voicing.make(first, model);
    if (run != _counting || !mounted) return;
    setState(() {
      words = w;
      chars = n;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final model = voices.selected;
    final pace = model == null ? null : voicing.paceOf(model);
    final a = range.start.round(), b = range.end.round();
    final mine = voicing.running && voicing.from == a - 1 && voicing.to == b;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, max(MediaQuery.paddingOf(context).bottom, 16) + 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Önden seslendir'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        const SizedBox(height: 6),
        Text(tr('Seçilen sayfalar arka planda, telefonu yormadan seslendirilip saklanır.'), style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 10),
        RangeSlider(
          values: range,
          min: 1,
          max: max(2, widget.count).toDouble(),
          divisions: max(1, widget.count - 1),
          labels: RangeLabels('$a', '$b'),
          onChanged: mine ? null : (v) => setState(() => range = v),
          onChangeEnd: (_) => _count(),
        ),
        Text('${tr('Sayfa')} $a – $b', style: TextStyle(color: c.ink, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          words == null
              ? tr('Hesaplanıyor…')
              : '$words ${tr('kelime')}'
                  '${pace == null ? '' : ' · ${tr('hazırlanması')} ~${spanOf(chars! * pace[0])} · ${tr('dinlemesi')} ~${spanOf(chars! * pace[1] / settings.ttsSpeed)}'}',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (mine) ...[
          LinearProgressIndicator(value: voicing.fraction, minHeight: 3, color: c.accent, backgroundColor: c.line),
          const SizedBox(height: 8),
          Row(children: [
            Text(voicing.label, style: TextStyle(color: c.ink, fontSize: 14, fontFeatures: const [FontFeature.tabularFigures()])),
            const Spacer(),
            TextButton(onPressed: voicing.cancel, style: TextButton.styleFrom(foregroundColor: c.muted), child: Text(tr('Durdur'))),
          ]),
        ] else
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: model == null ? null : () => voicing.start(a - 1, b, widget.sentencesOn),
              style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
              child: Text(tr('Başlat')),
            ),
          ),
      ]),
    );
  }
}

/// Listening caught up with automatic voicing. Turn the sound off, or go on in another voice picked here.
/// Answers true when a voice was applied.
class CatchUpSheet extends StatefulWidget {
  const CatchUpSheet({super.key, this.sample});
  final SpokenSentence? sample;

  @override
  State<CatchUpSheet> createState() => _CatchUpSheetState();
}

class _CatchUpSheetState extends State<CatchUpSheet> {
  // Starts on the voice chosen last.
  VoiceModel? model = settings.voiceSource == VoiceSource.model ? voices.selected : null;
  int voice = settings.ttsVoice;
  List<Map<String, String>> system = const [];
  int systemIndex = 0;

  @override
  void initState() {
    super.initState();
    speaker.systemVoices(widget.sample?.lang).then((v) {
      if (!mounted) return;
      setState(() {
        system = v;
        systemIndex = max(0, v.indexWhere((x) => '${x['name']}|${x['locale']}' == settings.systemVoice));
      });
    }, onError: (_) {});
  }

  int get _choices => model?.voiceCount ?? system.length;

  String get _label {
    if (model != null) return voiceLabel(model!, voice);
    return system.isEmpty ? tr('Varsayılan') : '${tr('Ses')} ${systemIndex + 1}';
  }

  String? get _systemVoice => system.isEmpty ? null : '${system[systemIndex]['name']}|${system[systemIndex]['locale']}';

  void _step(int by) {
    if (_choices < 2) return;
    setState(() {
      if (model != null) {
        voice = (voice + by) % _choices;
      } else {
        systemIndex = (systemIndex + by) % _choices;
      }
    });
  }

  void _preview() {
    final text = widget.sample?.text ?? '';
    final say = text.length > 140 ? '${text.substring(0, 140)}…' : (text.isEmpty ? tr('Bu ses böyle duyuluyor.') : text);
    unawaited(speaker.preview(say, widget.sample?.lang, model: model, voice: voice, systemVoice: _systemVoice).catchError((_) {}));
  }

  void _apply() {
    final m = model;
    settings.update((x) {
      if (m == null) {
        x.voiceSource = VoiceSource.system;
        x.systemVoice = _systemVoice;
      } else {
        x.voiceSource = VoiceSource.model;
        x.ttsModelId = m.id;
        x.ttsVoice = voice;
      }
    });
    // From here the chosen voice speaks as it goes; voicing ahead starts again with the next press of play.
    voicing.cancel();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return Padding(
      padding: EdgeInsets.fromLTRB(22, 20, 22, max(MediaQuery.paddingOf(context).bottom, 16) + 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr('Hazır ses bitti'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        const SizedBox(height: 6),
        Text(tr('Dinleme, seslendirmeye yetişti. Başka bir sesle devam edebilir ya da sesi kapatabilirsin.'),
            style: TextStyle(color: c.muted, fontSize: 13, height: 1.35)),
        const SizedBox(height: 14),
        DropdownButton<String>(
          value: model?.id ?? 'system',
          isExpanded: true,
          dropdownColor: c.surface,
          style: TextStyle(color: c.ink, fontSize: 15),
          items: [
            DropdownMenuItem(value: 'system', child: Text(tr('Sistem sesi'))),
            for (final m in voiceCatalog)
              DropdownMenuItem(
                value: m.id,
                enabled: voices.installed(m),
                child: Text(voices.installed(m) ? m.name : '${m.name} (${tr('yüklü değil')})',
                    style: TextStyle(color: voices.installed(m) ? c.ink : c.muted)),
              ),
          ],
          onChanged: (id) => setState(() {
            model = voiceCatalog.where((m) => m.id == id).firstOrNull;
            voice = model != null && model!.id == settings.ttsModelId ? settings.ttsVoice : 0;
          }),
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(onPressed: () => _step(-1), icon: Icon(Icons.chevron_left, color: c.ink), visualDensity: VisualDensity.compact),
          Expanded(child: Text(_label, textAlign: TextAlign.center, style: TextStyle(color: c.ink, fontSize: 15))),
          IconButton(onPressed: () => _step(1), icon: Icon(Icons.chevron_right, color: c.ink), visualDensity: VisualDensity.compact),
          IconButton(
            tooltip: tr('Dinle'),
            onPressed: _preview,
            icon: Icon(Icons.play_arrow_rounded, color: c.accent, size: 20),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: _apply,
            style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
            child: Text(tr('Uygula')),
          ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            style: OutlinedButton.styleFrom(foregroundColor: c.ink, side: BorderSide(color: c.line)),
            child: Text(tr('Sesi kapat')),
          ),
        ),
      ]),
    );
  }
}
