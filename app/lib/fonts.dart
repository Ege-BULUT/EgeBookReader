import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'l10n.dart';
import 'main.dart' show settings;

final fonts = FontStore();

class CatalogFont {
  CatalogFont(this.id, this.family, this.category, this.subsets, this.weights, this.styles, this.license);
  final String id, family, category, license;
  final List<String> subsets, styles;
  final List<int> weights;
}

class InstalledFont {
  InstalledFont(this.family, this.name, this.fallbacks, this.license);
  final String family, name, license;
  final List<String> fallbacks;
  Map<String, dynamic> toJson() => {'family': family, 'name': name, 'fallbacks': fallbacks, 'license': license};
}

Future<Uint8List> _get(String url, {int maxBytes = 40 << 20}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
    final out = BytesBuilder(copy: false);
    await for (final chunk in response) {
      out.add(chunk);
      if (out.length > maxBytes) throw const FormatException('Dosya çok büyük');
    }
    return out.takeBytes();
  } finally {
    client.close();
  }
}

/// Fontsource needs no API key and serves plain TTF files per script; see research/fonts-design.md.
class FontStore extends ChangeNotifier {
  static const _api = 'https://api.fontsource.org/v1/fonts';
  late Directory _dir;
  final installed = <String, InstalledFont>{};
  final _previews = <String, Future<String?>>{};
  int _running = 0;
  final _waiting = <Completer<void>>[];

  File get _index => File(p.join(_dir.path, 'installed.json'));

