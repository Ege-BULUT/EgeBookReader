# EgeBookReader: app architecture and stack

Researched 2026-11-10. Versions and star counts were read from GitHub or official docs that day. Anything not checked
against a primary source is marked **unverified**.

## 1. Summary and recommendation

**Primary: Flutter (3.47.x stable) for the UI on all six targets, plus one shared Rust core, plus thin native glue.**

```
┌──────────────── Flutter UI (Dart): one codebase for Android, iOS, Windows, macOS, Linux and web ───────────────┐
│ library, reader chrome, settings, motion; page curl and paper effects as GLSL fragment shaders over textures │
└───────────────▲──────────────────────────────────────────────────────────────▲─────────────────────────────────┘
                │ flutter_rust_bridge 2.13 (FFI; wasm on web)                   │ MethodChannel / EventChannel
┌───────────────┴──────────────────────────────────────┐   ┌───────────────────┴──────────────────────────────┐
│ Rust core (UI-agnostic crate, C ABI-friendly)        │   │ Native glue (small)                              │
│ formats → page rasters + text geometry, library DB,  │◀──│ Kotlin: volume keys, WorkManager/FGS worker that │
│ search, sync, ONNX queue (ort), TTS (sherpa-onnx C)  │JNI│ calls the Rust core directly, audio focus        │
└──────────────────────────────────────────────────────┘   │ Swift: AVAudioSession, BGProcessingTask          │
                                                           └──────────────────────────────────────────────────┘
```

Why Flutter:

1. **It is the only option here that is stable on all six targets with one UI codebase and custom GPU shaders.**
   Impeller is the only renderer on iOS. It is the default on Android API 29+, falling back to OpenGL below that or
   without Vulkan. It became the default on macOS, Windows and Linux in 3.47. One `.frag` GLSL source compiles for
   every backend, and fragment shaders also run on the web through Skia.
