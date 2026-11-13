import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'main.dart';
import 'shelf.dart' show userAgent;
import 'sources.dart';

// ---- audiobook files ----------------------------------------------------------------------------------

final audiobook = Audiobook();

/// Plays an audiobook file attached to a book, in place of a voice reading the text.
class Audiobook extends ChangeNotifier {
  // As for the voice, the reading service holds the audio focus, so the player asks for none itself.
  final _player = AudioPlayer()
    ..setAudioContext(AudioContext(
        android: const AudioContextAndroid(contentType: AndroidContentType.speech, audioFocus: AndroidAudioFocus.none)));
  bool active = false, paused = false;

  /// Ticks as the file plays, so only what shows the place redraws.
  final position = ValueNotifier(Duration.zero);
  Duration duration = Duration.zero;

  /// Where the file's chapters start, in seconds; empty when it has none.
  List<double> chapters = const [];

  /// Called when the file has played to its end.
  VoidCallback? onFinished;
  StreamSubscription<Duration>? _moving;
  StreamSubscription<void>? _done;

  /// Loads [path], paused at its start; false when it cannot be played.
  Future<bool> open(String path) async {
    stop();
    try {
      await _player.setSourceDeviceFile(path);
      duration = await _player.getDuration() ?? Duration.zero;
    } catch (_) {
      return false;
    }
    // A file whose chapters cannot be read still plays, mapped to the whole book.
    chapters = await readAudioChapters(path).catchError((_) => const <double>[]);
    _moving = _player.onPositionChanged.listen((at) => position.value = at);
    _done = _player.onPlayerComplete.listen((_) {
      stop();
      onFinished?.call();
    });
    active = true;
    paused = true;
    position.value = Duration.zero;
    notifyListeners();
    return true;
  }

  Future<void> seek(Duration at) async {
    final to = Duration(milliseconds: at.inMilliseconds.clamp(0, max(0, duration.inMilliseconds - 500)));
    position.value = to;
    await _player.seek(to);
  }

  void setRate(double rate) => _player.setPlaybackRate(rate);

  void resume() {
    paused = false;
    _player.resume();
    notifyListeners();
  }

  void pause() {
    paused = true;
    _player.pause();
    notifyListeners();
  }

  void stop() {
    if (!active) return;
    active = false;
    paused = false;
    _moving?.cancel();
    _done?.cancel();
    _player.stop();
    notifyListeners();
  }
}

/// The chapter starts of an .m4b, .m4a or .mp4 file, in seconds; empty for other files and files without chapters.
/// Only the 'moov' box is read, so a long audiobook costs a few megabytes at most.
Future<List<double>> readAudioChapters(String path) async {
  if (!const {'.m4b', '.m4a', '.mp4'}.contains(p.extension(path).toLowerCase())) return const [];
  final file = await File(path).open();
  try {
    final length = await file.length();
    var at = 0;
    while (at + 8 <= length) {
      await file.setPosition(at);
      final head = ByteData.sublistView(await file.read(16));
      var size = head.getUint32(0), skip = 8;
      final type = String.fromCharCodes(head.buffer.asUint8List(head.offsetInBytes + 4, 4));
      if (size == 1) (size, skip) = (head.getUint64(8), 16);
      if (size == 0) size = length - at;
      if (size < skip) break;
      if (type == 'moov') {
        await file.setPosition(at + skip);
        return mp4Chapters(await file.read(size - skip));
      }
      at += size;
    }
    return const [];
  } finally {
    await file.close();
  }
}

