<div align="center">

<img src="docs/assets/icon.png" width="120" height="120" alt="EgeBookReader icon" style="border-radius:24px">

<h1>EgeBookReader</h1>

<p><strong>An ebook and comic reader built around how reading feels.</strong><br>
Pages that really turn, an actual book mode, black-and-white manga coloured on your phone, and books read aloud.<br>
Free, open source, no account and no ads.</p>

<p>
  <a href="https://egebookreader.vercel.app/download/EgeBookReader.apk"><img alt="Download APK" src="https://img.shields.io/badge/download-APK-a8492f?style=for-the-badge&logo=android&logoColor=white"></a>
  <a href="https://egebookreader.vercel.app"><img alt="Website" src="https://img.shields.io/badge/website-egebookreader.vercel.app-231f1b?style=for-the-badge&logo=vercel&logoColor=white"></a>
</p>

<p>
  <img alt="Android 7+" src="https://img.shields.io/badge/Android-7%2B-3DDC84?logo=android&logoColor=white">
  <img alt="Flutter 3.47" src="https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white">
  <img alt="Works offline" src="https://img.shields.io/badge/works-offline-7E3321">
  <img alt="Version 0.2.0" src="https://img.shields.io/badge/version-0.2.0%20preview-F59E0B">
  <a href="LICENSE"><img alt="License: AGPL-3.0" src="https://img.shields.io/badge/license-AGPL--3.0-2EA043"></a>
</p>

<p>
  <a href="#why-egebookreader">Why</a> ·
  <a href="#gallery">Gallery</a> ·
  <a href="#features">Features</a> ·
  <a href="#install">Install</a> ·
  <a href="#build-from-source">Build</a> ·
  <a href="#known-limitations">Limitations</a> ·
  <a href="ROADMAP.md">Roadmap</a>
</p>

<img src="docs/assets/cover.gif" width="340" alt="The website's animated book cover: an E whose middle arm is a waving ribbon, with fantasy, science fiction and film noir silhouettes standing up and folding away">

</div>

> [!NOTE]
> **0.2.0 is a preview for Android.** It has been tested on an emulator and by its author on one phone. iOS, Windows, macOS and Linux will come from the same code later.

## Why EgeBookReader

Most readers show you a document. This one tries to give you a book.

- **A page you can hold.** Take it by the corner, the edge or the middle. The curl follows your finger, in single-page and two-page layouts.
- **It looks printed.** Actual book mode adds paper grain, the shadow of the fold, lighting, the stack of pages at the sides and a shadow on the table.
- **Colour for black and white.** A small model on your phone colours manga and other pictures, offline. Only colour is added, so every line and letter stays where it was.
- **Listen when your eyes are tired.** Use the phone's voice, download a better one, or bring your own API key.
- **Nothing leaves your phone.** No account, no analytics. The internet is used only when you ask for a font, a model or a cloud voice.

## Gallery

<table>
  <tr>
    <td width="33%"><img src="docs/assets/flip.jpg" alt="A page curling under the finger"></td>
    <td width="33%"><img src="docs/assets/book.jpg" alt="Actual book mode on parchment, with side pages and a shadow on the table"></td>
    <td width="33%"><img src="docs/assets/colorize.jpg" alt="A black-and-white comic page after colorization, in the same place and at the same size"></td>
  </tr>
  <tr>
    <td align="center"><sub>The page follows your finger</sub></td>
    <td align="center"><sub>Actual book mode</sub></td>
    <td align="center"><sub>Colorized on the phone</sub></td>
  </tr>
  <tr>
    <td><img src="docs/assets/onboarding.jpg" alt="First-run setup comparing the original page with two colorizers"></td>
    <td><img src="docs/assets/viewer.jpg" alt="A picture opened over the dimmed page, with a colour switch"></td>
    <td><img src="docs/assets/settings.jpg" alt="The settings sheet with themes"></td>
  </tr>
  <tr>
    <td align="center"><sub>Setup compares the models</sub></td>
    <td align="center"><sub>Tap a picture to open it</sub></td>
    <td align="center"><sub>Settings over the live page</sub></td>
  </tr>
  <tr>
    <td><img src="docs/assets/library.jpg" alt="The library with a continue-reading card and a Calibre book with its cover"></td>
    <td><img src="docs/assets/highlights.jpg" alt="Two sentences highlighted in green and yellow, with the note sheet open"></td>
    <td><img src="docs/assets/widget.jpg" alt="The bookshelf widget on the home screen with four books and a read-aloud button"></td>
  </tr>
  <tr>
    <td align="center"><sub>The library</sub></td>
    <td align="center"><sub>Highlights and notes</sub></td>
    <td align="center"><sub>A bookshelf on the home screen</sub></td>
  </tr>
  <tr>
    <td><img src="docs/assets/player.jpg" alt="The full-screen player with the cover, a seek bar and the words being read"></td>
    <td><img src="docs/assets/search.jpg" alt="A search result opened on its page, the matched word marked"></td>
    <td><img src="docs/assets/eink.jpg" alt="A page in E-ink mode, black on white"></td>
  </tr>
  <tr>
    <td align="center"><sub>The audiobook player</sub></td>
    <td align="center"><sub>Search inside a book</sub></td>
    <td align="center"><sub>E-ink mode</sub></td>
  </tr>
