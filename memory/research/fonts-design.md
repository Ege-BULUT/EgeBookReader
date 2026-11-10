# Fonts, themes, design rules and motion

Research for R2 (UX and look), R3 (themes), R6 (typography). Written 2026-11-10.
Claims checked this session against official docs, source code or the live endpoint carry a source.
Anything I could not check is marked **unverified**. Requirement ids refer to `../requirements.md`.

---

## 1. Recommendations

Fonts

1. **Build our own font catalog in CI, not in the app.** A scheduled job reads the Google Fonts
   metadata (`fonts.google.com/metadata/fonts`), Fontsource (`api.fontsource.org/v1/fonts`) and the
   `google/fonts` repo, merges them into one compact JSON (family, category, subsets, languages,
   axes, true-italic flag, file URLs, licence, size), and publishes it as a static file with the
   app's site. The app downloads that file, caches it, and works offline from the last copy. This
   avoids shipping a Google API key in an open-source APK, avoids the undocumented Google endpoint
   breaking the app, and gives one schema for every provider.
2. **Download the full font file for reading, use subsets only for previews.** Fontsource serves
   per-subset files (latin, latin-ext, cyrillic, ...), and Google's browser CSS slices fonts by
   `unicode-range`. A native text engine wants one file per face. Get it from
   `raw.githubusercontent.com/google/fonts/main/<licence>/<family>/<file>.ttf` (Google families) or
   the provider's full download. Prefer variable files (one file, every weight).
3. **Previews:** in the list, show each family name set in its own font, loaded lazily for visible
   rows only. Cheapest sources: Google css2 with `&text=<the family name>` (a tiny subset file) or
   the Developer API's `menu` file. For the detail view, render a sample paragraph in the
   **book's language** using the Google Fonts language data (`googlefonts/lang`, Apache-2.0, has
   UDHR sample texts and exemplar characters for every language, plus a Rust crate).
4. **Language-support badges come from the font's own cmap,** checked against the exemplar
   characters in `googlefonts/lang` (for example Turkish needs `Ç Ğ İ Ö Ş Ü ç ğ ı i ö ş ü`). Do this
   in CI for catalog fonts and on device for custom fonts. Subset names like `latin-ext` are too
   coarse to promise "works for Turkish".
5. **Do not bundle CJK fonts.** Android, iOS, macOS and Windows ship system CJK fonts that the text
   stack falls back to. Offer Noto Serif/Sans SC/TC/JP/KR and LXGW WenKai as optional downloads,
   with the size shown (12 to 25 MB per file) and a Wi-Fi prompt.