  Future<void> load() async {
    _dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'fonts'));
    await _dir.create(recursive: true);
    if (!_index.existsSync()) return;
    for (final e in jsonDecode(_index.readAsStringSync()) as List<dynamic>) {
      final j = e as Map<String, dynamic>;
      final f = InstalledFont(j['family'] as String, j['name'] as String,
          (j['fallbacks'] as List<dynamic>).cast<String>(), j['license'] as String? ?? '');
      installed[f.family] = f;
      for (final family in [f.family, ...f.fallbacks]) {
        await _register(family);
      }
    }
  }

  Future<void> _save() => _index.writeAsString(jsonEncode(installed.values.toList()));

  List<String> fallbacksOf(String family) => installed[family]?.fallbacks ?? const [];

  String nameOf(String family) => switch (family) {
        'serif' => tr('Serif (sistem)'),
        'sans-serif' => tr('Sans (sistem)'),
        'monospace' => tr('Monospace (sistem)'),
        _ => installed[family]?.name ?? family,
      };

  Future<void> _register(String family) async {
    final dir = Directory(p.join(_dir.path, family));
    if (!dir.existsSync()) return;
    final loader = FontLoader(family);
    for (final f in dir.listSync().whereType<File>()) {
      loader.addFont(f.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  Future<List<CatalogFont>> catalog() async {
    final cache = File(p.join(_dir.path, 'catalog.json'));
    String? text;
    final fresh = cache.existsSync() && DateTime.now().difference(cache.lastModifiedSync()).inDays < 7;
    if (!fresh) {
      try {
        text = utf8.decode(await _get(_api));
        await cache.writeAsString(text);
      } catch (_) {
        // offline: the last copy below will do
      }
    }
    text ??= cache.existsSync() ? cache.readAsStringSync() : null;
    if (text == null) throw const SocketException('Font listesi alınamadı');
    return (jsonDecode(text) as List<dynamic>).map((e) {
      final j = e as Map<String, dynamic>;
      return CatalogFont(
        j['id'] as String,
        j['family'] as String,
        j['category'] as String,
        (j['subsets'] as List<dynamic>).cast<String>(),
        (j['weights'] as List<dynamic>).cast<int>(),
        (j['styles'] as List<dynamic>).cast<String>(),
        j['license'] as String? ?? '',
      );
    }).toList();
  }

  Future<void> _slot() async {
    if (_running < 4) {
      _running++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeAt(0).complete();
    } else {
      _running--;
    }
  }

  /// A small file with the regular face, enough to set the font's own name in it. Null if it cannot be had.
  Future<String?> preview(CatalogFont f) => _previews[f.id] ??= _loadPreview(f);

  Future<String?> _loadPreview(CatalogFont f) async {
    final family = 'preview-${f.id}';
    final file = File(p.join(_dir.path, 'previews', '${f.id}.ttf'));
    await _slot();
    try {
      if (!file.existsSync()) {
        final subset = f.subsets.contains('latin') ? 'latin' : f.subsets.first;
        final weight = f.weights.contains(400) ? 400 : f.weights.first;
        final style = f.styles.contains('normal') ? 'normal' : f.styles.first;
        await file.create(recursive: true);
        await file.writeAsBytes(await _get('https://cdn.jsdelivr.net/fontsource/fonts/${f.id}@latest/$subset-$weight-$style.ttf'));
      }
      await (FontLoader(family)..addFont(file.readAsBytes().then(ByteData.sublistView))).load();
      return family;
    } catch (_) {
      if (file.existsSync()) file.deleteSync();
      return null;
    } finally {
      _release();
    }
  }

  /// Downloads regular, bold and italic faces for every script the font has. CJK scripts come in
  /// numbered slices that are left out: the system's CJK fonts cover those glyphs.
  Future<String> install(CatalogFont f, void Function(double) onProgress) async {
    final detail = jsonDecode(utf8.decode(await _get('$_api/${f.id}'))) as Map<String, dynamic>;
    final variants = detail['variants'] as Map<String, dynamic>;
    final weight = f.weights.contains(400) ? 400 : f.weights.first;
    final bold = f.weights.contains(700) ? 700 : null;
    final jobs = <(String subset, int weight, String style, String url)>[];
    for (final w in [weight, ?bold]) {
      final byStyle = variants['$w'] as Map<String, dynamic>;
      for (final style in byStyle.keys) {
        final bySubset = byStyle[style] as Map<String, dynamic>;
        for (final subset in bySubset.keys.where((s) => !s.startsWith('['))) {
          final url = (bySubset[subset] as Map<String, dynamic>)['url'] as Map<String, dynamic>;
          jobs.add((subset, w, style, url['ttf'] as String));
        }
      }
    }
    if (jobs.isEmpty) throw const FormatException('Bu fontun indirilecek dosyası yok');
    final base = 'ebr-${f.id}';
    String familyOf(String subset) => subset == 'latin' ? base : '$base--$subset';
    var done = 0;
    for (final j in jobs) {
      final file = File(p.join(_dir.path, familyOf(j.$1), '${j.$2}-${j.$3}.ttf'));
      await file.create(recursive: true);
      await file.writeAsBytes(await _get(j.$4));
      onProgress(++done / jobs.length);
    }
    final families = jobs.map((j) => familyOf(j.$1)).toSet().toList();
    final main = families.contains(base) ? base : families.first;
    final others = families.where((x) => x != main).toList();
    for (final family in families) {
      await _register(family);
    }
    installed[main] = InstalledFont(main, f.family, others, f.license);
    await _save();
    notifyListeners();
    return main;
  }

  // ponytail: magic-number check only; run OTS or a full parse before the font reaches FreeType (research/fonts-design.md §custom fonts).
  Future<String> installBytes(Uint8List bytes, String name) async {
    if (bytes.length < 12) throw const FormatException('Bu bir font dosyası değil');
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic == 'wOFF' || magic == 'wOF2') {
      throw const FormatException('WOFF henüz desteklenmiyor, TTF veya OTF kullan');
    }
    final isSfnt = magic == 'OTTO' || magic == 'true' || magic == 'ttcf' || (bytes[0] == 0 && bytes[1] == 1 && bytes[2] == 0 && bytes[3] == 0);
    if (!isSfnt) throw const FormatException('Bu bir font dosyası değil');
    final family = 'ebr-custom-${name.hashCode.toRadixString(16)}';
    final file = File(p.join(_dir.path, family, 'font.ttf'));
    await file.create(recursive: true);
    await file.writeAsBytes(bytes);
    await _register(family);
    installed[family] = InstalledFont(family, name, const [], '');
    await _save();
    notifyListeners();
    return family;
  }

  Future<String> installUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) throw const FormatException('Geçerli bir adres değil');
    return installBytes(await _get(uri.toString()), p.basenameWithoutExtension(uri.path));
  }
}