</table>

<p align="center">
  <img src="docs/assets/spread.jpg" width="760" alt="Landscape: two pages side by side, with the right page turning over">
  <br>
  <sub>Turn the phone and you get two pages, with the spine in the middle.</sub>
</p>

### Colorization examples

Done on the phone with the two downloadable models. Lines and lettering are untouched.

<table>
  <tr>
    <th width="33%">Original</th>
    <th width="33%">Model 1: DDColor</th>
    <th width="33%">Model 2: Manga Light Colorizer</th>
  </tr>
  <tr>
    <td><img src="docs/assets/compare-manga-orig.jpg" alt="A black-and-white manga page"></td>
    <td><img src="docs/assets/compare-manga-ddcolor.jpg" alt="The page coloured by DDColor"></td>
    <td><img src="docs/assets/compare-manga-manga.jpg" alt="The page coloured by Manga Light Colorizer"></td>
  </tr>
  <tr>
    <td><img src="docs/assets/compare-book-orig.jpg" alt="A black-and-white book illustration"></td>
    <td><img src="docs/assets/compare-book-ddcolor.jpg" alt="The illustration coloured by DDColor"></td>
    <td><img src="docs/assets/compare-book-manga.jpg" alt="The illustration coloured by Manga Light Colorizer"></td>
  </tr>
</table>

<sub><em>Give My Regards to Black Jack</em> by SHUHO SATO. Pepper&amp;Carrot by David Revoy, CC BY 4.0, converted to grayscale.</sub>

## Features

### Library