6. **Tag text with its language** (EPUB `xml:lang`/`lang`, or the book's metadata language) and pass
   it to the shaper. Without it, Han characters pick the wrong regional glyphs and Turkish `fi`
   ligatures can hide the dot on `i`.
7. **Providers for v1: Google Fonts (via our catalog) and Fontsource.** Bunny Fonts as an optional
   privacy mirror for Google families. Fontshare later, after someone reads the ITF licence
   (unverified terms, see 2.5). Skip Font Squirrel (old API, mixed licences).
8. **Keep each downloaded font's licence text** next to the file and show it in font details. The
   OFL requires the copyright and licence to travel with the font.

Custom fonts

9. Accept TTF, OTF, TTC/OTC, WOFF, WOFF2. Decode WOFF/WOFF2 to plain sfnt on device. Validate every
   file with **OTS** (OpenType Sanitizer, used by Chromium and Firefox; handles TTC, WOFF, WOFF2)
   or at least a full parse with Google's Rust **fontations** (`read-fonts`/`skrifa`), store the
   sanitized copy in app-private storage keyed by SHA-256, and only ever hand that copy to the
   platform. Run the check off the UI thread, ideally in an isolated process.

Themes

10. Ship the eight palettes in section 4.1 as defaults. All of them reach at least 7:1 for body text
    (WCAG AAA) and 4.5:1 for muted text.
11. Custom background: compose image + blur + brightness + colour overlay **once** into a cached
    bitmap, redo it only when a slider settles, and draw that bitmap behind pages. Zero per-frame
    cost while reading.
12. Auto text colour: measure the composed background under the text area (5th and 95th luminance
    percentile on a 64x64 downscale), choose the light or dark text colour with the better worst
    case, and if it still fails 4.5:1, raise the overlay alpha until it passes. Show the result and
    let the user override.
13. E-ink mode switches off every animation, gradient, blur, texture, shadow and transparency, uses
    pure black and white, adds weight to text, and is detected per device (never synced).

Design and motion

14. Follow **unslop** (heydamir/unslop) for the app chrome: quiet tinted neutrals, one accent, one
    radius system, weights 400 and 500, sentence case, no glows or gradients. The book page and the
    covers carry the richness. Use the old local **taste-skill** for its motion and anti-slop lists;
    the upstream taste-skill is now for company websites only.
15. Motion runs on springs, follows the finger, can be interrupted and keeps velocity. Use the
    Material 3 spring tokens on Android (values in 6.1) and `spring(duration:bounce:)` with bounce
    0 on iOS. Overshoot only after a gesture that had momentum.
16. Three signature motions and nothing loud: cover to book (shared element), the page turn, and
    sheet physics. Everything else is short fades and small slides. Reduced motion turns them into
    crossfades or cuts; e-ink turns them off.

---

## 2. Font providers

### 2.1 Comparison

| Provider | Catalog endpoint | Key | Limits | Licences | Files | Script filter |
|-|-|-|-|-|-|-|
| Google Fonts Developer API | `https://www.googleapis.com/webfonts/v1/webfonts` | **yes** | none stated on the docs page | OFL, Apache, UFL | TTF (default), WOFF2 (`capability=WOFF2`), variable (`capability=VF`) | `subset=` |
| Google Fonts metadata (undocumented) | `https://fonts.google.com/metadata/fonts` | no | unknown | per family (`isOpenSource`) | none listed, metadata only | `subsets`, `primaryScript`, `languages` fields |
| Google Fonts css2 | `https://fonts.googleapis.com/css2?family=...` | no | none stated | as above | depends on User-Agent | `text=`; browsers get `unicode-range` slices |
| google/fonts repo | GitHub `ofl/`, `apache/`, `ufl/` + `METADATA.pb` | no | GitHub limits | as above | full TTF, mostly variable | `subsets:` and `languages:` in METADATA.pb |
| Fontsource | `https://api.fontsource.org/v1/fonts` | no | hard limit 2500 req / 10 s | `license` field, e.g. `OFL-1.1` | per-subset WOFF2, WOFF, TTF; variable WOFF2 | `subsets=latin,latin-ext` (AND) |
| Bunny Fonts | `https://fonts.bunny.net/list` | none documented | none documented | Google's families | **unverified** (WOFF2/WOFF expected) | subset keys in `variants` |
| Fontshare (ITF) | `https://api.fontshare.com/v2/fonts` | none observed | none documented | `itf_ffl` (ITF Free Font License) or OFL | `cdn.fontshare.com/wf/...` per style | `script` field (one string, mostly `latin`) |
| Font Squirrel | `fontsquirrel.com/api/fontlist/all` (2010 blog) | none | unknown | mixed, per font EULA | font-face kits | classification only |

### 2.2 Google Fonts

**Developer API** (docs checked). `GET https://www.googleapis.com/webfonts/v1/webfonts?key=KEY`
with `sort=alpha|date|popularity|style|trending`, `family=`, `subset=`, `category=`,
`capability=WOFF2`, `capability=VF` (variable file plus axis ranges), `capability=FAMILY_TAGS`.
Response items: `family`, `variants`, `subsets`, `files` (one URL per variant), `axes` (with VF),
`menu` (a file that only covers the family name, made for font pickers), `lastModified`,
`category`. The key is required. In an open-source app the key ends up in the APK and in forks;
Android-app key restrictions help but every fork would need its own. Use it from CI, not the app.

**Metadata endpoint** (fetched live). `https://fonts.google.com/metadata/fonts`, about 2.7 MB of JSON,
no `)]}'` prefix seen. Top-level `axisRegistry` and `familyMetadataList`. Each family has `family`,
`displayName`, `category`, `stroke`, `classifications`, `size`, `subsets`, `fonts` (weights and
italics with metrics), `axes`, `designers`, `lastModified`, `dateAdded`, `popularity`,
`trending`, `defaultSort`, `androidFragment`, `isNoto`, `colorCapabilities`, `primaryScript`,
`primaryLanguage`, `isOpenSource`, `isBrandFont`, `languages`. It is what fonts.google.com itself
uses and is not documented, so its shape can change without notice. Good for CI, risky in the app.

**css2 API** (docs checked). Base `https://fonts.googleapis.com/css2`. Axis syntax
`family=Literata:ital,opsz,wght@0,7..72,200..900;1,7..72,200..900`, axes in alphabetical order,
ranges with `..`. `display=swap|fallback|optional|block|auto`. `text=` returns "a font file that's
optimized for your request", "up to 90%" smaller, must be URL-encoded, can appear once and applies
to every family in the request.
Observed with WebFetch (a non-browser User-Agent): both `Noto Sans SC` and a `text=` request came
back as **one `@font-face` with a single `.ttf` and no `unicode-range`**. Browsers get WOFF2 split
into many `unicode-range` slices (Google describes 100+ slices per CJK font in its 2018 Japanese and
Korean launch posts). The User-Agent behaviour is not documented: **unverified** as a stable
contract, so treat css2 as a preview source and the repo as the source of truth for full files.

**google/fonts repo** (checked with `gh api`). Directories `ofl/`, `apache/`, `ufl/` (Ubuntu
family). Each family folder has the font files, `METADATA.pb` (licence, `subsets`, `axes`,
`languages`, `primary_script`, upstream source repo) and the licence file. The repo is about
3.3 GB: never clone it in the app. Sizes seen: `Literata[opsz,wght].ttf` 955 KB,
`NotoSerifDevanagari[wdth,wght].ttf` 739 KB, `NotoSansSC[wght].ttf` 17.8 MB,
`NotoSerifSC[wght].ttf` 24.5 MB, `LXGWWenKaiTC-Regular.ttf` 12.8 MB.

**Android Downloadable Fonts** (docs checked). Provider authority `com.google.android.gms.fonts`,
package `com.google.android.gms`, certificate hashes required with AndroidX. Needs Google Play
services 11+, so it fails on de-Googled phones, many e-ink readers and F-Droid users. Compose
`ui-text-google-fonts` supports it, but "Variable fonts are not currently supported via
downloadable fonts" and new families take "several months" to reach the provider. Not worth it
for us; direct downloads cover every device.

**Privacy.** Google's FAQ says the Fonts API is unauthenticated and sets no cookies, and Google
receives IP addresses. A 2022 Munich court ruling on Google Fonts and GDPR is reported by many
secondary sources (**unverified** primary). Fetching fonts through our own catalog plus a mirror
(Bunny or Fontsource's jsDelivr CDN) keeps reader IPs away from Google if we want that.

### 2.3 Fontsource (best documented free API)

- No key: "a read-only API that can be accessed by any HTTP client". Hard limit "2500 requests per
  10 seconds", constant use at that rate "can result in a temporary ban".
- `GET /v1/fonts` with filters `id`, `family`, `subsets`, `weights`, `styles`, `defSubset`,
  `variable`, `lastModified`, `category`, `version`, `type` (`google` or `other`). Comma inside a
  filter means AND, so `subsets=latin-ext,cyrillic` finds fonts covering both.
- `GET /v1/fonts/{id}` (fetched for `literata`): `subsets`, `weights`, `styles`, `unicodeRange` per
  subset, `defSubset`, `variable`, `lastModified`, `category`, `license: "OFL-1.1"`, `type`, and
  `variants[weight][style][subset].url.{woff2,woff,ttf}`.
- Files: `https://cdn.jsdelivr.net/fontsource/fonts/{id}@{version}/{subset}-{weight}-{style}.{ext}`;
  variable: `.../fonts/{id}:vf@{version}/{subset}-{axes}-{style}.woff2`. Exact versions are
  immutable and cached long; `@latest` resolves with a short cache. Fontsource itself recommends
  self-hosting when possible.
- `type=other` held 119 non-Google families when fetched, including **OpenDyslexic**,
  **LXGW WenKai**, iA Writer Duo/Mono/Quattro, DejaVu and FiraGO. Read the `license` field per family.
- Per-subset TTF files load directly on Android. A Turkish book needs `latin` + `latin-ext` faces
  chained together, which is why recommendation 2 prefers full files for reading.

### 2.4 Bunny Fonts

EU-hosted (BunnyWay d.o.o.), "zero-tracking and no-logging policy", "fully compatible with the Google
Fonts CSS v1 API" by swapping the host to `fonts.bunny.net/css`. Catalog `https://fonts.bunny.net/list`
(fetched, about 490 KB): a map from id (`abeezee`) to `familyName`, `category`, `defSubset`,
`variants` (subset name to file count), `isVariable`, `styles`, `weights`. Support for css2 syntax
and `text=` is **unverified**. Use: optional mirror for Google families.

### 2.5 Fontshare (Indian Type Foundry)

`https://api.fontshare.com/v2/fonts` (fetched): `{count: 100, has_more: false, fonts: [...]}`. Per
font: `name`, `slug`, `category`, `script` (single string), `languages`, `license_type`
(`itf_ffl` seen), `axes`, `styles[]` with `file` (`//cdn.fontshare.com/wf/...`), `weight.number`,
`is_variable`, `is_italic`, and metrics (`cap_height`, `x_height`). The commonly used CSS form
`https://api.fontshare.com/v2/css?f[]=satoshi@400,700&display=swap` has no official docs I could
find (**unverified**). The ITF Free Font License page renders with JavaScript and I could not read
it; secondary sources say commercial use is allowed but redistribution is restricted
(**unverified**). The catalog is mostly Latin display and UI faces, so it adds little for book text.
Treat it as phase 2, download-on-demand only, never re-hosted, after the licence is read.

### 2.6 Font Squirrel and others

- Font Squirrel's API is documented only in a December 2010 blog post (`fontlist/all`,
  `fontlist/{classification}`, `familyinfo/{urlname}`, `fontfacekit/{urlname}`). My fetch of
  `fontlist/all` returned nothing, so its current state is **unverified**. Licences differ per
  font, some forbid app embedding. Skip; users can add these through "add from file/URL".
- Velvetyne, Collletttivo, The League of Moveable Type, Open Foundry: OFL foundries without an API.
  Hand-curate a few into our catalog if wanted.
- LXGW WenKai (OFL) ships on GitHub releases, on Google Fonts as TC/Mono TC, and on Fontsource.
- Adobe Fonts needs a subscription: out.

### 2.7 Script coverage and recommended families

| Need | Subsets / script | Good reading families (all in google/fonts unless noted) |
|-|-|-|
| German, French, Filipino | `latin` (+`latin-ext` for ẞ and rare marks) | Literata, Source Serif 4, EB Garamond, Merriweather, Charis SIL, Gentium Book Plus, Atkinson Hyperlegible Next |
| Turkish | `latin-ext` | Literata, Source Serif 4, Charis SIL, PT Serif (check exemplar chars per font) |
| Russian | `cyrillic` (+`cyrillic-ext`) | Literata, PT Serif, Charis SIL, Gentium Book Plus, Noto Serif |
| Hindi | `devanagari` | Noto Serif Devanagari (739 KB variable), Tiro Devanagari Hindi (with true italic) |
| Chinese | `chinese-simplified` / `chinese-traditional` | Noto Serif SC/TC, LXGW WenKai (TC on Google, others on Fontsource) |
| Japanese, Korean | `japanese`, `korean` | Noto Serif JP/KR, Zen Old Mincho |
| Filipino Baybayin (rare) | `tagalog` | Noto Sans Tagalog (51 KB) |
| Dyslexia-friendly | latin | Atkinson Hyperlegible Next, Lexend; OpenDyslexic (Fontsource `other`) |
| Arabic, Hebrew (RTL later) | `arabic`, `hebrew` | Noto Naskh Arabic, Noto Serif Hebrew |

Literata is the face Google designed for Play Books and covers Latin, Cyrillic, Greek and
Vietnamese with `opsz` and `wght` axes: a strong default.

### 2.8 Language-specific rendering notes (R6.5)

- **Turkish.** Fonts substitute `i` with a dotted form through `locl` for language `TRK` so the
  `fi` ligature does not swallow the dot; this only works when the text is tagged `tr` (Glyphs
  tutorial, TypeDrawers). Case mapping must be locale-aware (`i` to `İ`, `ı` to `I`) for any
  uppercase styling.
- **Chinese, Japanese, Korean.** One font can carry several regional glyph forms; picking the right
  one "requires an app that supports language tagging and the OpenType 'locl' GSUB feature"
  (Noto CJK README). Pass `zh-Hans`, `zh-Hant`, `ja` or `ko` to the shaper.
- **Hindi (Devanagari).** Needs full HarfBuzz-class shaping (conjuncts, reph, matras). Practice
  (**unverified** as a rule): no letter-spacing on Devanagari (it breaks the headline bar), taller
  line height than Latin, and no synthetic italic. Offer italic only if the font has a true italic.
- **French.** Uses U+202F narrow no-break space before `; : ! ?` and inside `« »`. Check the font has
  the glyph and that justification does not stretch it.
- **German.** Long compounds make hyphenation patterns essential for justified text; check `ẞ`
  (U+1E9E) coverage.
- **Russian and neighbours.** Bulgarian and Serbian have regional letterforms via `locl`; tag `bg`
  and `sr` correctly.
- **True italic and bold.** Readest hit two real bugs here: a CJK web font whose every subset was
  weight 400, so a weight slider did nothing until synthetic bold kicked in (Readest #5795), and
  synthetic oblique glyphs clipped at run ends in Android WebView 149 to 150 (Readest #5353). Store
  "has true italic" and "weight range" per family and show them in the picker; avoid synthesized
  styles when the user picks a font without them.

### 2.9 Cheap previews and offline caching

- **List rows:** family name in its own font. Google: css2 `&text=<name>` or the Developer API
  `menu` file. Fontsource: the `latin-400-normal.woff2` file (usually tens of KB).
  Load for visible rows only, cancel on scroll, LRU disk cache with a cap (around 20 MB).
- **Even cheaper:** render name strips to images in CI and ship them as a sprite sheet with the
  catalog. The OFL FAQ treats subsetting and format conversion as making a Modified Version (2.2,
  2.6), and Reserved Font Names then cannot be used. Images are not fonts, so a self-generated
  preview image sidesteps that question; re-hosting our own subset or WOFF2 files does not.
- **Detail view:** a paragraph in the book's language (sample texts from `googlefonts/lang`), fetched
  through css2 `text=` or as the full file when the user taps "Use".
- **Offline:** the catalog JSON is cached with an ETag; downloaded fonts live in app-private storage
  with their licence file and a SHA-256; the reader never depends on the network to render a font
  the user already picked.
- **Incremental Font Transfer** (W3C Candidate Recommendation, July 2025 snapshot, November 2025
  draft) will one day stream CJK fonts in parts. Not ready to build on.

### 2.10 Noto as the fallback chain and the CJK size problem

- Default fallback order for book text: chosen font, then Noto Serif or Sans (Latin, Greek,
  Cyrillic), Noto Serif Devanagari, the CJK family for the tagged language, Noto Sans Symbols 2,
  then the system emoji font.
- On Android, iOS, macOS and Windows the platform text stack already falls back per glyph to system
  fonts. On Linux and the web we must ship or download the chain ourselves.
- CJK sizes: Noto Sans SC variable TTF 17.8 MB, Noto Serif SC 24.5 MB, LXGW WenKai TC 12.5 to 13.4 MB
  per weight. The full Noto Serif CJK release zips are 132 MB (TTC) to 661 MB (all OTFs). The
  region-specific subset variable fonts in `notofonts/noto-cjk` are the smallest full-coverage
  option per language.
- Policy: system CJK font by default, optional download per language with size shown, never in the
  APK.

---

## 3. Custom fonts from a file or a URL (R6.3)

### 3.1 Formats

| Format | Magic bytes | Accept | Notes |
|-|-|-|-|
| TrueType | `00 01 00 00` or `true` | yes | |
| OpenType CFF | `OTTO` | yes | |
| Collection | `ttcf` | yes | let the user pick faces; Android `Font.Builder.setTtcIndex` |
| WOFF | `wOFF` | yes | decompress to sfnt before handing to the platform |
| WOFF2 | `wOF2` | yes | decode with google/woff2 (C++) or a Rust decoder |
| Variable (any of the above with `fvar`) | | yes | Compose: Android 8 (API 26) and up |
| Type 1, `.dfont`, SVG fonts, EOT | | no | |

Native support for WOFF/WOFF2 in Android's `Font.Builder` is not documented (**unverified**); decode
first to be safe on every platform. Readest accepts `.ttf`, `.otf`, `.ttc` and `.woff2` uploads.

### 3.2 Validation pipeline

1. Copy the file into app-private storage. Cap the size (CJK fonts reach 25 MB, so around 64 MB).
2. Sniff the magic bytes; ignore the extension and any server `Content-Type`.
3. Decode WOFF/WOFF2 to sfnt.
4. Sanitize with **OTS**: it "parses and serializes OpenType files (OTF, TTF) and WOFF and WOFF2",
   rebuilds the font so lengths and offsets are consistent, drops unknown tables, and handles
   collections (`ProcessTTC` in `src/ots.cc`). Latest release v9.3.0 (2026-08-04). If C++ is not
   wanted, parse every table with `read-fonts`/`skrifa` (Rust, memory-safe) and reject on error.
5. Read metadata from the sanitized copy: family and style names (name IDs 16/17, else 1/2),
   `OS/2` weight class and `fsSelection`, `post.italicAngle`, `fvar` axes, `cmap` coverage against
   `googlefonts/lang` exemplar characters, `OS/2.fsType` embedding bits (warn if "restricted").
6. Treat name-table strings as untrusted: strip control and bidi-override characters (U+202A to
   U+202E, U+2066 to U+2069), cap the length.
7. Store as `<sha256>.ttf` with a JSON sidecar. Load only this copy. Run steps 3 to 5 off the UI
   thread; an Android `isolatedProcess` service keeps a parser crash or exploit away from the app.

### 3.3 Why this matters

- Chrome's team calls fonts "untrusted network resources" with "mini-programs" (hinting, CFF
  charstrings) and passes every web font through OTS. FreeType CVE-2020-15999 was exploited in the
  wild. Chrome moved web fonts to the Rust Skrifa library in Chrome 133 (February 2025) on Android,
  Linux and ChromeOS, system fonts in Chrome 136, and removed FreeType from Blink in Chrome 145.
- CVE-2025-27363: out-of-bounds write in FreeType up to 2.13.0 while parsing TrueType GX/variable
  fonts; Meta's advisory says it "may have been exploited in the wild".
- CVE-2026-23865: integer overflow in FreeType 2.13.2 and 2.13.3 variation-store parsing, fixed in
  2.14.2 (from a CVE tracker snippet, **unverified**).
- An app that loads a font through Android `Typeface` reaches the system's FreeType. Old,
  unpatched phones are exactly our users, so sanitize before the platform sees the file.

### 3.4 Import from a URL

- HTTPS only, timeout, at most 5 redirects, stream with the same size cap.
- Response is a font: run 3.2. Response is CSS: parse `@font-face` `src:` URLs and prefer
  `woff2`, then `ttf`. Response is a ZIP: extract fonts only, with zip-slip (`..` paths) and
  zip-bomb checks (entry count, total uncompressed size). A `fonts.google.com/specimen/<Family>`
  link maps to our catalog entry instead of scraping the page.
- Show one line: "Only add fonts you have the right to use."

### 3.5 Licensing (OFL FAQ, checked)

- OFL fonts may be bundled with open-source or commercial apps (1.2, 1.3, 1.4); a mobile app must
  include the copyright and licence of the fonts it ships (1.20).
- A font may not be sold by itself (1.5).
- Format conversion "normally is considered modification" (2.2), except plain WOFF compression of
  unchanged data (2.2.1); removing glyphs when subsetting is modification (2.6). A Modified Version
  cannot use the Reserved Font Names (5.3). This only bites if **we distribute** converted or
  subset files; converting on the user's device for their own use is not distribution.

---

## 4. Reading themes (R3)

### 4.1 Default palettes (contrast computed with the WCAG 2 formula)

| Theme | Background | Body text | Muted text | Body ratio | Muted ratio |
|-|-|-|-|-|-|
| OLED dark | `#000000` | `#CCCCCC` | `#8C8C8C` | 13.1 | 6.3 |
| OLED light | `#FFFFFF` | `#1A1A1A` | `#5C5C5C` | 17.4 | 6.7 |
| E-ink light | `#FFFFFF` | `#000000` | `#000000` | 21.0 | 21.0 |
| E-ink dark | `#000000` | `#FFFFFF` | `#FFFFFF` | 21.0 | 21.0 |
| Paper light | `#F7F4EE` | `#2A2622` | `#5E574E` | 13.7 | 6.5 |
| Paper dark | `#1C1B19` | `#DAD4C8` | `#A39C90` | 11.7 | 6.3 |
| Parchment light | `#F0E2C2` | `#3A2E20` | `#6B5A43` | 10.3 | 5.2 |
| Parchment dark | `#2A2219` | `#E2D2B2` | `#AD9C7E` | 10.5 | 5.8 |

WCAG 2.2 AA asks 4.5:1 for normal text and 3:1 for large text (18 pt, or 14 pt bold); AAA is 7:1.
Every palette passes AAA for body text. These are starting values for the user to tune.
"OLED light" has no obvious meaning; see open questions.

### 4.2 OLED

- True black `#000000` page and chrome: pixels off, best battery, the reason the user asked for it.
- Dim the text (`#CCCCCC` default, user slider) instead of pure white; designers widely report
  halation and eye strain from white on black (practitioner advice, not a measured standard).
- **Smear:** on some OLED panels, scrolling light content over true black leaves a dark or purple
  trail because off pixels turn on late. Reports vary by panel, brightness and refresh rate
  (forums and design blogs, no controlled study). Paged mode hides it; vertical scroll shows it.
  Offer a "black level" setting: `#000000` default, an anti-smear option around `#0A0A0A`.
- Dim images in OLED dark (for example 85% brightness, user setting); never invert them.

### 4.3 E-ink

- Pure black on white (or inverted). Avoid grey text and thin hairlines: greys dither on 16-level
  panels.
- No animation of any kind: page turns, menus and sheets cut instantly. Readwise Reader's E-ink Mode
  bundles "Reduce motion", "Reduce page animations", "High contrast" and volume-button page turns,
  and turns itself on when it detects an e-ink device.
- No gradients, blur, shadows, transparency, textures or background images.
- Heavier text: thin fonts look faint. Add weight through the variable `wght` axis (for example
  +100) or a stroke option; single-weight fonts can only fake it (Readest #5795).
- Pressed state by inverting the control, not a ripple.
- Full refresh to clear ghosting: every N page turns (setting) and a bindable "Refresh page"
  action. Readest calls vendor methods through reflection, from KOReader's patterns: Onyx BOOX
  `View.refreshScreen(0,0,w,h,34)`, Tolino/Nook `View.postInvalidateDelayed(0,0,0,w,h,34)`,
  Rockchip `View.requestEpdMode(EPD_FULL, true)`. Android has no public e-ink API.
- Detection (Readest `eink.rs`): `ro.product.manufacturer/brand/model/device` against known
  e-ink makers, `ro.eink.support`, `ro.onyx.devicename`. Keep E-ink mode a **per-device** setting,
  never synced.
- Readest is AGPL-3.0: reuse the ideas, write our own code unless our licence is compatible.

### 4.4 Paper and Parchment

- Paper: cool-to-neutral warm off-white, very fine grain at 2 to 4% opacity, static, printed feel.
- Parchment: more yellow and brown, fibre texture, a faint vignette at the edges.
- The texture must never push local contrast under the target: test the darkest texture pixel
  against the text colour. Generate grain at device pixel scale (shader or a small tile) to avoid
  moiré. Disable in E-ink.
- taste-skill bans beige-and-brass palettes as a default for premium-consumer landing pages. That
  rule targets websites; here Paper and Parchment are themes the user asked for, so they apply to
  the page surface only. The chrome stays neutral.

### 4.5 Custom background: image, colour, overlay, blur, brightness (R3.5 to R3.7)

1. Copy the chosen image into app storage; decode downsampled to screen size.
2. Blur on a downscaled copy (around a quarter resolution; the blur hides the upscale).
   Compose `Modifier.blur`/`RenderEffect` work on Android 12 (API 31) and up and "will be ignored"
   below; there, blur the small bitmap on the CPU.
3. Brightness as a colour matrix multiply; overlay as `overlay * a + image * (1 - a)`.
4. Bake steps 2 and 3 into one cached bitmap. While a slider moves, preview on the GPU at low
   resolution; recompute the cached bitmap when the slider settles (debounce about 100 ms).
5. Draw the cached bitmap behind the page. The page-curl renderer uses it as the paper texture.
6. Save per theme: image file, overlay colour, alpha, blur radius, brightness, and a thumbnail for
   the theme picker.

### 4.6 Auto text colour and accessibility

- Measure the final composed background under the text box: downscale to 64x64, take the 5th and
  95th percentile relative luminance. Try light and dark text, keep the one with the better worst
  case. Below 4.5:1 (target 7:1), raise the overlay alpha step by step until it passes. WCAG
  measures contrast against the background "as rendered" and lists unreadable background images as
  failure F83. WCAG also allows lower contrast if a mechanism returns to compliant colours, so a
  user override is fine.
- `material-color-utilities` (Apache-2.0; Kotlin, Java, Swift, TypeScript, C++, Dart) can pull a seed
  colour from the background image and build a tonal palette for chrome accents.
- APCA (a WCAG 3 candidate, not adopted) can be a second check; its Lc 75 body-text threshold comes
  from secondary sources (**unverified**). Gate on WCAG 2 ratios.
- Honour system font scale, the system bold-text setting (Android `Configuration.fontWeightAdjustment`,
  API 31, **unverified**), and reduced motion (Android animator duration scale 0, iOS Reduce Motion,
  `prefers-reduced-motion` on web).

---

## 5. Design rules from taste-skill, unslop and stop-slop

### 5.1 What these skills are

- **taste-skill.** Upstream `Leonxlnx/taste-skill` (MIT, about 113k stars, last push 2026-11-08),
  skill name `design-taste-frontend`, now "tasteskill 2.5.1": builds company websites "at the
  figma.com and x.ai level" with a browser checker. The local copy at
  `~/.claude/skills/taste-skill` is an **older version** (three dials: variance, motion, density;
  87 KB) and says it is "NOT for ... Native mobile (use Apple HIG / Material directly)". Useful for
  us: its anti-slop lists, motion discipline and timing tokens.
- **unslop.** `heydamir/unslop` by Damir Sokolovsky (CC BY 4.0, about 13k stars): "turns vibecoded,
  AI-looking UI into a designed interface", explicitly for "dashboards, apps and landing pages". It
  audits, sets a direction, then fixes spacing, colour, icons, copy, type, layout, details, visuals,
  motion in that order. The best fit for an app. Several other repos called "unslop"
  (`theclaymethod/unslop`, `mshumer/unslop`, `MohamedAbdallah-14/unslop`) remove AI tells from prose.
- **stop-slop** (local, Hardik Pandya, MIT): prose only. Use it on UI copy, the store listing and the
  README: cut filler and adverbs, active voice, specific nouns, no "not X but Y", no em dashes.

### 5.2 Direction for EgeBookReader (unslop's five lines, a draft)

- Product: an ebook reader that makes any book read like a well-printed one, on every device.
- Character: calm, tactile, exact. (unslop forbids "clean, modern, sleek, minimal, premium".)
- World: paper, ink, bookbinding, a reading lamp at night.
- Moments: the cover opening into the book; the page turn.
- Signature: one detail, for example a thin ribbon used for bookmarks and the progress mark.

### 5.3 Rules that transfer to a native reading app

Typography (chrome, not the book)
- One UI family, weights 400 and 500, 600 only for rare emphasis; hierarchy from size and colour,
  not weight (unslop).
- Sentence case everywhere; no tracked uppercase labels like `LIBRARY` (unslop; taste-skill's
  eyebrow ban).
- Tabular figures for progress, page numbers, times; one number format per screen.
- No negative letter-spacing under 16 px; tight tracking only on large display text.
- Nothing under 12 to 13 px (unslop meta 12, taste-skill "nothing under 13px").
- Reading measure around 60 characters by default (taste-skill caps lines at 62); the user can
  change it.
- Inter is discouraged as an unthinking default by both skills. Our UI must also cover Turkish,
  Cyrillic, Devanagari and CJK, so the platform font plus fallback is a fair choice. Open question.

Spacing and shape
- 4 px scale: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64. Tighter inside groups than between them.
- Touch rows 40 to 44 (unslop), at least 48 dp tap targets on Android.
- One radius system with nested radius = outer minus padding, never under 4: controls 8 to 10,
  cards 12 to 16, sheets 14 to 20. Covers stay nearly square (2 to 4) so they read as books.

Colour
- Neutral ramp tinted toward the world (warm for paper, unslop's "Warm" ramp is a fit), one accent
  on a few percent of the screen: selection, primary action, current progress.
- Depth from surface steps and 6 to 10% hairlines, not shadows or glows.
- No purple-to-blue gradients, gradient text, coloured glows, glass cards with coloured shadows.
- Off-black instead of `#000000` for the chrome, **except** the OLED theme, which the user asked for.

Icons and copy
- One line-icon family, one size, one stroke. taste-skill prefers Phosphor and discourages Lucide;
  unslop defaults to Lucide 1.5. Pick one; Phosphor (MIT) works on every platform.
- No emoji as icons, no sparkle for AI features (colorize, read aloud): a plain icon that says what
  it does.
- No greetings ("Welcome back!"), no exclamation marks, no hype words; concrete text such as
  "Chapter 4, 23 min left". No em dashes in UI copy (taste-skill bans them outright).

States
- Empty library tells how to add books; loading uses a skeleton shaped like the cover grid, not a
  spinner; errors sit inline (DRM message, failed font download).

### 5.4 Slop to avoid in this app

Skeleton shimmer on every surface; pulsing dots on things that are not live; confetti when a
chapter ends; bouncy springs on toggles; parallax on the library; animated backgrounds behind text;
three equal feature cards in onboarding; "PRO" and "New ✨" badges; a different easing per screen;
`transition-all`-style catch-all animations; animating width, height or large blurs.

### 5.5 What does not transfer

Web-specific rules (hero layouts, eyebrows per section, bento grids, logo walls, Tailwind,
Next.js, GSAP, `100dvh`, Core Web Vitals) and taste-skill 2.5's "nothing animates on scroll"
landing-page rule. The reading app is a tool: the content screen should be still, and motion lives
in transitions and gestures.

---

## 6. Motion design

### 6.1 Tokens

| Use | Value | Source |
|-|-|-|
| Press feedback | 90 ms press; scale 0.97 to 0.985 | taste-skill motion ref; unslop tokens |
| Hover, press, toggles | 120 to 180 ms | unslop |
| Menus, popovers, toolbar show/hide | 160 to 220 ms; opening panel 200 ms, closing 120 ms | unslop; taste-skill |
| Sheets, layout changes, entrances | 300 to 500 ms | unslop |
| Stagger | 40 to 60 ms, at most six items | unslop |
| Easing when not a spring | `cubic-bezier(0.22, 1, 0.36, 1)` for enter; no overshoot | unslop; taste-skill `--m-ease-enter` |
| Rise distance on enter | 6 to 12 px | unslop |

Material 3 springs, from `androidx` Compose source (`StandardMotionTokens.kt`,
`ExpressiveMotionTokens.kt`, token version v0_14_0):

| Spring | Standard (stiffness / damping) | Expressive (stiffness / damping) |
|-|-|-|
| Fast spatial | 1400 / 0.9 | 800 / 0.6 |
| Default spatial | 700 / 0.9 | 380 / 0.8 |
| Slow spatial | 300 / 0.9 | 200 / 0.8 |
| Fast effects | 3800 / 1.0 | 3800 / 1.0 |
| Default effects | 1600 / 1.0 | 1600 / 1.0 |
| Slow effects | 800 / 1.0 | 800 / 1.0 |

"Spatial" is for animations that change shape or bounds; "effects" (no overshoot) is for colour
and alpha (`MotionScheme.kt` docs). Use the **Standard** scheme for reading surfaces and Expressive
only for rare playful moments; Expressive's 0.6 damping overshoots visibly.

Apple: `withAnimation(.spring(duration:bounce:))`, duration is "perceptual". "When you're not sure,
use a spring with bounce 0"; values above about 0.4 "may feel too exaggerated" (WWDC23 "Animate with
springs"). WWDC18 "Designing Fluid Interfaces": start at 100% damping, "reward that momentum with a
little bit of overshoot" only when the driving gesture had momentum (Music used 80% for a swipe
dismiss, 100% for a tap).

### 6.2 Principles

1. Respond on touch-down, with no timers or delays (WWDC18).
2. Track the finger 1:1; every animation can be interrupted and redirected, keeping its velocity
   (springs do this; fixed-duration curves cannot).
3. Choose the end state from the projected position (velocity with scroll deceleration, UIKit
   `.normal` is 0.998), not from a 50% threshold.
4. Rubber-band at boundaries (first and last page) instead of a dead stop.
5. Spatial consistency: what slides in from an edge leaves through the same edge.
6. Animate transform and opacity only; never relayout the book during an animation; pre-render the
   neighbouring pages for the turn.
7. Every motion states its purpose in one line (taste-skill "motion must be motivated"); cut the
   rest.
8. Reduced motion: crossfades or cuts, no scaling or travel. E-ink: no animation at all.

### 6.3 Interaction ideas

1. **Cover to book.** In the library, the tapped cover is a shared element that grows into the open
   book and crossfades into the last-read page; back reverses it. Compose shared transitions
   (`SharedTransitionLayout`, `sharedElement`/`sharedBounds`) are stable since Compose Animation
   1.10 (2025-12-03). iOS has a zoom navigation transition from iOS 18 (**unverified** here). Drive
   the reverse with predictive back (on by default for apps targeting SDK 36; use
   `OnBackAnimationCallback` progress so the user can scrub it). Start loading the book when the
   finger lands; if it is not ready when the transition ends, hold on the cover with a thin progress
   line, never a spinner over a blank page.
2. **Page turn.** Default curl follows the finger (R4.2); release uses the projected position;
   the settle is a Standard spatial spring, a small overshoot only after a fast fling. Tap zones play
   the same curl from the tapped edge, a bit faster. Styles to offer: Curl, Slide, Fade, None, plus a
   speed setting (Apple Books offers Curl, Slide/Fast Fade and Scroll; Moon+ Reader has a "real page
   turning effect" with speed, colour and transparency options).
3. **Haptics on the turn.** Page turns are frequent, so default to none. Optional:
   `GESTURE_THRESHOLD_ACTIVATE` when a dragged page passes the commit point and
   `GESTURE_THRESHOLD_DEACTIVATE` when pulled back (both API 34). Android's guidance: frequent events
   get very subtle haptics, "Given the choice of buzzy haptics or no haptics ... choose no haptics",
   avoid legacy one-shot vibrations.
4. **Reader chrome.** A tap in the middle fades toolbars in with a 6 to 8 px slide (160 to 200 ms);
   the text never moves.
5. **Settings sheets** (font, theme, layout). The sheet follows the finger, snaps to detents with
   velocity projection, rubber-bands past the top. The page behind it re-lays out live while
   sliders move and keeps the first visible word in place.
6. **Sliders** (font size, brightness, blur, margins): `SEGMENT_TICK` (API 34) at detents only, live
   preview, tabular value labels.
7. **Theme switch.** Crossfade page and chrome colours with an effects spring; no white flash when
   leaving a dark theme.
8. **Font browser.** Rows fade in their own-font name when loaded (about 120 ms, no shimmer wall).
   "Use" applies the font to a preview paragraph at once; the download shows inline progress that
   ends in a check and `CONFIRM` (API 30).
9. **Progress scrubber.** Thumbnail of the target page while dragging, `SEGMENT_TICK` at chapter
   boundaries.
10. **Bookmark** (the signature detail): the ribbon drops in from the top edge with a short spring.
11. **Colorized image** (R7.5, R7.9): the colour version dissolves in at exactly the same frame
    (300 to 400 ms), instant under reduced motion; no sparkle effect.

### 6.4 Avoid

Motion while reading other than the turn; looping or ambient animation on the page; entrance
animations on every launch; celebration effects; bouncy settings controls; scroll-linked effects in
the library; animated blur (blur is baked, see 4.5).

---

## 7. Open questions for the user

1. What should "OLED light" mean? Options: a plain white page with true-black chrome, or a
   brighter OLED-dark (grey text on black). Section 4.1 assumes the first.
2. UI font: platform font with fallback (best script coverage), or one chosen family for the chrome?
3. Fontshare in v1 or later? Its licence terms need a human read first.
4. Should fonts be fetched through Google directly, or through a privacy mirror (Bunny, Fontsource
   on jsDelivr) by default?
5. The final UI stack (see `stack.md`) decides which motion and font APIs apply; section 6 gives
   Android Compose and iOS names.

---

## 8. Sources

Fonts
- Google Fonts Developer API: https://developers.google.com/fonts/docs/developer_api
- Google Fonts CSS API v2: https://developers.google.com/fonts/docs/css2
- Google Fonts metadata (undocumented, fetched live): https://fonts.google.com/metadata/fonts
- Google Fonts FAQ and privacy: https://fonts.google.com/faq
- google/fonts repository: https://github.com/google/fonts
- Google Fonts language data and samples: https://github.com/googlefonts/lang
- Google Fonts CJK slicing (Japanese launch, 2018): https://developers.googleblog.com/2018/09/google-fonts-launches-japanese-support.html
- Google Fonts CJK slicing (Korean launch, 2018): https://developers.googleblog.com/2018/04/google-fonts-launches-korean-support.html
- Android Downloadable Fonts: https://developer.android.com/develop/ui/views/text-and-emoji/downloadable-fonts
- Compose fonts, downloadable and variable: https://developer.android.com/develop/ui/compose/text/fonts
- Fontsource API intro: https://fontsource.org/docs/api/introduction
- Fontsource fonts endpoint: https://fontsource.org/docs/api/fonts
- Fontsource CDN: https://fontsource.org/docs/getting-started/cdn
- Fontsource sample record: https://api.fontsource.org/v1/fonts/literata
- Bunny Fonts: https://fonts.bunny.net/about and https://fonts.bunny.net/list
- Fontshare API (fetched live): https://api.fontshare.com/v2/fonts
- Fontshare launch: https://www.indiantypefoundry.com/news/introducing-fontshare
- Font Squirrel API (2010): https://www.fontsquirrel.com/blog/2010/12/the-font-squirrel-api
- Noto CJK releases and README: https://github.com/notofonts/noto-cjk
- W3C Incremental Font Transfer history: https://www.w3.org/standards/history/IFT/
- OFL FAQ: https://openfontlicense.org/ofl-faq/
- Turkish i localisation (Glyphs): https://glyphsapp.com/learn/localize-your-font-turkish

Custom fonts and security
- OpenType Sanitizer: https://github.com/khaledhosny/ots
- Fontations (Rust font parsing): https://github.com/googlefonts/fontations
- Chrome, memory safety for web fonts (2025-03-19): https://developer.chrome.com/blog/memory-safety-fonts
- CVE-2025-27363 (Meta advisory): https://www.facebook.com/security/advisories/cve-2025-27363
- CVE-2026-23865 (tracker): https://cve.circl.lu/vuln/CVE-2026-23865

Themes and accessibility
- WCAG 2.2 Understanding 1.4.3: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- APCA introduction: https://github.com/Myndex/apca-introduction
- Material color utilities: https://github.com/material-foundation/material-color-utilities
- Compose `Modifier.blur`: https://developer.android.com/reference/kotlin/androidx/compose/ui/draw/blur.modifier
- Readwise Reader e-ink mode: https://docs.readwise.io/reader/docs/faqs/eink
- Readest (AGPL-3.0): https://github.com/readest/readest (`src-tauri/src/android/eink.rs`,
  `.claude/memory/eink-screen-refresh-pageturner-4687.md`, `eink-per-device-css-data-eink-5795.md`,
  `italic-synthetic-oblique-clip-5353.md`, `src/styles/fonts.ts`)
- Readest docs: https://readest.com/docs/customization
- OLED smear reports (forum): https://forums.macrumors.com/threads/massive-oled-smearing-with-enabled-dark-mode.2186228/page-2
- Onyx EPD notes (unofficial): https://progressive-kiwi.github.io/onyx-inking-unofficial-docs/epd-rendering.html

Design skills
- taste-skill upstream: https://github.com/Leonxlnx/taste-skill (SKILL.md, references/motion.md, references/system.md)
- taste-skill local copy: `~/.claude/skills/taste-skill/SKILL.md`
- unslop: https://github.com/heydamir/unslop (skills/unslop/SKILL.md, references/signs.md, references/tokens.md)
- stop-slop local copy: `~/.claude/skills/stop-slop/SKILL.md`

Motion and haptics
- Compose M3 motion tokens: https://github.com/androidx/androidx/tree/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/tokens
- Compose `MotionScheme.kt`: https://github.com/androidx/androidx/blob/androidx-main/compose/material3/material3/src/commonMain/kotlin/androidx/compose/material3/MotionScheme.kt
- Compose shared elements: https://developer.android.com/develop/ui/compose/animation/shared-elements
- Compose Animation releases: https://developer.android.com/jetpack/androidx/releases/compose-animation
- Predictive back: https://developer.android.com/guide/navigation/predictive-back-gesture
- Android haptics principles: https://developer.android.com/develop/ui/views/haptics/haptics-principles
- HapticFeedbackConstants: https://developer.android.com/reference/android/view/HapticFeedbackConstants
- WWDC23 Animate with springs: https://developer.apple.com/videos/play/wwdc2023/10158/
- WWDC18 Designing Fluid Interfaces: https://developer.apple.com/videos/play/wwdc2018/803/
- Apple Books page-turn styles: https://www.macrumors.com/how-to/re-enable-page-turning-animation-apple-books/
- Apple Books themes: https://iphonelife.com/content/how-to-customize-themes-apple-books-app-iphone
- Moon+ Reader features: https://wiki.mobileread.com/wiki/Moon+_Reader
