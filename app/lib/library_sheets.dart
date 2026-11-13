import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'l10n.dart';
import 'main.dart' show Book, BookCover, library, settings;
import 'meta.dart';
import 'player.dart';
import 'settings.dart';
import 'shelf.dart';

/// [books] in the order the reader chose. Books missing the sorted fact go last; ties keep the library's order.
List<Book> sortBooks(List<Book> books, SortBy by, bool descending) {
  Comparable<Object>? key(Book b) => switch (by) {
        SortBy.opened => b.opened == 0 ? null : b.opened,
        SortBy.added => b.added == 0 ? null : b.added,
        SortBy.published => yearOf(b.info['date']),
        SortBy.title => sortKey(b.title),
        SortBy.author => b.info['author'] == null ? null : sortKey(b.info['author']!),
        SortBy.publisher => b.info['publisher'] == null ? null : sortKey(b.info['publisher']!),
        SortBy.category => sortKey(tr(b.shelves.first)),
        SortBy.rating => b.rating == 0 ? null : b.rating,
        SortBy.series => b.info['series'] == null ? null : '${sortKey(b.info['series']!)}\u0000${volumeOf(b).toStringAsFixed(3).padLeft(12, '0')}',
      };
  final keyed = [for (final (i, b) in books.indexed) (i, b, key(b))];
  keyed.sort((x, y) {
    final (a, b) = (x.$3, y.$3);
    if (a == null || b == null) return a == b ? x.$1.compareTo(y.$1) : (a == null ? 1 : -1);
    final c = descending ? b.compareTo(a) : a.compareTo(b);
    return c != 0 ? c : x.$1.compareTo(y.$1);
  });
  return [for (final k in keyed) k.$2];
}

/// A section per series, in the order first met, its books by number; books in no series together.
Map<String, List<Book>> seriesSections(List<Book> books) {
  final out = <String, List<Book>>{};
  for (final b in books) {
    (out[b.info['series'] ?? tr('Seride değil')] ??= []).add(b);
  }
  for (final l in out.values) {
    l.sort((x, y) => volumeOf(x).compareTo(volumeOf(y)));
  }
  return out;
}

/// What the library search looks through, folded: the title, the shorter details and the tags.
String searchText(Book b) => foldForSearch([b.title, ...b.info.values.where((v) => v.length < 200), ...b.tags].join('\n'));

/// The book's number in its series, for ordering; books without one go after.
double volumeOf(Book b) => double.tryParse(RegExp(r'\d+(\.\d+)?').firstMatch(b.info['volume'] ?? '')?.group(0) ?? '') ?? 1e6;

String directionLabel(SortBy by, bool descending) =>
    tr(by.newestFirst ? (descending ? 'Önce en yeni' : 'Önce en eski') : (descending ? 'Z → A' : 'A → Z'));

String readingState(Book b) => b.total == 0 ? 'Okunmamış' : (b.page + 1 >= b.total ? 'Bitti' : 'Okunuyor');
String formatOf(Book b) => p.extension(b.path).replaceFirst('.', '').toUpperCase();

/// The filter sheet's choices. Within a group any choice matches; across groups all must.
class LibraryFilter {
  final states = <String>{}, categories = <String>{}, tags = <String>{}, formats = <String>{}, languages = <String>{};
  List<Set<String>> get _all => [states, categories, tags, formats, languages];
  int get count => _all.fold(0, (n, s) => n + s.length);

  /// The choices as one value, to tell whether they changed.
  String get signature => [for (final s in _all) (s.toList()..sort()).join('\u0001')].join('\u0002');
  void clear() {
    for (final s in _all) {
      s.clear();
    }
  }

  bool matches(Book b) =>
      (states.isEmpty || states.contains(readingState(b))) &&
      (categories.isEmpty || b.shelves.any(categories.contains)) &&
      (tags.isEmpty || b.tags.any(tags.contains)) &&
      (formats.isEmpty || formats.contains(formatOf(b))) &&
      (languages.isEmpty || languages.contains(b.info['language']));
}

Widget _chip(String label, bool on, VoidCallback tap, {Widget? avatar}) {
  final c = settings.palette;
  return FilterChip(
    selected: on,
    showCheckmark: false,
    avatar: avatar,
    label: Text(label),
    labelStyle: TextStyle(color: on ? c.paper : c.ink, fontSize: 13),
    selectedColor: c.accent,
    backgroundColor: c.surface,
    side: BorderSide(color: on ? c.accent : c.line),
    onSelected: (_) => tap(),
  );
}