- **Bring books in** from files, from a folder (with Calibre's titles, series and covers when it is a Calibre library), or from a computer on the same Wi-Fi: Add book, From a computer over Wi-Fi shows an address to open in the computer's browser. A watched folder (Settings, Library) adds the books put in it each time the app opens.
- **Ratings, series and a recently added shelf.** Rate a book from 1 to 5 stars in its sheet; sort by rating, or by series in volume order.
- **Pick several books** with the tick button to favourite, list, file or remove them together.
- **Home-screen bookshelf**: a widget with the last 3 or last 5 books. A cover opens its book; the button reads the first one aloud, and pauses or stops it while it speaks.
- **Reading statistics**: minutes a day, a daily goal, a streak and pages turned, kept only on the phone.
- **Favourites, your own lists, categories and tags.** A book can sit in several categories and lists. Long-press a book to change any of them, or to set your own cover picture (and go back to the original).
- **Search** the shelf by title, author, publisher or tag; Turkish letters and accents match without typing them ("ornegi" finds "Örneği").
- **Grid or list.** The list shows each book's cover, author and progress in one row.
- **Backup** in Settings, Library: the whole library (books, progress, bookmarks, tags, lists, listening shelves, covers, audiobook files) in one file saved where you choose. Restoring adds what is missing and leaves what is already there.
- **Automatic backup**, daily or weekly, into a folder you pick once (a Google Drive folder works). The three newest are kept. On a new phone Android's own backup brings the library's records back, and the app offers to restore the books from your newest backup.
- **Sort and filter** from the bar above the shelf: by last read, date added, publication date (newest or oldest first), or title, author or publisher (A to Z or Z to A, in Turkish alphabetical order), or in sections by category. The filter sheet narrows by reading status, category, tag, format and language.
- **Book details** are read from the file when a book is added: title, author, publisher, date, language, ISBN, series, description and subjects, from EPUB, PDF, MOBI/AZW3, FB2, DOCX, ODT, HTML, Markdown, RTF and ComicInfo.xml in comics. A manga that says it reads right to left opens that way.
- **Find online** looks the book up on Open Library and suggests a category, tags and missing details. The search text starts as the title and author and can be edited, with a button to put it back. It runs by itself for new books unless switched off in Settings, Library; only the search text is sent.
- **Details** shows what the library, the file and Open Library each say, side by side. Tick the values to keep, edit any with the pencil, and save them into the book.
- **Gallery.** Every coloured picture in one place. Tap the page label under an open picture to jump to that page of its book.

### Turning pages

- **Flip** is the default. A cylinder curl drawn per pixel in a GPU shader, driven by where you grab the page. It settles with a spring and keeps the speed of your swipe.
- **Tap zones.** Draw rectangles and circles on the screen and give each one a job: previous, next, menu, bookmark. Portrait and landscape have separate layouts.
- **Right to left** for manga, set per book. The page lifts from the left edge, the left side of the screen turns forward, two-page spreads read right to left, and the page bar runs from the right.
- **Panel by panel** for comics: the panel button zooms from one panel to the next, in reading order (right to left for manga).
- **Two-page spreads** for comics: Automatic (in landscape), Single or Double. The cover and wide pages stand alone; a wide page spans both halves.
- **Webtoons** scroll as one long strip: a comic whose pages are mostly taller than twice their width always scrolls, fitted to the width with no gap. In Scroll mode every comic and DjVu page keeps its own shape.
- **Endless vertical scroll**, with an adjustable gap between pages (2 px by default).
- **Volume keys** turn pages in every mode, and can be inverted.
- **Search inside a book** with the magnifier: every match with its sentence, found the way the library search finds ("sef" finds "Şef"). Tap one to open its page with the word marked.
- **Pinch to zoom.** Two fingers always zoom and one finger always turns, decided the moment the second finger lands. Zoomed pages are redrawn sharp.

### Formats

| Kind | Extensions |
|-|-|
| Books | EPUB, MOBI, AZW, AZW3, PRC, FB2, FBZ |
| Documents | PDF, DjVu, DOCX, ODT, RTF, HTML, XHTML, Markdown, TXT |
| Comics | CBZ, CBR, CB7, CBT |

DRM-protected books are not opened; the app says so. PDFs have a reflow switch, which pours the text into the reading layout.

### Themes and type

- **Paper, Parchment, OLED, E-ink and Custom**, each in light and dark. E-ink turns off every animation, gradient and texture, shows pictures in crisp grey, and refreshes the whole screen every few page turns to clear ghosting. It is picked by itself on the first start on an Onyx Boox, Kobo, PocketBook or similar reader.
- **Your own background:** a colour or a picture, with an overlay, brightness and blur. Text colour is measured against it and the background softens by itself until the text reaches 4.5:1 contrast.
- **About 2,100 free fonts** with live previews, filtered by style and script. Add your own from a file or a URL.
- **Flawless scripts.** Text is shaped with its language, so Turkish keeps the dot on its i, and Chinese, Hindi, Russian and Arabic set correctly.
- Dark PDFs recolour the type and leave photographs alone.

### Pictures

- **Filters** for saturation, contrast and sharpness, and a high-quality upscale. They apply to pictures only, never to text.
- **Sepia and tinted scans count as black and white.** The app looks at how many hue families a picture has, so only pictures that really have colour are left alone.
- **Colorize on demand** with the button on a picture. The same button then switches between colour and the original.
- **Colorize automatically:** the first pages when a book opens, the rest one by one in the background, resting between pictures and pausing when the phone is warm or saving battery.
- **Tap a picture** to open it over a dimmed page, zoom in and switch its colour.
- **Gallery** of everything coloured, with the book and page under each picture.
- **AI upscaling** for small scans: Real-ESRGAN enlarges pictures shown larger than their real size, a tile at a time, in the background.
- **Speech balloons translated** on the phone: long-press a comic page (or use the translate button) and each balloon is read (PP-OCRv5) and translated (Opus-MT), English to Turkish and Japanese to English or Turkish, laid over the original. "Show original" switches back.

### Read aloud

- Each word is marked like a yellow highlighter as it is read, and the page turns by itself.
- Drag the bar on the player, or hold the marker and move it: the highlight follows live and the voice goes there.
- Speaking speed from 0.5x to 3x. Tap the speed button on the player to step through speeds, or hold it for a slider.
- Keeps reading with the screen off or another app in front. Pause, resume and stop from the notification, the lock screen or headphone buttons. Music is turned down under the voice instead of drowning it, and unplugging headphones pauses it.
- The system voice is the default. Each downloadable voice lists its languages, license and source.
- Any service with an OpenAI-style `/audio/speech` endpoint works with your own key.
- **Voiced ahead, offline.** With automatic voicing on, the phone voices the pages ahead with a model voice in the background, resting between sentences and slowing down when it is warm, so listening never waits. Or pick a range of pages (50 to 150, say) and see the words, the time to prepare and the time to listen before you start. If listening catches up, a sheet lets you switch voice or turn the voice off.
- **Natural Turkish voices**: Antalia-2 Mini and Ahenk Cep, offline, with numbers, dates and abbreviations read out in Turkish.
- **Your own voice**: read a text aloud for about 30 seconds and a converter (OpenVoice v2) makes any model voice sound like you. Only a short voice print is kept; the recording is deleted.

### Audiobook player

- Tap the reading bar's cover for a full-screen player: the cover, the title and author, the words scrolling like lyrics with the current one marked, a seek bar, speed and a heart for favourites.
- About the author and about the book, from Wikipedia (in your language, then the book's, then English) or Open Library, only while online lookups are on.
- **Listening shelves**, like playlists: put books on a shelf in the order you want and press Listen; the next book starts when one ends.
- **Your own audiobook**: attach an mp3, m4a or m4b to a book. Its chapters are read from the file and the pages follow the audio.

### Notes and highlights

- Long-press a sentence: highlight it in one of four colours, add a note, copy it, look a word up with any dictionary app on the phone, or share it as a picture with the book's name.
- The contents sheet lists every highlight and note; export them as a Markdown file.

### Reading comfort

The time left in the chapter and the book, learnt from your own pace. Dark pages by the clock (from and to times of your own). Brightness by sliding a finger along the left edge. A top bar in the cover's colour. An error log you can save and send. Library with covers and a continue-reading card, bookmarks on a ribbon, table of contents, a page scrubber, a screen that stays on while you read, and a first-run guide that lets you hear the voices and compare the colorizers. The interface is in English and Turkish.

## Downloadable models

Nothing here ships in the app. Each model comes from its authors' own release when you ask for it, or, where we converted it for phones, from this project's [models-v1](https://github.com/Ege-BULUT/EgeBookReader/releases/tag/models-v1) release.

| Model | Purpose | Download | License | Source |
|-|-|-|-|-|
| Manga Light Colorizer | Manga and comics | 191 MB | CC BY-NC-SA 4.0 | [sharky172](https://huggingface.co/sharky172/manga-light-colorizer) |
| DDColor | Photographs | 206 MB | Apache-2.0 | [piddnad/DDColor](https://github.com/piddnad/DDColor) |
| Supertonic 3 | 10 voices, 31 languages including Turkish | 122 MB | MIT code, OpenRAIL-M model | [Supertone](https://github.com/supertone-oss-archive/supertonic) |
| Kokoro 1.1 | 103 voices, English and Chinese | 140 MB | Apache-2.0 | [hexgrad](https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh) |
| Antalia-2 Mini | Turkish voice | see app | Apache-2.0 | [cloud0day3](https://huggingface.co/spaces/cloud0day3/antalia-mini) |
| Ahenk Cep | Turkish voice | see app | CC BY 4.0 (Özgür Güler) | [ozgurguler](https://huggingface.co/ozgurguler/ahenk-cep-tr) |
| OpenVoice v2 converter | Your own voice | 35 MB | MIT | [myshell-ai/OpenVoice](https://github.com/myshell-ai/OpenVoice) |
| Real-ESRGAN animevideov3 | Upscaling scans | 2.5 MB | BSD-3 | [xinntao/Real-ESRGAN](https://github.com/xinntao/Real-ESRGAN) |
| PP-OCRv5 mobile | Reading speech balloons | 5 to 17 MB | Apache-2.0 | [PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR), via [RapidOCR](https://github.com/RapidAI/RapidOCR) |
| Opus-MT | Translating balloons (en-tr, ja-en) | 36 to 110 MB | Apache-2.0 | [Helsinki-NLP](https://huggingface.co/Helsinki-NLP) |

Manga Light Colorizer's license forbids commercial use. EgeBookReader is free and will stay free.

## Install

1. Download the [APK](https://egebookreader.vercel.app/download/EgeBookReader.apk) on an arm64 Android phone.
2. Allow installs from your browser when Android asks.
3. Open the app. The setup takes a minute, and every step can be skipped.

Every version, with its notes, is also on [GitHub Releases](https://github.com/Ege-BULUT/EgeBookReader/releases). The app is not on Google Play yet.

## Build from source

You need [Flutter](https://flutter.dev) 3.47, the Android SDK with the NDK, and a JDK.

```sh
git clone https://github.com/Ege-BULUT/EgeBookReader
cd EgeBookReader/app
flutter test                     # unit, migration (every earlier release's data) and performance tests
tool/e2e.sh <emulator AVD name>  # end-to-end, on a running emulator
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The APK is written to `build/app/outputs/flutter-apk/`.

```
app/lib/        the app: reader, formats, colorizer, voices, setup
app/shaders/    page curl, dark PDF pages, picture filters
app/android/app/src/main/cpp/   native builds of libarchive, xz and DjVuLibre
site/           the website, plain HTML, CSS and JavaScript
memory/         requirements, research and the decisions behind the project
```

## Known limitations

- Android on arm64 only for now.
- DjVu pages are pictures only: no reading aloud, search or table of contents for them yet.
- PDF reflow leaves pictures out.
- Colours from any model are a guess: often good, sometimes wrong.
- Balloon reading misses some narrow balloons and sound effects, and machine translation can get the meaning wrong.
- The upscaler flattens screentone to grey.
- A sentence that crosses two pages is read in two parts.
- Release builds are signed with a development key, so moving to a store build will need one reinstall.

## Contributing

[Report a bug](https://github.com/Ege-BULUT/EgeBookReader/issues/new?labels=bug) or [request a feature](https://github.com/Ege-BULUT/EgeBookReader/issues/new?labels=enhancement). A file that opens badly is the most useful bug report you can send.

## Credits

Sample pages from [Pepper&Carrot](https://www.peppercarrot.com) by David Revoy (CC BY 4.0) and *Give My Regards to Black Jack* by SHUHO SATO. Paper filters are inspired by [Okuma-Reader](https://github.com/DrMint/Okuma-Reader). PDF rendering by [PDFium](https://pdfium.googlesource.com/pdfium/) through [pdfrx](https://github.com/espresso3389/pdfrx), voices run on [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), DjVu through [DjVuLibre](https://djvu.sourceforge.net) (GPL-2.0-or-later), CBR and CB7 through [libarchive](https://github.com/libarchive/libarchive) and [xz](https://github.com/tukaani-project/xz), fonts from [Fontsource](https://fontsource.org). The logo's E is from the Ruthie typeface (OFL), and the website's silhouettes are from [game-icons.net](https://game-icons.net) (CC BY 3.0).

## License

[GNU Affero General Public License v3.0](LICENSE). Made by [Ege BULUT](https://github.com/Ege-BULUT).