/// Chapter starts in a 'moov' box's contents: from a Nero 'chpl' box, else from a QuickTime chapter track.
List<double> mp4Chapters(Uint8List moov) {
  final d = ByteData.sublistView(moov);

  // The boxes between [from] and [to]: type, where the contents start, and where the box ends.
  Iterable<(String, int, int)> boxes(int from, int to) sync* {
    for (var at = from; at + 8 <= to;) {
      var size = d.getUint32(at), skip = 8;
      if (size == 1) (size, skip) = (d.getUint64(at + 8), 16);
      if (size == 0) size = to - at;
      if (size < skip || at + size > to) return;
      yield (String.fromCharCodes(moov, at + 4, at + 8), at + skip, at + size);
      at += size;
    }
  }

  (int, int)? find(int from, int to, List<String> path) {
    for (final (type, start, end) in boxes(from, to)) {
      if (type != path.first) continue;
      if (path.length == 1) return (start, end);
      final found = find(start, end, path.sublist(1));
      if (found != null) return found;
    }
    return null;
  }

  // Nero: version and flags, four more bytes from version 1, a count, then a start in 100 ns units and a title each.
  if (find(0, moov.length, ['udta', 'chpl']) case (final start, final end)) {
    var at = start + 4 + (moov[start] == 0 ? 0 : 4);
    final count = moov[at++];
    final starts = <double>[];
    for (var i = 0; i < count && at + 9 <= end; i++) {
      starts.add(d.getUint64(at) / 1e7);
      at += 9 + moov[at + 8];
    }
    if (starts.isNotEmpty) return starts;
  }

  // QuickTime: a track names its chapter track in tref/chap; that track's sample times are the chapter starts.
  final tracks = [for (final (type, start, end) in boxes(0, moov.length)) if (type == 'trak') (start, end)];
  int? chapterTrack;
  for (final (start, end) in tracks) {
    if (find(start, end, ['tref', 'chap']) case (final s, final e) when e - s >= 4) chapterTrack = d.getUint32(s);
  }
  for (final (start, end) in tracks) {
    final (tkhd, _) = find(start, end, ['tkhd']) ?? (-1, 0);
    if (tkhd < 0 || d.getUint32(tkhd + (moov[tkhd] == 0 ? 12 : 20)) != chapterTrack) continue;
    final (mdhd, _) = find(start, end, ['mdia', 'mdhd']) ?? (-1, 0);
    final (stts, _) = find(start, end, ['mdia', 'minf', 'stbl', 'stts']) ?? (-1, 0);
    if (mdhd < 0 || stts < 0) return const [];
    final scale = d.getUint32(mdhd + (moov[mdhd] == 0 ? 12 : 20));
    final starts = <double>[];
    var t = 0;
    for (var i = 0, n = d.getUint32(stts + 4); i < n; i++) {
      final count = d.getUint32(stts + 8 + i * 8), delta = d.getUint32(stts + 12 + i * 8);
      for (var j = 0; j < count; j++, t += delta) {
        starts.add(t / max(scale, 1));
      }
    }
    return starts;
  }
  return const [];
}

/// Points in the audio (seconds) paired with points in the book (0 to 1): chapter i of the audio with the book's
/// top-level contents entry i, and the ends with the ends. Without chapters on both sides, the whole book is one span.
// ponytail: proportional sync, not forced alignment. Inside a chapter the text is taken to be read at an even pace, so the
// page can be a page or two off where the narrator pauses or skips, and chapters that do not pair one to one drift.
// Aligning the words with speech recognition would fix that.
(List<double>, List<double>) syncAnchors(List<double> chapters, double duration, List<int> parts, int pages) {
  final k = min(chapters.length, parts.length);
  if (k < 2 || pages <= 0 || duration <= 0) return ([0, max(duration, 1)], [0, 1]);
  final audio = <double>[], book = <double>[];
  var a = 0.0, b = 0.0;
  for (var i = 0; i < k; i++) {
    audio.add(a = max(a, chapters[i]));
    book.add(b = max(b, parts[i] / pages));
  }
  return ([...audio, max(a, duration)], [...book, 1]);
}

