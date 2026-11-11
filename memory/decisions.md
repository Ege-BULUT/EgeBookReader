# Decisions

Append-only, newest last. Each entry: date, decision, why, who decided. A reversed decision gets a new entry
that names the old one.

## 2026-11-10 D1 Project home and tracking

- Project in `~/projects/EgeBookReader`, git branch `main`.
- Knowledge base in `memory/`, tracking in `openlead/` (OpenLead workspace).
- Why: the user asked for a knowledge base first because the project is big, and offered OpenLead.
- Decided by: the user (brief).

## 2026-11-10 D2 Communication

- OpenCommunicate identity `egebookreader#2703`, `OPENCOM_HOME=~/.opencommunicate-ebr` (see `process.md`).
- Why: the user wants to talk over OpenCommunicate; a separate identity keeps this session apart from the
  OpenCommunicate project's own session.
- Decided by: the user.

## 2026-11-10 D3 Stack: Flutter on all six targets (provisional until the proof of concept is judged)

- One Flutter UI for Android, iOS, Windows, macOS, Linux and web. Page curl and paper effects are GLSL fragment
  shaders over page images. Native glue in Kotlin/Swift only where the platform demands it (volume keys, background
  work).
- Rune is not used now: Android is not started, iOS is embed-only, the repo is 19 days old with no releases. A Rune
  desktop app would be a second UI codebase. Revisit when it has Android and a stable release. See `research/stack.md`.
- Why: the only option that is stable on all six targets with one UI codebase and custom GPU shaders.
- Decided after the user asked to go straight to a working Android proof of concept. The user can
  overrule this once they have tried it.

## 2026-11-10 D4 Proof of concept scope and engines

- PDF: `pdfrx` (PDFium, BSD/MIT). EPUB: own small parser with Flutter text layout, paginated to images.
- Why: no AGPL decision is forced yet, and both feed the same page-image pipeline that the curl shader needs.
- This does not settle the final engines; see `open-questions.md` (Q1, Q2).
- For the proof of concept only.

## 2026-11-10 D5 Proof of concept shipped to the user for trying

- First APK sent over OpenCommunicate. Contains: library, PDF/EPUB/TXT/CBZ, procedural curl in single and two-page
  layouts, tap and vertical scroll modes, 4 themes in light and dark, typography basics, PDF reflow, volume keys,
  actual book mode.
- Deliberately not in it yet: tap-zone editor, custom theme, font browser, image filters and colorize, read aloud, the
  remaining formats.
- Known limits: PDF reflow drops pictures; dark themes invert whole PDF pages, photos included; lighting in actual
  book mode is baked into the page rather than screen-space.

## 2026-11-10 D6 Logo and proof of concept 2

- Logo (`brand/logo.svg`): an E made of a spine and two page edges, its middle arm the bookmark ribbon. Ink `#2A2622`,
  ribbon `#A8492F`, paper `#F7F4EE`. The ribbon is the app's signature, used for the launch motion, bookmarks and progress.
- The user asked for a logo and more motion in the second proof of concept. Motion added: the splash hands over to the
  ribbon sliding out and the mark travelling to the header; the cover flies from the shelf and swings open, and closes
  back; theme changes uncover the new page with a growing circle; library cards lean under the finger; settings rise in
  sequence; the first open lifts the page corner once as a hint; bookmarks drop as a ribbon and mark the scrubber.
- All of it is off in E-ink and under the system's reduced-motion setting (`motionOn` in `app/lib/motion.dart`).
- Decided by: the user.

## 2026-11-10 D7 Proof of concept 3

- Tap zones (R4.1): rectangles and circles per orientation, last drawn wins, editor in `app/lib/zones.dart`.
- Custom theme (R3.5–R3.7): colour or picture, overlay, brightness, blur, per light/dark; baked once into one image, and
  text colour plus a softening scrim are measured so text reaches 4.5:1.
- Font browser (R6.2, R6.3): Fontsource catalog (no key), previews in each font, TTF per script registered as fallbacks;
  custom fonts by file or URL (TTF/OTF only so far; WOFF is refused; no OTS yet, see the `ponytail:` note in `fonts.dart`).
