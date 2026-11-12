import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'main.dart' show library, settings;
import 'sources.dart' show supportedExtensions;

const _android = MethodChannel('egebookreader/volume');

/// A file on its way into the library: where it sits in the folder it came from, and how to get a local copy.
class Incoming {
  Incoming(this.path, this.fetch, {this.local});
  final String path;
  final Future<String> Function() fetch;

  /// Where it already is on the phone, if it is (sent over Wi-Fi); deleted once the import is done.
  final String? local;
}

/// Calibre keeps one book in several formats side by side; the first of these that is there is taken.
const _preferred = ['.epub', '.azw3', '.mobi', '.fb2', '.pdf'];

/// The books among [files], one per Calibre folder, each with that folder's metadata.opf and cover.jpg.
List<(Incoming book, Incoming? opf, Incoming? cover)> booksAmong(List<Incoming> files) {
  final byFolder = <String, List<Incoming>>{};
  for (final f in files) {
    (byFolder[p.dirname(f.path)] ??= []).add(f);
  }
  final found = <(Incoming, Incoming?, Incoming?)>[];
  for (final here in byFolder.values) {
    Incoming? named(String name) => here.where((f) => p.basename(f.path).toLowerCase() == name).firstOrNull;
    final opf = named('metadata.opf'), cover = named('cover.jpg');
    final books = here.where((f) => supportedExtensions.contains(p.extension(f.path).toLowerCase())).toList();
    if (opf != null && books.length > 1) {
      int rank(Incoming f) {
        final i = _preferred.indexOf(p.extension(f.path).toLowerCase());
        return i < 0 ? _preferred.length : i;
      }

      books.sort((a, b) => rank(a) - rank(b));
      books.removeRange(1, books.length);
    }
    for (final b in books) {
      found.add((b, opf, cover));
    }
  }
  return found;
}

/// Brings [files] into the library; returns how many were added and the names that could not be opened.
Future<(int, List<String>)> importAll(List<Incoming> files, {void Function(int done, int of)? progress}) async {
  final books = booksAmong(files);
  var added = 0;
  final failed = <String>[], copies = [for (final f in files) ?f.local];
  Future<String?> get(Incoming? f) async {
    if (f == null) return null;
    final path = await f.fetch();
    if (f.local == null) copies.add(path);
    return path;
  }
  for (final (i, (book, opf, cover)) in books.indexed) {
    progress?.call(i, books.length);
    try {
      if (await library.import((await get(book))!, opf: await get(opf), cover: await get(cover))) added++;
    } catch (_) {
      failed.add(p.basename(book.path));
    }
  }
  // each copy sits alone in a folder of its own
  for (final c in copies) {
    await File(c).parent.delete(recursive: true).catchError((_) => File(c).parent);
  }
  return (added, failed);
}

Future<String> _incoming(String rel) async =>
    p.join((await getApplicationCacheDirectory()).path, 'incoming', '${Random().nextInt(1 << 32)}', p.basename(rel));

// ---- a folder on the phone ---------------------------------------------------------------------------------------

/// Asks for a folder, then brings in every book under it. With [watch] the folder is kept, and books that
/// appear in it later come in on their own each time the app opens.
Future<(int, List<String>)?> importFolder({bool watch = false, void Function(int, int)? progress}) async {
  final uri = await _android.invokeMethod<String>('pickFolder');
  if (uri == null) return null;
  final files = await _list(uri);
  if (watch) {
    settings.update((x) {
      x.watchedFolder = uri;
      x.seenInFolder = {for (final f in files) f.path};
    });
  }
  return importAll(files, progress: progress);
}

Future<List<Incoming>> _list(String uri) async {
  final listed = await _android.invokeListMethod<Map<dynamic, dynamic>>('listFolder', uri) ?? [];
  return [
    for (final f in listed)
      Incoming(f['path'] as String, () async => (await _android.invokeMethod<String>('copyIn', {'uri': f['uri'], 'to': await _incoming(f['path'] as String)}))!),
  ];
}

/// Books that appeared in the watched folder since it was last looked at; 0 when there is none or it is gone.
Future<int> checkWatchedFolder() async {
  final uri = settings.watchedFolder;
  if (uri == null) return 0;
  try {
    final files = await _list(uri);
    final fresh = files.where((f) => !settings.seenInFolder.contains(f.path)).toList();
    if (fresh.isEmpty) return 0;
    // the whole folder counts as seen even if a book fails, so a broken file is not tried at every start
    settings.update((x) => x.seenInFolder = {for (final f in files) f.path});
    // a new book's Calibre opf and cover may have been there before it, so they are looked up among all files
    final folders = {for (final f in fresh) p.dirname(f.path)};
    return (await importAll(files.where((f) => folders.contains(p.dirname(f.path))).toList()
          ..removeWhere((f) => supportedExtensions.contains(p.extension(f.path).toLowerCase()) && !fresh.contains(f))))
        .$1;
  } on PlatformException {
    return 0;
  }
}

// ---- from a computer over Wi-Fi ----------------------------------------------------------------------------------

/// A small web page on the phone, at an address with a random part, where a computer on the same Wi-Fi drops
/// books or a whole folder (a Calibre library too). It runs only while its sheet is open.
class WifiTransfer {
  HttpServer? server;
  final _token = List.generate(6, (_) => Random.secure().nextInt(36).toRadixString(36)).join();
  final _received = <Incoming>[];
  final status = ValueNotifier<String>('');
  String? address;