/// Follows the line through ([xs], [ys]) to [x]; [xs] never goes down.
double lerpAlong(List<double> xs, List<double> ys, double x) {
  if (x <= xs.first) return ys.first;
  for (var i = 1; i < xs.length; i++) {
    if (x > xs[i]) continue;
    final span = xs[i] - xs[i - 1];
    return span <= 0 ? ys[i] : ys[i - 1] + (ys[i] - ys[i - 1]) * (x - xs[i - 1]) / span;
  }
  return ys.last;
}

/// Lets the reader pick an audio file for [b]. Null if they cancelled, false if it is not an mp3, m4b or m4a.
Future<bool?> pickAudioFor(Book b) async {
  // Any file: Android often does not know m4b's type, so a filter would hide the very files wanted.
  final path = (await FilePicker.pickFiles()).firstOrNull?.path;
  if (path == null) return null;
  if (!const {'.mp3', '.m4b', '.m4a'}.contains(p.extension(path).toLowerCase())) return false;
  await library.attachAudio(b, path);
  return true;
}

// ---- about the author and the book --------------------------------------------------------------------

/// A few paragraphs about an author or a book, and where they came from.
typedef About = ({String text, String source, String url});

Map<String, dynamic>? _aboutCache;
File? _aboutFile;

/// The Wikipedia languages to try, in order: the interface's, the book's, then English.
List<String> wikiLanguages(String? bookLanguage, String ui) {
  final l = (bookLanguage ?? '').toLowerCase();
  const three = {'eng': 'en', 'tur': 'tr', 'fre': 'fr', 'fra': 'fr', 'ger': 'de', 'deu': 'de', 'spa': 'es', 'ita': 'it', 'rus': 'ru', 'por': 'pt', 'jpn': 'ja', 'chi': 'zh', 'zho': 'zh', 'ara': 'ar', 'dut': 'nl', 'nld': 'nl'};
  final book = RegExp(r'^[a-z]{2}($|[-_])').hasMatch(l) ? l.substring(0, 2) : three[l];
  return {ui, ?book, 'en'}.toList();
}

/// Open Library writes a bio or a description either as text or as {type, value}.
String? openLibraryText(Object? value) => switch (value) {
      String s when s.trim().isNotEmpty => s.trim(),
      {'value': String s} when s.trim().isNotEmpty => s.trim(),
      _ => null,
    };

/// About the book's author: Wikipedia first, else Open Library's bio. Null when not known, offline, or lookups are off.
Future<About?> aboutAuthor(Book b) async {
  final name = b.info['author']?.split(',').first.trim();
  if (name == null || name.isEmpty) return null;
  return _remembered('author|$name|$uiLanguage', () async {
    for (final lang in wikiLanguages(b.info['language'], uiLanguage)) {
      if (await _wikipedia(name, lang, (_) => true) case final found?) return found;
    }
    final docs = (await _getJson(Uri.https('openlibrary.org', '/search/authors.json', {'q': name, 'limit': '1'})))?['docs'] as List?;
    final key = (docs?.firstOrNull as Map?)?['key'] as String?;
    if (key == null) return null;
    final bio = openLibraryText((await _getJson(Uri.https('openlibrary.org', '/authors/$key.json')))?['bio']);
    return bio == null ? null : (text: bio, source: 'Open Library', url: 'https://openlibrary.org/authors/$key');
  });
}

/// About the book: Wikipedia when the article names its author, else Open Library's description of the work.
Future<About?> aboutBook(Book b) {
  final author = b.info['author']?.split(',').first.trim();
  return _remembered('book|${b.title}|$author|$uiLanguage', () async {
    // A title alone is often another thing's name, so the article must name the author too.
    final surname = author?.split(' ').last.toLowerCase();
    if (surname != null && surname.length > 1) {
      for (final lang in wikiLanguages(b.info['language'], uiLanguage)) {
        if (await _wikipedia(b.title, lang, (text) => text.toLowerCase().contains(surname)) case final found?) return found;
      }
    }
    final docs = (await _getJson(Uri.https('openlibrary.org', '/search.json', {'q': b.query ?? b.defaultQuery, 'fields': 'key', 'limit': '1'})))?['docs'] as List?;
    final key = (docs?.firstOrNull as Map?)?['key'] as String?;
    if (key == null) return null;
    final text = openLibraryText((await _getJson(Uri.https('openlibrary.org', '$key.json')))?['description']);
    return text == null ? null : (text: text, source: 'Open Library', url: 'https://openlibrary.org$key');
  });
}