Widget _label(String text) => Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(tr(text), style: TextStyle(color: settings.palette.muted, fontSize: 13)),
    );

Widget _sheetTitle(String text) => Text(tr(text), style: TextStyle(color: settings.palette.ink, fontFamily: 'serif', fontSize: 21));

/// Shows a sheet sized to its content, at most most of the screen, scrolling past that.
Future<void> showShelfSheet(BuildContext context, Widget Function(BuildContext) child) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
          child: SafeArea(child: child(context)),
        ),
      ),
    );

/// One row per way to order the shelf. A tap picks it; a tap on the one already picked turns the order round.
class SortSheet extends StatelessWidget {
  const SortSheet({super.key});

  static const _icons = {
    SortBy.opened: Icons.menu_book_outlined,
    SortBy.added: Icons.library_add_outlined,
    SortBy.published: Icons.event_outlined,
    SortBy.title: Icons.sort_by_alpha,
    SortBy.author: Icons.person_outline,
    SortBy.publisher: Icons.apartment_outlined,
    SortBy.category: Icons.category_outlined,
    SortBy.rating: Icons.star_outline_rounded,
    SortBy.series: Icons.collections_bookmark_outlined,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final s = settings;
          final c = s.palette;
          return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(12, 18, 12, 12), children: [
            Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 4), child: _sheetTitle('Sırala')),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(tr('Seçili olana tekrar dokunursan sıra tersine döner.'), style: TextStyle(color: c.muted, fontSize: 13)),
            ),
            for (final by in SortBy.values)
              ListTile(
                dense: true,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                selected: s.sortBy == by,
                selectedTileColor: c.surface,
                leading: Icon(_icons[by], color: s.sortBy == by ? c.accent : c.muted, size: 21),
                title: Text(tr(by.label), style: TextStyle(color: c.ink, fontSize: 15, fontWeight: s.sortBy == by ? FontWeight.w600 : FontWeight.w400)),
                trailing: s.sortBy != by
                    ? null
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(directionLabel(by, s.sortDescending), style: TextStyle(color: c.accent, fontSize: 13)),
                        const SizedBox(width: 4),
                        Icon(s.sortDescending ? Icons.arrow_downward : Icons.arrow_upward, size: 16, color: c.accent),
                      ]),
                onTap: () => s.update((x) {
                  if (x.sortBy == by) {
                    x.sortDescending = !x.sortDescending;
                  } else {
                    x.sortBy = by;
                    x.sortDescending = by.newestFirst;
                  }
                }),
              ),
          ]);
        },
      );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key, required this.filter, required this.onChanged});
  final LibraryFilter filter;
  final VoidCallback onChanged;
  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  void _flip(Set<String> set, String value) {
    setState(() => set.remove(value) || set.add(value));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    final f = widget.filter;
    final books = library.books;
    final count = <String, int>{};
    for (final t in books.expand((b) => b.tags)) {
      count[t] = (count[t] ?? 0) + 1;
    }
    final tags = (count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!))).take(24);
    final formats = {for (final b in books) formatOf(b)}.toList()..sort();
    final languages = {for (final b in books) ?b.info['language']}.toList()..sort();
    Widget group(String title, Iterable<String> values, Set<String> set, {bool translate = false}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(title),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in values) _chip(translate ? tr(v) : v, set.contains(v), () => _flip(set, v)),
            ]),
          ],
        );
    final shown = books.where(f.matches).length;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 18, 24, 8), children: [
          _sheetTitle('Filtrele'),
          group('Durum', const ['Okunmamış', 'Okunuyor', 'Bitti'], f.states, translate: true),
          group('Kategori', categories.where((k) => books.any((b) => b.shelves.contains(k))), f.categories, translate: true),
          if (tags.isNotEmpty) group('Etiket', tags, f.tags),
          if (formats.length > 1) group('Biçim', formats, f.formats),
          if (languages.length > 1) group('Dil', languages, f.languages),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          TextButton(
            onPressed: f.count == 0
                ? null
                : () {
                    setState(f.clear);
                    widget.onChanged();
                  },
            child: Text(tr('Temizle')),
          ),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
            onPressed: () => Navigator.pop(context),
            child: Text('${tr('Göster')} ($shown)'),
          ),
        ]),
      ),
    ]);
  }
}

/// What a long press on a book opens: cover, favourite, categories, lists, tags, the online search and its details.
class BookSheet extends StatefulWidget {
  const BookSheet({super.key, required this.book, required this.newList});
  final Book book;
  final Future<String?> Function() newList;
  @override
  State<BookSheet> createState() => _BookSheetState();
}

