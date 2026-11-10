# Page turning, "Actual book mode" filters, volume keys, tap zones

Research for R4.1–R4.5 (page-turn modes), R9.1–R9.6 (Okuma "Actual book mode"), R1.4/R1.5 (orientation,
spreads), R2.4 (reduced motion). Written 2026-11-10. All repo facts were read from source through the GitHub API
or raw.githubusercontent.com on that date; commit SHAs and versions are given where they matter. Anything not checked
against source or an official page is marked **unverified**.

---

## 0. Recommendation

1. **Flip mode (R4.2): an analytic cylinder curl, drawn per pixel in one fragment shader.**
   - Model: the turning page rolls over a cylinder of radius `R`. A fold axis (point `P`, unit normal `n` that
     points at the free edge) is computed from the grab point and the finger each frame (§2.2). The page stays
     fixed to a hinge: the screen's left edge in single-page mode, the spine in spread mode.
   - Rendering: each pixel finds which paper point is on top by inverting the cylinder map in closed form
     (asin + two candidates, §2.3). It then samples the turning page's front or back, or the page underneath, and
     adds diffuse/specular light from the cylinder normal plus drop and self shadows. There is no mesh and no CPU
     geometry, and the result does not depend on resolution. This is the approach of the HP/gl-transitions
     `InvertedPageCurl` (BSD-3) and of `flutter_page_curl` (MIT), but driven by the finger.
   - The same function ports to GLSL (Flutter `FragmentProgram`, WebGL), AGSL (Android 13+), SkSL (Skia/Skiko)
     and WGSL (wgpu, if the desktop app uses Rune/Rust). Fallback where custom shaders are missing (native Android
     below API 33 without GL): a strip mesh in the style of harism, drawn with `drawBitmapMesh`, or OpenGL ES 2.
   - Grab handling: project the touch onto the free edge. Snap to the top or bottom corner inside a band (≈20 % of
     page height), otherwise keep the touch's y (an "edge/middle" grab). Use relative drag so the page never jumps.
     Clamp the finger with the hinge circles that StPageFlip uses, so the page never tears off the spine.
   - Release: velocity from a velocity tracker, then project the release point forward (Compose `pagecurl` does
     this with `splineBasedDecay`). Complete the turn if the projected point lands past the hinge's mid-line,
     otherwise cancel. Animate with a critically damped spring seeded with the release velocity.
   - Spreads: the same code with the hinge at the spine. A backward turn and RTL books mirror the x axis. In a
     spread the back face shows the next spread's facing page; in single-page mode it shows the same page through
     the paper (wash ≈ 0.85–0.9).
   - Cone (Hong/Card/Chen, Nuon): don't use it. It is hard to tune and cannot reach some corner positions
     (flirble, §2.1).
   - Flat-fold libraries (StPageFlip, Compose `pagecurl`, turn.js) are not enough on their own: they fold the page
     flat, with no curl. Use them only as references for geometry, constraints and shadows.
2. **Actual book mode (R9): port Okuma's five layers into the same compositor, and reuse its MIT textures
   verbatim** (with the MIT notice). Okuma is pure DOM/CSS: overlay `<div>`s with blend modes (`exclusion`,
   `multiply`, `soft-light`) and a `box-shadow`. There is no canvas or WebGL, so all of it ports as a few lines of
   shader or platform blend modes.
   - Side pages: use the later version by the same author in Accord's Library (MIT). The number of visible page
     edges there equals the real page count, and a clip-path gives the page stack a perspective taper (§1.7).
   - Paper grain is sampled in page space, so it travels with the page while the page curls. Lighting stays in
     screen space.
3. **Volume keys (R4.4/R4.5):**
   - Android: override `Activity.dispatchKeyEvent`. Act on the first `ACTION_DOWN` (`repeatCount == 0`) and consume
     both DOWN and UP. Consuming the keys means no volume change and no volume HUD. The mangayomi (Flutter,
     Apache-2.0) and Readest (Tauri) pattern is quoted in §3.1.
   - Don't intercept while the reader menu is open (Mihon) or while TTS is playing.
   - iOS: there is no public API. The only working pattern is to observe `AVAudioSession.outputVolume` with a hidden
     `MPVolumeView` (Readest does this on the App Store). It conflicts with App Review guideline 2.5.9, so ship it
     off by default and labelled experimental.
   - Desktop: arrow keys, PageUp/PageDown, Space and Shift+Space, Home/End, mouse wheel with an accumulation
     threshold, and the tap zones for mouse clicks.
4. **Tap zones (R4.1):** normalized shapes over the reading viewport, kept in z-order, one action each, and one set
   per orientation. The data shape is in §4.3, after the Mihon `Region` model (normalized `Rect` plus type, and an
   invert mode) and KOReader's `{x, y, w, h}` fractions. A tap that hits no zone does nothing by default, or toggles
   the menu as in Mihon if the user chooses that.

---

## 1. Okuma-Reader filters, read from source

### 1.1 Repository facts

| item | value |
|-|-|
| Repo | https://github.com/DrMint/Okuma-Reader |
| License | MIT, "Copyright (c) 2021 DrMint" (`LICENSE`) |
| HEAD | `842cf37` (2024-12-30, README only). The last code change is 2021-12-11 ("Fixed bug where the last chapter of webtoon typed books would not display"). Releases: v1.0 (2021-03-04), v1.1 (2021-03-20). |
| Size | `js/read.js` 870 lines, `js/directive.js` 673 lines, `css/navImage.css` 104 lines, 10 texture `.webp` files (~240 KB total) |
| Tech | Static HTML, ES modules and CSS. **The filters are CSS only: absolutely positioned `<div>`s with `background-image` and `mix-blend-mode`, plus a `box-shadow`. No canvas, no WebGL, no SVG filters.** |
| Page turn | None. The README's TODO list includes "Page turning animation?!". A page change just swaps `<img src>`. |
| Third-party code | `js/directive.js` is a modified copy of ironexdev/zoom, which has been **Apache-2.0** since 2018. The file carries no license header. |

The DOM is the whole rendering model (`read.html`, lines 34–46):

```html
<div id="navImageContainer" class="zoom">
  <div id="navImage">
    <img id="imgPageLeft">
    <img id="imgPageRight">
    <div id="continuousScrollingPages"></div>
    <div id="filters">
      <div id="paperTexture"></div>
      <div id="bookFold"></div>
      <div id="lighting"></div>
      <div id="specular"></div>
    </div>
  </div>
</div>
```

Every filter `<div>` is stretched over `#navImage` (`css/navImage.css`):

```css
#navImage > #filters > div { position: absolute; top: 0; bottom: 0; left: 0; right: 0; pointer-events: none; }
```

`#navImage` is a grid laid out in a column with `width: min-content`. The two `<img>` elements sit side by side, so
the overlays cover exactly the book (one page or a two-page spread) plus the side-page padding.

One menu toggle maps to one `UCONFIG` flag and adds or removes CSS classes (`js/read.js`, lines 441–446):

```js
toggleHandlerElement("doublePageButton", "useDoublePage", ["doublePageButton"], ["enabled"], true);
toggleHandlerElement("bookFoldButton", "bookFold", ["bookFoldButton", "bookFold"], ["enabled", "enabled"]);
toggleHandlerElement("lightingButton", "lighting", ["lightingButton", "lighting", "specular"], ["enabled", "enabled", "enabled"]);
toggleHandlerElement("sidePagesButton", "sidePages", ["sidePagesButton"], ["enabled"], true);
toggleHandlerElement("paperTextureButton", "paperTexture", ["paperTextureButton", "paperTexture"], ["enabled", "enabled"]);
toggleHandlerElement("bookShadowButton", "bookShadow", ["bookShadowButton", "navImage"], ["enabled", "bookShadow"]);
```

There is no single "realistic" switch. On first use, all five filters default to **on in landscape and off in
portrait** (`applyCookie`, lines 707–743: `const defaultRealisticOption = window.innerWidth > window.innerHeight;`).
Choices are then saved as cookies. Our "Actual book mode" (R9.1) is the missing master switch.

### 1.2 Paper texture (R9.2)

```css
#navImage > #filters > #paperTexture.enabled {
  background-image: url("../img/paper.webp");
  mix-blend-mode: exclusion;
  background-size: 20vmin 20vmin;
}
body.book #navImage > #filters > #paperTexture.enabled {
  background-image: url("../img/paper-book.webp");
  opacity: 0.8;
}
```

On every page change the tile is moved to a random offset so the grain does not repeat between pages
(`read.js`, line 387):

```js
document.getElementById("paperTexture").style.backgroundPosition = Math.floor((Math.random() * 100) + 1).toString() + "%" + Math.floor((Math.random() * 100) + 1).toString() + "%";
```