/// What was found for [key] before, else [find]'s answer, kept on the device found or not.
/// Nothing is asked when lookups are off, and a failed request is not kept, so it is asked again next time.
Future<About?> _remembered(String key, Future<About?> Function() find) async {
  _aboutFile ??= File(p.join((await getApplicationDocumentsDirectory()).path, 'about.json'));
  if (_aboutCache == null) {
    try {
      _aboutCache = jsonDecode(await _aboutFile!.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      _aboutCache = {};
    }
  }
  final cache = _aboutCache!;
  if (cache.containsKey(key)) {
    final j = cache[key] as Map<String, dynamic>?;
    return j == null ? null : (text: j['text'] as String, source: j['source'] as String, url: j['url'] as String);
  }
  if (!settings.onlineLookup) return null;
  try {
    final found = await find();
    cache[key] = found == null ? null : {'text': found.text, 'source': found.source, 'url': found.url};
    writeWhole(_aboutFile!, jsonEncode(cache));
    return found;
  } catch (_) {
    return null;
  }
}

/// Wikipedia's summary of the page [title] in [lang], if there is one that [fits]; disambiguation pages do not count.
Future<About?> _wikipedia(String title, String lang, bool Function(String) fits) async {
  final j = await _getJson(Uri.parse('https://$lang.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(title.replaceAll(' ', '_'))}'));
  final text = (j?['extract'] as String?)?.trim() ?? '';
  if (j?['type'] != 'standard' || text.isEmpty || !fits(text)) return null;
  final url = ((j!['content_urls'] as Map?)?['desktop'] as Map?)?['page'] as String? ?? 'https://$lang.wikipedia.org/wiki/${Uri.encodeComponent(title)}';
  return (text: text, source: 'Wikipedia · CC BY-SA 4.0', url: url);
}

/// The JSON at [uri]; null when it is not there (404). Throws when it could not be asked.
Future<Map<String, dynamic>?> _getJson(Uri uri) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, userAgent);
    final response = await request.close().timeout(const Duration(seconds: 20));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}', uri: uri);
    return jsonDecode(body) as Map<String, dynamic>;
  } finally {
    client.close();
  }
}

void openUrl(String url) => device.invokeMethod('openUrl', url);

// ---- the now-playing screen ---------------------------------------------------------------------------

/// What the now-playing screen shows at a moment: how far through the book, time listened and left, the sentences
/// being read with the one and the word being read now, and whether it is paused or plays a file.
typedef PlayerNow = ({
  double at,
  Duration listened,
  Duration left,
  List<SpokenSentence> lines,
  int line,
  SpokenWord? word,
  bool paused,
  bool file,
});

/// Laid out like a music player's now-playing screen: cover, title and author, seek bar, controls, the words being read
/// as lyrics, and about the author and the book. It sits over the reader, which keeps turning pages under it.
class NowPlaying extends StatefulWidget {
  const NowPlaying({
    super.key,
    required this.book,
    required this.tint,
    required this.ticks,
    required this.now,
    required this.lyrics,
    required this.onLyrics,
    required this.onClose,
    required this.onSeek,
    required this.onPlayPause,
    required this.onStep,
    required this.onSpeed,
    required this.onPickAudio,
  });
  final Book book;
  final Color? tint;

  /// Ticks whenever something shown may have changed.
  final Listenable ticks;
  final PlayerNow Function() now;