- The user reported two bugs on a real phone: dark PDFs were a plain inversion including photos (fixed: `page_dark.frag`
  plus image boxes from PDFium, read on PDFium's own isolate because its font callbacks abort on any other), and volume keys
  did nothing in flip mode. The volume keys worked on the emulator; the one difference found was that they were off
  while the menu was open, so that was removed. Not confirmed on the user's phone yet.

## 2026-11-10 D8 Proof of concept 4: image filters and colorize

- Filters (R7.1–R7.3): saturation, contrast, CAS sharpening and Catmull-Rom upscaling in `shaders/image_filter.frag`, applied only to pictures.
- Colorize (R7.4–R7.10): Qualcomm's official DDColor ONNX export (Apache-2.0, 206 MB download, fetched from Qualcomm's public URL so nothing is
  re-hosted), run with `flutter_onnxruntime` on the CPU. Only colour comes from the model, at 256²; results are redrawn in the original
  rectangle, cached by content and listed in the gallery.
- Screentones are black and white dots with no room for colour at their own lightness, so regions are judged on blurred lightness and dots
  are tinted like ink on coloured paper. Found by testing: the first merge left halftones colourless.
- Queue: on-demand jumps the line; auto does the first N pages with pictures before the first open, the rest one by one with a rest as long as the last
  job, pausing while Android reports moderate heat or battery saver.
- The release build needs a keep rule for `ai.onnxruntime.**` (R8 renaming crashes JNI). Compressed native libraries keep the APK at 23 MB, under
  OpenCommunicate's 50 MB limit.
- The sample book `assets/samples/colorize.epub` uses a Pepper&Carrot page (David Revoy, CC BY 4.0), turned grayscale, credited in the book.

## 2026-11-10 D9 Proof of concept 5: read aloud, zoom, picture viewer, new logo motion

- Read aloud (R8): system voice by default, downloadable Supertonic 3 (31 languages including Turkish) and Kokoro 1.1 (English, Chinese) through sherpa-onnx, and any
  OpenAI-style `/audio/speech` service with the user's key. Kitten is left out: under sherpa-onnx 2.x it needs the GPL phonemizer. The API key stays in app-private storage and backups are off.
- sherpa-onnx and the `flutter_onnxruntime` plugin each ship a `libonnxruntime.so` with different symbol versions, so they cannot load together. The plugin is gone; `app/lib/onnx.dart` calls sherpa's copy through the C API.
- Page gestures: one finger turns (or pans when zoomed), two fingers always zoom, decided the moment the second finger lands; after a pinch no turn until all fingers lift. Covered by widget tests, because the emulator cannot do multi-touch through adb.
- A tap on a picture opens the dimmed viewer unless the picture fills over 70% of the page, so comic pages keep their tap zones.
- The system splash is now empty paper; the logo builds itself in Flutter (`_LogoPainter`).
- Added unasked: contents and bookmarks sheet, screen stays on while reading.
- Known limits: speech stops if Android kills the app in the background (no foreground service yet); a sentence crossing two pages is read as two.

## 2026-11-10 D10 Manga Light Colorizer becomes the default colorizer

- The user pointed out the app will stay free and open source, so a non-commercial licence is acceptable. Manga Light Colorizer v6 (sharky172, CC BY-NC-SA 4.0) is offered as a download from
  its author's repository, with the licence on its card. Nothing is re-hosted. If the app is ever monetized this model must go.
- Tried on real pages: the generator alone (no SAM encoder, which saves 109 MB) gives results near the author's own samples, far better than DDColor on comics. 1.1 s on a Mac CPU; about 9 s on the emulator including model load.
- Only its colour is used, merged over the original lightness, so lines and text stay sharp.
- DDColor stays as the option for photographs.
- manga-colorization-v2 has no licence, so all rights are reserved even though it looks abandoned: not distributed.

## 2026-11-10 D11 License

- GNU AGPL-3.0, chosen by the user after a comparison with GPL-3.0, MIT and Apache-2.0. It leaves room for MuPDF and DjVuLibre later. Any hosted web build must offer its source. The iOS App Store remains a risk (`research/formats.md` §1.1).