I measured the textures (decoded, converted to luminance):

| file | size | luminance (0–255) | used for |
|-|-|-|-|
| `img/paper.webp` | 1024×1024, 171 KB | min 0, max 73, mean 18 (≈7 %) | `manga` (opacity 1) |
| `img/paper-book.webp` | 327×327, 16 KB | min 1, max 27, mean 12 (≈5 %) | `book` (opacity 0.8) |

**Why exclusion:** `exclusion(a, b) = a + b − 2ab`. With a dark grain `b`, white paper (a = 1) becomes `1 − b`, a
slightly darker grain, and black ink (a = 0) becomes `b`, so the ink is lifted a little. The grain therefore shows
on both paper and ink, as on real print. "Amount and type by book type" is exactly two textures and two opacities,
chosen by the `bookType` body class.

### 1.3 Book fold (R9.3)

```css
#navImage.doublePage > #filters > #bookFold.enabled {
  background-image: url("../img/bookFold.webp");
  background-size: 100% 100%;
  mix-blend-mode: multiply;
}
body.lightTheme #navImage.doublePage > #filters > #bookFold.enabled { opacity: 0.5; }
```

- `bookFold.webp` is 1488×16: a horizontal 1-D profile stretched over the whole spread. It is white (255)
  everywhere except a centred band at x = 664…824 of 1488, about ±5.4 % of the spread width around the spine. The
  band falls smoothly to **144 at the spine**, so multiply darkens the gutter by up to about 44 %.
- Self-shadowing is only this gradient; nothing is computed.
- It applies **only in double-page mode** (`.doublePage` selector). The menu button is hidden when double page is
  off.

### 1.4 Realistic lighting (R9.4): two layers on one toggle

```css
#navImage > #filters > #lighting.enabled {
  background-image: url("../img/lightingSinglePage.webp");
  background-size: 100% 100%;
  mix-blend-mode: multiply;
}
#navImage.doublePage > #filters > #lighting.enabled { background-image: url("../img/lightingDoublePage.webp"); }
body.lightTheme #navImage > #filters > #lighting { display: none !important; }

#navImage > #filters > #specular.enabled {
  background-image: url("../img/specularSinglePage.webp");
  background-size: 100% 100%;
  background-blend-mode: multiply;
  mix-blend-mode: soft-light;
}
body.book #navImage > #filters > #specular.enabled { opacity: 0.5; }
#navImage.doublePage > #filters > #specular.enabled { background-image: url("../img/specularDoublePage.webp"); }
```

| file | size | what it holds (measured) |
|-|-|-|
| `lightingSinglePage.webp` | 744×1039 | Range 198–255. Hot spot upper-centre (about 20–30 % from the top); falls to about 206 at the bottom and about 228 at the sides. A soft overhead lamp; multiply darkens by up to about 22 %. |
| `lightingDoublePage.webp` | 1488×1039 | Range 177–255. The same lamp over the whole spread; edges about 193–201, so up to about 30 % darkening. |
| `specularSinglePage.webp` | 744×1039 | Range 90–255. The upper two-thirds near 255 (soft-light brightens: the gloss), falling to about 130 (≈ neutral) at the bottom. |
| `specularDoublePage.webp` | 1488×1039 | A **black (0) line down the spine**, so soft-light darkens it strongly and the fold deepens. Bright lobes on each page beside the spine, about 100 at the outer edges (slight darkening). |

- So "specularity" is a pre-rendered, static gloss map composited with `soft-light`. Values above 0.5 lighten and
  values below 0.5 darken.
- It does not react to anything: not the page, not device tilt, not a page turn.
- In the light theme only the specular layer is drawn.
- `img/page.webp` (1488×1039) looks like a preview of fold plus lighting; nothing references it.

### 1.5 Side pages (R9.5): how they come from page count and position

```js
function refreshSidePages() {
  /* Move the side page to simulate the fact that you place the next page on the side */
  if (UCONFIG.sidePages && UCONFIG.doublePage) {
    const sidePageMaxValue = Math.min(VCONFIG.numPages / 150 * 4, 6);
    const progress = PAGE / VCONFIG.numPages;
    const viewedPagesWidth = (progress * sidePageMaxValue * pageWidthSlider.value / 100).toString() + "vmin";
    const toBeViewedPagesWidth = ((1 - progress) * sidePageMaxValue * pageWidthSlider.value / 100).toString() + "vmin";

    if (TCONFIG.japaneseOrder) {
      navImage.style.paddingLeft = toBeViewedPagesWidth;
      navImage.style.paddingRight = viewedPagesWidth;
    } else {
      navImage.style.paddingLeft = viewedPagesWidth;
      navImage.style.paddingRight = toBeViewedPagesWidth;
    }
    document.getElementById("lighting").style.backgroundSize = "calc(100% + " + (navImage.style.paddingLeft).toString() + " - " + (navImage.style.paddingRight).toString() + ") 100%";
    document.getElementById("specular").style.backgroundSize = /* same */;
    document.getElementById("bookFold").style.backgroundSize = /* same */;
  } else { /* reset paddings and sizes */ }
}
```
(`js/read.js`, lines 256–284)

- **Total stack thickness:** `min(numPages / 150 × 4, 6)` vmin, scaled by the page-width slider (%). A 150-page
  volume has 4 vmin; 225 pages or more is capped at 6 vmin.
- **Split:** `progress = PAGE / numPages`. Read pages pile on the left (LTR) and unread pages on the right;
  `japaneseOrder` mirrors this.
- **Drawing:** the stack is not drawn as geometry. `#navImage` gets padding, and its own background, a page-edge
  texture tiled horizontally, shows only in the padding because the `<img>`s cover the rest:

  ```css
  body.manga #navImage { background-image: url("../img/side.webp"); }      /* 135×1622, background-size: contain */
  body.book  #navImage { background-image: url("../img/side-book.webp");    /* 212×1502 */
                         background-size: 11vmin 100%; }
  ```
- **Overlays stay centred on the spine:** the overlays have `left: 0; right: 0` over the padded box. Their
  background width is `100% + padL − padR` from x = 0, so the centre of the fold, lighting and specular images
  falls at `(W + padL − padR) / 2`. That equals the spine position `padL + (W − padL − padR) / 2`, so the fold
  stays on the gutter even when the stacks are uneven.
- Limits: double-page mode only. The number of edge lines drawn does not match the real page count (it is a tile).
  There is no perspective.

### 1.6 Book shadow (R9.6)

```css
#navImage.bookShadow {
  box-shadow: 0 0 0.5em rgba(0,0,0,0.3), 0 1em 1em rgba(0,0,0,0.4), 0 2em 2em rgba(0,0,0,0.6), 0 6em 6em rgba(0,0,0,0.5);
}
#navImage.doublePage.bookShadow {
  box-shadow: 0 0 0.5em rgba(0,0,0,0.3), 0 1em 1em rgba(0,0,0,0.4), 0 2em 2em rgba(0,0,0,0.6), 0 12em 12em rgba(0,0,0,0.8);
}
body.lightTheme #navImage.bookShadow {
  box-shadow: 0 0.25em 0.5em rgb(0 0 0 / 60%), 0 1em 1em rgb(0 0 0 / 25%), 0 2em 2em rgb(0 0 0 / 27%), 0 12em 12em rgb(0 0 0 / 57%);
}
```

Four stacked shadows with growing blur and downward offset: a tight contact shadow plus a large soft one. This
reads as a book lying on a table lit from above. Units are `em`, so the shadow scales with font size, not with the
book.

### 1.7 Config files and book types

The library uses three levels of JSON (README; `js/tools.js` fetches them):

```jsonc
// <library>/config.json
{ "titles": ["an-example-book", "another-one"] }

// <library>/<slug>/config.json: the title
{ "title": "An Exemple Book", "bookType": "manga", "numVolumes": 3, "fileExtension": ".webp", "japaneseOrder": false }

// <library>/<slug>/<n>/config.json: the volume
{ "numPages": 104, "firstPagesDouble": false, "disallowDoublePage": false,
  "bookmarks": [ { "name": "", "type": "chapter", "page": 1 } ] }
```

There are four book types. They decide which filters are allowed (`setBookTypeConfig`, `read.js` lines 776–805):

```js
switch (TCONFIG.bookType) {
  case "imageset": BOOKTYPE.bookShadowButton = true; break;
  case "webtoon":  BOOKTYPE.bookShadowButton = true; BOOKTYPE.touchAction = "pan-y"; break;
  case "manga":
  case "book":
    BOOKTYPE.useDoublePage = true; BOOKTYPE.bookFoldButton = true; BOOKTYPE.sidePagesButton = true;
    BOOKTYPE.lightingButton = true; BOOKTYPE.paperTextureButton = true; BOOKTYPE.bookShadowButton = true;
    break;
}
```

