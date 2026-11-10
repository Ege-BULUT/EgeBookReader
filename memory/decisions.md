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