## 2026-11-10 D12 First public version 0.1.0

- Site at egebookreader.vercel.app, a real book: cover with looping scenes, pages that bend as they turn. Deployed at the user's request.
- First-run setup, English and Turkish interface (`app/lib/l10n.dart`, Turkish strings are the keys).
- Manga sample from "Give My Regards to Black Jack" (SHUHO SATO) under its free secondary-use terms: title and author must stay visible, and the rights holder asks for an email report within a month of publication. The user has to send that.
- The public APK is still debug-signed. Move to a real key before any store; that needs one uninstall on existing phones.

## 2026-11-10 D13 Reading aloud with the screen off

- A foreground service of type mediaPlayback (`ReadingService.kt`) with a partial wake lock keeps the process alive; speaking stays in Dart. Page turns skip the curl and page drawing waits while the screen is off. Asked for by the user.
- Checked on the emulator with Supertonic: the service stayed in the foreground and reading moved on to the next chapter during 2.5 minutes asleep. Audio itself cannot be heard there; the system voice and the notification buttons were not exercised.

## 2026-11-10 D14 Version 0.1.1: word highlight and seeking

- `SpeechMap` in `app/lib/tts.dart` holds positions. System voices report word boundaries (a paced estimate covers engines that do not); on-device and API voices give no timings, so a word's place is its share of the sentence's letters. PDF words come from PDFium's character boxes.
- While the bar or marker is held the voice waits and the highlight follows; on release it speaks from that word. The marker's long press is 170 ms so it wins over the page-turn gesture.
- Checked on the emulator with Supertonic: highlight moves with speech, bar and marker both move it and the voice resumes there. Not exercised: system voice boundaries, PDF highlight.

## 2026-11-10 D15 Version 0.1.2: speaking speed

- Speed slider 0.5x to 3x in 0.1 steps, default 1.0, below the voice choice. Supertonic follows it exactly (0.5x, 1x, 3x gave 10.81, 5.40, 1.80 s for one sentence).
- 0.1.1 was released on GitHub as a prerelease at the user's request; the site still serves 0.1.0-era files until the user asks for a deploy.
- Released on GitHub as a prerelease (v0.1.2) at the user's request; the site was not updated.

## 2026-11-11 D16 CB7

- CB7 opens through libarchive's 7z reader, the same path as CBR (unpacked once to a cache folder). liblzma from xz 5.8.1 (0BSD) is built static and linked in for LZMA and LZMA2, the usual 7z methods; Deflate uses the system zlib.
- Checked on the emulator with three files made by bsdtar (LZMA2, LZMA, Deflate): all three import with their cover and open with all 6 pages. Not checked: BCJ2 filter archives, solid archives with many pages on a slow phone, encrypted 7z (refused like a password-protected CBR).

## 2026-11-11 D17 DjVu and version 0.1.3

- DjVu opens through DjVuLibre 3.5.28 (GPL-2.0-or-later, which may be combined into the AGPL-3.0 app). Only libdjvu is built, from the release tarball, with a hand-written `djvu/config.h`; `djvu/ebr_djvu.cpp` is a small C face (open, page count, page size, render RGBA, close) called from `app/lib/djvu.dart` on helper isolates, one call at a time.
- Each DjVu page is drawn as a picture fitted to the page, so filters, colorize and the gallery work on it. No text layer yet: no reading aloud, search or contents for DjVu.
- A tap on a picture fitted edge to edge in either direction now counts as a tap on the page, so DjVu and landscape comic pages keep their tap zones instead of opening the picture viewer. Found while testing.
- Checked on the emulator with a three-page DjVu made by c44, cjb2 and djvm (two IW44 colour pages, one JB2 text page): cover, all three pages, page count and the middle tap. An in-text EPUB picture still opens the viewer.
- The site was updated to 0.1.3 at the user's request (features, changelog, credits, APK) and deployed to egebookreader.vercel.app.
- Released on GitHub as a prerelease (v0.1.3) at the user's request.
