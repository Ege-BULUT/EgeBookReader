# Roadmap

## Done on Android

Reader, page turning, themes, typography, actual book mode, image filters, colorization, read aloud, picture viewer, all common formats, right-to-left reading, the webtoon strip, and a library with favourites, lists, categories, tags, sorting, filters and book details (0.1.7). Highlights and notes, panel-by-panel comics, reading statistics, ratings and series, imports from a folder, Calibre or Wi-Fi, a home-screen shelf and read aloud from the lock screen (0.2.0).

## Next

Everything stays local and serverless. There is no server of our own. The phone talks straight to public services (Open Library, Wikipedia), models download from GitHub releases, and the free Vercel site and its free add-ons are the only hosting.

1. **0.3.0: search and voices.**
   - Full-text search inside a book.
   - Automatic voicing: pages are voiced ahead and kept, so even a slow phone reads without gaps. Built, waiting for a listening test.
   - Small natural Turkish voices.
   - Cloning the reader's own voice, or a loved one's, on the phone.
2. **0.4.0: audiobook player.** A now-playing screen like a music app:
   - the cover as album art, the words being read as lyrics, the author as artist;
   - about the author and about the book, found online and kept;
   - favourites and listening shelves;
   - audiobook files matched to the ebook.
3. **0.5.0: comics.** Two-page spreads, upscaling low-resolution scans, and finding speech balloons, reading their text and translating it offline.
4. **0.6.0: e-ink mode.** No animations, high contrast and full refreshes, for Boox and similar readers.
5. **Before 1.0: reliability.**
   - Every older library file opens in tests on each release.
   - Automatic backups, and the library survives a new phone.
   - End-to-end tests run on the emulator without a person.
   - Measured limits for a large library, a large PDF and an old phone.
6. **Interface languages.** English and Turkish today. Then Russian, Arabic, Chinese, Japanese, Korean, German, French and Hindi.
7. **More platforms.** iOS, Windows, macOS and Linux from the same code.
