import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:egebookreader/library_sheets.dart';
import 'package:egebookreader/main.dart' show Book, Highlight, Library;
import 'package:egebookreader/settings.dart';
import 'package:egebookreader/shelf.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Folders extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Folders(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationCachePath() async => p.join(dir, 'cache');
}

/// Limits for a 10,000-book library, in milliseconds. Measured on an M1 Mac under `flutter test` (debug, JIT), best
/// of three, and set five to ten times higher (a slow phone's margin), so only a real slowdown fails: the old series
/// grouping, quadratic, took 31 s here. `sort` is all nine orders together. The numbers are in tool/perf.md.
const limits = {'load': 2500, 'save': 1000, 'sort': 5000, 'filter': 100, 'search': 1000, 'sections': 1500};

const books = 10000;

/// The best of [times] runs, so a busy machine does not fail the test.
Future<int> _ms(FutureOr<void> Function() work, {int times = 3}) async {
  var best = 1 << 30;
  for (var i = 0; i < times; i++) {
    final watch = Stopwatch()..start();
    await work();
    best = min(best, watch.elapsedMilliseconds);
  }
  return best;
}

void main() {
  test('a 10,000-book library loads, saves, sorts, filters and searches within its limits', () async {
    final docs = Directory.systemTemp.createTempSync('ebr-perf');
    PathProviderPlatform.instance = _Folders(docs.path);
    File(p.join(docs.path, 'samples-added.txt')).writeAsStringSync('sample.epub\nsample.pdf\ncolorize.epub');
    Directory(p.join(docs.path, 'books')).createSync();
    final random = Random(1);
    const words = ['Kırmızı', 'Şehir', 'Gölge', 'İstanbul', 'Ölüm', 'Çocuk', 'Deniz', 'Ağaç', 'Night', 'Garden', 'Zaman', 'Yıldız'];
    const authors = ['Orhan Pamuk', 'Sabahattin Ali', 'Ursula K. Le Guin', 'Yaşar Kemal', 'Agatha Christie', 'Elif Şafak'];
    String title() => [for (var i = 0; i < 1 + random.nextInt(4); i++) words[random.nextInt(words.length)]].join(' ');

    final setup = Library();
    await setup.load();
    for (var i = 0; i < books; i++) {
      final file = File(p.join(docs.path, 'books', '$i ${title()}.epub'))..writeAsStringSync('');
      setup.books.add(Book(file.path, title(), null, page: random.nextInt(300), total: 300, bookmarks: [random.nextDouble()])
        ..favorite = random.nextInt(10) == 0
        ..categories.add(categories[random.nextInt(categories.length)])
        ..tags.addAll(['etiket ${random.nextInt(40)}', 'tag ${random.nextInt(40)}'])
        ..lists.add('Liste ${random.nextInt(5)}')
        ..info.addAll({
          'author': authors[random.nextInt(authors.length)],
          'publisher': 'Yayınevi ${random.nextInt(50)}',
          'date': '${1900 + random.nextInt(125)}',
          'language': random.nextBool() ? 'tr' : 'en',
          if (random.nextInt(4) == 0) ...{'series': 'Seri ${random.nextInt(300)}', 'volume': '${random.nextInt(12)}'},
        })
        ..added = 1731300000000 + i
        ..opened = random.nextInt(3) == 0 ? 0 : 1731400000000 + random.nextInt(1 << 30)
        ..rating = random.nextInt(6)
        ..highlights.addAll([if (i % 7 == 0) Highlight('Bir cümle, $i.', random.nextDouble(), 0xFFF2C94C, made: 1)]));
    }

    final took = <String, int>{};
    took['save'] = await _ms(setup.flush);
    final lib = Library();
    took['load'] = await _ms(lib.load, times: 1);
    expect(lib.books.length, books);

    took['sort'] = await _ms(() {
      for (final by in SortBy.values) {
        sortBooks(lib.books, by, by.newestFirst);
      }
    });
    final filter = LibraryFilter()
      ..states.add('Okunuyor')
      ..categories.addAll(['Roman', 'Polisiye'])
      ..languages.add('tr');
    var found = 0;
    took['filter'] = await _ms(() => found = lib.books.where((b) => b.favorite || filter.matches(b)).length);
    expect(found, greaterThan(0));
    took['search'] = await _ms(() {
      final folded = {for (final b in lib.books) b: searchText(b)}; // once per library change
      for (final q in ['istanbul', 'sabahattin', 'etiket 3', 'yok böyle bir şey']) {
        found = lib.books.where((b) => folded[b]!.contains(foldForSearch(q))).length;
      }
    });
    took['sections'] = await _ms(() {
      seriesSections(lib.books);
      for (final k in categories) {
        sortBooks(lib.books.where((b) => b.shelves.contains(k)).toList(), SortBy.title, false);
      }
    });

    // ignore: avoid_print
    print('10,000 books, ms: $took');
    for (final MapEntry(:key, :value) in took.entries) {
      expect(value, lessThan(limits[key]!), reason: '$key took $value ms');
    }
    docs.deleteSync(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
