import 'dart:convert';
import 'dart:io';

/// Categories a book can be filed under, in the order the library shows them. The names are keys for tr().
const categories = ['Çizgi roman', 'Roman', 'Bilim kurgu', 'Fantastik', 'Polisiye', 'Çocuk', 'Şiir', 'Biyografi', 'Tarih', 'Felsefe', 'Bilim', 'Diğer'];

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

/// Open Library's subjects for the book called [title]: empty when it is not known, null when it could not be asked.
/// Only the title is sent.
Future<List<String>?> lookUpSubjects(String title) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.https('openlibrary.org', '/search.json', {'q': title, 'fields': 'subject', 'limit': '1'}));
    request.headers.set(HttpHeaders.userAgentHeader, 'EgeBookReader (egebulut.iletisim@outlook.com)');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    final docs = json['docs'] as List<dynamic>? ?? const [];
    if (docs.isEmpty) return const [];
    return ((docs.first as Map<String, dynamic>)['subject'] as List<dynamic>? ?? const []).cast<String>();
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}
