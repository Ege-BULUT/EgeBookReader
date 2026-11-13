// End to end on a phone or emulator, offline: `tool/e2e.sh <device id>`.
// The app runs on folders of its own inside its cache, so the library on the device is never touched.
import 'dart:io';

import 'package:egebookreader/backup.dart';
import 'package:egebookreader/l10n.dart';
import 'package:egebookreader/library_sheets.dart';
import 'package:egebookreader/main.dart' as app;
import 'package:egebookreader/main.dart' show Library, highlightColors, library, settings;
import 'package:egebookreader/reader.dart' show ReaderScreen;
import 'package:egebookreader/settings.dart';
import 'package:egebookreader/tts.dart' show speaker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Sandbox extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Sandbox(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => p.join(root, 'docs');
  @override
  Future<String?> getApplicationCachePath() async => p.join(root, 'cache');
  @override
  Future<String?> getTemporaryPath() async => p.join(root, 'tmp');
  @override
  Future<String?> getApplicationSupportPath() async => p.join(root, 'support');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first run, reading, marks, reopening, search, sort, backup and read aloud', (t) async {
    // Frames in real time until [done], or fail.
    Future<void> until(String what, bool Function() done, {int seconds = 30}) async {
      for (var i = 0; i < seconds * 10; i++) {
        if (done()) return;
        await t.pump(const Duration(milliseconds: 100));
      }
      fail('Waited $seconds s for: $what');
    }

    Future<void> wait(double seconds) async {
      for (var i = 0; i < seconds * 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
    }

    bool shows(Finder f) => f.evaluate().isNotEmpty;

    final cache = await getApplicationCacheDirectory();
    for (final old in cache.listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('e2e-'))) {
      old.deleteSync(recursive: true);
    }
    final root = Directory(p.join(cache.path, 'e2e-${DateTime.now().millisecondsSinceEpoch}'))..createSync();
    PathProviderPlatform.instance = _Sandbox(root.path);

    await app.main();

    // First run: the setup is skipped.
    await until('the setup', () => shows(find.text(tr('Atla'))));
    await t.tap(find.text(tr('Atla')));
    await until('the library', () => shows(find.byType(app.LibraryScreen)));
    await wait(3); // the logo's entrance

    // The samples are there in a new library.
    expect({for (final b in library.books) p.basename(b.path)}, {'Dunyanin Dilleri.epub', 'Sayfa Örneği.pdf', 'Renklendirme Denemesi.epub'});
    final book = library.books.firstWhere((b) => p.basename(b.path) == 'Dunyanin Dilleri.epub');
    final pdfPath = library.books.firstWhere((b) => b.path.endsWith('.pdf')).path;

    // Open a sample.
    await t.tap(find.byKey(ValueKey(book.path)));
    await until('the book to open', () => book.total > 0);
    await wait(1.5);
    final size = t.view.physicalSize / t.view.devicePixelRatio;
    Future<void> tapAt(double x, double y) async {
      await t.tapAt(Offset(size.width * x, size.height * y));
      await wait(1.5);
    }

    // Pages forward and back.
    await tapAt(0.9, 0.5);
    expect(book.page, 1);
    await tapAt(0.9, 0.5);
    expect(book.page, 2);
    await tapAt(0.1, 0.5);
    expect(book.page, 1);

    // A bookmark, from the menu's ribbon.
    await tapAt(0.5, 0.5);
    await t.tap(find.byKey(const ValueKey('bookmark')));
    await wait(1);
    expect(book.bookmarks, hasLength(1));
    await tapAt(0.5, 0.5);

    // A highlight: a long press on a sentence, then the first colour.
    final dot = find.byWidgetPredicate((w) =>
        w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color == Color(highlightColors.first));
    for (final (x, y) in [(0.3, 0.3), (0.5, 0.4), (0.3, 0.5), (0.5, 0.6), (0.3, 0.2), (0.5, 0.7)]) {
      await t.longPressAt(Offset(size.width * x, size.height * y));
      await wait(1.5);
      if (shows(dot)) break;
    }
    expect(dot, findsOneWidget, reason: 'a long press on the page found no sentence');
    await t.tap(dot);
    await wait(0.5);
    expect(book.highlights, hasLength(1));
    await tapAt(0.5, 0.05); // outside the sheet

    // Closed: back in the library.
    await t.binding.handlePopRoute();
    await until('the reader to close', () => !shows(find.byType(ReaderScreen)));
    await wait(1);

    // Read again from the files, as a fresh start would: place, bookmark and highlight survived.
    await library.flush();
    final fresh = Library();
    await fresh.load();
    await fresh.flush();
    final kept = fresh.books.firstWhere((b) => b.path == book.path);
    expect(kept.page, 1);
    expect(kept.bookmarks, book.bookmarks);
    expect(kept.highlights.single.text, book.highlights.single.text);

    // Reopened, it opens where it was left.
    await t.tap(find.byKey(ValueKey(book.path)));
    await until('the reader', () => shows(find.byType(ReaderScreen)));
    await wait(3);
    expect(book.page, 1);

    // Read aloud with the phone's voice, then stop.
    expect(settings.voiceSource, VoiceSource.system);
    await tapAt(0.5, 0.5);
    await t.tap(find.byTooltip(tr('Sesli oku')));
    await until('reading aloud', () => speaker.active, seconds: 15);
    await wait(2);
    await t.tap(find.byIcon(Icons.close_rounded).last);
    await wait(0.5);
    expect(speaker.active, isFalse);
    await t.binding.handlePopRoute();
    await until('the reader to close', () => !shows(find.byType(ReaderScreen)));
    await wait(1);

    // Search: the book by a word of its title, and not the PDF.
    await t.tap(find.byTooltip(tr('Ara')));
    await wait(0.5);
    await t.enterText(find.byType(TextField), book.title.split(' ').first);
    await wait(1);
    expect(find.byKey(ValueKey(book.path)), findsOneWidget);
    expect(find.byKey(ValueKey(pdfPath)), findsNothing);
    await t.tap(find.byTooltip(tr('Aramayı kapat')));
    await wait(1);

    // Sort by title, from the sort sheet: the shelf follows.
    await t.tap(find.text(tr(settings.sortBy.label)));
    await wait(1);
    await t.tap(find.text(tr(SortBy.title.label)).last);
    await wait(0.5);
    await tapAt(0.5, 0.05);
    expect(settings.sortBy, SortBy.title);
    final expected = [for (final b in sortBooks(library.books, SortBy.title, settings.sortDescending)) b.path];
    Offset at(String path) => t.getTopLeft(find.byKey(ValueKey(path)));
    final onScreen = [for (final b in library.books) b.path]
      ..sort((a, b) => at(a).dy != at(b).dy ? at(a).dy.compareTo(at(b).dy) : at(a).dx.compareTo(at(b).dx));
    expect(onScreen, expected);

    // A backup in a folder, a book removed, then restored with what was kept for it.
    final backups = Directory(p.join(root.path, 'backups'))..createSync();
    final made = await writeBackup();
    final copy = made.copySync(p.join(backups.path, p.basename(made.path)));
    made.deleteSync();
    final removed = library.books.firstWhere((b) => b.path == book.path);
    await library.remove(removed);
    await wait(1);
    expect(find.byKey(ValueKey(book.path)), findsNothing);
    expect(await restoreBackup(copy.path), 1);
    await wait(1);
    expect(find.byKey(ValueKey(book.path)), findsOneWidget);
    final back = library.books.firstWhere((b) => b.path == book.path);
    expect(back.page, 1);
    expect(back.bookmarks, kept.bookmarks);
    expect(back.highlights.single.text, kept.highlights.single.text);
  });
}