  Future<void> start() async {
    final s = server = await HttpServer.bind(InternetAddress.anyIPv4, 8080).catchError((_) => HttpServer.bind(InternetAddress.anyIPv4, 0));
    final ips = [for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) ...i.addresses.map((a) => (i.name, a.address))];
    final ip = (ips.where((e) => e.$1.startsWith('wlan')).firstOrNull ?? ips.firstOrNull)?.$2;
    address = ip == null ? null : 'http://$ip:${s.port}/$_token/';
    s.listen((r) => _handle(r).catchError((Object _) => r.response.close()));
  }

  Future<void> stop() async => server?.close(force: true);

  Future<void> _handle(HttpRequest r) async {
    final parts = r.uri.pathSegments;
    final res = r.response;
    if (parts.isEmpty || parts.first != _token) {
      res.statusCode = HttpStatus.notFound;
    } else if (parts.length == 1 || parts[1].isEmpty) {
      if (!r.uri.path.endsWith('/')) {
        await res.redirect(r.uri.replace(path: '${r.uri.path}/'));
        return;
      }
      res.headers.contentType = ContentType.html;
      res.write(_page());
    } else if (parts[1] == 'upload' && r.method == 'PUT') {
      final rel = p.posix.normalize(r.uri.queryParameters['path'] ?? '');
      // a path from the network: only a plain relative one, never out of the folder
      if (rel.isEmpty || rel == '.' || p.posix.isAbsolute(rel) || p.posix.split(rel).contains('..')) {
        res.statusCode = HttpStatus.badRequest;
      } else {
        final local = await _incoming(rel);
        await File(local).create(recursive: true);
        final sink = File(local).openWrite();
        await sink.addStream(r);
        await sink.close();
        _received.add(Incoming(rel, () async => local, local: local));
        status.value = '${tr('Alınan dosya')}: ${_received.length}';
      }
    } else if (parts[1] == 'done' && r.method == 'POST') {
      final files = [..._received];
      _received.clear();
      status.value = tr('Kitaplığa ekleniyor…');
      final (added, failed) = await importAll(files);
      status.value = '${tr('Eklenen kitap')}: $added${failed.isEmpty ? '' : ' · ${tr('Açılamadı')}: ${failed.join(', ')}'}';
      res.headers.contentType = ContentType.json;
      res.write(jsonEncode({'added': added, 'failed': failed}));
    } else {
      res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  }

  String _page() {
    String t(String s) => const HtmlEscape().convert(tr(s));
    return '''<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>EgeBookReader</title>
<style>
body{font:16px/1.5 system-ui,sans-serif;max-width:560px;margin:48px auto;padding:0 16px;background:#f7f3ec;color:#2a2622}
h1{font-family:Georgia,serif;font-weight:400}label{display:block;margin:18px 0;padding:18px;border:1px dashed #b9ab98;border-radius:10px;cursor:pointer}
input{display:block;margin-top:8px}#s{color:#9b4d2e}
</style>
<h1>EgeBookReader</h1>
<p>${t('Kitapları ya da bir klasörü seç; telefondaki kitaplığa eklenir. Calibre kitaplığının klasörünü seçersen adlar, seriler ve kapaklar da gelir.')}</p>
<label>${t('Kitaplar')}<input type="file" multiple id="f"></label>
<label>${t('Klasör')}<input type="file" webkitdirectory id="d"></label>
<p id="s"></p>
<script>
const s = document.getElementById('s');
async function send(list) {
  let i = 0;
  for (const f of list) {
    s.textContent = (++i) + '/' + list.length + ' · ' + f.name;
    const r = await fetch('upload?path=' + encodeURIComponent(f.webkitRelativePath || f.name), {method: 'PUT', body: f});
    if (!r.ok) { s.textContent = '${t('Gönderilemedi')}: ' + f.name; return; }
  }
  s.textContent = '${t('Kitaplığa ekleniyor…')}';
  const j = await (await fetch('done', {method: 'POST'})).json();
  s.textContent = '${t('Eklenen kitap')}: ' + j.added + (j.failed.length ? ' · ${t('Açılamadı')}: ' + j.failed.join(', ') : '');
}
for (const id of ['f', 'd']) document.getElementById(id).onchange = e => send([...e.target.files]);
</script>''';
  }
}

/// The sheet that runs [WifiTransfer] and shows its address.
class WifiSheet extends StatefulWidget {
  const WifiSheet({super.key});
  @override
  State<WifiSheet> createState() => _WifiSheetState();
}

class _WifiSheetState extends State<WifiSheet> {
  final _transfer = WifiTransfer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _transfer.start().then((_) {
      if (mounted) setState(() {});
    }, onError: (Object e) {
      if (mounted) setState(() => _error = tr('Başlatılamadı.'));
    });
  }

  @override
  void dispose() {
    _transfer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Bilgisayardan Wi-Fi ile'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 22)),
          const SizedBox(height: 10),
          Text(tr('Bilgisayar bu telefonla aynı Wi-Fi ağında olsun. Tarayıcıda şu adresi aç; bu pencere açıkken çalışır.'),
              style: TextStyle(color: c.muted, fontSize: 14, height: 1.4)),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: TextStyle(color: c.ink))
          else if (_transfer.server == null)
            SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent))
          else
            SelectableText(_transfer.address ?? tr('Wi-Fi bağlantısı yok.'),
                style: TextStyle(color: c.accent, fontSize: 20, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: _transfer.status,
            builder: (_, v, _) => Text(v, style: TextStyle(color: c.ink, fontSize: 14)),
          ),
        ]),
      ),
    );
  }
}
