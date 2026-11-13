import 'dart:convert';
import 'dart:io';

import 'package:egebookreader/backup.dart';
import 'package:egebookreader/main.dart' show Book, Highlight, Library, highlightColors, library;
import 'package:egebookreader/settings.dart';
import 'package:egebookreader/stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// The app's folders, inside a fresh temporary one.
class _Folders extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Folders(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationCachePath() async => p.join(dir, 'cache');
}

/// A new app folder, made the app's own.
Directory _fresh(String name) {
  final docs = Directory.systemTemp.createTempSync(name);
  PathProviderPlatform.instance = _Folders(docs.path);
  return docs;
}

dynamic _plain(Object? x) => jsonDecode(jsonEncode(x));

List<Map<String, dynamic>> _read(File f) => (jsonDecode(f.readAsStringSync()) as List<dynamic>).cast<Map<String, dynamic>>();

/// A real book file under the app folder: the sample EPUB, so the library can open it if it has to.
void _bookFile(Directory docs, String folder, String name) =>
    (File(p.join(docs.path, folder, name))..createSync(recursive: true)).writeAsBytesSync(File('assets/samples/sample.epub').readAsBytesSync());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Each release's files, as that release wrote them (test/fixtures/<release>/). A new release adds its own folder.
  final releases = [for (final d in Directory('test/fixtures').listSync().whereType<Directory>()) p.basename(d.path)]..sort();

  test('there is a fixture for every release up to this one', () {
    expect(releases, containsAll(['0.1.0', '0.1.8', '0.2.0']));
    expect(releases.last, appVersion);
  });

  for (final release in releases) {
    test('$release: titles, progress, bookmarks, highlights, tags, lists, settings and stats all load', () async {
      final docs = _fresh('ebr-$release');
      for (final f in Directory('test/fixtures/$release').listSync().whereType<File>()) {
        f.copySync(p.join(docs.path, p.basename(f.path)));
      }
      final old = _read(File(p.join(docs.path, 'library.json')));
      // The fixtures were written on a phone; here the app folder is elsewhere, as after a move to a new phone.
      for (final b in old) {
        _bookFile(docs, 'books', p.basename(b['path'] as String));
        if (b['cover'] case final String c) _bookFile(docs, 'covers', p.basename(c));
      }

      final lib = Library();
      await lib.load();
      expect(lib.missing, isEmpty);
      expect(lib.books.length, old.length);
      for (final (i, was) in old.indexed) {
        final now = _plain(lib.books[i]) as Map<String, dynamic>;
        for (final MapEntry(:key, :value) in was.entries) {
          final why = '$release ${was['title']} $key';
          switch (key) {
            case 'path' || 'cover':
              expect(p.basename(now[key] as String? ?? ''), p.basename(value as String? ?? ''), reason: why);
              if (value != null) expect(File(now[key] as String).existsSync(), isTrue, reason: why);
            case 'customCover':
              expect(p.basename(now[key] as String? ?? ''), p.basename(value as String? ?? ''), reason: why);
            case 'category': // one category became several in 0.1.7
              if (value != null) expect(now['categories'], [value], reason: why);
            default:
              expect(now[key], value, reason: why);
          }
        }
      }

      final lists = File(p.join(docs.path, 'lists.json'));
      expect(lib.listNames, lists.existsSync() ? jsonDecode(lists.readAsStringSync()) : isEmpty);

      final oldSettings = jsonDecode(File(p.join(docs.path, 'settings.json')).readAsStringSync()) as Map<String, dynamic>;
      final s = Settings();
      await s.load();
      final now = _plain(s.toJson()) as Map<String, dynamic>;
      for (final MapEntry(:key, :value) in oldSettings.entries) {
        if (key == 'groupByCategory') {
          expect(s.sortBy, value == true ? SortBy.category : SortBy.opened, reason: '$release $key');
        } else {
          expect(now[key], value, reason: '$release $key');
        }
      }

      final statsFile = File(p.join(docs.path, 'stats.json'));
      if (statsFile.existsSync()) {
        final was = jsonDecode(statsFile.readAsStringSync()) as Map<String, dynamic>;
        final stats = ReadingStats();
        await stats.load();
        expect(stats.seconds, was['seconds']);
        expect(stats.pages, was['pages']);
        expect(stats.goalMinutes, was['goal']);
      }

      // What this version writes back is read again the same.
      await lib.flush();
      final again = Library();
      await again.load();
      expect(_plain(again.books), _plain(lib.books));
      expect(again.listNames, lib.listNames);
    });
  }

  test('a cut-short library.json is kept as .broken and the books come back from the books folder', () async {
    final docs = _fresh('ebr-broken');
    File(p.join(docs.path, 'samples-added.txt')).writeAsStringSync('sample.epub\nsample.pdf\ncolorize.epub');
    final whole = File('test/fixtures/0.2.0/library.json').readAsStringSync();
    final cut = whole.substring(0, whole.length ~/ 2);
    File(p.join(docs.path, 'library.json')).writeAsStringSync(cut);
    for (final name in ['Suç ve Ceza.epub', 'Dunyanin Dilleri.epub']) {
      _bookFile(docs, 'books', name);
    }

    final lib = Library();
    await lib.load();
    expect(File(p.join(docs.path, 'library.json.broken')).readAsStringSync(), cut);
    expect({for (final b in lib.books) p.basename(b.path)}, {'Suç ve Ceza.epub', 'Dunyanin Dilleri.epub'});
    expect(lib.books.every((b) => b.title.isNotEmpty), isTrue);
    await lib.flush();
    expect(_read(File(p.join(docs.path, 'library.json'))).length, 2);
  });

  test('a library.json written by this version loads whole, and books without their files are kept, not dropped', () async {
    final docs = _fresh('ebr-newest');
    File(p.join(docs.path, 'samples-added.txt')).writeAsStringSync('sample.epub\nsample.pdf\ncolorize.epub');
    final lib = Library();
    await lib.load();
    _bookFile(docs, 'books', 'Kitap.epub');
    _bookFile(docs, 'covers', 'kapak.png');
    lib.books.add(Book(p.join(docs.path, 'books', 'Kitap.epub'), 'Kitap', p.join(docs.path, 'covers', 'kapak.png'), page: 4, total: 10, bookmarks: [0.4])
      ..rtl = true
      ..favorite = true
      ..categories.addAll(['Roman', 'Tarih'])
      ..tags.add('ödünç')
      ..lists.add('Yaz')
      ..info.addAll({'author': 'Yazar', 'series': 'Seri', 'volume': '2'})
      ..looked = true
      ..metaRead = true
      ..query = 'Kitap Yazar'
      ..added = 1
      ..opened = 2
      ..rating = 3
      ..secondsPerPage = 12.5
      ..highlights.add(Highlight('Bir cümle.', 0.41, 0xFF7BC67E, note: 'not', made: 3)));
    lib.listNames.addAll(['Yaz', 'Boş']);
    // A book whose file is not on this phone (a library Android restored without its books).
    final away = {'path': '/data/user/0/dev.egebulut.egebookreader/app_flutter/books/Uzakta.epub', 'title': 'Uzakta', 'cover': null, 'page': 7, 'total': 9};
    lib.missing.add(away);
    await lib.flush();

    final again = Library();
    await again.load();
    expect(_plain(again.books), _plain(lib.books));
    expect(again.listNames, ['Yaz', 'Boş']);
    expect(again.missing, [away]);
    await again.flush();
    expect(_read(File(p.join(docs.path, 'library.json'))).last, away);
  });

  group('backup', () {
    test('names sort in the order made; only our own names are pruned, three stay', () {
      expect(backupName(DateTime(2026, 1, 2, 3, 4)), 'EgeBookReader-2026-01-02-0304.ebrbackup');
      final listed = [
        for (final d in ['2026-11-10-0900', '2026-11-12-0900', '2026-11-11-0900', '2026-11-13-0900']) {'uri': d, 'path': 'EgeBookReader-$d.ebrbackup'},
        {'uri': 'mine', 'path': 'Benim yedeğim.ebrbackup'},
        {'uri': 'deep', 'path': 'eski/EgeBookReader-2020-01-01-0000.ebrbackup'},
      ];
      expect(staleBackups(listed), ['2026-11-11-0900', '2026-11-10-0900']);
      expect(staleBackups(listed.take(2).toList()), isEmpty);
    });

    test('due once the chosen period has passed, never when off', () {
      final now = DateTime(2026, 11, 13, 12);
      final day = Duration.millisecondsPerDay, at = now.millisecondsSinceEpoch;
      expect(backupDue(0, 0, now), isFalse);
      expect(backupDue(1, 0, now), isTrue);
      expect(backupDue(1, at - day + 1000, now), isFalse);
      expect(backupDue(1, at - day, now), isTrue);
      expect(backupDue(7, at - 3 * day, now), isFalse);
      expect(backupDue(7, at - 7 * day, now), isTrue);
    });

    test('a backup brings a removed book back, and fills a new phone\'s library with the files it lacks', () async {
      final docs = _fresh('ebr-backup');
      File(p.join(docs.path, 'samples-added.txt')).writeAsStringSync('sample.epub\nsample.pdf\ncolorize.epub');
      library.books.clear();
      library.missing.clear();
      await library.load();
      for (final name in ['Bir.epub', 'İki.epub']) {
        _bookFile(docs, 'books', name);
        _bookFile(docs, 'covers', '$name.png');
        library.books.add(Book(p.join(docs.path, 'books', name), name, p.join(docs.path, 'covers', '$name.png'), page: 3, total: 9, bookmarks: [0.3])
          ..opened = 10
          ..highlights.add(Highlight('Altı çizili.', 0.3, highlightColors.first, made: 1)));
      }
      library.listNames.add('Liste');
      final backup = await writeBackup();
      final kept = File(p.join(docs.path, 'kept.ebrbackup'));
      backup.renameSync(kept.path);

      // Removed, then restored: back with its place, bookmark and highlight.
      final two = library.books.last;
      final was = _plain(two);
      await library.remove(two);
      expect(File(two.path).existsSync(), isFalse);
      expect(await restoreBackup(kept.path), 1);
      final back = library.books.last;
      // covers come back under the backup's numbered names
      expect({..._plain(back) as Map<String, dynamic>, 'cover': null}, {...was as Map<String, dynamic>, 'cover': null});
      expect(File(back.path).existsSync(), isTrue);
      expect(File(back.coverPath!).existsSync(), isTrue);

      // A new phone: the library came back without its files, and read on since the backup.
      final restored = _plain(library.books) as List<dynamic>;
      (restored.first as Map<String, dynamic>)
        ..['page'] = 6
        ..['opened'] = 20;
      for (final b in library.books.toList()) {
        await library.remove(b);
      }
      library.listNames.clear();
      library.missing.addAll(restored.cast<Map<String, dynamic>>());
      expect(await restoreBackup(kept.path), 2);
      expect(library.missing, isEmpty);
      expect([for (final b in library.books) b.page], [6, 3]);
      expect([for (final b in library.books) b.highlights.single.text], ['Altı çizili.', 'Altı çizili.']);
      expect(library.listNames, ['Liste']);
      expect(library.books.every((b) => File(b.path).existsSync()), isTrue);
    });
  });
}