  /// The lyrics fill the screen.
  final bool lyrics;
  final ValueChanged<bool> onLyrics;
  final VoidCallback onClose, onPlayPause, onSpeed, onPickAudio;
  final ValueChanged<double> onSeek;
  final ValueChanged<int> onStep;
  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  late final _author = aboutAuthor(widget.book), _about = aboutBook(widget.book);

  /// Where the finger holds the seek bar; null when it does not.
  double? _dragging;

  static String _time(Duration d) {
    final s = d.inSeconds.abs(), h = s ~/ 3600, m = s % 3600 ~/ 60, sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final tint = settings.isEink ? null : widget.tint;
    final bg = tint == null ? c.paper : Color.lerp(c.paper, tint, 0.55)!;
    final fg = tint == null ? c.ink : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark ? Colors.white : const Color(0xFF1C1A17));
    final card = Color.lerp(bg, fg, 0.08)!;
    final b = widget.book;
    return Material(
      color: bg,
      child: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.ticks, library, settings]),
          builder: (context, _) {
            final n = widget.now();
            final top = Row(children: [
              IconButton(
                tooltip: tr('Kapat'),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: fg, size: 30),
                onPressed: widget.lyrics ? () => widget.onLyrics(false) : widget.onClose,
              ),
              Expanded(
                child: Text(widget.lyrics ? b.title : library.playing ?? tr('Şimdi dinleniyor'),
                    textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              MenuAnchor(
                menuChildren: [
                  MenuItemButton(leadingIcon: const Icon(Icons.audio_file_outlined), onPressed: widget.onPickAudio, child: Text(tr('Sesli kitap dosyası seç'))),
                  if (b.audio != null)
                    MenuItemButton(
                      leadingIcon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        audiobook.stop();
                        library.detachAudio(b);
                      },
                      child: Text(tr('Sesli kitap dosyasını kaldır')),
                    ),
                ],
                builder: (_, m, _) => IconButton(icon: Icon(Icons.more_vert, color: fg), onPressed: () => m.isOpen ? m.close() : m.open()),
              ),
            ]);
            final play = IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: fg, foregroundColor: bg, fixedSize: const Size(64, 64)),
              icon: Icon(n.paused ? Icons.play_arrow_rounded : Icons.pause_rounded, size: 36),
              onPressed: widget.onPlayPause,
            );
            if (widget.lyrics) {
              return Column(children: [
                top,
                Expanded(child: _Lyrics(n: n, fg: fg, size: 26)),
                Padding(padding: const EdgeInsets.all(16), child: play),
              ]);
            }
            final width = MediaQuery.sizeOf(context).width;
            final at = _dragging ?? n.at.clamp(0.0, 1.0);
            return ListView(padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
              top,
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: min(width - 72, MediaQuery.sizeOf(context).height * 0.3),
                  decoration: BoxDecoration(boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 24, offset: const Offset(0, 10))]),
                  child: AspectRatio(aspectRatio: 2 / 3, child: BookCover(book: b, ribbon: false)),
                ),
              ),
              const SizedBox(height: 28),
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.w700, height: 1.2)),
                    if (b.info['author'] case final author?)
                      Text(author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 15)),
                  ]),
                ),
                IconButton(
                  tooltip: tr(b.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle'),
                  icon: Icon(b.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: b.favorite ? c.accent : fg, size: 28),
                  onPressed: () {
                    b.favorite = !b.favorite;
                    library.changed();
                  },
                ),
              ]),
              const SizedBox(height: 10),
              SliderTheme(
                data: SliderThemeData(activeTrackColor: fg, inactiveTrackColor: fg.withValues(alpha: 0.25), thumbColor: fg, trackHeight: 3),
                child: Slider(
                  value: at,
                  onChanged: (v) => setState(() => _dragging = v),
                  onChangeEnd: (v) {
                    setState(() => _dragging = null);
                    widget.onSeek(v);
                  },
                ),
              ),
              Row(children: [
                Text(_time(n.listened), style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12)),
                const Spacer(),
                Text('-${_time(n.left)}', style: TextStyle(color: fg.withValues(alpha: 0.7), fontSize: 12)),
              ]),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                TextButton(
                  onPressed: widget.onSpeed,
                  style: TextButton.styleFrom(foregroundColor: fg),
                  child: Text('${settings.ttsSpeed}x', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                IconButton(
                  tooltip: tr(n.file ? '10 sn geri' : 'Önceki cümle'),
                  icon: Icon(n.file ? Icons.replay_10_rounded : Icons.skip_previous_rounded, color: fg, size: 36),
                  onPressed: () => widget.onStep(-1),
                ),
                play,
                IconButton(
                  tooltip: tr(n.file ? '10 sn ileri' : 'Sonraki cümle'),
                  icon: Icon(n.file ? Icons.forward_10_rounded : Icons.skip_next_rounded, color: fg, size: 36),
                  onPressed: () => widget.onStep(1),
                ),
                ShelfButton(book: b, color: fg),
              ]),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => widget.onLyrics(true),
                child: Container(
                  height: 320,
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 0),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(tr('Okunan metin'), style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700))),
                      Icon(Icons.open_in_full_rounded, color: fg, size: 18),
                      const SizedBox(width: 8),
                    ]),
                    Expanded(child: IgnorePointer(child: _Lyrics(n: n, fg: fg, size: 20))),
                  ]),
                ),
              ),
              if (b.info['author'] != null) _AboutCard(title: 'Yazar hakkında', about: _author, fg: fg, color: card),
              _AboutCard(title: 'Kitap hakkında', about: _about, fg: fg, color: card),
            ]);
          },
        ),
      ),
    );
  }
}