`body.classList.add(TCONFIG.bookType)` then picks the per-type CSS:

| bookType | paper texture | specular opacity | side texture | double page | filters available |
|-|-|-|-|-|-|
| `manga` | `paper.webp`, opacity 1 | 1 | `side.webp`, `contain` | yes | all five |
| `book` | `paper-book.webp`, opacity 0.8 | 0.5 | `side-book.webp`, `11vmin 100%` | yes | all five |
| `imageset` | none | none | none | no | book shadow only |
| `webtoon` | none | none | none | no (vertical scroll) | book shadow only |

The "grain depends on the book type, set in config files" requirement is just this: `bookType` in the title's
`config.json` selects a CSS class.

### 1.8 Okuma's input, for reference

- **Click zones:** `directive.js` `handlesSingleClick` uses `edgeClickArea = 0.2`, so the left 20 % of the page box
  is `clickLeft`, the right 20 % is `clickRight`, and the rest is `clickMiddle` (toggle menu). The CSS variable
  `--next-previous-page-width: 30%` is unused. `japaneseOrder` swaps left and right.
- **Keys:** ←/→, PageUp (33)/PageDown (34), Home/End to change chapter. **Quirk:** in LTR mode PageUp calls
  `goNextPage()` (`case 33: goNextPage()`), which is inverted from the usual convention.
- **Other bugs seen:** `document.getElementById("bookShadow")` does not exist (it should be `bookShadowButton`; that
  branch never runs). `img/background-imperfections.webp` is referenced in `global.css` but returns 404.

### 1.9 The later version by the same author: Accord's Library reader (MIT)

DrMint later reimplemented these filters in the Accord's Library website:
https://github.com/Accords-Library/accords-library.com, MIT, "Copyright (c) 2021 Accord's Library". File:
`src/pages/library/[slug]/reader.tsx`, last changed 2023-06-05 (`284bbd6`). Textures are in `public/reader/`. The
improvements worth copying:

- **Side pages match the real page count.** `sidepages-{book,manga}.webp` hold 200 page edges. The background
  width is set so the strip shows exactly `count` edges:

  ```tsx
  const SIDEPAGES_PAGE_COUNT_ON_TEXTURE = 200;
  const SIDEPAGES_PAGE_WIDTH = 0.02;
  const ajustedSidepagesTotalWidth = pages.length * SIDEPAGES_PAGE_WIDTH * (120 / pageWidth);   // vmin; pageWidth = physical width, default 120
  const leftSidePagesWidth = `${(currentPageIndex / pages.length) * ajustedSidepagesTotalWidth}vmin`; // LTR
  // ...
  backgroundImage: `url(/reader/sidepages-${bookType}.webp)`,
  backgroundSize: `${(SIDEPAGES_PAGE_COUNT_ON_TEXTURE / leftSidePagesCount) * 100}% 100%`,
  ```
- **The page stack has perspective, and the gutter is pinched (book fold).** A `clip-path` polygon tapers the
  outer edge of the stack by a third of its width at top and bottom. When the fold is on, it also curves the page
  corners into the spine:

  ```tsx
  const leftSideClipPath = `polygon(
    ${leftSidePagesWidth} 100%, 0% calc(100% - ${leftSidePagesWidth} / 3), 0% calc(${leftSidePagesWidth} / 3), ${leftSidePagesWidth} 0%,
    70% 0%,
    ${filterSettings.bookFold ? `90% .25%, 95% .5%, 98% .8%, 99% 1%, 101% 2%, 101% 98%, 99% 99%, 98% 99.2%, 95% 99.5%, 90% 99.75%,`
                              : "101% 0%, 101% 100%,"}
    70% 100%)`;
  ```
- **Per-page overlays.** In the spread, each page gets the double-page texture at `background-size: 200% 100%`, and
  the right page uses `background-position-x: -100%`. Fold and lighting are drawn at opacity 0.5. Specular is
  `bg-[#FFF]/30 bg-blend-lighten mix-blend-soft-light` (black in dark mode).
- **A sixth layer, "teint":** a paper tint, `#ffbf7f` with `mix-blend-multiply` at opacity `teint` (default 0.1,
  user slider). This is useful for our Paper and Parchment themes (R3.3/R3.4).
- **The drop shadow is a CSS `filter: drop-shadow(...)`** stack, applied to the actual page shapes so it follows
  the clipped outline. It is **turned off on WebKit** (`!filterSettings.dropShadow || isWebKit ? undefined : ...`),
  most likely for performance.
- Defaults: `bookFold: true, lighting: false, paperTexture: true, teint: 0.1, dropShadow: false,
  isSidePagesEnabled: true`.

### 1.10 License: what we may reuse verbatim and what we must reimplement

| asset | license | verdict |
|-|-|-|
| Okuma textures `img/{paper,paper-book,bookFold,lighting*,specular*,side,side-book}.webp` | MIT (DrMint) | **Reuse verbatim.** Ship the MIT notice in our third-party licenses screen and file. |
| Accord's `public/reader/{sidepages-book,sidepages-manga,paper,book-fold,lighting-*,specular-*}.webp` | MIT (Accord's Library) | **Reuse verbatim**, same notice. |
| CSS constants and formulas (blend modes, opacities, tile sizes, side-page formulas, clip-path points, shadow stacks) | MIT | Reuse; facts and parameters. |
| `js/read.js`, React code | MIT | Allowed, but useless outside a DOM. **Reimplement** in our renderer. |
| `js/directive.js` | Apache-2.0 (from ironexdev/zoom), header missing | **Do not copy.** We don't need it (native gestures). |
| Texture provenance | — | **Unverified.** Nothing in either repo says where the grain or page-edge photos came from. The MIT grant from the repo owner is what we rely on. A procedural grain (value or blue noise) is a zero-risk alternative if this ever matters. |

### 1.11 How to port into EgeBookReader

Composite in this order, over the page or spread quad. All formulas are the W3C compositing definitions, so the
result matches the browser:

| # | layer | space | operation |
|-|-|-|-|
| 1 | page content (from the page cache, §2.8) | page UV | — |
| 2 | paper grain | **page UV** (tile ≈ 20 vmin, random offset per page) | `exclusion: c = c + g − 2·c·g`, mixed by opacity |
| 3 | teint (optional, Accord) | — | `multiply` with `#ffbf7f` at 0.1 |
| 4 | book fold (spread only) | spread space, centred on the spine | `multiply` with the 1-D profile |
| 5 | lighting (dark theme only, as Okuma) | screen/spread space | `multiply` |
| 6 | specular | screen/spread space | `soft-light`: for `b ≤ .5`, `c − (1 − 2b)·c·(1 − c)`; else `c + (2b − 1)·(D(c) − c)` with `D(c) = c ≤ .25 ? ((16c − 12)c + 4)c : √c` |
| 7 | side pages | left/right strips | Accord method: count-accurate, perspective taper |
| 8 | book shadow | under the book outline | 4 stacked gaussian shadows (Okuma values); one blurred 9-patch is fine |

- **While a page curls (§2):**
  - Layers 1–2 are sampled at the paper point `q` the curl shader found, so the grain moves with the page.
  - Layers 5–6 stay fixed in screen space (the lamp does not move).
  - On the curled part, add the dynamic diffuse and specular terms from §2.5.
  - When the turn completes, the side stacks change by one page; animate their width over the same spring.
- **Platform blend modes**, if we composite with the platform instead of a shader:
  - Multiply exists everywhere.
  - Exclusion and soft-light need `android.graphics.BlendMode` on API 29+ for native Android Canvas/Compose.
  - Flutter `BlendMode.exclusion`/`softLight` and CSS `mix-blend-mode` have them.
  - Doing all of it in the curl shader avoids the question entirely.
- **Book-type presets** replace Okuma's per-title `config.json`. Per book we store `bookType`, auto-detected:
  image archives (CBZ/CBR) → `manga`; reflowable or text PDF → `book`; very tall image strips (aspect > 3:1) →
  `webtoon`; mixed photo sets → `imageset`. The user can override it. The presets ship as a JSON asset:

  ```jsonc
  {
    "version": 1,
    "bookTypes": {
      "book":  { "paper": { "texture": "okuma/paper-book.webp", "opacity": 0.8, "tileVmin": 20 },
                 "sides": { "texture": "accords/sidepages-book.webp", "edgesOnTexture": 200, "vminPerPage": 0.02 },
                 "specularOpacity": 0.5, "foldOpacity": 1.0, "filters": ["paper", "fold", "lighting", "sides", "shadow"] },
      "manga": { "paper": { "texture": "okuma/paper.webp", "opacity": 1.0, "tileVmin": 20 },
                 "sides": { "texture": "accords/sidepages-manga.webp", "edgesOnTexture": 200, "vminPerPage": 0.02 },
                 "specularOpacity": 1.0, "foldOpacity": 1.0, "filters": ["paper", "fold", "lighting", "sides", "shadow"] },
      "imageset": { "filters": ["shadow"] },
      "webtoon":  { "filters": ["shadow"] }
    }
  }
  ```
