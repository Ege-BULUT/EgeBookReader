# Open questions

What still needs the user's call. Each has a recommendation; once answered it moves to `decisions.md`.

## Q1 App license: permissive or AGPL/GPL?

Several of the best components are copyleft: MuPDF (AGPL, the strongest PDF reflow), piper-phonemize (GPL-3.0, the
text front end for Piper-style voices), DjVuLibre (GPL-2.0+). The UnRAR license is incompatible with GPL/AGPL.
AGPL/GPL is fine on Google Play, F-Droid and desktop, but risky on the iOS App Store.

**Recommendation:** AGPL-3.0 for the app, with Apple PDFKit (not MuPDF) on iOS and libarchive's RAR support instead of
UnRAR. Details: `research/formats.md` §1.1, `research/tts.md` §0.1.

## Q2 Engine for reflowable text (EPUB and friends)

`research/formats.md` recommends the platform browser engine with foliate-js, because only browser engines do vertical
CJK, ruby and full CSS. `research/stack.md` wants every page as an image so the curl is the same for every format. A
WebView page must be captured to an image before it can curl, which is slow and awkward. The proof of concept uses
Flutter text layout (good shaping incl. Devanagari and RTL; no vertical writing, limited CSS).

**Recommendation:** judge the proof of concept, then choose between (a) Flutter layout with a richer CSS subset,
(b) hidden WebView capture, or (c) a native engine.

## Q3 Rune on desktop

Later, only if it gains Android or the user accepts a second UI codebase. **Recommendation:** Flutter desktop first.

## Q4 Colorizer quality on manga

DDColor-tiny is the only lightweight colorizer whose code and weights are clearly redistributable, but it was trained
on photos, and a good result on manga is not proven. Needs a test on real manga pages before committing.
Details: `research/image-ai.md`.

## Q5 Design details (`research/fonts-design.md` §7)

- "OLED light": plain white page with true-black chrome (**recommended**), or a brighter OLED-dark.
- UI font: platform font with fallback (**recommended**, best script coverage) or one chosen family.
- Fontshare in v1: later (**recommended**; its license terms need a human read).
- Fonts through Google directly or a privacy mirror: Fontsource/Bunny by default (**recommended**).