/// The page's sentences, the one being read bright with its word marked, kept in view as the voice moves on.
class _Lyrics extends StatefulWidget {
  const _Lyrics({required this.n, required this.fg, required this.size});
  final PlayerNow n;
  final Color fg;
  final double size;
  @override
  State<_Lyrics> createState() => _LyricsState();
}

class _LyricsState extends State<_Lyrics> {
  var _keys = <GlobalKey>[];
  Object? _shown;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.n, fg = widget.fg;
    if (_keys.length != n.lines.length) _keys = [for (final _ in n.lines) GlobalKey()];
    // Scrolls to the line being read when it changes.
    if (_shown != (n.lines, n.line) && n.line < _keys.length) {
      _shown = (n.lines, n.line);
      final key = _keys[n.line];
      // Only this list scrolls, not the screen it sits in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final line = key.currentContext?.findRenderObject();
        if (line == null || !_scroll.hasClients) return;
        final to = RenderAbstractViewport.of(line).getOffsetToReveal(line, 0.3).offset;
        _scroll.animateTo(to.clamp(0, _scroll.position.maxScrollExtent),
            duration: Duration(milliseconds: settings.isEink ? 1 : 400), curve: Curves.easeOutCubic);
      });
    }
    if (n.lines.isEmpty) {
      return Center(child: Text(tr('Okumaya başlayınca metin burada akar.'), style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 15)));
    }
    final base = TextStyle(fontSize: widget.size, fontWeight: FontWeight.w700, height: 1.35);
    return SingleChildScrollView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(4, 12, 12, 120),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, s) in n.lines.indexed)
          Padding(
            key: _keys[i],
            padding: const EdgeInsets.only(bottom: 14),
            child: i != n.line || n.word == null
                ? Text(s.text, style: base.copyWith(color: fg.withValues(alpha: i == n.line ? 1 : 0.45)))
                : Text.rich(
                    TextSpan(style: base.copyWith(color: fg), children: [
                      TextSpan(text: s.text.substring(0, n.word!.start)),
                      TextSpan(
                          text: s.text.substring(n.word!.start, min(n.word!.end, s.text.length)),
                          style: TextStyle(backgroundColor: fg.withValues(alpha: 0.22))),
                      TextSpan(text: s.text.substring(min(n.word!.end, s.text.length))),
                    ]),
                  ),
          ),
      ]),
    );
  }
}