const _scripts = {
  'latin-ext': 'Türkçe',
  'cyrillic': 'Кириллица',
  'devanagari': 'देवनागरी',
  'arabic': 'العربية',
  'greek': 'Ελληνικά',
  'vietnamese': 'Tiếng Việt',
};

const _categories = {'serif': 'Serif', 'sans-serif': 'Sans', 'display': 'Display', 'handwriting': 'El yazısı', 'monospace': 'Mono'};

class FontBrowser extends StatefulWidget {
  const FontBrowser({super.key});
  @override
  State<FontBrowser> createState() => _FontBrowserState();
}

class _FontBrowserState extends State<FontBrowser> {
  List<CatalogFont>? _all;
  String? _error;
  String _query = '';
  String? _category, _script;
  final _progress = <String, double>{};

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    setState(() => _error = null);
    try {
      final list = await fonts.catalog();
      if (mounted) setState(() => _all = list);
    } catch (_) {
      if (mounted) setState(() => _error = tr('Font listesi alınamadı. İnternet bağlantını kontrol et.'));
    }
  }

  void _show(Object e) {
    if (!mounted) return;
    final text = e is FormatException ? tr(e.message) : tr('İndirilemedi. Bağlantını kontrol et.');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _use(String family) {
    HapticFeedback.selectionClick();
    settings.update((x) => x.fontFamily = family);
  }

  Future<void> _download(CatalogFont f) async {
    setState(() => _progress[f.id] = 0);
    try {
      final family = await fonts.install(f, (v) {
        if (mounted) setState(() => _progress[f.id] = v);
      });
      if (mounted) _use(family); // a download that ends after leaving this screen must not change the font
    } catch (e) {
      _show(e);
    }
    if (mounted) setState(() => _progress.remove(f.id));
  }

  Future<void> _fromFile() async {
    final picked = await FilePicker.pickFiles();
    if (picked.isEmpty || picked.first.path == null) return;
    try {
      final path = picked.first.path!;
      _use(await fonts.installBytes(await File(path).readAsBytes(), p.basenameWithoutExtension(path)));
    } catch (e) {
      _show(e);
    }
  }

  Future<void> _fromUrl() async {
    final c = settings.palette;
    final field = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.paper,
        title: Text(tr('Adresten font ekle'), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        content: TextField(
          controller: field,
          autofocus: true,
          keyboardType: TextInputType.url,
          style: TextStyle(color: c.ink),
          decoration: const InputDecoration(hintText: 'https://…/font.ttf'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Vazgeç'))),
          TextButton(onPressed: () => Navigator.pop(context, field.text), child: Text(tr('Ekle'))),
        ],
      ),
    );
    if (url == null || url.trim().isEmpty) return;
    try {
      _use(await fonts.installUrl(url));
    } catch (e) {
      _show(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([settings, fonts]),
      builder: (context, _) {
        final c = settings.palette;
        final q = _query.toLowerCase();
        final list = (_all ?? const <CatalogFont>[])
            .where((f) =>
                (q.isEmpty || f.family.toLowerCase().contains(q)) &&
                (_category == null || f.category == _category) &&
                (_script == null || f.subsets.contains(_script)))
            .toList();
        final local = ['serif', 'sans-serif', 'monospace', ...fonts.installed.keys];
        return Scaffold(
          backgroundColor: c.paper,
          appBar: AppBar(
            backgroundColor: c.paper,
            foregroundColor: c.ink,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Text(tr('Fontlar'), style: TextStyle(fontFamily: 'serif', fontSize: 22, color: c.ink)),
            actions: [
              TextButton(onPressed: _fromFile, style: TextButton.styleFrom(foregroundColor: c.accent), child: Text(tr('Dosya'))),
              TextButton(onPressed: _fromUrl, style: TextButton.styleFrom(foregroundColor: c.accent), child: const Text('URL')),
            ],
          ),
          body: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(color: c.ink),
                  decoration: InputDecoration(
                    hintText: tr('Ara'),
                    hintStyle: TextStyle(color: c.muted),
                    filled: true,
                    fillColor: c.surface,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _chips(_categories, _category, (v) => setState(() => _category = v))),
            SliverToBoxAdapter(child: _chips(_scripts, _script, (v) => setState(() => _script = v))),
            SliverPadding(
              padding: const EdgeInsets.only(top: 6),
              sliver: SliverList.builder(
                itemCount: local.length,
                itemBuilder: (_, i) => _row(family: local[i], title: fonts.nameOf(local[i]), selected: settings.fontFamily == local[i], onTap: () => _use(local[i])),
              ),
            ),
            SliverToBoxAdapter(child: Divider(color: c.line, height: 22, indent: 20, endIndent: 20)),
            if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
                    TextButton(onPressed: _loadCatalog, child: Text(tr('Tekrar dene'))),
                  ]),
                ),
              )
            else if (_all == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
                ),
              )
            else
              SliverList.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final f = list[i];
                  final mine = 'ebr-${f.id}';
                  final have = fonts.installed.containsKey(mine);
                  return _CatalogRow(
                    key: ValueKey(f.id),
                    font: f,
                    installed: have,
                    selected: settings.fontFamily == mine,
                    progress: _progress[f.id],
                    onTap: () => have ? _use(mine) : _download(f),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ]),
        );
      },
    );
  }

  Widget _chips(Map<String, String> options, String? value, ValueChanged<String?> onChanged) {
    final c = settings.palette;
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        children: [
          for (final e in options.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onChanged(value == e.key ? null : e.key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == e.key ? c.accent : c.surface,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(tr(e.value), style: TextStyle(color: value == e.key ? c.paper : c.ink, fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row({required String family, required String title, required bool selected, required VoidCallback onTap}) {
    final c = settings.palette;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Text(title, style: TextStyle(color: c.ink, fontFamily: family, fontFamilyFallback: fonts.fallbacksOf(family), fontSize: 20)),
          ),
          if (selected) Icon(Icons.check, color: c.accent, size: 20),
        ]),
      ),
    );
  }
}

