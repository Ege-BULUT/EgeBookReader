import 'dart:convert';
import 'dart:io';

import 'meta.dart';

/// Categories a book can be filed under, in the order the library shows them. The names are keys for tr().
const categories = ['Çizgi roman', 'Roman', 'Bilim kurgu', 'Fantastik', 'Polisiye', 'Çocuk', 'Şiir', 'Biyografi', 'Tarih', 'Felsefe', 'Bilim', 'Diğer'];

/// Each category's place in [categories].
final categoriesOrder = {for (final (i, c) in categories.indexed) c: i};

const comicExtensions = {'.cbz', '.cbt', '.cbr', '.cb7'};

/// Words in Open Library subjects that point to each category. A subject counts for the first one it matches.
/// The first six are kinds of story: one mention is enough, since most stories are also tagged plain "Fiction".
const _rules = [
  ('Çizgi roman', ['comic', 'manga', 'graphic novel', 'manhwa', 'webtoon']),
  ('Bilim kurgu', ['science fiction']),
  ('Fantastik', ['fantasy']),
  ('Polisiye', ['detective', 'mystery', 'crime']),
  ('Çocuk', ['juvenile', "children's"]),
  ('Şiir', ['poetry', 'poems']),
  ('Biyografi', ['biography', 'autobiography', 'memoir']),
  ('Tarih', ['history']),
  ('Felsefe', ['philosophy']),
  ('Bilim', ['science', 'mathematics', 'physics', 'biology']),
  ('Roman', ['fiction', 'novel']),
];

/// The category [subjects] point to, or null when none does.
String? categoryFor(Iterable<String> subjects) {
  final votes = List.filled(_rules.length, 0);
  for (final s in subjects.map((s) => s.toLowerCase())) {
    final i = _rules.indexWhere((r) => r.$2.any(s.contains));
    if (i >= 0) votes[i]++;
  }
  final story = votes.indexWhere((v) => v > 0);
  if (story >= 0 && story < 6) return _rules[story].$1;
  var best = -1;
  for (var i = 0; i < votes.length; i++) {
    if (votes[i] > 0 && (best < 0 || votes[i] > votes[best])) best = i;
  }
  return best < 0 ? null : _rules[best].$1;
}

/// A few short subjects worth showing as tags; long catalogue headings ("England -- Fiction") are left out.
List<String> tagsFrom(Iterable<String> subjects) {
  final seen = <String>{};
  return [
    for (final s in subjects.map((s) => s.trim()))
      if (s.isNotEmpty && s.length <= 24 && !s.contains('--') && !s.contains(',') && seen.add(s.toLowerCase())) s,
  ].take(5).toList();
}

/// What Open Library knows about the book [query] names (a title, perhaps with its author): empty when it is not
/// known, null when it could not be asked. Only [query] is sent.
Future<BookMeta?> lookUpOnline(String query) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final uri = Uri.https('openlibrary.org', '/search.json',
        {'q': query, 'fields': 'title,author_name,publisher,first_publish_year,language,isbn,subject', 'limit': '1'});
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, 'EgeBookReader (egebulut.iletisim@outlook.com)');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final docs = json['docs'] as List<dynamic>? ?? const [];
    return docs.isEmpty ? BookMeta() : metaFromOpenLibrary(docs.first as Map<String, dynamic>);
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

BookMeta metaFromOpenLibrary(Map<String, dynamic> doc) {
  List<String> list(String key) => ((doc[key] as List<dynamic>?) ?? const []).map((e) => '$e').toList();
  return BookMeta()
    ..put('title', doc['title'] as String?)
    ..put('author', list('author_name').take(3).join(', '))
    ..put('publisher', list('publisher').firstOrNull)
    ..put('date', doc['first_publish_year']?.toString())
    ..put('language', list('language').firstOrNull)
    ..put('isbn', list('isbn').where((i) => i.length == 13).firstOrNull ?? list('isbn').firstOrNull)
    ..addSubjects(list('subject'));
}

const _alphabet = 'aâbcçdefgğhıiîjklmnoöpqrsştuüûvwxyz';
const _plain = {'á': 'a', 'à': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'í': 'i', 'ì': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ù': 'u', 'ñ': 'n', 'ß': 's', 'ÿ': 'y'};

/// Lower case as Turkish writes it: I becomes ı and İ becomes i.
String turkishLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// A key that puts names in Turkish alphabetical order (c, ç, d … s, ş, t …), other accented letters next to their plain
/// letter, and digits and signs before letters.
// ponytail: one alphabet for every language; per-language collation (ICU) if readers ask for it.
String sortKey(String s) => String.fromCharCodes(turkishLower(s).split('').map((ch) {
      final i = _alphabet.indexOf(_plain[ch] ?? ch);
      return i >= 0 ? 0x1000 + i * 2 + (_plain.containsKey(ch) ? 1 : 0) : ch.codeUnitAt(0);
    }));

/// Text folded for search: Turkish lower case with accents dropped, so "sef" finds "Şef" and "istanbul" finds "İstanbul".
String foldForSearch(String s) => foldWithMap(s).$1;

/// [foldForSearch], plus for each folded character the index in [s] it came from, to find a hit's place in the original.
(String, List<int>) foldWithMap(String s) {
  final out = StringBuffer(), from = <int>[];
  for (var i = 0; i < s.length; i++) {
    final ch = turkishLower(s[i]);
    // ponytail: one UTF-16 unit at a time; a surrogate pair folds as two units, which only matters for emoji.
    for (final f in ch.split('')) {
      out.write(_plain[f] ?? const {'ç': 'c', 'ğ': 'g', 'ı': 'i', 'ö': 'o', 'ş': 's', 'ü': 'u', 'â': 'a', 'î': 'i', 'û': 'u'}[f] ?? f);
      from.add(i);
    }
  }
  return (out.toString(), from);
}