/// About the author or the book, shortened until tapped, with where it came from as a link.
class _AboutCard extends StatefulWidget {
  const _AboutCard({required this.title, required this.about, required this.fg, required this.color});
  final String title;
  final Future<About?> about;
  final Color fg, color;
  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final fg = widget.fg;
    return FutureBuilder<About?>(
      future: widget.about,
      builder: (context, snap) {
        final a = snap.data;
        final waiting = snap.connectionState != ConnectionState.done;
        return GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
            decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(widget.title), style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (waiting)
                Padding(padding: const EdgeInsets.only(bottom: 12), child: LinearProgressIndicator(minHeight: 2, color: fg, backgroundColor: fg.withValues(alpha: 0.15)))
              else if (a == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(tr(settings.onlineLookup ? 'Bilgi bulunamadı.' : 'İnternetten bilgi bulma kapalı (Ayarlar).'),
                      style: TextStyle(color: fg.withValues(alpha: 0.6), fontSize: 14)),
                )
              else ...[
                Text(a.text, maxLines: _open ? null : 5, overflow: _open ? null : TextOverflow.ellipsis, style: TextStyle(color: fg, fontSize: 14.5, height: 1.45)),
                TextButton.icon(
                  onPressed: () => openUrl(a.url),
                  style: TextButton.styleFrom(foregroundColor: fg.withValues(alpha: 0.75), padding: EdgeInsets.zero),
                  icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  label: Text('${tr('Kaynak')}: ${a.source}', style: const TextStyle(fontSize: 12.5)),
                ),
              ],
            ]),
          ),
        );
      },
    );
  }
}

// ---- listening shelves --------------------------------------------------------------------------------

/// Asks for a shelf's name; null if the reader changed their mind.
Future<String?> askShelfName(BuildContext context, {String initial = ''}) async {
  final c = settings.palette;
  final field = TextEditingController(text: initial);
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: c.paper,
      title: Text(tr(initial.isEmpty ? 'Yeni dinleme rafı' : 'Rafın adını değiştir'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
      content: TextField(
        controller: field,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: tr('Rafın adı')),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Vazgeç'))),
        TextButton(onPressed: () => Navigator.pop(context, field.text), child: Text(tr(initial.isEmpty ? 'Oluştur' : 'Kaydet'))),
      ],
    ),
  );
  field.dispose();
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty || library.shelves.containsKey(trimmed) ? null : trimmed;
}

/// Ticks for each listening shelf [b] can be on, and a way to make a new one with it.
List<Widget> shelfItems(BuildContext context, Book b) => [
      for (final name in library.shelves.keys)
        CheckboxMenuButton(
          value: library.shelves[name]!.contains(b.path),
          closeOnActivate: false,
          onChanged: (_) => library.toggleOnShelf(name, b),
          child: Text(name),
        ),
      MenuItemButton(
        leadingIcon: Icon(Icons.add, size: 18, color: settings.palette.accent),
        onPressed: () async {
          final name = await askShelfName(context);
          if (name != null) library.toggleOnShelf(name, b);
        },
        child: Text(tr('Yeni dinleme rafı'), style: TextStyle(color: settings.palette.accent)),
      ),
    ];

/// Adds the book to listening shelves from the player.
class ShelfButton extends StatelessWidget {
  const ShelfButton({super.key, required this.book, required this.color});
  final Book book;
  final Color color;

  @override
  Widget build(BuildContext context) => MenuAnchor(
        menuChildren: shelfItems(context, book),
        builder: (_, m, _) => IconButton(
          tooltip: tr('Dinleme rafına ekle'),
          icon: Icon(library.shelves.values.any((s) => s.contains(book.path)) ? Icons.playlist_add_check_rounded : Icons.playlist_add_rounded, color: color, size: 28),
          onPressed: () => m.isOpen ? m.close() : m.open(),
        ),
      );
}

