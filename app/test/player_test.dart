import 'package:egebookreader/main.dart' show Book, Library, settings;
import 'package:egebookreader/player.dart';
import 'package:egebookreader/sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Made with ffmpeg: 6 s of silence, chapters at 0, 2 and 4.5 s; the first has both kinds, the second
  // (-movflags +disable_chpl) only the QuickTime chapter track.
  test('m4b chapters are read from the Nero box and from the QuickTime chapter track', () async {
    expect(await readAudioChapters('test/fixtures/chapters-nero.m4b'), [0, 2, 4.5]);
    expect(await readAudioChapters('test/fixtures/chapters-quicktime.m4b'), [0, 2, 4.5]);
    expect(await readAudioChapters('book.mp3'), isEmpty);
  });

  test('audio chapter i meets contents entry i, and the place maps both ways', () {
    // Chapters at 0, 100 and 300 s of 400; the book's parts start on pages 2, 10 and 50 of 100.
    final (audio, book) = syncAnchors([0, 100, 300], 400, [2, 10, 50], 100);
    expect(audio, [0, 100, 300, 400]);
    expect(book, [0.02, 0.1, 0.5, 1]);
    expect(lerpAlong(audio, book, 50), closeTo(0.06, 1e-9));
    expect(lerpAlong(audio, book, 350), closeTo(0.75, 1e-9));
    expect(lerpAlong(book, audio, 0.3), closeTo(200, 1e-9));
    // Without chapters on one side the whole book is one span.
    final (a, b) = syncAnchors(const [], 400, [2, 10, 50], 100);
    expect(lerpAlong(a, b, 100), 0.25);
    expect(lerpAlong(b, a, 0.5), 200);
  });

  test('library.json from before shelves still loads; the new one keeps the shelves', () {
    final (oldBooks, none) = Library.readIndex([
      {'path': 'a'},
    ]);
    expect(oldBooks.length, 1);
    expect(none, isEmpty);
    final (books, shelves) = Library.readIndex({
      'books': [
        {'path': 'a'},
      ],
      'shelves': {
        'Yol': ['a'],
      },
    });
    expect(books.length, 1);
    expect(shelves, {'Yol': ['a']});
  });

  test('about: Wikipedia languages and Open Library texts', () {
    expect(wikiLanguages('en-US', 'tr'), ['tr', 'en']);
    expect(wikiLanguages('fre', 'tr'), ['tr', 'fr', 'en']);
    expect(wikiLanguages(null, 'en'), ['en']);
    expect(openLibraryText('A bio. '), 'A bio.');
    expect(openLibraryText({'type': '/type/text', 'value': 'Described.'}), 'Described.');
    expect(openLibraryText({'type': '/type/text'}), isNull);
  });

  testWidgets('the now-playing screen lays out on a phone and marks the word being read', (tester) async {
    settings.onlineLookup = false; // no network in tests
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final book = Book('/nowhere/book.epub', 'Kitap', null)..info['author'] = 'Ada Yazar';
    final lines = [
      SpokenSentence('Birinci cümle.', 'tr', 0, const []),
      SpokenSentence('İkinci cümle burada.', 'tr', 0, const [], [SpokenWord(0, 6, const []), SpokenWord(7, 12, const [])]),
    ];
    var seekedTo = -1.0;
    PlayerNow now() => (at: 0.5, listened: const Duration(minutes: 3), left: const Duration(minutes: 3), lines: lines, line: 1, word: lines[1].words[1], paused: false, file: false);
    await tester.pumpWidget(MaterialApp(
      home: NowPlaying(
        book: book, tint: Colors.indigo, ticks: ValueNotifier(0), now: now, lyrics: false, onLyrics: (_) {}, onClose: () {},
        onSeek: (v) => seekedTo = v, onPlayPause: () {}, onStep: (_) {}, onSpeed: () {}, onPickAudio: () {},
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Ada Yazar'), findsOneWidget);
    expect(find.text('3:00'), findsOneWidget);
    expect(find.textContaining('cümle', findRichText: true), findsWidgets);
    await tester.tap(find.byType(Slider));
    expect(seekedTo, closeTo(0.5, 0.05));
  });
}