class _BookSheetState extends State<BookSheet> {
  final _tag = TextEditingController();
  late final _query = TextEditingController(text: widget.book.query ?? widget.book.defaultQuery);
  bool _looking = false;
  bool _offline = false;

  @override
  void dispose() {
    _tag.dispose();
    _query.dispose();
    super.dispose();
  }

  void _addTag(String text) {
    final t = text.trim();
    if (t.isNotEmpty && !widget.book.tags.contains(t)) {
      widget.book.tags.add(t);
      library.changed();
    }
    _tag.clear();
  }

  void _setQuery(String text) {
    final b = widget.book;
    b.query = text.trim().isEmpty || text == b.defaultQuery ? null : text;
    library.changed();
  }

  Future<void> _lookUp() async {
    FocusScope.of(context).unfocus();
    setState(() => _looking = true);
    final ok = await library.lookUp(widget.book, replace: true);
    if (mounted) {
      setState(() {
        _looking = false;
        _offline = !ok;
      });
    }
  }

  Future<void> _pickAudio(Book b) async {
    final ok = await pickAudioFor(b);
    if (ok == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Sesli kitap için mp3, m4b ya da m4a dosyası seç.'))));
    }
  }

  Future<void> _pickCover() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    final path = picked.firstOrNull?.path;
    if (path != null) await library.setCover(widget.book, path);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final c = settings.palette;
        final b = widget.book;
        final author = b.info['author'];
        return ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 18, 24, 12), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GestureDetector(onTap: _pickCover, child: SizedBox(width: 58, height: 84, child: BookCover(book: b, ribbon: false))),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(b.title, style: TextStyle(color: c.ink, fontSize: 18, fontWeight: FontWeight.w500)),
                if (author != null) Text(author, style: TextStyle(color: c.muted, fontSize: 13)),
                const SizedBox(height: 4),
                Row(children: [
                  for (var i = 1; i <= 5; i++)
                    GestureDetector(
                      onTap: () {
                        b.rating = b.rating == i ? 0 : i; // the same star again clears the rating
                        library.changed();
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(i <= b.rating ? Icons.star_rounded : Icons.star_outline_rounded, size: 24, color: i <= b.rating ? c.accent : c.muted),
                      ),
                    ),
                ]),
                Wrap(children: [
                  TextButton(
                    onPressed: _pickCover,
                    style: TextButton.styleFrom(padding: const EdgeInsets.only(right: 12), foregroundColor: c.accent),
                    child: Text(tr('Kapak yükle')),
                  ),
                  if (b.customCover != null)
                    TextButton(
                      onPressed: () => library.clearCover(b),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.muted),
                      child: Text(tr('Orijinal kapak')),
                    ),
                ]),
              ]),
            ),
            IconButton(
              tooltip: tr(b.favorite ? 'Favorilerden çıkar' : 'Favorilere ekle'),
              icon: Icon(b.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: b.favorite ? c.accent : c.muted),
              onPressed: () {
                b.favorite = !b.favorite;
                library.changed();
              },
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _dropdown('Kategoriler', [for (final k in categories) if (b.categories.contains(k)) tr(k)], [
                for (final k in categories)
                  CheckboxMenuButton(
                    value: b.categories.contains(k),
                    closeOnActivate: false,
                    onChanged: (_) {
                      if (!b.categories.remove(k)) b.categories.add(k);
                      library.changed();
                    },
                    child: Text(tr(k)),
                  ),
              ]),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _dropdown('Listeler', [for (final l in library.listNames) if (b.lists.contains(l)) l], [
                for (final l in library.listNames)
                  CheckboxMenuButton(
                    value: b.lists.contains(l),
                    closeOnActivate: false,
                    onChanged: (_) {
                      if (!b.lists.remove(l)) b.lists.add(l);
                      library.changed();
                    },
                    child: Text(l),
                  ),
                MenuItemButton(
                  leadingIcon: Icon(Icons.add, size: 18, color: c.accent),
                  onPressed: () async {
                    final name = await widget.newList();
                    if (name == null) return;
                    b.lists.add(name);
                    library.changed();
                  },
                  child: Text(tr('Yeni liste'), style: TextStyle(color: c.accent)),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: _dropdown('Dinleme rafları', [for (final name in library.shelves.keys) if (library.shelves[name]!.contains(b.path)) name],
                  shelfItems(context, b)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextButton.icon(
                onPressed: b.audio != null ? () => library.detachAudio(b) : () => _pickAudio(b),
                style: TextButton.styleFrom(foregroundColor: b.audio != null ? c.muted : c.accent),
                icon: Icon(b.audio != null ? Icons.delete_outline : Icons.audio_file_outlined, size: 18),
                label: Text(tr(b.audio != null ? 'Sesli kitap dosyasını kaldır' : 'Sesli kitap dosyası seç'), maxLines: 2),
              ),
            ),
          ]),
          _fold(b.tags.isEmpty ? tr('Etiketler') : '${tr('Etiketler')} · ${b.tags.join(', ')}', [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in b.tags)
                InputChip(
                  label: Text(t),
                  labelStyle: TextStyle(color: c.ink, fontSize: 13),
                  backgroundColor: c.surface,
                  side: BorderSide(color: c.line),
                  deleteIconColor: c.muted,
                  onDeleted: () {
                    b.tags.remove(t);
                    library.changed();
                  },
                ),
            ]),
            TextField(
              controller: _tag,
              style: TextStyle(color: c.ink, fontSize: 14),
              decoration: InputDecoration(hintText: tr('Etiket ekle'), isDense: true),
              onSubmitted: _addTag,
            ),
          ]),
          _fold(tr('İnternetten bul'), [
            _label('İnternette aranacak metin'),
            TextField(
              controller: _query,
              style: TextStyle(color: c.ink, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                suffixIcon: b.query == null
                    ? null
                    : IconButton(
                        tooltip: tr('Varsayılana dön'),
                        icon: Icon(Icons.restart_alt, color: c.muted, size: 20),
                        onPressed: () {
                          _query.text = b.defaultQuery;
                          _setQuery(b.defaultQuery);
                        },
                      ),
              ),
              onChanged: _setQuery,
              onSubmitted: (_) => _lookUp(),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _looking ? null : _lookUp,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.accent),
                child: Text(tr(_looking ? 'Aranıyor…' : 'İnternetten bul')),
              ),
            ),
            if (_offline) Text(tr('İnternete ulaşılamadı.'), style: TextStyle(color: c.muted, fontSize: 13)),
          ]),
          Row(children: [
            TextButton(
              onPressed: () => showShelfSheet(context, (_) => DetailsSheet(book: b)),
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.accent),
              child: Text(tr('Ayrıntılar')),
            ),
            const Spacer(),
            TextButton(
              onPressed: () {
                library.remove(b);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: c.muted),
              child: Text(tr('Kitaplıktan kaldır')),
            ),
          ]),
        ]);
      },
    );
  }

  /// A button that shows what is picked and opens a menu of ticks; the menu stays open while ticking.
  Widget _dropdown(String label, List<String> picked, List<Widget> items) {
    final c = settings.palette;
    return MenuAnchor(
      menuChildren: items,
      builder: (context, menu, _) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => menu.isOpen ? menu.close() : menu.open(),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
          decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr(label), style: TextStyle(color: c.muted, fontSize: 12)),
                Text(picked.isEmpty ? tr('Seç') : picked.join(', '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: picked.isEmpty ? c.muted : c.ink, fontSize: 14)),
              ]),
            ),
            Icon(Icons.arrow_drop_down, color: c.muted),
          ]),
        ),
      ),
    );
  }

  /// A section that opens on a tap, closed to begin with.
  Widget _fold(String title, List<Widget> children) {
    final c = settings.palette;
    return ExpansionTile(
      dense: true,
      tilePadding: EdgeInsets.zero,
      shape: const Border(),
      collapsedShape: const Border(),
      iconColor: c.muted,
      collapsedIconColor: c.muted,
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 14)),
      children: children,
    );
  }
}