/// Reads [name]'s books aloud one after another, from the first not finished.
void playShelf(String name) {
  final books = library.shelfBooks(name);
  if (books.isEmpty) return;
  library.playing = name;
  final first = books.where((b) => b.total == 0 || b.page + 1 < b.total).firstOrNull ?? books.first;
  openRequest.value = (first.path, true);
}

/// A listening shelf's books in playing order: play, reorder, take off, rename, delete.
class ShelfScreen extends StatelessWidget {
  const ShelfScreen({super.key, required this.name});
  final String name;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: library,
        builder: (context, _) {
          final c = settings.palette;
          final books = library.shelfBooks(name);
          return Scaffold(
            backgroundColor: c.paper,
            appBar: AppBar(
              backgroundColor: c.paper,
              foregroundColor: c.ink,
              elevation: 0,
              scrolledUnderElevation: 0,
              title: Text(name, style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.ink)),
              actions: [
                IconButton(
                  tooltip: tr('Rafın adını değiştir'),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final to = await askShelfName(context, initial: name);
                    if (to == null || !context.mounted) return;
                    library.renameShelf(name, to);
                    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => ShelfScreen(name: to)));
                  },
                ),
                IconButton(
                  tooltip: tr('Rafı sil'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    library.removeShelf(name);
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
            body: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Row(children: [
                  Expanded(
                    child: Text('${books.length} ${tr('kitap')} · ${tr('Rafı silmek kitapları silmez.')}', style: TextStyle(color: c.muted, fontSize: 13)),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
                    onPressed: books.isEmpty ? null : () => playShelf(name),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(tr('Dinle')),
                  ),
                ]),
              ),
              if (books.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr('Raf boş. Bir kitaba uzun basıp ya da dinlerken oynatıcıdan ekle.'),
                      textAlign: TextAlign.center, style: TextStyle(color: c.muted, fontSize: 14)),
                ),
              Expanded(
                child: ReorderableListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onReorderItem: (from, to) => library.moveOnShelf(name, from, to),
                  children: [
                    for (final b in books)
                      ListTile(
                        key: ValueKey(b.path),
                        leading: SizedBox(width: 36, height: 52, child: BookCover(book: b, ribbon: false)),
                        title: Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 15)),
                        subtitle: Text([?b.info['author'], if (b.audio != null) tr('sesli kitap')].join(' · '),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 13)),
                        trailing: IconButton(
                          tooltip: tr('Raftan çıkar'),
                          icon: Icon(Icons.remove_circle_outline, color: c.muted),
                          onPressed: () => library.toggleOnShelf(name, b),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          );
        },
      );
}

/// The library's row of listening shelves; each opens its [ShelfScreen].
List<Widget> listeningShelves(BuildContext context) {
  if (library.shelves.isEmpty) return const [];
  final c = settings.palette;
  return [
    SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
      sliver: SliverToBoxAdapter(child: Text(tr('Dinleme rafları'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 19))),
    ),
    SliverToBoxAdapter(
      child: SizedBox(
        height: 64,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            for (final name in library.shelves.keys)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ShelfScreen(name: name))),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
                    decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      SizedBox(
                        width: 36,
                        height: 52,
                        child: switch (library.shelfBooks(name).firstOrNull) {
                          final b? => BookCover(book: b, ribbon: false),
                          null => Icon(Icons.queue_music_rounded, color: c.muted),
                        },
                      ),
                      const SizedBox(width: 10),
                      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: TextStyle(color: c.ink, fontSize: 14, fontWeight: FontWeight.w500)),
                        Text('${library.shelfBooks(name).length} ${tr('kitap')}', style: TextStyle(color: c.muted, fontSize: 12)),
                      ]),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    const SliverToBoxAdapter(child: SizedBox(height: 22)),
  ];
}

