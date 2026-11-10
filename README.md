# EgeBookReader

An ebook and comic reader built around how reading feels. Pages turn under your finger with a real curl, in one-page and two-page layouts, and an "actual book" mode adds paper grain, the fold, side pages and a shadow on the table.

Android is the first target. iOS, Windows, macOS and Linux come later, from the same Flutter code.

## What it does

- **Formats:** PDF, EPUB, MOBI, AZW, AZW3, FB2, CBZ, CBR, CBT, DOCX, ODT, HTML, Markdown, RTF, TXT. DRM-protected books are not opened.
- **Page turning:** finger-tracked curl, tap zones you draw yourself, endless vertical scroll, volume keys.
- **Themes:** Paper, Parchment, OLED, E-ink and your own background, each light and dark. Text colour is chosen so it stays readable.
- **Type:** about 2,100 free fonts with previews, your own fonts by file or URL, CJK, Devanagari, Cyrillic, Turkish and right-to-left text.
- **Pictures:** saturation, contrast, sharpening, upscaling, and optional on-device colorization of black-and-white pages. Works offline. Lines and text keep their original pixels.
- **Read aloud:** the system voice, downloadable on-device voices, or your own API key.

## Build

Needs Flutter 3.47 and the Android SDK with NDK.

```sh
cd app
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
```

## Downloadable models

Models are fetched from their authors on request and are not part of this repository. Each keeps its own license, shown in the app. Manga Light Colorizer is CC BY-NC-SA 4.0 and may not be used commercially.

The sample book in `app/assets/samples/colorize.epub` uses a page of [Pepper&Carrot](https://www.peppercarrot.com) by David Revoy (CC BY 4.0), converted to grayscale.

`memory/` holds the requirements, research and decisions behind the project. See [ROADMAP.md](ROADMAP.md) for what comes next.

## License

GNU Affero General Public License v3.0. See [LICENSE](LICENSE).