- **"Actual book mode" = turn on every filter in `filters` for the book's type.** The individual toggles stay for
  fine-tuning.
- Fold and side pages are spread-only in Okuma. For single-page mode, our proposal (not Okuma's) is a right-hand
  stack of unread pages plus a light hinge shade.

---

## 2. Procedural page curl

### 2.1 The models

| model | how it works | who uses it | verdict |
|-|-|-|-|
| **Flat fold (reflection)** | The page is mirrored across the perpendicular bisector of corner→finger. The two parts are clip polygons; shadows are linear gradients. | StPageFlip (`FlipCalculation.calculateAngle`: `angle = 2 * Math.acos(left / Math.sqrt(top*top + left*left))`), turn.js 3rd release, Compose `oleksandrbalan/pagecurl` (`scale(-1f, 1f)` + `rotateRad(angle)` + `clipPath`) | Cheap, Canvas2D-only. No curl, so not "real". Keep as the e-ink and low-power fallback. |
| **Cylinder** | Paper beyond the fold axis wraps around a cylinder of radius `R`, then lies flat on top. | harism/android-pagecurl (CPU mesh, GL ES 1.0), eschao/android-PageFlip (mesh, GL ES 2.0), HP `InvertedPageCurl` shader (per pixel, progress only), flutter_page_curl (per pixel, interactive), page_curl_flip (28 slices) | **Recommended.** One parametrisation `(P, n, R)` covers corner, edge and middle grabs, and the inverse is closed-form. |
| **Cone** | The page wraps a cone with apex on the spine; parameters `θ`, `A`, `ρ` (Hong, Card and Chen at Xerox PARC; W. Dana Nuon's 2010 iBooks-style port). `R = sqrt(x² + (y−A)²)`, `r = R·sinθ`, `β = asin(x/R)/sinθ`, then `v.x = r·sinβ`, `v.y = R + A − r(1−cosβ)sinθ`, `v.z = r(1−cosβ)cosθ`. | Nuon's ConeCurl demo; flirble.org (2010) | **Avoid.** Flirble found it "finicky", needed an extra apex x-offset for a flat region, still could not reach some corner positions, and switched to a cylinder. No closed-form inverse, so it needs a mesh. PARC patents on this (US7667703, US7898541) are listed by Google Patents as "Expired – Fee Related" (not legal advice). |
| **Apple UIPageViewController `.pageCurl`** | Public API: `transitionStyle: .pageCurl`, `spineLocation` `.min`/`.mid`/`.max`, `isDoubleSided`. `.mid` (spread) requires double-sided and two view controllers. The renderer is private Core Animation. | Apple Books-style apps on iOS only | Not portable and not tunable. A UIKit page-curl bug has been reported since iOS 16 (Apple forums thread 734956; **unverified** detail). Look-and-feel reference only. |

I could not find any "Steve Wade" page-curl source. The iBooks cone write-ups are by W. Dana Nuon (wdnuon.blogspot.com,
2010) and Chris Luke (blog.flirble.org, 2010), after Hong, Card and Chen (PARC). Marked **unverified**: the name in
the brief may refer to one of these.

### 2.2 From the touch to the fold axis

Coordinates are page-local, in **pixels** (not normalized UV: on a non-square page a normalized radius would
stretch into an ellipse, a mistake in `flutter_page_curl`'s `uv = fragCoord / uSize`). The hinge is at `x = 0`,
the free edge at `x = W`, and y points down. A backward turn and RTL books mirror x before and after.

1. **Grab origin `G'`.** Take the finger-down point `G` and project it onto the free edge: `G' = (W, clamp(G.y, 0, H))`.
   This is harism's `ACTION_DOWN`: "its position is mapped to right or left edge of page".
   - Corner grab: if `G.y < b·H` or `G.y > (1−b)·H`, snap `G'.y` to `0` or `H`. Start with `b ≈ 0.2`. StPageFlip
     uses a `diagonal/5` square at each corner (`isPointOnCorners`).
   - Edge or middle grab: otherwise keep `G'.y`. A horizontal drag then gives a vertical fold; a slanted drag tilts
     it, as in iBooks. eschao gets the same effect by limiting the curl angle with the start-touch distance from
     the origin corner (`computeTanOfCurlAngle`).
   - Use relative drag `T = G' + (finger − G)`, so the edge does not jump to the finger on the first move. harism
     does jump. Optionally let the offset decay to 0 over the drag so the edge ends up under the finger.
2. **Hinge constraint (never tear the page off).**
   - A paper point `X` stays put if and only if `|X − T| ≤ |X − G'|` (perpendicular-bisector property). So clamp
     `T` into both circles centred on the hinge ends: `|T − (0,0)| ≤ |G' − (0,0)|` and `|T − (0,H)| ≤ |G' − (0,H)|`.
   - For a top-corner grab these are StPageFlip's two circles, radius `W` and the diagonal
     (`checkPositionAtCenterLine` → `Helper.LimitPointToCircle(centerOne, this.pageWidth, ...)`, then
     `rad = sqrt(W² + H²)`).
   - Compose `pagecurl` adds a simpler guard: `Offset(max(0f, topIntersection.x), ...)` keeps the fold's top and
     bottom intersections on the page side of the hinge.
3. **Axis direction:** `n = normalize(G' − T)`, which points at the free edge. `dist = |G' − T|`.
4. **Radius `R`.**
   - Start at about `0.12–0.18·W` and tune by eye. harism uses `W/3 · (1 − pressure)`; eschao uses
     `0.8·dist/π` (`mSemiPerimeterRatio = 0.8`).
   - Shrink it to 0 as the page approaches lying flat on the far side (harism):
     `curlLen = πR; if (dist > 2W − curlLen) { curlLen = max(2W − dist, 0); R = curlLen / π; }`.
   - Also shrink `R` near the hinge so the axis never crosses it.
5. **Axis point `P`**, so that the grabbed point `G'` shows up exactly under `T`:
   - If `dist ≥ πR` (`G'` is on the flat top layer): `P = T + n·(dist − πR)/2`. This is harism's
     `mCurlPos -= mCurlDir * translate / dist` with `translate = (dist − curlLen)/2`; I re-derived it.
   - If `dist < πR` (`G'` still on the cylinder): solve `R(θ − sinθ) = dist` for `θ ∈ [0, π]` (Newton, 3–4 steps,
     start at `θ0 = cbrt(6·dist/R)`), then `P = G' − n·R·θ`. harism uses a heuristic here
     (`angle = π·sqrt(dist/curlLen)`); the exact form keeps the finger glued to the paper.
6. Feed `(P, n, R)` to the shader (§2.3) every frame.

### 2.3 Rendering: closed-form inverse of the cylinder, per pixel

Forward map for a paper point `q`, with `s = dot(q − P, n)` and `foot = q − n·s`:

- `s ≤ 0`: flat and unmoved (front face up).
- `0 < s < πR`: `θ = s/R` on the cylinder, screen `foot + n·R·sinθ`, height `z = R(1 − cosθ)`. The front face is
  visible for `θ ≤ π/2` and the back for `θ > π/2`.
- `s ≥ πR`: flat on top, screen `foot + n·(πR − s)`, `z = 2R`, back face up.

Inverse for a screen pixel `p`, with `d = dot(p − P, n)`. The candidates are tested in descending `z`; the first
one whose source `q` lies inside the page wins:

```glsl
// GLSL ES 3.0 / Flutter FragmentProgram style; all lengths in px, page-local coordinates.
uniform vec2  uPage;            // (W, H)
uniform vec2  uP, uN;           // axis point, unit normal toward the free edge
uniform float uR;               // radius; 0 => flat fold
const float PI = 3.14159265;

bool inPage(vec2 q) { return all(greaterThanEqual(q, vec2(0.0))) && all(lessThanEqual(q, uPage)); }

vec4 curl(vec2 p) {
  float d = dot(p - uP, uN);
  if (d <= 0.0) {
    vec2 qTop = p + uN * (PI * uR - 2.0 * d);          // flat part folded over on top (back face)
    if (inPage(qTop)) return backFace(qTop, /*normal*/ vec3(0.0, 0.0, 1.0));
    if (inPage(p))    return frontFace(p) * selfShadow(p, d);   // untouched part of the turning page
    return underneath(p);                                // e.g. the static facing page in a spread
  }
  if (uR > 0.0 && d <= uR) {
    float a  = asin(d / uR);
    vec2  qb = p + uN * (uR * (PI - a) - d);             // upper half of the cylinder (back face)
    if (inPage(qb)) return backFace(qb, cylNormalBack(PI - a));
    vec2  qf = p + uN * (uR * a - d);                    // lower half (front face)
    if (inPage(qf)) return frontFace(qf) * cylLight(a);
  }
  return underneath(p) * dropShadow(d - uR);             // revealed next page
}
```

- **Checked:** `tools/curl_check2.py` in this session's scratchpad (not kept in the repo) forward-projected 600 000
  random paper points over 200 random `(P, n, R)`. It confirmed that the inverse always returns the topmost paper
  point, with 0 failures.
- **Anti-aliasing:** replace the hard `inPage` test with a signed distance to the rectangle and a 1-px `smoothstep`
  (`fwidth`). Blend over 1 px across `d = R` (the curl silhouette). The HP shader's `antiAlias()` does the same
  thing.
- **Cost per pixel:** at most two texture fetches plus one for the page underneath, one `asin`, a few dot
  products. No mesh, no CPU work per frame beyond about six uniforms.

### 2.4 The back of the page

- **Spread mode:** the back of the right page *is* the next spread's left page. Sample the back texture at
  `(1 − u, v)`, where `(u, v) = q / (W, H)`, so that once the page lies flat on the left it reads correctly. A
  backward turn uses the previous spread's right page.
- **Single-page mode:** a page has no "next" content on its back in a reflowable book. Show the same page seen
  through paper: sample the **front** texture at `q` (it then appears mirrored on its own) and mix it towards the
  paper colour. Values in the field:
  - Compose `pagecurl`: `backPageColor = White`, `backPageContentAlpha = 0.1f` (90 % wash).
  - harism demo: `page.setColor(Color.rgb(180, 180, 180), CurlPage.SIDE_BACK)`.
  - eschao: a back-mask alpha (`u_maskColor`).
  - HP shader: greyscale plus brightening.
  - flutter_page_curl: grey mix plus `color.rgb *= mix(0.6, 0.85, uBackOpacity)`.

  Recommend paper colour of the current theme, content alpha 0.10–0.15, and the cylinder light on top.
- **Image books (manga, PDF fixed layout):** pages are printed on both sides, but the file only has front images.
  Use the single-page wash in single mode and the real facing page in spread mode.
- The back face has no grain-offset trick: use the same grain UV mirrored, so front and back share the paper.

### 2.5 Light and shadows

- **Normals on the cylinder.** Front face at arc angle `θ`: `N = (−sinθ·n, cosθ)`. Back face: `N = (sinθ·n, −cosθ)`.
  - Diffuse `max(dot(N, L), 0)` with an overhead light tilted towards the top-left of the screen. This gives the
    characteristic darkening at the curl silhouette (`θ → π/2`) and a bright band where the back face turns
    towards the viewer (`θ → π`).
  - Add a Blinn-Phong specular streak along the curl (`H = normalize(L + (0, 0, 1))`, shininess about 20–40,
    weak). This is the dynamic counterpart of Okuma's static specular map.
  - harism uses a simpler `colorFactor = .1 + .9 * sqrt(sin(rotY) + 1)`.
- **Drop shadow on the revealed page** for `d > R`: alpha `a0·(1 − smoothstep(0, w, d − R))`, with width `w`
  growing with `R` (the lift). harism's penumbra is `z/2` along `−curlDir`, with colour proportional to `z/R`.
  StPageFlip draws an "outer shadow" gradient along the fold line with `maxShadowOpacity` (default 1). Compose
  `pagecurl` uses `shadowAlpha 0.2`, `shadowRadius 15.dp`.
- **Self shadow:** the folded-over flap shades the flat part of the same page next to it. harism adds a second
  shadow strip for vertices with `z > R`. StPageFlip draws an "inner shadow" gradient with stops at 0, 0.7, 0.9
  and 1. A cheap approximation is to darken `frontFace` for `d ∈ [−w2, 0]` while the top layer is present.
- **Spine shadow** in spreads: Okuma's book-fold profile (§1.3), or StPageFlip's `drawBookShadow`. That one is
  a `width/20` gradient with stops `0 → .2 → .1 → .5 (at the spine) → .4 → 0`.
- **Okuma lighting while turning:** keep layers 5–6 of §1.11 in screen space and add the cylinder terms above.

### 2.6 Two-page spreads (R1.5)

- **Hinge = spine.** Forward turn in an LTR book:
  - turning page = current right page `R_k`
  - back = next left page `L_{k+1}`
  - underneath, right half = `R_{k+1}`
  - underneath, left half = the static `L_k`, until the flap covers it.
- **Backward turn:** mirror x around the spine and run the same code. Front `L_k`, back `R_{k−1}`, underneath
  `L_{k−1}`.
- **RTL (manga):** forward is the left page. Mirror again. Okuma's `japaneseOrder` and Mihon's `isReversed` are
  the same flag.
- **Which page is grabbed:** the touch's half of the spread decides. harism: `if (mDragStartPos.x < rightRect.left
  && mCurrentIndex > 0) { ... startCurl(CURL_LEFT) }`. eschao swaps its two pages so "the first page is always
  active page which touch event is happening on".
- **Constraints** are §2.2.2 with the hinge at the spine. The target pose for a completed turn is `T* = (−W, G'.y)`
  with `R → 0`, so the page lies flat on the other side. eschao recomputes the fold points when
  `page.isXOutsidePage(mXFoldP1.x)` so the page "is still going forward".
- **Covers and odd counts:** the cover is shown alone on the right, the last page alone on the left (Okuma
  `firstPagesDouble`; Accord `effectiveDisplayMode`). A missing back page becomes blank paper or the inside-cover
  colour.
- **Single-page mode:** the hinge is the screen's left edge (UIPageViewController `.min`).
  - Forward: `R_k` curls off to the left, revealing `R_{k+1}`.
  - Backward: page `k−1` starts in the fully turned pose `T = (−W, y)` and follows the finger back. This is
    harism's one-page `CURL_LEFT`, "let curl follow pointer position".
- **Orientation:** landscape on a tablet or desktop gives a spread, portrait gives a single page (eschao
  `AUTO_PAGE_MODE`, Accord `is1ColumnLayout`, StPageFlip `usePortrait`). Keep the reading position anchored to the
  page index when switching.

### 2.7 Release: snap and fling

| implementation | rule |
|-|-|
| harism | No velocity. The side of the page midline (one page) or the spine (two pages) decides. A linear 300 ms tween of the simulated pointer (`mAnimationDurationTime = 300`). |
| StPageFlip | No velocity in `stopMove`: `if (pos.x <= 0) animateFlippingTo(pos, {x: -pageWidth, y}, true) else ... false`. Duration proportional to path length (`flippingTime` 1000 ms for ≥ 1000 px). Fast swipes are detected separately (`swipeDistance: 30`). |
| Compose `pagecurl` | `VelocityTracker`, then `splineBasedDecay(...).calculateTargetValue(...)`. The turn succeeds if the *projected* end point is inside the "end" rectangle (left half for forward), then `edge.animateTo(end)`. |
| eschao | An Android `Scroller` (`mScroller.computeScrollOffset()`) toward the target corner. |

Recommendation:

- Progress `p = (W − T.x) / 2W`.
- Project the release point with platform decay (Android `splineBasedDecay`, Flutter `FrictionSimulation`, iOS
  `UIScrollView.DecelerationRate.normal` maths).
- Complete if the projected `T.x < 0` (past the hinge mid-line). A fast flick against the turn direction always
  cancels.
- Animate `T` to the target with a critically damped spring (damping ratio 1, so no bounce on paper; stiffness
  around Android `STIFFNESS_MEDIUM` = 1500) seeded with the release velocity, so there is no speed jump.
  Interpolate `T.y` toward the grabbed row and `R → 0` at the end. Cap at about 400 ms.
- Tap, key or volume turns use a scripted path:
  - from the bottom corner `(W, 0.85H)` to `(−W, 0.85H)`
  - a slight y-dip mid-way
  - ease-in-out, about 350–450 ms
  - StPageFlip's `flipNext` corner animation is the model.
- R2.4: with reduced motion on, use a cross-fade or slide. In e-ink themes (R3.2), turn pages instantly
  (ghosting).

### 2.8 Performance on mobile GPUs

| | fragment-only (recommended) | mesh (harism / eschao) |
|-|-|-|
| CPU per frame | ~6 uniforms | Rebuild vertices. harism splits the rotated page into scan-line strips and moves intersections; eschao uses a `mMeshCount` grid. |
| GPU | 1 full-quad pass; ≤ 3 texture fetches plus `asin` per pixel | Few hundred vertices; per-pixel cost ≈ 1 fetch |
| Quality | Exact at any resolution; analytic AA | Faceting unless dense; separate shadow meshes |
| Real 3D perspective | Awkward (needs ray–cylinder intersection) | Easy |
| Portability | GLSL / AGSL / SkSL / WGSL, one function | Needs a vertex API: GL ES, Metal, `drawVertices` (Android HW-accelerated only from **API 29**), `drawBitmapMesh` (HW; colours array API 18) |

- **Fill-rate estimate (arithmetic, not a benchmark):** a 1440×3120 screen is 4.5 Mpx. At 120 Hz that is about
  540 M fragment invocations per second with 2–3 fetches each. That is fine on current mid and high-end GPUs. On
  low-end ones, limit the pass to the page quad, use `mediump`, and drop to 60 Hz during the turn. **Unverified**
  on real devices; measure on the cheapest test phone early.
- **The real cost is page textures, not the curl.**
  - Rasterise the current, next and previous pages (and both faces in a spread) off the UI thread before the drag
    starts. Keep a small LRU cache, and never re-upload a texture during a gesture. Android's own guidance: "Every
    time you change the content of a bitmap, it is uploaded again as a GPU texture".
  - A 1080×2400 RGBA8 page is about 10.4 MB, so 5 cached textures are about 52 MB. Keep RGBA8 because text
    anti-aliasing suffers at lower depths.
  - flutter_page_curl captures with `RepaintBoundary.toImage()` per page. Fine at drag start; too slow per frame.
- **Shader availability by possible stack** (the stack decision is in `stack.md`):
  - **Flutter:** `FragmentProgram` (GLSL, sampler uniforms) on all six platforms; `flutter_page_curl` is a working
    proof. Its README says it needs Impeller, "opt-in on Android". **Unverified** for current Flutter, where
    Impeller is believed to be the default on Vulkan-capable Android devices.
  - **Native Android:** AGSL `RuntimeShader` needs API 33. Below that, use OpenGL ES 2/3 in a `TextureView`
    (harism and eschao run on GL ES) or the mesh fallback.
  - **Compose Multiplatform** (desktop/iOS/web via Skiko): SkSL runtime effects. **Unverified** API surface.
  - **Web:** a WebGL2 fragment shader; Canvas2D fallback = StPageFlip-style flat fold.
  - **Rust/wgpu (Rune):** WGSL port of the same function.

### 2.9 Reference implementations

| project | approach | license | version / last code | read it for |
|-|-|-|-|-|
| [harism/android-pagecurl](https://github.com/harism/android-pagecurl) | Cylinder, CPU mesh, GL ES 1.0 | Apache-2.0 | last commit 2012-06-06 (`7a2c8f1`) | Touch→axis maths (`CurlView.updateCurlPos`), strip mesh, drop and self shadows (`CurlMesh.curl`), one- and two-page modes |
| [eschao/android-PageFlip](https://github.com/eschao/android-PageFlip) | Cylinder, mesh, GL ES 2.0 shaders | Apache-2.0 | 1.0.2 (jitpack); last commit 2024-04-11 | Auto single/double page, vertical vs slope fold, shadow widths, back mask, `Scroller` animation |
| [Nghi-NV/flutter_page_curl](https://github.com/Nghi-NV/flutter_page_curl) (`shaders/page_curl.frag`) | Cylinder, **per-pixel inverse**, Flutter `FragmentProgram` | MIT | pub 0.1.0; pushed 2026-04-25; 5 stars | Proof that §2.3 runs in Flutter. Mind its normalized-UV radius and young age. |
| [gl-transitions InvertedPageCurl](https://github.com/gl-transitions/gl-transitions/blob/master/transitions/InvertedPageCurl.glsl) | Cylinder per pixel, progress-only, fixed 100° angle | BSD-3 (HP 2010); repo MIT | active 2026 | Back-face shading, anti-aliasing helpers, shadow falloffs |
| [Nodlik/StPageFlip](https://github.com/Nodlik/StPageFlip) (npm `page-flip`) | Flat fold, Canvas2D/HTML | MIT | 2.0.7 (2021-04-18) | Hinge circle constraint, clip polygons, inner/outer/book shadows, portrait vs landscape |
| [oleksandrbalan/pagecurl](https://github.com/oleksandrbalan/pagecurl) | Flat fold, Jetpack Compose | Apache-2.0 | v1.5.1 (2024-02-09) | Compose gesture wiring, decay-projected fling, back-page alpha, shadow via `setShadowLayer` (HW from API 28) |
| [nkalahanov/book_page_flip](https://github.com/nkalahanov/book_page_flip) | "True 3D page curl on a real mesh", spreads | MIT | pub 0.1.0; pushed 2026-06-30 | Flutter spread handling, `BookFlipPhysics`. Internals **unverified** (only pub.dev read). |
| [vanisupriya/page_curl_flip](https://pub.dev/packages/page_curl_flip) | Cylinder over 28 slices, fling-only (no finger tracking) | MIT | 0.2.5 | Not suitable; finger tracking is required |
| [blasten/turn.js](https://github.com/blasten/turn.js) | Flat fold, DOM | BSD ("turn.js 3rd release", © 2012 Emmanuel Garcia). turn.js 4 is commercial (**unverified**). | 2024-02 push | Historical reference only |
| [xissburg/XBPageCurl](https://github.com/xissburg/XBPageCurl) | Cylinder, OpenGL ES, iOS | MIT | 2019 | iBooks-like curl on iOS (not read in depth) |
| Nuon ConeCurl, flirble | Cone, then cylinder | none stated | 2010 | Background only |

**License policy for us:**

- MIT, BSD and Apache-2.0: we may port the maths and, with the notice, the code.
- Our final curl will be our own code: about 150 lines of shader plus gesture glue.
- GPL and AGPL projects (KOReader, Readest, Librera, Aidoku) are behaviour references only. Copy no code from them
  unless the project's license is decided to be compatible.

---

## 3. Input: volume keys and desktop equivalents

### 3.1 Android

- Volume keys reach the focused activity before the system adjusts the stream volume. Returning `true` (consuming)
  for both `ACTION_DOWN` and `ACTION_UP` stops the volume change, and with it the volume HUD.
- `KeyEvent` docs: `KEYCODE_VOLUME_UP` (24) "Adjusts the speaker volume up", `KEYCODE_VOLUME_DOWN` (25).
- Shipped code doing exactly this:

  mangayomi (Flutter app, Apache-2.0), `android/.../MainActivity.kt` (`4da400f`, 2026-10-23):
  ```kotlin
  override fun dispatchKeyEvent(event: KeyEvent): Boolean {
      val keyCode = event.keyCode
      if (interceptVolumeKeys &&
          (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
      ) {
          // One page per press: the first down, not the repeats of a held
          // key nor the up. Both are consumed so the volume does not move.
          if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
              volumeKeysChannel?.invokeMethod("press", if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) "up" else "down")
          }
          return true
      }
      return super.dispatchKeyEvent(event)
  }
  ```

  Mihon (Compose, Apache-2.0, v0.21.3), `ReaderActivity.onKeyEvent` via `onPreviewKeyEvent` (`524fa53`,
  2026-11-09). It acts on key **up**, consumes both, and both toggles exist:
  ```kotlin
  Key.VolumeDown, Key.VolumeUp -> {
      val general = settingsViewModel.general.value
      if (!general.volumeKeysEnabled || viewModel.state.value.menuVisible) return false
      if ((event.key == Key.VolumeDown) != general.volumeKeysInverted) Action.FORWARD else Action.BACKWARD
  }
  ```

  Readest (Tauri, AGPL-3.0) `MainActivity.dispatchKeyEvent` forwards `VolumeUp`/`VolumeDown` to the WebView and
  `return true` while `interceptVolumeKeysEnabled`. It also has a key-learn mode for media and page-turner keys.
- **Recommended behaviour:**
  - Default: **Volume Down = next, Volume Up = previous** (Mihon's default). R4.5's invert swaps them. Librera
    inverts by default on small screens (`isReverseKeys = Dips.isSmallScreen()`).
  - Act on the first DOWN for responsiveness (mangayomi), with optional auto-repeat while held.
  - Hand the keys back to the system (`return false`) when the toggle is off, when a menu, sheet or dialog is open
    (Mihon), and **while TTS is playing** (the user needs real volume then; R8).
  - Use `Activity.dispatchKeyEvent`, not a Compose focus target: it does not depend on focus. With Flutter, add
    this tiny platform hook, as mangayomi does. Whether Flutter's own key handling alone suppresses the HUD is
    **unverified**.
  - The system still owns the keys during calls and for the accessibility volume-key shortcut (believed, on-device
    check **unverified**).
- **Bluetooth page turners:** most send arrows, PageUp/PageDown, Space, Enter or media keys. Map
  `KEYCODE_PAGE_UP/DOWN` (92/93), `DPAD_LEFT/RIGHT/UP/DOWN` and `MEDIA_NEXT/PREVIOUS`. A "press a key to bind it"
  screen like Readest's key-learn mode covers odd remotes.

### 3.2 iOS / iPadOS

- **There is no public API for volume-button events in a reader app.**
  - `AVCaptureEventInteraction` (iOS 17.2+) delivers hardware button presses only while an `AVCaptureSession` is
    running. Apple's WWDC25 session says apps "that do not have an active AVCaptureSession running, won't receive
    any events". Not usable.
  - App Review Guideline **2.5.9**: "Apps that alter or disable the functions of standard switches, such as the
    Volume Up/Down and Ring/Silent switches, or other native user interface elements or behaviors will be
    rejected."
- **What readers do anyway** (Readest, on the App Store, in
  `tauri-plugin-native-bridge/ios/Sources/NativeBridgePlugin.swift`, `6e2390f`, 2026-11-03):
  1. Activate an audio session (`.playback`, `.mixWithOthers`).
  2. Clamp a reference volume into [0.1, 0.9].
  3. Add an off-screen `MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))`. Its presence hides
     the system HUD.
  4. KVO `outputVolume`. On a change, emit VolumeUp or VolumeDown by comparing with the previous value, then reset
     the slider to the reference so the volume never actually drifts.
  5. On stop, restore the original volume and remove the view.
  6. Leave the session alone while TTS owns it.
- **Caveats:**
  - Holding the button gives one event per step.
  - Nothing fires at 0 % or 100 % (hence the clamp).
  - Muting or AirPlay changes behaviour.
  - Other apps' audio may be affected by the session.
  - Review risk under 2.5.9. Readest passed review, but that is no guarantee.
- **Recommendation:**
  - Ship the iOS volume toggle **off by default**, marked experimental, with the same invert option.
  - For hardware keyboards and remotes on iPad, use `UIKeyCommand` (arrows, PageUp/PageDown, Space) or
    `pressesBegan`. `wantsPriorityOverSystemBehavior` is needed for arrows inside scroll views (iOS 15+,
    **unverified** detail).

### 3.3 Desktop (Windows, macOS, Linux) and web

| input | action |
|-|-|
| → / ← | next / previous in LTR (swapped for RTL; Mihon maps arrows through the zone layout's `RIGHT`/`LEFT` regions, so they follow RTL) |
| ↓ / ↑ | next / previous in paged modes; scroll in endless mode |
| PageDown / PageUp, Space / Shift+Space | next / previous screen (Mihon: `Key.DirectionDown, Key.PageDown -> Action.FORWARD`) |
| Home / End | first / last page (Okuma uses them for chapters) |
| Mouse wheel | Paged modes: accumulate `deltaY` (normalise `deltaMode`: 0 px, 1 line ≈ 16 px, 2 page) until a threshold (≈ 100 px), turn one page, then ignore further deltas for about 300 ms so trackpad momentum doesn't skip pages. In endless scroll, native scrolling. **Ctrl + wheel = zoom.** Chromium and Firefox report trackpad pinch as `wheel` with `ctrlKey = true` (Safari: **unverified**). |
| Mouse click | Same tap-zone engine as touch (§4) |
| Click-drag on page | Same curl gesture as touch (mouse = one pointer) |

With the flip animation on, keys, wheel and taps start the scripted turn (§2.7). Queue at most one pending turn,
so a fast double press turns two pages without dropping either.

---

## 4. Tap zones (R4.1)

### 4.1 What other readers do

| app | model (verified from source unless marked) |
|-|-|
| **KOReader** (AGPL-3.0, v2026.07.1) | Normalized rectangles in `defaults.lua`: `DTAP_ZONE_FORWARD = {x = 1/4, y = 0, w = 3/4, h = 1}`, `DTAP_ZONE_BACKWARD = {x = 0, y = 0, w = 1/4, h = 1}`, `DTAP_ZONE_MENU = {x = 0, y = 0, w = 1, h = 1/8}`, `DTAP_ZONE_CONFIG = {x = 0, y = 7/8, w = 1, h = 1/8}`, four corner zones of 1/8 × 1/8. Menu (`frontend/ui/elements/page_turns.lua`): tap-zone type Default / Left-right / Top-bottom / Bottom-top, a "Backward / forward tap zone size" slider pair (percent of width or height), "Invert page turn taps and swipes". The Gestures plugin assigns any action to corners and other gestures. |
| **Mihon** (Apache-2.0, v0.21.3) | `ViewerNavigation.Region(rect: Rect /*0..1*/, type: NavigationRegion)` with types MENU, PREV, NEXT, LEFT, RIGHT. Presets: L-shaped (default), Kindle-ish, Edge, Right-and-Left, Disabled. Inversion `TappingInvertMode` (NONE / HORIZONTAL / VERTICAL / BOTH) mirrors the rects: `left = if (horizontal) 1f - rect.right else rect.left`. A tap outside every region = **MENU**. Colour-coded overlay (`MENU 0xCC95818D`, `PREV 0xCCFF7733`, `NEXT 0xCC84E296`, `LEFT 0xCC7D1128`, `RIGHT 0xCCA6CFD5`) shown when the layout changes and optionally on reader start (`showNavigationOverlayOnStart`, `showNavigationOverlayNewUser`). |
| **Librera** (GPL-3.0) | `TapZoneDialog`: four side zones (left / right / top / bottom), each set to Next page / Previous page / Do nothing. Defaults: top = prev, bottom = next, left = prev, right = next. Size `tapzoneSize` = 25 % (15 % on extra-large screens). `isShowRectangularTapZones`. |
| **Moon+ Reader** (closed source) | Configurable tap areas mapped to actions (next/prev, menu, brightness and others). The exact grid and menu path are **unverified**; I found no first-party documentation. |
| **BookFusion** (closed source) | Custom tap zones on a **3×3 grid**: Page Left, Page Right, Toggle Toolbar, Play/Pause, No Action (from their release blog). |
| **Okuma** | Fixed 20 % / 60 % / 20 % (left / menu / right) on the page box, not the screen (`edgeClickArea = 0.2`). |

None of these let you *draw* free shapes. Ours (rectangles and circles placed on a phone canvas) is a superset.
Ship the Mihon presets and KOReader-style sliders as starting points.

### 4.2 Editor UX proposal

- **Canvas:** a phone outline at the current device's aspect ratio, in the current orientation, with a portrait /
  landscape switch. A dimmed sample page sits behind, and a spread in landscape when two-page is on.
- **Tools:** add rectangle, add circle, duplicate, delete, presets (L, Kindle-ish, Edge, Left/Right, KOReader-style
  sizes), "copy from portrait".
- **Manipulation:**
  - Drag to move. Rectangles get 8 resize handles; circles one radial handle.
  - Snap to thirds, quarters and the other zones' edges, and show the size live as a percentage.
  - Long-press for z-order (bring forward / send back).
  - Handles at least 48 dp, for accessibility.
- **Action picker:** a bottom sheet with Next page, Previous page, Toggle menu, None. It can be extended later
  (next/prev chapter, bookmark, TTS play/pause, brightness), but do not add those until asked.
- **Colours:** one per action, Mihon palette, with the label inside the shape.
- **Test mode:** tap the canvas and the matching zone flashes and names its action.
- **In the reader:** show the zone overlay for about 1.5 s after the layout changes and on first use (Mihon
  pattern).
- **Unmatched taps:** a setting "Taps outside zones: do nothing | toggle menu" (Mihon uses menu).
- **RTL books:** auto-mirror horizontally (Mihon `isReversed`). Per-book override "invert horizontally".

### 4.3 Data shape

```jsonc
{
  "version": 1,
  "unmatched": "none",                 // "none" | "toggleMenu"
  "mirrorForRtl": true,
  "portrait": {
    "zones": [                          // array order = z-order; the LAST hit wins (drawn on top)
      { "id": "z1", "shape": "rect",   "x": 0.0,  "y": 0.0, "w": 0.33, "h": 1.0, "action": "prevPage" },
      { "id": "z2", "shape": "rect",   "x": 0.67, "y": 0.0, "w": 0.33, "h": 1.0, "action": "nextPage" },
      { "id": "z3", "shape": "circle", "cx": 0.5, "cy": 0.5, "r": 0.18,         "action": "toggleMenu" }
    ]
  },
  "landscape": "fromPortrait"          // or a full { "zones": [...] } set of its own
}
```

```kotlin
// The same model as types (Kotlin shown; mirror it in Dart or TS).
enum class TapAction { PrevPage, NextPage, ToggleMenu, None }
sealed interface ZoneShape {
    data class Rect(val x: Float, val y: Float, val w: Float, val h: Float) : ZoneShape   // fractions of viewport w/h
    data class Circle(val cx: Float, val cy: Float, val r: Float) : ZoneShape           // r = fraction of min(w, h)
}
data class TapZone(val id: String, val shape: ZoneShape, val action: TapAction)
data class ZoneSet(val zones: List<TapZone>)
data class TapLayout(val portrait: ZoneSet, val landscape: ZoneSet?, /* null = use portrait */
                     val unmatched: TapAction = TapAction.None, val mirrorForRtl: Boolean = true)
```

- **Normalization:** rectangles use fractions of the *reading viewport* (inside the safe area), so a layout
  survives any screen size.
  - Circles: `cx` and `cy` are fractions of width and height, but `r` is a fraction of `min(width, height)`, so a
    circle stays round in both orientations. Hit test: `(px − cx·W)² + (py − cy·H)² ≤ (r·min(W, H))²`.
  - Store values clamped to [0, 1]. Shapes may overlap.
- **Hit test:** walk the zones from last to first. The first hit returns its action; otherwise `unmatched`. For RTL
  with `mirrorForRtl`, test `x' = 1 − x` and swap prev and next (Mihon applies `invert` to the rects and swaps
  `LEFT`/`RIGHT` through `isReversed`).
- **"fromPortrait"** reuses the fractions as they are, which is the KOReader and Mihon behaviour. A separate
  landscape set is opt-in.
- **Interaction with flip mode:** in Flip mode a tap inside a page-turn zone starts the scripted turn, while a drag
  starts the curl. Decide "tap" by touch slop: a drag beyond `ViewConfiguration.scaledTouchSlop` (≈ 8 dp) is a
  curl.
- **Endless scroll mode:** zones still work. Prev/next scroll by one viewport minus a small overlap.
- **Where it lives:** global default, with a per-book override, as the implied "settings per book vs. global"
  requirement asks.

---

## 5. Unverified or open items

- The "Steve Wade / iBooks page curl" source was not found. The cone write-ups are by Nuon and flirble (§2.1).
- Moon+ Reader's exact tap-zone grid and menus: closed source, no first-party docs found.
- Flutter Impeller status on Android, the Compose Multiplatform SkSL API, and iOS `wantsPriorityOverSystemBehavior`
  details.
- Safari's trackpad pinch to `wheel` + `ctrlKey` behaviour.
- Whether a Flutter-only key handler (no `dispatchKeyEvent` override) suppresses the Android volume HUD.
- System precedence of the accessibility volume shortcut and in-call volume over app interception.
- Provenance of the Okuma and Accord textures beyond the repos' MIT grants.
- `book_page_flip` internals (only its pub.dev page was read).
- Real-device fill-rate of the per-pixel curl on a low-end GPU (§2.8 numbers are arithmetic).

---

## 6. Sources

Okuma and Accord's Library
- Okuma-Reader repo and README: https://github.com/DrMint/Okuma-Reader (files read at `842cf37`: `read.html`,
  `css/navImage.css`, `css/read.css`, `css/config.css`, `css/global.css`, `js/read.js`, `js/directive.js`,
  `js/tools.js`, `js/constants.js`, `img/*.webp`)
- Okuma demo: https://drmint.github.io/Okuma-Reader/
- ironexdev/zoom (Apache-2.0, origin of `directive.js`): https://github.com/ironexdev/zoom
- Accord's Library reader: https://github.com/Accords-Library/accords-library.com/blob/main/src/pages/library/%5Bslug%5D/reader.tsx ,
  settings: https://github.com/Accords-Library/accords-library.com/blob/main/src/hooks/useReaderSettings.ts ,
  textures: https://github.com/Accords-Library/accords-library.com/tree/main/public/reader
- W3C Compositing and Blending Level 1 (blend formulas): https://www.w3.org/TR/compositing-1/

Page curl
- harism/android-pagecurl: https://github.com/harism/android-pagecurl (`src/fi/harism/curl/CurlView.java`, `CurlMesh.java`, `CurlActivity.java`)
- eschao/android-PageFlip: https://github.com/eschao/android-PageFlip (`PageFlip.java`, `Page.java`, `res/raw/*.glsl`)
- Nodlik/StPageFlip: https://github.com/Nodlik/StPageFlip (`src/Flip/FlipCalculation.ts`, `src/Flip/Flip.ts`, `src/Render/CanvasRender.ts`, `src/Settings.ts`); npm: https://www.npmjs.com/package/page-flip
- oleksandrbalan/pagecurl (Compose): https://github.com/oleksandrbalan/pagecurl (`page/CurlDraw.kt`, `page/DragCommonGesture.kt`, `page/DragStartEnd.kt`, `config/PageCurlConfig.kt`)
- gl-transitions InvertedPageCurl (HP, BSD-3): https://github.com/gl-transitions/gl-transitions/blob/master/transitions/InvertedPageCurl.glsl
- flutter_page_curl: https://pub.dev/packages/flutter_page_curl , https://github.com/Nghi-NV/flutter_page_curl
- book_page_flip: https://pub.dev/packages/book_page_flip , https://github.com/nkalahanov/book_page_flip
- page_curl_flip: https://pub.dev/packages/page_curl_flip
- page_turn_animation: https://pub.dev/packages/page_turn_animation (listed, not read in depth)
- turn.js 3rd release: https://github.com/blasten/turn.js
- XBPageCurl: https://github.com/xissburg/XBPageCurl
- W. Dana Nuon, "Implementing iBooks page curling using a conical deformation" (2010): https://wdnuon.blogspot.com/2010/05/implementing-ibooks-page-curling-using.html
- Chris Luke, "The anatomy of a page curl" (2010): https://blog.flirble.org/2010/10/08/the-anatomy-of-a-page-curl
- PARC patents: https://patents.google.com/patent/US7667703 , https://patents.google.com/patent/US7898541
- UIPageViewController: https://developer.apple.com/documentation/uikit/uipageviewcontroller ; ZoomingPDFViewer sample (spine `.mid` in landscape): https://developer.apple.com/library/archive/samplecode/ZoomingPDFViewer/Listings/ZoomingPDFViewerSwift_ZoomingPDFViewer_RootViewController_swift.html ; curl bug thread: https://developer.apple.com/forums/thread/734956
- Android hardware-acceleration support table (`drawVertices` API 29, `setShadowLayer` API 28): https://developer.android.com/develop/ui/views/graphics/hardware-accel

Input
- Android `KeyEvent`: https://developer.android.com/reference/android/view/KeyEvent
- mangayomi `MainActivity.kt`: https://github.com/kodjodevf/mangayomi/blob/main/android/app/src/main/kotlin/com/kodjodevf/mangayomi/MainActivity.kt
- Mihon `ReaderActivity.kt`: https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/ReaderActivity.kt ; `ReaderPreferences.kt`: https://github.com/mihonapp/mihon/blob/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/setting/ReaderPreferences.kt
- Readest Android `MainActivity.kt`: https://github.com/readest/readest/blob/main/apps/readest-app/src-tauri/gen/android/app/src/main/java/com/bilingify/readest/MainActivity.kt ; iOS `NativeBridgePlugin.swift`: https://github.com/readest/readest/blob/main/apps/readest-app/src-tauri/plugins/tauri-plugin-native-bridge/ios/Sources/NativeBridgePlugin.swift
- App Review Guidelines 2.5.9: https://developer.apple.com/app-store/review/guidelines/
- AVCaptureEventInteraction: https://developer.apple.com/documentation/avkit/avcaptureeventinteraction ; WWDC25 session 253: https://developer.apple.com/videos/play/wwdc2025/253/

Tap zones
- Mihon navigation: https://github.com/mihonapp/mihon/tree/main/app/src/main/java/eu/kanade/tachiyomi/ui/reader/viewer (`ViewerNavigation.kt`, `navigation/*.kt`); docs: https://mihon.app/docs/guides/reader-settings
- KOReader `defaults.lua`: https://github.com/koreader/koreader/blob/master/defaults.lua ; `page_turns.lua`: https://github.com/koreader/koreader/blob/master/frontend/ui/elements/page_turns.lua
- Librera `TapZoneDialog.java`: https://github.com/foobnix/LibreraReader/blob/master/app/src/main/java/com/foobnix/pdf/info/widget/TapZoneDialog.java ; `AppState.java`: https://github.com/foobnix/LibreraReader/blob/master/app/src/main/java/com/foobnix/model/AppState.java ; FAQ: https://librera.mobi/faq
- BookFusion custom tap zones: https://www.blog.bookfusion.com/bookfusion-ios-1-31-0-custom-tap-zones-other-improvements/
- Moon+ Reader (MobileRead wiki): https://wiki.mobileread.com/wiki/Moon+_Reader