2. **Page curl fits its shader model.** The curl is a per-pixel cylinder mapping in a fragment shader over two page
   textures, plus `Canvas.drawVertices` for a deformed mesh where needed. Lighting, fold shadow, paper texture and
   specular all live in the same shader. Working precedents exist: `flutter_page_curl` on pub.dev, and Rahiche's
   `riveo_page_curl` (no licence file, so learn from it but don't copy it). Pages arrive from the Rust core as RGBA,
   go through `decodeImageFromPixels`, become a `ui.Image`, and are passed in with `setImageSampler`.
3. **Android-first is cheap.** `FlutterActivity` is an ordinary Activity, so volume keys (`dispatchKeyEvent`),
   WorkManager and foreground services take a few dozen lines of Kotlin. The `vol_spotter`, `volume_button_override`
   and `workmanager` plugins exist too.
4. **It has the richest motion and design ecosystem of the cross-platform options:** implicit and physics animation,
   Rive, Lottie, 120 Hz. AI agents also write Dart and Flutter well, which matters for one developer working with
   agents.
5. **An ebook reader on this stack already ships.** Anx Reader (MIT, ★9.2k) runs Flutter with foliate-js on Android,
   iOS, macOS and Windows. sherpa-onnx has official Dart/Flutter packages, and `ort` (Rust ONNX Runtime) ships
   prebuilt binaries for Android arm64/x64 and iOS arm64.
6. **The web build can share the app later** (CanvasKit or skwasm). The landing page at egebookreader.vercel.app
   should still be a static site, because Flutter web downloads several MB and does poorly for SEO (unverified size).

Design rule that keeps options open: **the Rust core renders every page to a texture and returns text geometry**
(glyph and word boxes, sentence ranges for TTS highlighting, links). The UI only composites, animates and shades.
That keeps the Flutter layer thin, makes the curl identical for PDF, EPUB and comics, and makes a later UI swap
(for example to Rune on desktop) a UI-only rewrite.

**Runner-up: Compose Multiplatform 1.12 (Kotlin) with the same Rust core through UniFFI.** Its Android story is the
best of any option, because it is Android's own toolkit: WorkManager, volume keys, the ONNX Runtime AAR and
sherpa-onnx Kotlin all work with no bridge. It is stable on iOS (since 1.8.0, May 2025) and on desktop (JVM). Web
(Kotlin/Wasm) is beta. Pick it over Flutter if Android "native feel" matters more than one shader language and a
mature web target. The costs:

- Runtime shaders split into AGSL (`RuntimeShader`, Android 13 / API 33+ only, so older devices need a fallback) and
  SkSL (Skiko `RuntimeEffect`) on iOS, desktop and web.
- The desktop app is a JVM app, so it is bigger and starts slower.
- Rust↔KMP for iOS is less mature (Gobley 0.3.7, Oct 2025).

**Third: Tauri 2 (2.12.5) with foliate-js.** This is the fastest way to a feature-complete reader, and Readest (AGPL,
★26k) proves it on all six targets. But it is a WebView UI (the least native feel), WebView performance varies
(Android System WebView, WebKitGTK on Linux), DOM pages can't be curled until they are rasterized, and Tauri 3 is in
alpha (3.0.0-alpha.6, 2026-11-06), so a migration is coming.

**Rune, honestly: excellent desktop tech, no mobile today.** Android is "not started" (milestone M7, no estimate), and
iOS is embedding-only. Using Rune for desktop now means a **second UI codebase**:

- every screen built twice, in Dart and in Rust;
- two shader dialects (GLSL and WGSL);
- two motion tunings, two accessibility and test setups;
- pinning a pre-release framework that moves about 100 commits a day.

My estimate is +60–100% ongoing UI work for the lowest-priority platforms. Keep the Rust core UI-agnostic and revisit
Rune when it ships an Android shell with IME and TalkBack and a stability policy. Details are in section 2.

### UI codebases per option

| Option | Android | iOS | Win | mac | Linux | Web | UI codebases |
|---|---|---|---|---|---|---|---|
| **Flutter** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | **1** (+ small Kotlin/Swift glue) |
| Compose Multiplatform | ✅ native | ✅ | ✅ JVM | ✅ JVM | ✅ JVM | beta | **1** (+ expect/actual shaders) |
| Tauri 2 | ✅ WebView | ✅ WebView | ✅ | ✅ | ✅ WebKitGTK | ✅ | **1** web UI (+ Kotlin/Swift plugins) |
| Avalonia 12 | ✅ (.NET 10) | ✅ | ✅ | ✅ | ✅ X11, Wayland opt-in | ✅ WASM | **1** |
| Slint 1.18 | ✅ | ✅ (winit+Skia) | ✅ | ✅ | ✅ | demos only (unverified) | **1** |
| Dioxus 0.7 | WebView (native renderer experimental) | same | ✅ | ✅ | ✅ | ✅ | **1** |
| React Native 0.88 | ✅ | ✅ | MS fork (0.85) | MS fork (0.83) | ❌ | react-native-web | **1 + a Linux gap** |
| .NET MAUI 10 | ✅ | ✅ | ✅ | Catalyst | ❌ | ❌ | **2** (Linux and web need another UI) |
| **Rune** | ❌ not started | embed only | ✅ | ✅ | ✅ X11+Wayland | experimental (WebGPU) | **2** (Rune desktop + a mobile UI), 3 if Android and iOS are native |

## 2. Rune (anomalyco/rune)

Facts were checked against the repo on 2026-11-10 (dev at `7ed827a2`). A few come from an outside architecture
review, which is marked where used.

- **Identity:** "Rune: Native UI framework". MIT, Rust 2024, ★5,978, 195 forks, 206 open issues.
- **Age and activity:**
  - The first commit is 2026-10-22, so the public history is **19 days old**, with about 1,820 commits on `dev`.
  - One author made about 84% of them (kitlangton 1,523; 10 contributors in all).
  - It has no releases or tags. The README says "Rune is pre-release. Pin a rev of `dev`".
  - It does not accept pull requests: "Have your agent open an issue … our agents usually turn it around fast."
- **Purpose:** Anomaly's in-house stack (the OpenCode team). The flagship test is recreating OpenCode Desktop.
  PLAN.md platform order: "macOS + Windows + Linux together → web → iOS → Android".

### Platform support

| Platform | Status | Evidence |
|---|---|---|
| macOS | Most complete; own Metal backend default since 2026-10-31 | `gpu/metal/`, CHANGELOG |
| Windows | Supported (winit, wgpu DX12, precompiled DXBC uber shader) | `platform/win32*`, `render/dxbc.rs` |
| Linux | X11 and Wayland through winit; layer-shell overlays | README "Linux"; Wayland gaps: no file drops in winit 0.30, closing destroys the window, no interactive overlays |
| Web | **Experimental**, WebGPU only ("no WebGL fallback" in WEB.md; the review mentions an opt-in WebGL2 feature) | WEB.md; open Safari keyboard bug #165 |
| iOS | **Embedding only:** `embed::LayerHost` mounts Rune on a `CAMetalLayer` inside a UIKit or SwiftUI app (2026-10-30). No shell, no `UITextInput`, no accessibility | changelog `2026-10-30-ios-embed.md`, issue #110 |
| Android | **Not started.** Only `cfg` exclusions in Cargo.toml. M7 in PLAN.md. The roadmap proposal (#267) says the "Android shell's work starts after iOS text input ships" and "Android has no estimate until its spike reports" | PLAN.md §10, #267 |

An outside review at rev `1571ad5` (2026-11-07, entrpi.github.io) counted 27 platform features as yes/partial/no:

| Platform | Yes | Partial | No |
|---|---|---|---|
| macOS | 19 | 5 | 3 |
| Windows | 10 | 10 | 7 |
| Linux | 5 | 14 | 8 |
| Web | 3 | 7 | 14 |
| iOS | 1 | 5 | 18 |

The same review found "0 required CI checks on the branch apps pin".

### Capabilities against our needs

- **Rendering:** wgpu (Metal, DX12, Vulkan, WebGPU) plus its own Metal backend. One instanced SDF "uber-quad"
  pipeline, a glyph atlas, and its own text rasterizer (Windfoil).
- **Custom GPU drawing (page curl): yes, and well designed.**
  - `rune::run_with(spec, compositor)` hands each frame's wgpu device, queue, encoder and target to a `Compositor`.
  - `El::effect(mark)` slots paint custom passes in painter order, keeping clip, opacity and soft edges.
    `effect_backdrop(true)` reads what was drawn before the slot. `render::CLIP_WGSL` shares Rune's clip maths.
  - `rune::Pixels` streams RGBA textures from any thread without re-running the view, which suits page rasters.
  - `Live` values and `Tx::live_only()` move a value (a finger-driven curl) without rebuilding the view.
  - Bundled crates: `rune-fx` (WGSL effects such as distortion, grain, glow) and `rune-light` (SDF lighting with soft
    shadows, bevels and specular).
  - On paper, this is the strongest fit for the paper-effects requirement of any option.
- **Animation:** analytic springs that retarget with velocity, per-edge layout animation, presence and exit
  transitions, shared-element motion, reduced motion, and a motion-audit tool. The README says animation is
  currently evaluated on the main thread at frame time; the render thread in PLAN.md isn't built yet.
- **Text and i18n:**
  - Parley, HarfRust (Rust HarfBuzz), skrifa and fontique, with bidi through Parley.
  - System-font fallback for Hebrew, Arabic, Devanagari, Bengali and Thai; hinted CJK; colour emoji; RTL-aware
    justification. `rune-i18n` provides JSON catalogs and CLDR plurals and numbers.
  - Gaps:
    - setting a paragraph's RTL base direction is still open (#244);
    - RTL layout mirroring is a later roadmap phase;
    - IME is winit's (no reconversion or replacement ranges);
    - no mobile text input.
- **Accessibility:** AccessKit on macOS, Windows and Linux since 2026-11-04. Nothing on iOS or Android (#110). The
  web uses a separate DOM mirror.
- **Packaging:** none in the framework. The sibling apps script their own. Hokum ships AUR, deb, rpm, a Nix flake and
  GitHub releases. Clip runs `scripts/bundle.sh` to make a `.app`, ships a DMG and updates itself. Rune measured a
  9.3 MB stripped arm64 binary for its settings example.
- **API churn:**
  - It moves about 100 commits a day, and CHANGELOG lists changes that move app output without a code change.
  - AGENTS.md warns that adding a pub field to 12 literal-built types breaks apps.
  - Roadmap #267 asks for a stability policy and cargo-semver-checks; neither exists yet.
- **Sharing a Rust core:** this is Rune's best property. The core is just another crate in the workspace: no FFI and
  no codegen.
- **Agent tooling:** headless render to PNG, element and accessibility tree dumps, scripted input, and hot-patching
  (about 1 s). Good for an agent-driven team.
- **Sibling apps:** both are desktop-only and pin exact `dev` revs.
  - `anomalyco/hokum` (MIT, ★251, created 2026-10-28): a Wayland notification and control centre for layer-shell
    compositors (not GNOME).
  - `anomalyco/clip` (★6, no licence file, created 2026-11-04): a macOS screen recorder for macOS 15+ on Apple
    silicon.

### Fit verdict

- **Rune cannot be the primary stack for an Android-first app.** Android has no code and no estimate, and the iOS
  shell, text input and accessibility don't exist yet.
- **For desktop it is technically attractive** (GPU hooks, springs, text quality, small binaries), but adopting it now
  means a second UI codebase. That costs:
  - each screen twice (library, reader chrome, annotations, TTS controls, settings, onboarding: realistically 30–50
    screens);
  - shaders twice: GLSL for Flutter and WGSL for Rune. naga can translate some of it, but Flutter's GLSL subset
    limits that;
  - motion tuned twice, accessibility twice, and two golden and screenshot test harnesses;
  - pin bumps against a fast-moving pre-release.
- **Path that keeps the door open:** keep the core in Rust and UI-agnostic; ship Flutter everywhere first; check
  Rune again when it has (a) an Android shell with IME and TalkBack, (b) a tagged release or stability policy, and
  (c) required CI. If all three hold, Rune on desktop (or everywhere) becomes a UI-only rewrite.

## 3. Alternatives comparison (state on 2026-11-10)

| | Flutter | Compose Multiplatform | Tauri 2 | Dioxus | Slint | React Native | Avalonia / MAUI |
|---|---|---|---|---|---|---|---|
| Version | 3.47.9 (2026-10-29), Dart 3.13 | 1.12.2 (2026-10-15) | 2.12.5; 3.0 alpha.6 | 0.7.10 (2026-07-30) | 1.18.1 (2026-09-21) | 0.88.1 (2026-10-27) | Avalonia 12.1.6, MAUI 10.0.130 |
| Licence | BSD-3 | Apache-2.0 | Apache/MIT | Apache/MIT | GPLv3, royalty-free or commercial | MIT | MIT |
| Rendering | Impeller (Vulkan, Metal, GLES fallback); Skia on web | Android: platform renderer; others: Skia (Skiko M150) | System WebView | WebView, or Blitz (wgpu HTML/CSS, experimental) | Skia, FemtoVG or software; winit | Native views; Skia via RN-Skia | Skia / native controls |
| Custom shaders | GLSL fragment shaders on all targets (no vertex shaders, no UBO, `sampler2D` only); `flutter_gpu` (vertex + 3D) still preview | AGSL on API 33+, SkSL elsewhere | WebGL2 / WebGPU in the page | Native: wgpu (unverified API) | No shader DSL; `wgpu_texture` / OpenGL underlay examples | RN-Skia `RuntimeEffect` (SkSL); react-native-wgpu preview | Skia `SKRuntimeEffect` through custom draw op (unverified details); MAUI: none in common |
| Animation | Excellent | Excellent | CSS / JS (WAAPI, GSAP) | CSS | Built-in property animations, simpler | Reanimated (UI-thread worklets) | Good / basic |
| Native feel | Custom-drawn, own design | Android-native; custom elsewhere | Web | Web | Custom-drawn | Native widgets | Custom / native |
| Rust or C core FFI | `dart:ffi` + flutter_rust_bridge 2.13 (MIT; wasm on web) | JNI / UniFFI 0.32 (Android, JVM); Kotlin/Native cinterop or Gobley (iOS) | Native: the core *is* the app | Native | Native | JSI / Turbo Modules; uniffi-bindgen-react-native 0.31 | P/Invoke (very good) |
| App size (≈, unverified) | Android ~5–8 MB base + native libs | Android ~2–5 MB; desktop JVM ~60–100 MB | ~3–10 MB | ~5–15 MB | ~3–10 MB | ~10–20 MB | ~20–40 MB on Android |
| Android background work | `workmanager` plugin, or a Kotlin Worker calling Rust | WorkManager directly | Kotlin plugin | Kotlin glue (unverified tooling) | Rust / JNI by hand | Headless JS / native modules | .NET AndroidX.Work bindings |
| Volume keys | Plugin or about 20 lines in `MainActivity` | `onKeyDown` directly | Kotlin in `MainActivity` (Readest does this) | Glue by hand | Glue by hand | `react-native-keyevent`-style module | Activity override |
| iOS quality | Mature | Stable since 1.8.0 (May 2025) | Stable since 2.0 (Oct 2024) | WebView | Supported (winit + Skia) | Best in class | Avalonia: iOS 26 Tier 1; MAUI good |

Notes:

- **Android background work is roughly stack-neutral if the core is Rust.**
  - Run the in-app "next pages" ONNX queue (colorize, upscale) on a low-priority Rust thread pool while the app is
    open.
  - Run library-wide batch jobs from a Kotlin `CoroutineWorker`, with constraints such as charging and idle, that
    calls the Rust core over JNI without starting the UI engine.
  - Android 14+ requires foreground-service types. Recent Android versions cap `dataSync` FGS runtime (Android 15:
    6 h/day, unverified for 16/17).
- **Volume keys on iOS have no public API for non-camera apps** (`AVCaptureEventInteraction` is meant for capture
  apps). The usual workaround watches `outputVolume` with a hidden `MPVolumeView` and risks App Review. This applies
  to every stack. Unverified for iOS 26/27.
- **Text shaping:** Flutter uses SkParagraph with HarfBuzz and ICU. Compose uses Minikin on Android and SkParagraph
  elsewhere. Both handle CJK, Devanagari, Cyrillic and RTL. Book-page layout is done in the core anyway (section 1).
  - Flutter caveat: Dart's `toUpperCase()` / `toLowerCase()` is locale-independent, so Turkish İ/ı breaks. Do case
    mapping and search folding in Rust with ICU4X `icu_casemap`.
- **Flutter WebView on desktop is weak.** If EPUB is rendered by foliate-js in a WebView instead of the core, Windows
  and Linux become the problem. Anx Reader forks `flutter_inappwebview` (last pushed 2026-02) and uses `webview_cef`
  on desktop. This is one more reason for the core-rendered page pipeline.
- **Slint licensing:** GPLv3 is fine for a public project, but the royalty-free licence is the safer default.
  Slint's Rust shaping used `rustybuzz`, which RustSec flagged as unmaintained in 2026-07; check what 1.18 uses
  (unverified).
- **Dioxus:** mobile is a WebView (essentially Tauri's wry). Blitz native is "experimental", with CSS gaps and
  writing-direction bugs.
- **Avalonia 12:** rebuilt Android backend; Android 16 is Tier 1, API 31–35 Tier 2. Wayland is opt-in from 12.1;
  Browser runs CanvasKit/WebGL. Viable if the team preferred C#, but its mobile track record is thinner than
  Flutter's or Compose's.

## 4. Reference readers (what to learn from or reuse)

| Project | Stack | Licence | Notes for us |
|---|---|---|---|
| **Readest** (readest/readest) ★26.1k, v0.12.20 (2026-11-05) | Tauri 2 + Next.js 16 + React; foliate-js fork; pdf.js; native plugins for TTS, bridge and WebView upgrade | **AGPL-3.0** | Best feature reference: sync, TTS, all six targets including web. Volume keys handled in `MainActivity.kt`. Copying code makes us AGPL. |
| **foliate-js** (johnfactotum) ★1.2k, no releases, pushed 2026-05 | Plain JS: EPUB, MOBI/KF8, FB2, CBZ, PDF via pdf.js; paginator, CFI, search, TTS/SSML | **MIT** | **Reusable freely.** A fallback or second EPUB engine in a WebView. |
| **Foliate** ★8.9k, 3.3.0 (2025-04) | GJS + GTK4 + WebKitGTK + foliate-js | GPL-3.0 | UX reference for Linux only. |
| **Anx Reader** (Anxcye) ★9.2k, v1.14.0 (2026-03) | **Flutter** + foliate-js in a forked `flutter_inappwebview`; `webview_cef` on desktop | **MIT** (since 1.2.6; GPL for 1.1.4–1.2.6) | The closest precedent for our stack. MIT means reusable, but check that copied code comes from MIT-era files. |
| **KOReader** ★31k, v2026.07.1 | Lua/LuaJIT UI over koreader-base (C/C++): **crengine** (EPUB, FB2, …), **MuPDF**, DjVuLibre | **AGPL-3.0** (crengine: "GPL version 2") | Gold standard for typography, hyphenation, e-ink and dictionaries. A native page-raster model like ours. Check crengine for "or later" before combining it with (A)GPLv3. |
| **Librera** ★5.0k, 10.0.31 (2026-11-09) | Android Java + MuPDF 1.28.5 (AGPL) + DjVuLibre (GPL-2+) + antiword | GPL-3.0-or-later | Proof that MuPDF can cover almost every format on Android. |
| **Koodo Reader** ★28.8k, v2.4.7 | Electron 35 + React 19; web version; Android and iOS apps (mobile stack unverified) | AGPL-3.0 | UX and sync reference. |
| **Thorium Reader** ★2.9k, v3.5.1 | Electron + Readium TS + pdf.js fork; `@readium/speech` | **BSD-3** | Accessibility-first. Readium Kotlin 3.4.0 and Swift 3.11.1 toolkits are BSD-3 and reusable (WebView EPUB). |
| **Mihon** ★25.2k, v0.21.3 | Kotlin + Jetpack Compose | Apache-2.0 | Reference for the manga reader UX: pager and webtoon viewers, tiling of huge images. Reusable. |
| Others | MuPDF (AGPL or commercial), PDFium via bblanchon/pdfium-binaries (BSD/Apache) and `pdfium-render`, **hayro** (pure-Rust PDF, Apache-2.0, v0.9.0, immature), libmobi (LGPL-3), YACReader (GPL-3, comics), SumatraPDF (GPL-3), Compose `pagecurl` (Apache-2.0) | — | Pick permissive PDFium over MuPDF if we want to stay out of AGPL. |

Licence consequences:

- **Copying from Readest or KOReader, or linking MuPDF, makes the whole app AGPL-3.0.** That is fine for a public
  project, but forks, server features and commercial use inherit it.
- **The Apple App Store vs (A)GPL is contested.** FSF's position is that App Store terms add restrictions. Readest can
  ship there because it owns its copyright. We would not own MuPDF's or KOReader's.
- **Permissive building blocks:** foliate-js (MIT), Readium (BSD-3), PDFium (BSD/Apache), pdf.js (Apache-2.0),
  Mihon (Apache-2.0), Anx Reader (MIT), sherpa-onnx (Apache-2.0), ONNX Runtime (MIT).
- **CBR:** unrar is non-free; use libarchive or another RAR reader with a free licence (verify RAR5 support).

## 5. Risks

1. **The page pipeline (the biggest technical risk).** "Core renders pages to textures" gives perfect curls and one
   path for every format. In exchange, selection, highlights, TTS sentence highlighting, links and *screen-reader
   access to book text* all have to be rebuilt from core-provided geometry. Reflowable EPUB fidelity then depends on
   the engine chosen: MuPDF has limited CSS; crengine is good but GPL-2; vertical CJK and ruby are weak in both. The
   alternative, foliate-js in a WebView with snapshots for the curl, has the best CSS but per-platform WebView pain,
   especially Flutter on desktop.
2. **Flutter limits.**
   - Fragment shaders only (no vertex stage, no UBOs); `flutter_gpu` is still preview.
   - Impeller on desktop only became the default in 3.47, so expect rough edges.
   - Locale-independent case mapping.
   - The bridge's bus factor: flutter_rust_bridge is about 95% one maintainer (fzyzcjy, 21k of about 22k commits).
     Mitigation: keep a plain C ABI under the generated bindings.
3. **Rune, if adopted early:** pre-release churn, no mobile, and two UI codebases.
4. **iOS:** no sanctioned volume-key page turns; background ML only through `BGProcessingTask` scheduling.
5. **Android:**
   - FGS type rules and battery limits; thermal throttling during ONNX jobs.
   - NNAPI is deprecated (unverified scope), so use the XNNPACK, QNN or GPU execution providers.
   - 16 KB page size is required for native libraries on new Play uploads, so every `.so` (Rust, ONNX Runtime,
     MuPDF) must be built with 16 KB alignment (unverified as a hard date).
6. **App size:** ONNX Runtime, sherpa-onnx and MuPDF add tens of MB per ABI. Ship per-ABI splits or an App Bundle,
   and download models on demand.
7. **Licensing:** using AGPL code decides the project's licence and complicates the App Store (section 4).

## 6. Sources

Rune and siblings:
- https://github.com/anomalyco/rune (README, `crates/rune/README.md`, PLAN.md, WEB.md, AGENTS.md, CHANGELOG.md,
  `changelog/unreleased/2026-10-30-ios-embed.md`, `2026-10-31-metal-ios.md`, `crates/rune-fx`, `crates/rune-light`,
  `crates/rune-motion`; read at dev `7ed827a2`, 2026-11-10)
- https://github.com/anomalyco/rune/issues/267 (roadmap proposal), /issues/110 (iOS/Android a11y), /issues/244
  (RTL base direction), /issues/165 (Safari keyboard)
- https://entrpi.github.io/misc/rune-review/ (outside review, rev 1571ad5, 2026-11-07)
- https://github.com/anomalyco/hokum, https://github.com/anomalyco/clip

Frameworks:
- https://docs.flutter.dev/perf/impeller (per-platform Impeller status, 3.47)
- https://docs.flutter.dev/ui/design/graphics/fragment-shaders (shader limits)
- https://flutter.dev/blog/flutter-darts-2026-roadmap (2026-02-24)
- https://storage.googleapis.com/flutter_infra_release/releases/releases_macos.json (3.47.9 stable, 2026-10-29)
- https://flutter.googlesource.com/mirrors/flutter/+/HEAD/docs/engine/impeller/Flutter-GPU.md (preview status)
- https://pub.dev/packages/flutter_page_curl, https://github.com/Rahiche/riveo_page_curl
- https://pub.dev/packages/vol_spotter, https://github.com/fluttercommunity/flutter_workmanager (v0.10.10)
- https://github.com/fzyzcjy/flutter_rust_bridge (v2.13.0, 2026-08-23)
- https://kotlinlang.org/docs/multiplatform/supported-platforms.html
- https://kotlinlang.org/docs/multiplatform/whats-new-compose-112.html
- https://github.com/JetBrains/compose-multiplatform (v1.12.2)
- https://chrisbanes.github.io/haze/latest/api/haze-utils/dev.chrisbanes.haze/-platform-runtime-effect/index.html
  (AGSL/Skiko split)
- https://klibs.io/project/Debanshu777/ShaderX (AGSL API 33+)
- https://github.com/mozilla/uniffi-rs (0.32.2), https://github.com/gobley/gobley (0.3.7)
- https://github.com/tauri-apps/tauri (2.12.5; 3.0.0-alpha.6)
- https://github.com/DioxusLabs/dioxus (0.7.10), https://dioxuslabs.com/learn/0.7/beyond/project_structure,
  https://github.com/DioxusLabs/blitz
- https://github.com/slint-ui/slint (1.18.1; `docs/astro/.../platforms/mobile/{android,ios}.mdx`;
  `examples/wgpu_texture`)
- https://github.com/react/react-native (0.88.1), https://github.com/microsoft/react-native-windows (0.85),
  https://github.com/microsoft/react-native-macos (0.83),
  https://docs.expo.dev/versions/unversioned/sdk/skia.md, https://github.com/jhugman/uniffi-bindgen-react-native
- https://docs.avaloniaui.net/docs/supported-platforms, https://avaloniaui.net/blog/avalonia-12,
  https://github.com/dotnet/maui
- https://github.com/k2-fsa/sherpa-onnx (v2.0.1; Dart, Kotlin, Swift, Rust, C APIs)
- https://github.com/microsoft/onnxruntime (v1.31.1)
- https://github.com/pykeio/ort (2.0.0-rc.15; `docs/core/platform.tsx`: binaries for Android arm64/x64 and iOS
  arm64)

Readers and libraries:
- https://github.com/readest/readest, https://readest.com/compare/readest-vs-foliate
- https://github.com/johnfactotum/foliate-js, https://github.com/johnfactotum/foliate
- https://github.com/Anxcye/anx-reader
- https://github.com/koreader/koreader, https://github.com/koreader/crengine
- https://github.com/foobnix/LibreraReader
- https://github.com/koodo-reader/koodo-reader
- https://github.com/edrlab/thorium-reader, https://github.com/readium/kotlin-toolkit,
  https://github.com/readium/swift-toolkit, https://github.com/readium/ts-toolkit
- https://github.com/mihonapp/mihon
- https://github.com/ArtifexSoftware/mupdf, https://github.com/bblanchon/pdfium-binaries,
  https://github.com/ajrcarey/pdfium-render, https://github.com/LaurenzV/hayro
- https://github.com/bfabiszewski/libmobi, https://github.com/oleksandrbalan/pagecurl
