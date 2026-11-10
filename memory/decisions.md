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
