# Formats and rendering engines

Research for EgeBookReader, 2026-11-10. Targets: Android first, then iOS, Windows, macOS, Linux, web.
Versions were checked on 2026-11-10 against GitHub, npm and crates.io. Anything I could not confirm
from an official repo, official docs or the source code is marked **(unverified)**.

DRM is out of scope. EgeBookReader does not remove, bypass or weaken DRM. Section 3.2 says how a DRM
file is detected and what the user sees.

---

## 1. Recommendation

**Use two engines and a few small adapters. Do not write a layout engine.**

| Role | Engine | License | What it covers |
|---|---|---|---|
| **A. Reflowable text, fixed-layout EPUB, comics** | The platform browser engine (Android System WebView, WKWebView, WebView2, WebKitGTK, or the browser itself on web), driven by **foliate-js** | MIT (foliate-js) | EPUB 2/3 reflowable and fixed-layout, MOBI, AZW3/KF8, FB2/FBZ, CBZ. Our own small adapters (foliate's "book" interface) add TXT, HTML/HTMLZ, Markdown, CBR/CB7/CBT, DOCX. PDF Reflow output is also displayed here. |
| **B. Paged documents** | **MuPDF 1.28.x**: native C/JNI on Android and desktop, `mupdf` WASM on web | AGPL-3.0, or a paid commercial license from Artifex | PDF (rendering, search, outline, links), XPS/OXPS, and **PDF Reflow** through structured text with images kept (section 5). It also gives image bounding boxes for the image swap requirement (section 6). |
| C. Optional, later | **DjVuLibre** native, or **djvu.js** on web | GPL-2.0-or-later | DjVu. MuPDF and PDFium do not read DjVu. |

Why this split:

- **Text quality.** The requirements (CJK including vertical writing, Devanagari conjuncts, RTL bidi,
  hyphenation, custom fonts, bold/italic, colours) are met fully only by browser engines. Section 4
  compares the engines. MuPDF's own HTML engine has no `writing-mode`, no ruby and only a subset of CSS.
  Flutter and Compose have no vertical text. So reflowable text goes to the browser engine on every
  platform. Android System WebView is Chromium and is updated through Play.
- **PDF.** MuPDF is the strongest open engine for the "Reflow on/off, also for PDF" requirement. Its
  structured-text extraction has `preserve-images`, `segment`, `paragraph-break`, `dehyphenate` and
  `table-hunt`, and outputs HTML/XHTML, and the same API returns image bounding boxes. pdf.js and
  PDFium only give text runs, so with them we would have to write reflow ourselves.
- **Breadth.** MuPDF is also the engine that covers the most formats by itself (section 2.10). But
  its EPUB, MOBI and Office support is basic, so it is the paged engine here, not the reflowable one.

### 1.1 The license decision (decide before writing code)

Linking MuPDF makes the distributed app a work under **AGPL-3.0**. The repo is public, so this can be
acceptable. The trade-offs:

- **What it costs:** every build we ship (APK/AAB, desktop installers, iOS, and the **hosted web build**,
  because of AGPL §13) must offer its full Corresponding Source. A link in the About screen to the
  matching public tag is enough. The app can never ship a closed or proprietary variant without buying
  an Artifex commercial license (price is not published, **unverified**). Every dependency must be
  AGPL-compatible:
  - Compatible: MIT, BSD, Apache-2.0, zlib, LGPL, MPL-2.0, and **GPL-2.0-or-later** (DjVuLibre and djvu.js are "v2 or later": I checked the djvu.js LICENSE and a DjVuLibre source header).
  - Not compatible: GPL-2.0-only code, and the **UnRAR license**.
- **iOS App Store risk:** the FSF holds that App Store terms add restrictions the GPL forbids. Apple
  removed GNU Go (2010) and VLC (2011) from the App Store after GPL complaints. We do not hold MuPDF's
  copyright, and Artifex enforces its licenses (it sued Hancom over Ghostscript in 2017). Shipping
  AGPL MuPDF inside our iOS app is therefore a real, unresolved risk. Mitigations: on iOS, use
  Apple **PDFKit** or **pdf.js** for PDF and accept weaker PDF reflow there, or buy the commercial
  license. Google Play, F-Droid and desktop have no such conflict.
- **Precedent:** KOReader is AGPL-3.0 and is built on MuPDF, DjVuLibre, crengine, libk2pdfopt, HarfBuzz,
  FriBidi, libunibreak and libarchive (checked in `koreader-base/thirdparty`).

**Permissive alternative (the app stays MIT/Apache):** in role B, replace MuPDF with **pdf.js**
(Apache-2.0) in the same WebView on every platform. Optionally use **PDFium** (BSD-3) natively on
Android for speed. What is lost: XPS/OXPS, MuPDF's page segmentation and paragraph detection for
PDF Reflow (we would build reflow on `getTextContent()` ourselves), and some rendering speed on large
PDFs.

**My pick:** MuPDF + foliate-js under AGPL-3.0 for Android, desktop and web, with the iOS PDF engine
decided when iOS work starts. Keep all MuPDF calls in one module, because iOS may need a second
implementation (PDFKit or pdf.js).

### 1.2 Per-platform mapping

| Platform | Role A (text) | Role B (PDF/XPS) | Notes |
|---|---|---|---|
| Android | Android System WebView + foliate-js | MuPDF via JNI (`mupdf-android-fitz`, AGPL), or PDFium if permissive | Android-first. MuPDF's Android build drops its bundled Noto fonts (`TOFU_NOTO`, `TOFU_CJK`, `TOFU_SIL`), so fonts must come from the system or the app (§4.6). |
| iOS | WKWebView + foliate-js | PDFKit or pdf.js (App Store risk, §1.1), or MuPDF C library | |
| Windows | WebView2 (Chromium) + foliate-js | MuPDF native, or mupdf WASM inside the WebView | |
| macOS | WKWebView + foliate-js | MuPDF native or WASM, or PDFKit | |
| Linux | WebKitGTK + foliate-js | MuPDF native or WASM | Text quality depends on installed fonts (fontconfig). |
| Web | Browser + foliate-js | `mupdf` npm 1.28.6 (WASM), or pdf.js | The default `mupdf` WASM build has no XPS, no SVG, no hyphenation and no bundled fallback fonts (§2.1). |

### 1.3 Formats we do not render in-app (v1)

- **KFX** and anything else with DRM: detect it and explain (§3.2).
- **LIT, LRF, TCR, eReader PDB, CHM, ODT, RTF:** show "convert with calibre" and add them later only if users ask. RTF and ODT
  are the likeliest to be asked for. `pandoc` 3.13 now ships an official WASM build, but it is GPL-2.0+ and heavy.

---

## 2. Format table

The prevalence ranking is my judgment, based on what reader apps and calibre support by default and on
community usage. I found **no public measured market-share data** for ebook file formats.

| # | Format | Prevalence | Engine options | License | Notes |
|---|---|---|---|---|---|
| 1 | **PDF** | Very high (universal document format) | MuPDF; PDFium (`pdfium-render`, `pdfium-binaries`, Android `PdfRenderer` / `androidx.pdf`); pdf.js; Apple PDFKit; `hayro` (pure Rust, young) | AGPL/commercial; BSD-3; Apache-2.0; system; MIT/Apache | Standard password encryption is not DRM: prompt for the password. Adobe ADEPT PDF (`/Filter /EBX_HANDLER`) is DRM. |
| 2 | **EPUB 2 / EPUB 3 reflowable** | Very high (the standard ebook format) | Browser engine via foliate-js, Readium (Kotlin/Swift/TS) or epub.js; MuPDF's own HTML engine; `rbook` (Rust, parse only) | MIT; BSD-3; BSD-2; AGPL; Apache-2.0 | EPUB 3.3 is a W3C Recommendation. EPUB 3.4 reached Candidate Recommendation on 2026-07-21. Font obfuscation (IDPF/Adobe) is **not** DRM and must be supported (foliate-js does, via SHA-1 from Web Crypto). |
| 3 | **EPUB 3 fixed-layout (FXL)** | Medium (children's books, manga, comics, cookbooks) | foliate-js `fixed-layout.js`; Readium Kotlin/Swift/TS | MIT; BSD-3 | Uses `rendition:layout=pre-paginated` and `rendition:spread`, and pairs pages left/right as spreads. I found no pre-paginated handling in MuPDF's `epub-doc.c` (1.28 only respects `meta viewport` for page size), so treat MuPDF FXL as **not supported**. |
| 4 | **MOBI (MOBI6 / PRC)** | Medium-high in existing libraries, declining | foliate-js `mobi.js`; libmobi; MuPDF (basic); calibre | MIT; LGPL-3.0; AGPL; GPL-3.0 | MuPDF only decodes uncompressed and PalmDOC records. HUFF/CDIC throws "unknown compression method". It also skips the encryption field, so a DRM'd MOBI may give garbage instead of an error. |
| 5 | **AZW3 (KF8), AZW, combo MOBI** | Medium (DRM-free Kindle-sourced files, calibre output) | foliate-js (KF8 including HUFF/CDIC; zlib fonts via fflate); libmobi (KF8, AZW, AZW4); calibre | MIT; LGPL-3.0; GPL-3.0 | AZW bought from Amazon is usually DRM'd. MuPDF does not parse KF8 structure (skeleton/fragment indexes). |
| 6 | **KFX** (`.kfx`, `.azw8`, `.kfx-zip`) | High on Amazon devices, but locked | No open in-app renderer. The only decoder I found is jhowell's calibre "KFX Input" plugin (Python; GPL-3.0 per a second-hand MobileRead post, **unverified**; no public repo). | — | Amazon-store KFX always carries DRM, so we show an "unsupported, DRM" message. Amazon removed "Download & Transfer via USB" on 2025-02-26. |
| 7 | **CBZ** | High for comics/manga | foliate-js `comic-book.js` + zip.js; MuPDF; any zip library | MIT; BSD-3; AGPL | Order pages by natural sort. Read `ComicInfo.xml` (§7). |
| 8 | **CBR** | High for older comic scans | libarchive (RAR v3 + RAR5 read, "some limitations"); `libarchive.js` (WASM); MuPDF only when built with system libarchive; UnRAR / `unrar` crate | BSD-2; MIT; AGPL; **UnRAR license (non-free)** | UnRAR source may not be used to recreate RAR compression. Debian/FSF treat it as non-free and it is not GPL-compatible, so **use libarchive, not UnRAR**. Encrypted RAR is not supported (**unverified** detail). |
| 9 | **CB7 / CBT** | Low | libarchive / libarchive.js; `sevenz-rust2`; MuPDF reads CBT (tar) natively | BSD-2; MIT; Apache-2.0; AGPL | |
| 10 | **FB2 / FBZ** | High in Russia/CIS, low elsewhere | foliate-js `fb2.js` (FB2 and zipped FBZ); MuPDF (FB2); calibre; crengine | MIT; AGPL; GPL-3.0; GPL-2.0 | Images are inline base64 `<binary>`. Rich metadata including series (§7). |
| 11 | **TXT** | High (especially Chinese web novels, often GB18030/GBK/Big5; Russian files often CP1251) | Trivial to render. Needs charset detection: `TextDecoder` (gb18030, big5, windows-1251…) + **chardetng** (Firefox's detector) or ICU; MuPDF txt handler | browser; Apache/MIT; Unicode | Chapter detection needs heuristics (`第…章`, `Chapter N`, `Глава N`). Wrong encoding is the most common failure for this format. |
| 12 | **DjVu** | Medium (scanned books, academic, Russian libraries) | DjVuLibre (C++); djvu.js (JS); `djvu-rs` (pure Rust + WASM, created 2026-04, 15 stars) | GPL-2.0+; GPL-2.0+; MIT | Not read by MuPDF, PDFium or pdf.js. `djvu-rs` is promising but young (**quality unverified**). |
| 13 | **DOCX** | Medium (personal documents) | mammoth.js 1.13 → semantic HTML; docx-preview/docxjs → closer to the page look; MuPDF office handler (docx/xlsx/pptx/hwpx, basic, since 1.23); pandoc | BSD-2; Apache-2.0; AGPL; GPL-2.0+ | Show it in the reflowable reader as HTML. |
| 14 | **HTML / XHTML / HTMLZ** | Medium | Browser directly; MuPDF HTML; HTMLZ is a zip of HTML + `metadata.opf` (calibre) | — | Sandbox it like EPUB (no scripts, CSP). |
| 15 | **RTF** | Low-medium | pandoc (has an RTF reader); rtf.js (last push 2023); calibre; crengine | GPL-2.0+; MIT; GPL-3.0; GPL-2.0 | No good small, maintained, permissive option. Defer. |
| 16 | **Markdown** | Low-medium, rising | markdown-it → HTML; MuPDF 1.28 (cmark-gfm) | MIT; AGPL | Easy adapter. |
| 17 | **ODT** | Low | pandoc; calibre; LibreOffice (too heavy) | GPL-2.0+; GPL-3.0; MPL-2.0 | Defer. |
| 18 | **CHM** | Low (legacy help files and docs) | CHMLib (last push 2023); calibre; crengine | LGPL-2.1; GPL-3.0; GPL-2.0 | Defer. |
| 19 | **XPS / OXPS** | Very low | MuPDF only | AGPL | The default `mupdf` WASM build excludes XPS (`xps=no`). |
| 20 | **AZW4 (Print Replica)** | Low | libmobi; calibre (`azw4_input`) | LGPL-3.0; GPL-3.0 | A PDF wrapped in a MOBI container. |
| 21 | **PDB** (PalmDOC, eReader, Plucker, zTXT, Haodoo) | Very low; Haodoo matters for Traditional Chinese | MuPDF (PalmDOC `.pdb`); calibre (`ereader`, `haodoo`, `palmdoc`, `plucker`, `ztxt`); foliate's PalmDOC decompressor can be reused | AGPL; GPL-3.0; MIT | eReader's name + card-number lock counts as DRM. |
| 22 | **LIT** | Very low (Microsoft Reader was discontinued in 2012) | calibre only | GPL-3.0 | DRM'd LIT is common. |
| 23 | **LRF** (Sony) / **TCR** (Psion) / **SNB** / **PML** / **RB** | Negligible | calibre | GPL-3.0 | Convert outside the app. |
| 24 | **Images** (JPEG/PNG/WebP/AVIF/GIF/TIFF/JXL) and image folders/zips | Medium (manga scans) | Platform decoders, browser; MuPDF img handler (JPEG, PNG, TIFF, GIF, BMP, PNM, PSD, JXR, JPX) | — | Treat as a comic. |
| 25 | **KEPUB** (Kobo) | Medium among Kobo users | Open as EPUB | — | Kobo-store KEPUBs are DRM'd. |
| — | Audiobooks, DAISY, Readium Web Publication | — | Readium supports them | BSD-3 | Out of scope for v1. |

---

## 3. Formats: details

### 3.1 Notes per format family

- **EPUB 2/3** is a zip containing an OPF package, an XHTML/SVG spine, CSS, fonts, and an NCX (EPUB 2)
  or nav document (EPUB 3). Reflowable and fixed-layout (FXL) books need different renderers.
  foliate-js chooses its FXL renderer when `rendition.layout === "pre-paginated"`. EPUB scripting is
  dangerous: foliate-js does not run book scripts and says to block them with a CSP, because blob:
  URLs make the iframe same-origin and the WebKit bug 218086 makes `allow-scripts` necessary.
- **Kindle family.** MOBI6 is HTML in PalmDOC or HUFF/CDIC records. KF8/AZW3 is
  skeleton + fragment XHTML with `kindle:embed`/`kindle:pos` references. A "combo" `.mobi` holds both. KFX is
  a different, proprietary container format (Ion-based). Amazon stopped offering USB downloads on
  2025-02-26, so new DRM-free Kindle files now come mostly from users' own conversions or from
  non-Amazon stores.
- **Comics.** CBZ (zip), CBR (rar), CB7 (7z), CBT (tar), sometimes ACBF. Pages are images. Metadata,
  if any, is in `ComicInfo.xml`, including `Manga=YesAndRightToLeft` for right-to-left reading.
- **FB2** is one XML file, with images as base64 `<binary>` elements. FBZ is a zipped FB2.
- **DjVu** is a layered scan format (JB2 mask, IW44 background/foreground) with an optional hidden text
  layer (`TXTa`/`TXTz`) and outline (`NAVM`).
- **TXT** has no structure. Encoding detection and chapter detection make up most of the work.

### 3.2 DRM: what we detect and what happens

We never decrypt. For each case, the user sees: *"This book is protected by DRM (<vendor>). Open it in
<vendor's app>. EgeBookReader does not remove DRM."* The book can still be listed in the library with
the metadata that is readable without decryption, which is usually the OPF, Info dict or EXTH.

| Format | How to detect | Notes |
|---|---|---|
| EPUB, Adobe ADEPT (also B&N, Google Play downloads) | `META-INF/rights.xml` exists, or `encryption.xml` lists content (not just fonts) with `xmlenc#aes128-cbc` | Font obfuscation (`http://www.idpf.org/2008/embedding`, `http://ns.adobe.com/pdf/enc#RC`) is **not** DRM and must keep working. |
| EPUB/PDF, Readium LCP | `META-INF/license.lcpl` (EPUB) or `license.lcpl` in the package | LCP is the one DRM that **can be supported legitimately**. Readium Kotlin/Swift implement it, but production needs EDRLab membership, a certificate and a yearly fee (tiered pricing from 2025). It is the only realistic future path if lending libraries matter. |
| EPUB, Apple FairPlay | `META-INF/sinf.xml` | Apple Books only. |
| KEPUB from Kobo | encrypted entries + Kobo-specific `encryption.xml` (**unverified** detail) | |
| MOBI/AZW | PalmDOC header encryption field ≠ 0 | Check this ourselves; MuPDF ignores it. |
| KFX | From the Amazon store, always DRM (DRMION container) | Unsupported even when DRM-free: no open renderer. |
| PDF, Adobe ADEPT | Encrypt dictionary `/Filter /EBX_HANDLER` | Standard-security PDFs (user/owner password) are fine: prompt for the password. |
| LIT, eReader PDB | DRM flags in the file | Unsupported. |

---

## 4. Engines and libraries

### 4.1 MuPDF (Artifex). 1.28.6, 2026-11-09. AGPL-3.0 or commercial

- **Formats (document handlers in `source/fitz/document-all.c`):**
  - PDF, XPS/OXPS, SVG.
  - CBZ, CBT and tar/zip of images. CBR only `#ifdef HAVE_LIBARCHIVE`, an optional system dependency.
  - Images: JPEG, PNG, TIFF, GIF, BMP, PNM, PSD, JXR, JPX, JBIG2 inside PDF.
  - FB2, HTML, XHTML, EPUB.
  - MOBI/PRC/PDB, basic: MOBI6/PalmDOC only, no HUFF/CDIC, no KF8.
  - TXT, Markdown (new in 1.28, via cmark-gfm), Office (docx/xlsx/pptx/hwpx, since 1.23), `.gz`.
- **HTML/EPUB engine:**
  - Shaping: HarfBuzz, with bidi (better since 1.27: `direction` and `dir=rtl`).
  - Line breaking: a UAX #14 pair table.
  - **Hyphenation since 1.27** (Aug 2025), using TeX patterns from tex-hyphen CTAN-2025.06.02. The core set is bn de en es fr gu hi it kn mr pt ru ta te **tr**; enable it with `lang` + `hyphens:auto`.
  - Position absolute/relative, tables, `@font-face` (`src`), user CSS through `Document.style(publisherCSS, userCSS)` (per document since 1.28).
  - **Missing: `writing-mode` (no vertical text), ruby, flex/grid, `text-justify`, scripting, FXL.** I checked the full CSS property list in `css-properties.gperf`.
- **PDF Reflow:** structured text (`fz_stext`) with the options `preserve-images`, `dehyphenate`, `paragraph-break`, `segment`,
  `table-hunt`, `structured` (tagged PDF), `collect-styles` and `clip`. Output can be HTML, XHTML, JSON or XML. A C-only
  `fz_open_reflowed_document()` (since 1.19) wraps any document: each page goes to stext, then XHTML, then an HTML document laid out at a new size.
  The JS and Java bindings expose `toStructuredText(options)` and `.asHTML()` but not the wrapper. That is fine, because we want
  the HTML anyway.
- **Bindings and builds:**
  - Android: `mupdf-android-fitz` (JNI, AGPL). Its build defines `TOFU_NOTO`, `TOFU_CJK` and `TOFU_SIL`, so the built-in Noto fallback fonts are left out.
  - Web: `mupdf` npm 1.28.6, about 14.3 MB unpacked. Since 1.27 it is built from the main repo. Its default build script uses `-DTOFU -DTOFU_CJK_EXT -DFZ_ENABLE_HYPHEN=0` and `xps=no svg=no mujs=no extract=no`, so **a custom WASM build is needed for XPS and hyphenation**.
  - Rust: `mupdf` crate 0.8.0 (AGPL).
  - Others: C++ and Python (PyMuPDF) bindings.
- **Verdict:** best open PDF engine for this app (rendering, reflow, image access, editing). Its
  HTML engine is acceptable for Latin/Cyrillic/Devanagari/RTL but is not "flawless CJK" (no vertical text).

### 4.2 PDFium (Google). BSD-3 (+Apache-2.0 parts)

- Prebuilt binaries: `bblanchon/pdfium-binaries` chromium/8138 (2026-11-04), for Android arm/arm64/x86/x64, iOS,
  macOS, Windows, Linux and WASM. Those WASM builds have a non-growable heap: pdfium-render recommends the
  `paulocoutinhox/pdfium-lib` WASM builds instead.
- `pdfium-render` 0.9.5 (MIT/Apache) for Rust: binds at runtime and can compile to WASM. Has text, image
  extraction and image replacement (`PdfPageImageObject::set_image`). PDFium is not thread-safe, so the crate wraps it in a mutex.
- Android's platform `PdfRenderer` is PDFium-based. Jetpack `androidx.pdf` (PdfViewerFragment) is at
  1.0.0-beta01 (2026-08) and needs SDK extension 13 or a backport to minSdk 28. Recent Android versions do not let apps use
  the system `libpdfium.so` directly (from the pdfium-render README).
- No reflow, no XPS. Fast and permissive. The Readium Kotlin PDF adapter uses the old
  `barteksc/PdfiumAndroid`.

### 4.3 pdf.js (Mozilla). v6.5.438, 2026-11-01. Apache-2.0

- Pure JS; runs in any WebView and the browser. Has a canvas renderer, a text layer, an annotation layer, search and
  `getStructTree()` for tagged PDFs. `getTextContent()` returns positioned text items (string, transform,
  width, font, `hasEOL`).
- No reflow. No first-class image API: images are found by walking `getOperatorList()` for
  `paintImageXObject`/`paintInlineImageXObject` and tracking the transform matrix yourself. It is read-only, so
  images cannot be replaced, only overlaid. The npm package is large (about 37.6 MB unpacked, mostly optional files).

### 4.4 foliate-js. MIT. npm 1.0.1 (2025-04); master active (last commit 2026-05-01)

- EPUB (reflowable and FXL), MOBI, KF8/AZW3, FB2/FBZ, CBZ, PDF (experimental, via pdf.js), plus `opds.js`, TTS,
  search, `progress.js` and annotations (`overlayer.js`). Pure ES modules with no build step. Uses zip.js (BSD-3) for random-access zip
  reading and fflate for KF8 fonts.
- The paginator handles `vertical-rl`/`vertical-lr` and RTL (`getDirection()`), and spreads (`max-column-count`;
  FXL `spread` with portrait/landscape behaviour).
- `book.transformTarget` lets the app rewrite any resource as it loads. That is the hook for the image swap (§6).
- New formats are added by implementing the documented "book" interface (`sections[].load()`, `toc`,
  `metadata`, `rendition`, `resolveHref`).
- Status: the author calls the API **not stable** and recommends vendoring it as a git submodule. It powers
  Foliate 3.3.0 (GPL-3.0; the library itself is MIT).

### 4.5 Readium toolkits. BSD-3

- **Kotlin 3.4.0** (2026-09):
  - Formats: EPUB 2/3, PDF (needs an adapter: pdfium or PSPDFKit), audiobooks, partial CBZ/Divina. CBR is not planned.
  - Other: OPDS 1.2/2.0, LCP, a WebView-based navigator, and alpha Compose web navigators.
- **Swift 3.11.1** (2026-10): EPUB reflowable and FXL, PDF via PDFKit, CBZ, Divina, LCP.
- **TS toolkit** (`@readium/navigator` 2.15.0, 2026-11): a web navigator. It warns that minor versions break APIs.
- **ReadiumCSS 2.0.5** ships `cjk-horizontal`, `cjk-vertical` and `rtl` stylesheet sets, which are worth copying even when not using Readium.
- Verdict: the best-engineered **EPUB + LCP** stack, but one codebase per platform and no MOBI/FB2.
  foliate-js covers more formats and one JS codebase runs everywhere.

### 4.6 Others

| Library | Version / date | License | Use |
|---|---|---|---|
| epub.js | npm 0.3.93 (2022-02); repo has had only small merges since | BSD-2 | Stale; prefer foliate-js. |
| libmobi | v0.12 (2024-06) | LGPL-3.0 | C library: MOBI, KF8/AZW3, AZW4, PDB; metadata. It also decrypts with a user PID; we do not use that. |
| DjVuLibre | (version unverified) | GPL-2.0+ | Native DjVu (KOReader uses it). |
| djvu.js | L.0.5.4 / V.0.10.1 (2024-05) | GPL-2.0+ | DjVu in the browser. |
| djvu-rs | 0.44.0 (2026-10) | MIT | Pure Rust, WASM; claims to be faster than DjVuLibre; very new. |
| libarchive | 3.8.11 (2026-10) | BSD-2 (a few files UC/PD/CC0) | CBR (RAR v3, RAR5), CB7, CBT. `libarchive.js` 2.0.2 is its WASM port (MIT; last push 2024-04). |
| UnRAR / `unrar` crate | crate 0.5.8 | Crate MIT/Apache, but it vendors the UnRAR source (non-free license) | Avoid. |
| calibre | 9.18.0 (2026-11) | GPL-3.0 | Desktop Python. Converts every input through an **OEB (XHTML + OPF) intermediate**. Input formats: AZW, AZW3, AZW4, CBZ, CBR, CB7, CBC, CHM, DJVU, DOCX, EPUB, FB2, FBZ, HTML, HTMLZ, KEPUB, LIT, LRF, MOBI, ODT, PDF, PRC, PDB, PML, RB, RTF, SNB, TCR, TXT, TXTZ. foliate-js does the same normalisation at runtime, and our adapters should too: everything becomes HTML sections + a TOC + metadata. |
| pandoc | 3.13 (2026-10), ships an official `pandoc-3.13-wasm.zip` | GPL-2.0+ | Readers for DOCX, ODT, RTF, EPUB, FB2 and more. Too heavy for v1. |
| mammoth.js / docx-preview | 1.13.0 / active 2026 | BSD-2 / Apache-2.0 | DOCX → HTML in JS. |
| markdown-it | active 2026 | MIT | Markdown → HTML. |
| crengine (CoolReader / KOReader) | active | GPL-2.0 ("version 2" in the README; **"only" vs "or later" unverified**) | EPUB, FB2, DOC, RTF, HTML, CHM, TXT, PDB, MOBI. A C++ layout engine; only relevant if we drop WebViews. |
| k2pdfopt (`libk2pdfopt`) | active fork in KOReader | AGPL-3.0+ (source headers) | Bitmap-based PDF/DjVu reflow (§5). |
| Rust: `lopdf` 0.47 | 2026-11 | MIT | Reads and edits PDF objects; **no rendering**. |
| Rust: `hayro` 0.9 | 2026-11 | MIT/Apache | Pure-Rust PDF parser/rasterizer, read-only. Watch it, too young to depend on. |
| Rust: `epub` 2.1.6 | 2026-11 | **GPL-3.0-or-later** | Note the copyleft. Prefer `rbook` 0.7.12 (Apache-2.0: EPUB 2/3 read/write). |
| Rust: `mobi` 0.8 | 2022-12 | MIT | Stale. |

### 4.7 Which single engine covers the most formats on Android + desktop + web?

**MuPDF.** It reads about 15 of the formats in §2 (PDF, XPS/OXPS, EPUB reflowable, FB2, MOBI6/PRC/PDB, CBZ/CBT, CBR with
libarchive, images, SVG, HTML/XHTML, TXT, Markdown, DOCX/XLSX/PPTX) and has a C core, Android JNI, iOS and
desktop builds, and a WASM build. It does **not** cover KF8/AZW3, EPUB FXL, DjVu, CHM, RTF, ODT, LIT or KFX,
and its HTML typesetting misses vertical CJK and ruby. The **smallest set that covers the format list at
the required quality** is two: the browser engine with foliate-js, plus MuPDF (or pdf.js for a permissive app).
DjVu is an optional third.

---

## 5. Reflow for PDF

Three approaches:

1. **Text-based reflow from the content stream** (MuPDF stext, pdf.js `getTextContent`, PDFium text API).
   - Extract characters with positions and fonts, group them into lines, blocks and paragraphs, find reading order and columns,
     remove running headers and footers, dehyphenate, and output HTML. That HTML goes to the browser engine, so **all font and
     colour customisation works**, which meets the font-customisation requirement.
   - MuPDF does most of this: `segment` (page segmentation and columns), `paragraph-break`, `dehyphenate`,
     `table-hunt`, `structured` (uses the tag tree of tagged PDFs, the best case), `collect-styles` (fake bold, underline), and
     `preserve-images` (images become `<img>` in the HTML, with a bbox and transform in stext).
   - With pdf.js you write the grouping and column logic yourself (a heuristic), and images need operator-list walking.
   - Recommended options for our use: `preserve-images,dehyphenate,paragraph-break,segment,structured`.
     MuPDF's own wrapper reflows **one source page at a time**, so a paragraph that crosses a page break is split. Joining
     consecutive pages before building the HTML is our job (**design idea, untested**).
2. **Bitmap-based reflow** (k2pdfopt, used by KOReader).
   - Renders the page, detects columns, lines and words as image regions, and re-flows those **bitmaps** to the new width.
   - It works for scanned PDF/DjVu and for any script (no text extraction needed), and it keeps figures as they are. But fonts
     and colours **cannot** be changed (only zoom and contrast), and text can't be selected or searched without OCR.
   - AGPL-3.0+. Good as the "scanned document" reflow mode.
3. **Convert to EPUB ahead of time** (calibre's PDF input via poppler `pdftohtml`, or `mutool convert -F html`). Same
   limits as approach 1, done offline. Not needed if approach 1 runs on the fly.

**Quality limits (all text-based reflow):**

- Multi-column magazines, footnotes, sidebars, tables, math, drop caps and captions end up out of order.
  Tagged PDFs (PDF/UA) are much better.
- **No ToUnicode / broken ToUnicode gives garbage text.** This is common in older CJK PDFs and in **Devanagari PDFs**, where
  conjunct glyphs often map to wrong or reordered code points. It is a well-known limit of PDF itself, not of one engine,
  and I did not measure it here. Offer "Original" mode or bitmap reflow when the extracted text looks broken.
- Vertical CJK PDFs: column order and reading direction are hard to detect.
- Scanned PDFs have no text, so use bitmap reflow (2) or OCR. KOReader bundles Tesseract (Apache-2.0).

**Keeping images:** MuPDF `preserve-images` puts each image into the HTML. Use the image's stext bbox
to size it the same relative to the text column, and link each one back to its source XObject so the image
pipeline (§6) can swap it.

---

## 6. Images inside books: access and swap-back

Requirement: every image must be reachable on its own, post-processed (upscale, saturation, AI colourise), and
put back at exactly the same position and size.

- **EPUB/MOBI/KF8/FB2/HTML/DOCX (role A):**
  - Images are separate resources: manifest items, MOBI image records, FB2 `<binary>`, zip entries. Swap the
    resource Blob in foliate-js's `transformTarget` `"data"` event; the book file itself is never touched.
  - To keep exact size: record the original `naturalWidth`/`naturalHeight` and set them as `width`/`height` attributes
    (or inline CSS px) on the `<img>`, or on the SVG `<image>`, before swapping. The larger image then fills the same box and simply looks
    sharper on HiDPI screens.
  - CSS `background-image` needs a `url()` rewrite in the stylesheet.
- **CBZ/CBR/CB7/images:** each page is a file, so swap it in memory.
- **PDF (MuPDF or PDFium):** two options.
  - **Replace the image XObject** and leave the content stream alone. A PDF image is always drawn into
    the unit square under the current transform, so a replacement with the same aspect ratio lands at
    **exactly** the same place and size by construction, and clipping, soft masks and blend modes still apply.
    - MuPDF: `pdf_add_image` + update the page's XObject resource (**design idea, untested**).
    - PDFium: `FPDFImageObj_SetBitmap`, or `set_image` in pdfium-render, then regenerate the content.
    - Caveats: SMask/alpha must be resized to match; Indexed/CMYK/stencil-mask images need colour-space handling; a shared
      XObject changes everywhere it is used; inline images (`BI…EI`) are not XObjects; and scanners often split one picture into many strips.
  - **Overlay at render time:** draw the processed image over the rendered page using the stext bbox/transform.
    Works with read-only engines (pdf.js), but loses clipping and masks.
- **DjVu:** the page is layered, so "an image" means the whole page. Process the rendered page bitmap.

---

## 7. Text shaping and typesetting

### 7.1 Building blocks

| Component | Version | License | Role |
|---|---|---|---|
| HarfBuzz | 15.1.0 (2026-11-04) | MIT ("Old MIT") | OpenType shaping (Indic conjuncts, Arabic joining, CJK features). Used by Chromium, Firefox, Android (Minikin), Flutter (SkParagraph), MuPDF, KOReader. |
| HarfRust | 0.15.0 (2026-10) | MIT | The HarfBuzz project's Rust port (`harfbuzz/harfrust`). `rustybuzz` is the older port. |
| ICU / ICU4X `icu_segmenter` | 2.4.0 (2026-10) | Unicode-3.0 | UAX #14 line breaking (+ dictionaries for Thai/Lao/Khmer/Burmese), UAX #29 segmentation, bidi. |
| libunibreak | 8.0 (2026-09) | zlib | Small UAX #14 implementation (KOReader). |
| FriBidi | — | LGPL-2.1 | UAX #9 bidi (KOReader). |
| tex-hyphen patterns | CTAN-2025.06.02 in MuPDF | per-file (mostly permissive/LPPL) | Knuth–Liang patterns: tr, hi, de-1996, fr, ru and about 75 more. **No Tagalog/Filipino.** |
| Hyphenopoly | 6.1.0 (2026-01) | MIT | JS/WASM hyphenator that inserts U+00AD. Has `tr`, `hi`, `de`, `fr`, `ru`… (no `tl`). Fills the gaps in browser hyphenation. |
| hunspell/hyphen | 2.8.10 (2026-10) | GPL-2+/LGPL-2.1+/MPL-1.1 tri-license | libhyphen (LibreOffice, WebKitGTK). |

### 7.2 What each engine gets right

| Need | Browser engine (Chromium WebView / WebView2, WebKit) | MuPDF HTML | Flutter (SkParagraph) | Jetpack Compose (Android) |
|---|---|---|---|---|
| Complex shaping (Devanagari conjuncts, Arabic) | Yes (HarfBuzz; CoreText on Apple) | Yes (HarfBuzz) | Yes (HarfBuzz) | Yes (Minikin + HarfBuzz) |
| Bidi / RTL | Full (UAX #9, `dir`, `direction`, EPUB `page-progression-direction`) | Yes, improved in 1.27 | Yes | Yes |
| CJK line breaking (kinsoku) | `line-break: strict/normal/loose` (Chrome 58, Safari 11); `word-break: auto-phrase` (Chrome 119, ja/ko) | UAX #14 pair table only | ICU | `LineBreak.Strictness`, `WordBreak.Phrase` |
| **Vertical writing** (EPUB `writing-mode: vertical-rl`), `text-combine-upright`, `text-orientation` | **Yes** (Chrome 48, Safari 10.1/14/15.4) | **No** | **No** (third-party `tategaki` package only) | **No** |
| Ruby (furigana) | Yes (`ruby-position`: Chrome 84, Safari 18.2) | No | No | No |
| CJK spacing (`text-spacing-trim`, `text-autospace`) | Chrome 123 / Chrome 140, Safari 18.4 | No | No | No |
| Automatic hyphenation | `hyphens:auto`. Chrome desktop dictionaries cover de, fr, ru, hi… but **not Turkish**. Safari and Firefox have Turkish. Android's system patterns (53 languages) have **no Turkish**. | Yes since 1.27 (bn de en es fr gu hi it kn mr pt ru ta te th **tr**); off in the default WASM build | **Soft hyphen (U+00AD) rendering only**, stable in Flutter 3.50; no automatic hyphenation | `Hyphens.Auto` with system patterns (no Turkish). Compose Multiplatform on desktop/iOS: not implemented as of 2024 (JetBrains CMP-4792; current status **unverified**) |
| Justification | `text-align: justify`; `text-justify` (Chrome 145, Firefox 55; not Safari); `text-wrap: pretty` (Chrome 130, Safari 26) | justify | justify | justify + `LineBreak.Paragraph` (high quality) |
| Custom fonts | `@font-face` from blob/file URLs; any TTF/OTF/WOFF2 | `@font-face` (`src`) | Asset/runtime loading | Runtime loading |
| Font fallback | System fallback chain | Bundled Noto unless built with `TOFU*` (the Android and WASM builds are) | System on native; **web build fetches Noto from fonts.gstatic.com by default** (`fontFallbackBaseUrl`) | System |

**Conclusions for the target languages:**

- **Chinese:** needs the browser engine for vertical text, ruby and kinsoku. Horizontal Chinese works anywhere with a CJK font. Chinese TXT
  needs encoding detection (§2 #11).
- **Hindi (Devanagari):** every HarfBuzz engine shapes it correctly if a font with Indic OpenType tables is
  present (Noto Sans Devanagari is on Android). Hindi hyphenation exists in Chrome, Android and MuPDF.
- **Turkish:** the main trap is **dotted/dotless i casing** (`text-transform` and our own search/case-folding must use
  the `tr` locale) and **hyphenation**: no Chromium-based engine and no Android system dictionary has Turkish patterns. Insert soft hyphens with
  Hyphenopoly (tr) before rendering. This works in every engine, including Flutter since 3.50.
- **German, French, Russian:** fine everywhere; hyphenation is available in Chrome, Safari, Firefox, Android and MuPDF.
- **Filipino (Tagalog):** Latin script, no special shaping. There are **no hyphenation patterns** in tex-hyphen, Hyphenopoly or Android
  (checked), so justify without hyphenation or offer ragged-right.
- **Arabic/Hebrew:** browser engine with `dir=rtl` and RTL page progression. Kashida-based justification
  is not well supported in mainstream engines (**unverified**).

### 7.3 Font fallback chain (proposal)

The book's embedded fonts, then the user's chosen font, then a per-script Noto family (Noto Serif/Sans; Noto Sans/Serif CJK
SC/TC/JP/KR; Noto Sans Devanagari; Noto Naskh Arabic; Noto Sans Hebrew), then the system default.

- Android, macOS and iOS ship most of these. On Windows and Linux, offer an optional download of a "Noto pack".
- Noto CJK is about 16–20 MB per weight as OTF (**unverified size**), so do not bundle it in the APK. Do not depend on Google's CDN either: self-host the fonts if the web build needs them.
- In MuPDF builds made with `TOFU*`, supply fonts through MuPDF's font-loading callbacks.

---

## 8. Metadata, cover and TOC extraction

| Format | Metadata | Cover | TOC |
|---|---|---|---|
| EPUB 3 | OPF `dc:title/creator/language/identifier/publisher/date/description/subject`, `meta refines` (`file-as`, `title-type`), `belongs-to-collection` + `group-position` (series), calibre `calibre:series` meta | manifest item with `properties="cover-image"` | nav document `epub:type="toc"`; also `page-list`, `landmarks` |
| EPUB 2 | OPF Dublin Core + `opf:file-as`/`opf:role` | `<meta name="cover" content="<id>">`, guide `type="cover"`, else the first image of the first spine item | NCX `navMap` |
| PDF | Info dict (Title, Author, Subject, Keywords, Creator, Producer, dates) + XMP stream | render page 1 | Outlines (bookmarks); `PageLabels` for printed page numbers |
| MOBI / AZW3 | PalmDB name; EXTH records 100 author, 101 publisher, 103 description, 104 ISBN, 105 subject, 106 date, 113 ASIN, 503 updated title, 524 language | EXTH 201 (cover offset), 202 (thumbnail) | KF8: NCX index (INDX records); MOBI6: HTML TOC via the guide reference |
| FB2 | `<description><title-info>`: `book-title`, `author`, `genre`, `lang`, `annotation`, `sequence name/number` (series), `<publish-info>` | `<coverpage><image l:href="#id">` pointing to a `<binary>` | nested `<section><title>` |
| CBZ/CBR/CB7 | `ComicInfo.xml` (Title, Series, Number, Writer, Summary, LanguageISO, Manga) | first image by natural sort, or the ComicInfo `FrontCover` page | ComicInfo `Pages` bookmarks, else none |
| DjVu | `ANTa`/`ANTz` metadata (rare) | render page 1 | `NAVM` outline |
| DOCX / ODT | `docProps/core.xml` / `meta.xml` | first image or none | heading styles |
| HTML / HTMLZ / Markdown | `<title>`, `<meta name=author>`; HTMLZ `metadata.opf` | first image / `cover.jpg` in HTMLZ | headings |
| TXT | file name only | generated | chapter regex heuristics |
| CHM | `#SYSTEM` title | — | `.hhc` sitemap |
| XPS | `docProps/core.xml` | render page 1 | DocumentStructure outline |

The engines already expose most of this: foliate-js `book.metadata` (Readium webpub-manifest
shape, multilingual titles) plus `book.toc` / `pageList`; MuPDF `lookupMetadata` / `loadOutline`; libmobi EXTH;
pdf.js `getMetadata()` / `getOutline()`. calibre's `metadata.opf` sidecar files are worth reading when present.

### 8.1 OPDS catalogs (nice-to-have)

- OPDS 1.2 is Atom XML. OPDS 2.0 is JSON, based on the Readium Web Publication Manifest.
- Readium Kotlin supports both. foliate-js ships `opds.js`, which got legacy link-relation support in 2026-04, so v1 would need no new
  dependency.
- Typical servers: calibre content server, Calibre-Web, Kavita, Komga, Project Gutenberg (which versions each server speaks is **unverified**).
- OPDS-PSE (page streaming for comics) is a Komga/Kavita extension (**unverified**).
- Authentication for OPDS 1.0 is still "planned" in Readium Kotlin.

---

## 9. Open questions / unverified

- Price and terms of a MuPDF commercial license. Whether Artifex objects to AGPL MuPDF inside third-party iOS App Store apps.
- KFX Input plugin license (second-hand GPL-3.0 claim).
- Whether libarchive's RAR5 reader handles solid, multivolume and encrypted archives.
- How Android WebView hyphenates (system patterns or Chrome's dictionaries) and which languages are available on WebView2 and WebKitGTK.
- Current status of Compose Multiplatform hyphenation (CMP-4792).
- Quality of `djvu-rs` and `hayro` on real-world files.
- MuPDF reflow quality on our own test set (multi-column, CJK, Devanagari, tagged vs untagged PDFs). This needs a hands-on spike.

---

## 10. Sources

Repos, packages and code (read via GitHub API / registry on 2026-11-10):

- MuPDF source, CHANGES (1.26–1.28), document handlers, CSS property list, stext options, reflow wrapper, WASM build script: https://github.com/ArtifexSoftware/mupdf (`source/fitz/document-all.c`, `source/html/*.c`, `source/html/css-properties.gperf`, `docs/reference/common/stext-options.md`, `source/reflow/reflow-doc.c`, `platform/wasm/tools/build.sh`, `platform/java/Android.mk`, `resources/hyphen/README`, `Makethird`)
- MuPDF JS docs: https://mupdf.readthedocs.io/en/latest/reference/javascript/ ; npm: https://www.npmjs.com/package/mupdf
- MuPDF Android: https://github.com/ArtifexSoftware/mupdf-android-fitz , https://github.com/ArtifexSoftware/mupdf-android-viewer
- mupdf-rs: https://github.com/messense/mupdf-rs
- PDFium binaries: https://github.com/bblanchon/pdfium-binaries ; pdfium-render: https://github.com/ajrcarey/pdfium-render ; WASM builds: https://github.com/paulocoutinhox/pdfium-lib
- androidx.pdf: https://developer.android.com/jetpack/androidx/releases/pdf , https://developer.android.com/media/grow/implement-pdf-viewer
- pdf.js: https://github.com/mozilla/pdf.js , https://www.npmjs.com/package/pdfjs-dist
- foliate-js: https://github.com/johnfactotum/foliate-js (README, `paginator.js`, `fixed-layout.js`, `view.js`) ; Foliate: https://github.com/johnfactotum/foliate
- Readium: https://github.com/readium/kotlin-toolkit (README, `docs/guides/pdf.md`), https://github.com/readium/swift-toolkit , https://github.com/readium/ts-toolkit , https://github.com/readium/readium-css
- epub.js: https://github.com/futurepress/epub.js
- libmobi: https://github.com/bfabiszewski/libmobi
- djvu.js: https://github.com/RussCoder/djvujs ; DjVuLibre: https://sourceforge.net/p/djvu/djvulibre-git/ ; djvu-rs: https://github.com/matyushkin/djvu-rs
- libarchive: https://github.com/libarchive/libarchive (README, COPYING, `libarchive-formats.5`) ; libarchive.js: https://github.com/nika-begiashvili/libarchivejs
- unrar crate: https://crates.io/crates/unrar
- calibre: https://github.com/kovidgoyal/calibre (`src/calibre/ebooks/conversion/plugins`, `src/calibre/ebooks/pdb`) ; FAQ: https://manual.calibre-ebook.com/faq.html
- pandoc: https://github.com/jgm/pandoc (README, release 3.13 assets)
- mammoth.js: https://github.com/mwilliamson/mammoth.js ; docxjs: https://github.com/VolodymyrBaydalka/docxjs ; rtf.js: https://github.com/tbluemel/rtf.js ; markdown-it: https://github.com/markdown-it/markdown-it ; zip.js: https://github.com/gildas-lormeau/zip.js
- CHMLib: https://github.com/jedwing/CHMLib
- KOReader: https://github.com/koreader/koreader , https://github.com/koreader/koreader-base (`thirdparty/`), https://github.com/koreader/libk2pdfopt , https://github.com/koreader/crengine
- Rust crates: https://crates.io/crates/lopdf , https://crates.io/crates/epub , https://crates.io/crates/rbook , https://crates.io/crates/hayro , https://crates.io/crates/harfrust , https://crates.io/crates/icu_segmenter , https://crates.io/crates/chardetng , https://crates.io/crates/sevenz-rust2
- HarfBuzz: https://github.com/harfbuzz/harfbuzz ; libunibreak: https://github.com/adah1972/libunibreak ; hyphen: https://github.com/hunspell/hyphen ; tex-hyphen: https://github.com/hyphenation/tex-hyphen ; Hyphenopoly: https://github.com/mnater/Hyphenopoly
- Android hyphenation patterns: https://android.googlesource.com/platform/external/hyphenation-patterns/+/refs/heads/main/Android.bp

Specs and docs:

- EPUB 3.4 CR: https://www.w3.org/TR/2026/CR-epub-34-20260721/ ; https://www.w3.org/news/2026/w3c-invites-implementations-of-epub-3-4-epub-reading-systems-3-4-and-epub-accessibility-1-2
- MDN browser-compat-data (hyphens, writing-mode, text-orientation, text-combine-upright, word-break, line-break, text-wrap-style, text-autospace, text-spacing-trim, text-justify, ruby-position): https://github.com/mdn/browser-compat-data
- Compose paragraph styling (LineBreak, Hyphens): https://developer.android.com/develop/ui/compose/text/style-paragraph
- Compose Multiplatform hyphenation issue: https://github.com/JetBrains/compose-multiplatform/issues/4792
- Flutter soft hyphen change (3.50): https://docs.flutter.dev/release/breaking-changes/soft-hyphen-rendering ; https://github.com/flutter/flutter/issues/18443
- Flutter web font fallback: https://docs.flutter.dev/platform-integration/web/initialization-legacy
- tategaki (Flutter vertical text package): https://pub.dev/packages/tategaki
- OPDS: https://specs.opds.io/opds-1.2 , https://specs.opds.io/opds-2.0
- Readium LCP pricing / process: https://www.edrlab.org/projects/readium-lcp/pricing , https://www.edrlab.org/readium-lcp/how-to-lcp-reading-system-provider/

News and community (lower authority):

- Amazon USB download removal (2025-02-26): https://blog.the-ebook-reader.com/2025/02/12/download-transfer-for-kindle-ebooks-going-away-on-february-26/ , https://www.techradar.com/tablets/ereaders/attention-kindle-owners-today-is-your-last-chance-to-download-backups-of-your-ebooks
- KFX Input / DRM discussion: https://www.mobileread.com/forums/showthread.php?p=4568838 , https://www.mobileread.com/forums/showthread.php?p=4601157
- GPL vs App Store (GNU Go 2010, VLC 2011): https://www.theregister.com/2010/05/27/gnu_go_fsf_apple_itunes/ , https://www.engadget.com/2011-01-09-the-gpl-the-app-store-and-you.html
- pdf.js image extraction via the operator list: https://dev.to/linmingren/extracting-images-from-pdf-in-the-browser-a-pure-client-side-implementation-kga