/// One value a fact could take, with where it came from.
class _Choice {
  _Choice(this.value, this.sources);
  String value;
  final Set<String> sources;
}

/// Everything known about a book (in the library, in its file, online) side by side. Ticked values are saved into the book.
class DetailsSheet extends StatefulWidget {
  const DetailsSheet({super.key, required this.book});
  final Book book;
  @override
  State<DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends State<DetailsSheet> {
  final _choices = <String, List<_Choice>>{};
  final _picked = <String, _Choice?>{};
  final _tags = <String>[];
  final _tagsOn = <String>{};
  final _categoriesOn = <String>{};
  final _suggested = <String>{};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = widget.book;
    final file = await readMeta(b.path);
    final sources = {
      'Kitapta': {'title': b.title, ...b.info},
      'Dosyada': file.fields,
      'İnternette': b.online?.fields ?? const {},
    };
    for (final key in metaFields.keys) {
      final list = <_Choice>[];
      for (final MapEntry(key: source, value: fields) in sources.entries) {
        final v = fields[key]?.trim();
        if (v == null || v.isEmpty) continue;
        final same = list.where((x) => x.value == v).firstOrNull;
        same == null ? list.add(_Choice(v, {source})) : same.sources.add(source);
      }
      _choices[key] = list.isEmpty ? [_Choice('', {})] : list;
      _picked[key] = list.where((x) => x.sources.contains('Kitapta')).firstOrNull;
    }
    for (final t in [...b.tags, ...tagsFrom(file.subjects), ...tagsFrom(b.online?.subjects ?? const [])]) {
      if (!_tags.contains(t)) _tags.add(t);
    }
    _tagsOn.addAll(b.tags);
    _categoriesOn.addAll(b.categories);
    _suggested.addAll([categoryFor(file.subjects), categoryFor(b.online?.subjects ?? const [])].nonNulls);
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _edit(String key, _Choice choice) async {
    final c = settings.palette;
    final field = TextEditingController(text: choice.value);
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.paper,
        title: Text(tr(metaFields[key]!), style: TextStyle(color: c.ink, fontFamily: 'serif', fontSize: 20)),
        content: TextField(controller: field, autofocus: true, minLines: 1, maxLines: key == 'description' ? 8 : 2),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Vazgeç'))),
          TextButton(onPressed: () => Navigator.pop(context, field.text.trim()), child: Text(tr('Tamam'))),
        ],
      ),
    );
    field.dispose();
    if (text == null) return;
    setState(() {
      choice.value = text;
      _picked[key] = text.isEmpty ? null : choice;
    });
  }

  void _save() {
    final b = widget.book;
    for (final key in metaFields.keys) {
      final v = _picked[key]?.value.trim() ?? '';
      if (key == 'title') {
        if (v.isNotEmpty) b.title = v;
      } else if (v.isEmpty) {
        b.info.remove(key);
      } else {
        b.info[key] = v;
      }
    }
    b.tags
      ..clear()
      ..addAll(_tags.where(_tagsOn.contains));
    b.categories
      ..clear()
      ..addAll(_categoriesOn);
    library.changed();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = settings.palette;
    if (!_ready) return const SizedBox(height: 200, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    Widget row(String key, _Choice choice) {
      final on = _picked[key] == choice;
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(
          value: on,
          activeColor: c.accent,
          onChanged: choice.value.isEmpty ? null : (v) => setState(() => _picked[key] = v! ? choice : null),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(choice.value.isEmpty ? '—' : choice.value,
                  maxLines: key == 'description' ? 6 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: choice.value.isEmpty ? c.muted : c.ink, fontSize: 14, height: 1.3)),
              if (choice.sources.isNotEmpty)
                Text(choice.sources.map(tr).join(' · '), style: TextStyle(color: c.muted, fontSize: 11)),
            ]),
          ),
        ),
        IconButton(
          tooltip: tr('Düzenle'),
          icon: Icon(Icons.edit_outlined, size: 18, color: c.muted),
          onPressed: () => _edit(key, choice),
        ),
      ]);
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Flexible(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 18, 16, 8), children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _sheetTitle('Ayrıntılar')),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Text(tr('İşaretli bilgiler kitaba kaydedilir. Kalemle düzenleyebilirsin.'), style: TextStyle(color: c.muted, fontSize: 13)),
          ),
          for (final MapEntry(key: key, value: name) in metaFields.entries) ...[
            Padding(padding: const EdgeInsets.only(left: 8), child: _label(name)),
            for (final choice in _choices[key]!) row(key, choice),
          ],
          Padding(padding: const EdgeInsets.only(left: 8), child: _label('Kategoriler')),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (final k in categories)
                _chip(tr(k), _categoriesOn.contains(k), () => setState(() => _categoriesOn.remove(k) || _categoriesOn.add(k)),
                    avatar: _suggested.contains(k) ? Icon(Icons.auto_awesome, size: 14, color: _categoriesOn.contains(k) ? c.paper : c.accent) : null),
            ]),
          ),
          if (_tags.isNotEmpty) ...[
            Padding(padding: const EdgeInsets.only(left: 8), child: _label('Etiketler')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in _tags) _chip(t, _tagsOn.contains(t), () => setState(() => _tagsOn.remove(t) || _tagsOn.add(t))),
              ]),
            ),
          ],
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(children: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Vazgeç'))),
          const Spacer(),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.accent, foregroundColor: c.paper),
            onPressed: _save,
            child: Text(tr('Kaydet')),
          ),
        ]),
      ),
    ]);
  }
}