class _CatalogRow extends StatefulWidget {
  const _CatalogRow({super.key, required this.font, required this.installed, required this.selected, required this.progress, required this.onTap});
  final CatalogFont font;
  final bool installed, selected;
  final double? progress;
  final VoidCallback onTap;
  @override
  State<_CatalogRow> createState() => _CatalogRowState();
}

class _CatalogRowState extends State<_CatalogRow> {
  String? _family;

  @override
  void initState() {
    super.initState();
    // Fast scrolling passes many rows; only the ones that stay get their font fetched.
    Future<void>.delayed(const Duration(milliseconds: 160), () async {
      if (!mounted) return;
      final family = await fonts.preview(widget.font);
      if (mounted && family != null) setState(() => _family = family);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final f = widget.font;
    return InkWell(
      onTap: widget.progress == null ? widget.onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedOpacity(
                opacity: _family == null ? 0.45 : 1,
                duration: const Duration(milliseconds: 220),
                child: Text(f.family, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontFamily: _family, fontSize: 21)),
              ),
              const SizedBox(height: 2),
              Text('${tr(_categories[f.category] ?? f.category)} · ${f.license}', style: TextStyle(color: c.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 12),
          if (widget.progress != null)
            SizedBox.square(dimension: 20, child: CircularProgressIndicator(value: widget.progress, strokeWidth: 2, color: c.accent))
          else if (widget.selected)
            Icon(Icons.check, color: c.accent, size: 20)
          else if (!widget.installed)
            Icon(Icons.download_outlined, color: c.muted, size: 20),
        ]),
      ),
    );
  }
}
