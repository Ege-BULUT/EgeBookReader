# Requirements

Structured reading of `brief-original.md` (the user's words, which win on any disagreement).
Each requirement has an id so tasks, commits and decisions can point at it. "Must" = asked for
explicitly; "Should" = implied by the brief; "Nice" = suggested as optional.

## R0 Project

| id | requirement | level |
|-|-|-|
| R0.1 | Name: **EgeBookReader**, in `~/projects/EgeBookReader` | Must |
| R0.2 | Public GitHub repo under `Ege-BULUT` (ask before the first push, per the global remote-action rule) | Must |
| R0.3 | When finished, a site at `egebookreader.vercel.app` (ask before deploying) | Must |
| R0.4 | Talk with the user over OpenCommunicate (see `process.md`) | Must |
| R0.5 | Project tracking with OpenLead (`openlead/` workspace), kept in sync with this knowledge base | Should |
| R0.6 | Priority: **Android app first**; then iOS, Windows, macOS, Linux | Must |

## R1 Platforms and formats

| id | requirement | level |
|-|-|-|
| R1.1 | Native apps: Android, iOS, Windows, macOS, Linux | Must |
| R1.2 | The user suggested `anomalyco/rune` (Rust native UI framework) for Windows/macOS/Linux; use it if it fits (see `research/stack.md`, `decisions.md`) | Nice |
| R1.3 | Open all common ebook formats, PDF and EPUB first (full list in `research/formats.md`) | Must |
| R1.4 | Portrait and landscape, responsive layouts (phone, tablet, desktop window sizes) | Must |
| R1.5 | Single-page and two-page (spread) display | Must (stated under R3.2) |

## R2 UX and look

| id | requirement | level |
|-|-|-|
| R2.1 | User-friendly UX/UI is the first priority | Must |
| R2.2 | Modern, innovative, sleek design with plenty of motion design and interaction animation | Must |
| R2.3 | Study popular design skills (taste-skill, "unslop") and apply what fits (`research/fonts-design.md`) | Should |
| R2.4 | Motion must never get in the way of reading: honour reduced-motion, no jank (60/120 fps) | Should |

## R3 Themes

Every theme exists in a **light and a dark** variant.

| id | requirement | level |
|-|-|-|
| R3.1 | OLED mode | Must |
| R3.2 | E-ink mode | Must |
| R3.3 | Paper mode | Must |
| R3.4 | Parchment mode | Must |
| R3.5 | Custom mode: custom background image, colour, or background + colour overlay with transparency | Must |
| R3.6 | Background brightness slider | Must |
| R3.7 | Background blur slider | Must |

## R4 Page turning

| id | requirement | level |
|-|-|-|
| R4.1 | **Click mode**: user-placed tap zones on a phone-screen canvas, rectangular or circular, each bound to an action (previous page, next page, show/hide menu, …) | Must |
| R4.2 | **Flip mode (default)**: real, procedural page-turn animation that follows where the finger holds the page; flawless in single-page and two-page modes | Must |
| R4.3 | **Vertical endless scroll** mode; setting for the gap between pages, default 2px | Must |
| R4.4 | Toggle (all modes): volume buttons turn pages | Must |
| R4.5 | Toggle (all modes): invert previous/next for the volume buttons | Must |

## R5 Reflow

| id | requirement | level |
|-|-|-|
| R5.1 | Reflow mode on/off (including for PDF, where it means extracting text into a reflowable layout) | Must |

## R6 Typography

| id | requirement | level |
|-|-|-|
| R6.1 | Many theme/typography customizations | Must |
| R6.2 | Font browser with previews from popular free online font providers; download fonts in-app | Must |
| R6.3 | Add custom fonts from a file or a URL | Must |
| R6.4 | Text colour, bold, italic and similar choices | Must |
| R6.5 | No problems with Chinese, Hindi, Turkish, German, French, Filipino, Russian and similar (CJK, Devanagari, Cyrillic, Latin-extended; RTL is a reasonable extension) | Must |
| R6.6 | Special-character support (the brief marks this optional) | Nice |

## R7 Images

| id | requirement | level |
|-|-|-|
| R7.1 | Post-processing filters for images in books, only useful ones | Must |
| R7.2 | Fast, quality upscale that does not damage the image | Must |
| R7.3 | Saturation boost | Must |
| R7.4 | On-device colorization of B&W images (manga panels and others), via an optional model download | Must if feasible |
| R7.5 | Colorize on demand: a small icon on an image colorizes that one image | Must (with R7.4) |
| R7.6 | Colorized images are saved automatically to the app's image gallery | Must (with R7.4) |
| R7.7 | Auto colorize: on a book's first open, colorize the images of at least N pages (setting, default 3); first open may take a little longer; later opens need no wait | Must (with R7.4) |
| R7.8 | Auto colorize continues in the background, one image after another, without heating the phone or making the app stutter | Must (with R7.4) |
| R7.9 | A colorized image shows at exactly the same position and size as the original; it must never hurt the reading experience | Must |
| R7.10 | Works offline; an API-key solution only if offline is impossible | Must / fallback |

## R8 Read aloud (TTS)

| id | requirement | level |
|-|-|-|
| R8.1 | Read the book aloud, toggle on/off | Must |
| R8.2 | Default engine: the system TTS | Must |
| R8.3 | Optional downloadable on-device TTS models; a few options | Must |
| R8.4 | Each model's details list its supported languages and its official source URL | Must |
| R8.5 | Bring-your-own API key for a cloud TTS | Must |
| R8.6 | Pick the voice source from downloaded models or the API | Must |
| R8.7 | Survey current tiny, high-quality multilingual models (`research/tts.md`) | Must |

## R9 Actual book mode

| id | requirement | level |
|-|-|-|
| R9.1 | "Actual book mode" toggle that turns on all Okuma-Reader filters at once | Must |
| R9.2 | Paper texture: grain whose amount and type depend on the book type | Must |
| R9.3 | Book fold: a self-shadowed area in the middle of the book | Must |
| R9.4 | Realistic lighting: specularity on the paper | Must |
| R9.5 | Side pages: the previous/next pages visible at the sides, matching the reading position | Must |
| R9.6 | Book shadow: shadow at the bottom and side, as if the book lies on a surface | Must |

## Implied (Should)

- Library screen: import, covers, progress, recent books; reading position saved per book.
- TOC, bookmarks, search in book.
- Settings per book vs. global defaults (e.g. Okuma book type, reflow, page-turn mode).
- No DRM breaking: DRM-protected files get a clear message.
