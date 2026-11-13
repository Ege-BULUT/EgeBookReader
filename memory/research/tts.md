# TTS research for EgeBookReader

Researched 2026-11-10. Sources are listed at the end. Model cards, GitHub repos and the sherpa-onnx release
list were checked directly through the Hugging Face and GitHub APIs. Anything marked **unverified** came only
from third-party pages or from memory and should be checked before we depend on it. All quality figures for
Turkish are self-reported by the people who built competing models. They broadly agree with each other, but no
independent listening test exists.

---

## 0. Recommendation

### 0.1 The one runtime: sherpa-onnx 2.x (Apache-2.0)

- `k2-fsa/sherpa-onnx` v2.0.1 (2026-10-26). It ships ONNX Runtime inside and has bindings for Kotlin/Java,
  Swift, C/C++, Dart/Flutter (`sherpa_onnx` 2.0.1 on pub.dev), Rust (crate 2.0.1), JS (node-addon and
  WASM, npm 2.0.1), C#, Go and Python. It runs on Android, iOS, Windows, macOS, Linux, HarmonyOS and the
  web (WASM).
- With one integration it runs Supertonic 3, Kokoro, KittenTTS, Piper/VITS, MMS, Matcha, MeloTTS (VITS),
  Pocket TTS, ZipVoice and Kokoro-architecture fine-tunes such as Nabra (Arabic). No other runtime covers
  as many of the small TTS families.
- **Breaking change in 2.0.0 (2026-10-20/23): espeak-ng and piper-phonemize were removed** so that
  sherpa-onnx is free of GPL code (PR #4055, issue #3731). Text front ends are now:
  1. character or token based models, which need no G2P: Supertonic 3, MMS, Pocket TTS, Antalia/Ahenk-style
     Turkish models;
  2. a built-in `lexicon.txt`, which works for English and Chinese (Kokoro, Kitten, Matcha). **Words that
     are not in the lexicon are skipped** (issue #4075 comments). An English number/symbol FST is in
     progress (#4144);
  3. external phonemes passed in through `phoneme_codepoints`/`tokens`, for example from
     `csukuangfj/piper-phonemize` (**GPL-3.0**, v1.5.9 2026-10-20, with Android/iOS/Flutter/WASM/Rust/Swift
     builds).
- **Decision we need to make: the app's license.** If EgeBookReader is GPL-3.0, we can ship the
  piper-phonemize add-on. That unlocks Piper in about 58 locales, Kokoro's ja/es/fr/hi/it/pt voices and
  full-G2P Kitten. If the app is MIT or Apache, we stay with the GPL-free models: Supertonic 3, Kokoro en/zh,
  MMS, Pocket and the Turkish character-based models. The shortlist below works either way.
- No word timestamps: issue #3727, maintainer: "no plans". `GenerateWithCallback` streams audio as each
  sentence chunk is ready. For on-device voices we highlight the sentence and estimate word timing by
  character share.

### 0.2 Shortlist for the in-app catalog (6 entries)

| # | Catalog entry | Why | Download | Languages from our list |
|---|---|---|---|---|
| 1 | **Supertonic 3 (int8)**, default multilingual neural voice | 99M params, 31 languages **including Turkish**, 10 preset voices, character-based (no espeak, no GPL), 44.1 kHz | 122 MB | tr en hi de fr ru ja es ar (not zh, not fil) |
| 2 | **Kokoro-82M v1.1 (int8)**, best English and Chinese | Best-known small-model quality, Apache-2.0, 103 voices (zh+en) | 140 MB | en zh (v1.0 adds ja es fr hi it pt-BR only with the GPL phonemizer) |
| 3 | **Antalia-2 Mini (Turkish, int8 ONNX)**, tiny Turkish specialist | 7.6M params, Apache-2.0, about 10 MB int8, Turkish WER about 1% in published benchmarks (Piper dfki is about 3.3%), RTF 0.024 on 2 laptop threads. Single male synthetic voice. Pair it with **Ahenk Cep** (8.6M, CC BY 4.0, female synthetic voice, ONNX) so Turkish has a female voice too | ~10 MB (+~12 MB Ahenk Cep int8) | tr |
| 4 | **KittenTTS nano v0.8 (int8)**, tiny English for low-end phones | 15M params, 8 voices, Apache-2.0, RTF 0.39 on a 2019 Galaxy S10 (v0.2) | 29 MB | en |
| 5 | **Piper voices (int8), one per locale**, tiny tier | About 20 MB each, fastest (RTF 0.08 on the S10), 180 voices in about 58 locales. **Needs the GPL phonemizer under sherpa 2.x.** Each voice has its own license. Turkish `dfki` is **non-commercial** (CC BY-NC-SA dataset) | 20 MB/voice | en zh hi de fr ru ja es ar (tr is NC only, no fil) |
| 6 | **MMS-TTS (Meta VITS), one per language**, long-tail fallback | 1,100+ languages including **Filipino (tgl)** and Turkish, character-based so it works in sherpa 2.x. **CC BY-NC 4.0 (non-commercial)**, so mark it with a badge and leave it off by default. Mediocre quality (Turkish WER 6.4%) | ~100 MB/lang | everything, including fil |

Turkish in short: Supertonic 3 is the ready-made sherpa-onnx route. Antalia-2 Mini and Ahenk Cep sound
more accurate in Turkish and are about 10 times smaller, but they need a small custom ONNX Runtime path plus
a port of their Turkish text normaliser (JS exists). Plan them as phase 2, or contribute them to sherpa-onnx
as a new model type. Nothing small speaks Filipino under a permissive license. For Filipino use system TTS
(Google TTS has fil-PH), MMS (NC) or cloud.

Not shortlisted, and why: Chatterbox Multilingual (good Turkish, but about 1.5 GB and slower than real time
even on an L4 GPU), KittenTTS 2 (1.7B, restrictive Stellon license), OmniVoice/VoxCPM2/Qwen3-TTS (0.6–2B,
GPU class), MOSS-TTS-Nano (about 0.76 GB ONNX, voice-cloning focus, not in sherpa yet), Phonon multilingual
(CC BY-NC), Pocket TTS (English-only in sherpa so far; worth adding later for English voice cloning).

### 0.3 Other recommendations

- **Benchmark on the user's device at install time.** Synthesize 5 s of audio, show "x times real time on your
  phone" and warn when RTF > 0.8. Kokoro is slower than real time on 2019-era phones (S10 RTF 1.13, and int8
  is slower still at 2.42).
- **Mirror the files ourselves.** Point `downloadUrl` at our own GitHub release with sha256 checksums. Supertonic
  upstream is archived, and sherpa-onnx still hosts voices that their authors withdrew (Piper `fahrettin` and
  `fettah`, see section 1).
- **Cloud: one "OpenAI-compatible /v1/audio/speech" adapter** (base URL + key + model + voice) covers many
  providers and local servers. Add native adapters for **Gemini TTS** (free tier, 130+ languages, tr and fil),
  **Azure** (tr-TR, fil-PH, word boundaries, 0.5M characters free each month) and **ElevenLabs** (top quality,
  character timestamps). **Do not build on OpenAI's tts-1/gpt-4o-mini-tts: they shut down on 2027-01-06.**

### 0.4 Proposed catalog entry shape

```json
{
  "id": "supertonic-3-int8",
  "name": "Supertonic 3",
  "version": "2026-05-11",
  "sizeMB": 122,
  "installedSizeMB": 160,
  "languages": ["ar","bg","cs","da","de","el","en","es","et","fi","fr","hi","hr","hu","id","it","ja","ko","lt","lv","nl","pl","pt","ro","ru","sk","sl","sv","tr","uk","vi"],
  "voices": [{ "id": "F1", "sid": 0, "gender": "female" }, { "id": "M1", "sid": 5, "gender": "male" }],
  "license": {
    "weights": "OpenRAIL-M", "code": "MIT",
    "commercialUse": true, "attributionRequired": true,
    "restrictions": "use-based restrictions (Attachment A) must be passed on to users",
    "url": "https://huggingface.co/supertone-oss-archive/supertonic-3/blob/main/LICENSE"
  },
  "sourceUrl": "https://github.com/supertone-oss-archive/supertonic",
  "downloadUrl": "https://github.com/<our-org>/egebookreader-models/releases/download/v1/sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2",
  "sha256": "<fill>",
  "runtime": "sherpa-onnx",
  "modelType": "supertonic",
  "minRuntimeVersion": "2.0.0",
  "frontend": "none",
  "sampleRate": 44100,
  "tier": "multilingual",
  "notes": "Upstream archived 2026-09; quality for Turkish not independently tested."
}
```

`frontend` is one of `none | lexicon | phonemizer-gpl`. Hide `phonemizer-gpl` entries unless the GPL add-on
is installed. `modelType` is one of `supertonic | kokoro | vits | kitten | matcha | pocket | zipvoice |
onnx-custom:<name>`. For the sherpa `sid` of each voice, check its order in the model's `voice.bin`; the `sid`
values in the example are placeholders.

---

## Model table

Sizes are download sizes (sherpa-onnx `.tar.bz2` where one exists; otherwise the upstream files). "Turkish?"
means the model has a Turkish voice and the developers or a benchmark claim it is usable.

| Model | Size | Languages | Turkish? | License (code / weights) | Runtime | Official URL |
|---|---|---|---|---|---|---|
| **Supertonic 3** (2026-04-29) | 122 MB int8 (sherpa); ~400 MB fp32 ONNX | 31: ar bg cs da de el en es et fi fr hi hr hu id it ja ko lt lv nl pl pt ro ru sk sl sv tr uk vi | **Yes** (quality not independently tested) | MIT / OpenRAIL-M | sherpa-onnx, ONNX Runtime (incl. Web/WebGPU), MLX | github.com/supertone-oss-archive/supertonic |
| Supertonic 2 (2026-01-06) | 80 MB int8 (sherpa, 2026-03-06; inferred) | en ko es pt fr | No | MIT / OpenRAIL-M | sherpa-onnx, ORT | huggingface.co/supertone-oss-archive/supertonic-2 |
| **Kokoro-82M** v1.0 / v1.1-zh | 126 / 140 MB int8; 333 / 347 MB fp32 (sherpa); 92 MB q8 (onnx-community) | v1.0: en-US en-GB ja zh es fr hi it pt-BR (54 voices); v1.1: zh+en (103 voices) | No | Apache-2.0 / Apache-2.0 | sherpa-onnx (only en/zh without GPL phonemizer), ORT, kokoro-js, MLX | huggingface.co/hexgrad/Kokoro-82M |
| **KittenTTS v0.8** nano / micro / mini (2026-02-19) | 29 MB int8 nano; 42 / 64 MB (sherpa) | en (8 voices) | No | Apache-2.0 | sherpa-onnx, ORT | github.com/KittenML/KittenTTS |
| KittenTTS 2 (2026-09-30) | 1.7B; 954 MB ternary LM + ~0.5 GB decoder (39 MB w4 student) | 16 via voices, incl. tr, zh, hi, ja, ru, ar (115 voices) | Yes (voice "Turkish…") | Stellon Labs Community License (revenue/funding cap $1M, registration, "Powered by KittenML") | PyTorch, llama.cpp fork (GGUF) | huggingface.co/KittenML/kitten-tts-2 |
| **Piper** (piper1-gpl v1.8.0, 2026-09-04) | 20 MB int8 / 34 MB fp16 / 64 MB fp32 per voice (sherpa) | 180 voices, ~58 locales (no fil; ja 1 voice) | dfki-medium only, **NC** | GPL-3.0 (piper1-gpl) / per-voice dataset licenses | sherpa-onnx (+GPL phonemizer in 2.x), piper1-gpl, ORT | github.com/OHF-Voice/piper1-gpl, huggingface.co/rhasspy/piper-voices |
| Matcha-TTS (icefall) | 71–75 MB | en (LJSpeech), zh (Baker), zh+en, fa+en | No | MIT / dataset-dependent | sherpa-onnx | github.com/shivammehta25/Matcha-TTS |
| MeloTTS | 155–159 MB (sherpa en, zh_en) | en (US/GB/IN/AU), es, fr, zh(+en), ja, ko | No | MIT / MIT | sherpa-onnx (VITS) | github.com/myshell-ai/MeloTTS |
| **MMS-TTS** (Meta, 2023) | ~100–145 MB per language | 1,100+ (incl. tur, tgl) | Yes (WER ~6.4%) | CC BY-NC 4.0 | sherpa-onnx (VITS), transformers | huggingface.co/facebook/mms-tts |
| Pocket TTS (Kyutai) | 93 MB int8 / 160 MB (sherpa, English); 24-layer fr/de/pt/it/es ~670 MB safetensors | official: en fr de pt it es (26 voices, cloning) | No | code n/a / CC BY 4.0 (gated, accept terms) | PyTorch, sherpa-onnx (en), community ONNX/LiteRT/MLX/Rust | huggingface.co/kyutai/pocket-tts |
| Kyutai TTS 1.6B | ~4 GB | en fr | No | MIT/Apache code / CC BY 4.0 | PyTorch/Rust, GPU | huggingface.co/kyutai/tts-1.6b-en_fr |
| NeuTTS Air / Nano / 2e | Air q4 GGUF 527 MB; Nano q4 195 MB; 2e q4 301 MB | en; Nano also de / fr / es variants (2026-02) | No | Air Apache-2.0; Nano/2e "NeuTTS" custom license (unverified terms) | llama.cpp GGUF + NeuCodec ONNX | huggingface.co/neuphonic |
| Chatterbox Multilingual (v3 2026-06) | ~2–5 GB; community ONNX q4 ≈ 1.5 GB total | 23: ar da de el en es fi fr he hi it ja ko ms nl no pl pt ru sv sw tr zh | **Yes** (WER 1.8–1.9%) | MIT / MIT | PyTorch, ONNX (onnx-community) | github.com/resemble-ai/chatterbox |
| Chatterbox Turbo (2025-12) / Nano (2026-04) | Turbo 350M; Nano 110M (~0.9 GB T3 + 1 GB S3Gen) | en | No | MIT | PyTorch, community ONNX | huggingface.co/ResembleAI/chatterbox-nano |
| VibeVoice Realtime-0.5B / 1.5B | 2.0 GB / 5.4 GB | 0.5B: en; 1.5B: en zh | No | MIT | PyTorch, GPU | github.com/microsoft/VibeVoice |
| Orpheus 3B (+ multilingual research) | ~6–15 GB; GGUF smaller | en; research models in 7 more languages (fr de ko hi zh es it, unverified list) | No | Apache-2.0 + Llama 3.2 terms | llama.cpp/vLLM + SNAC | github.com/canopyai/Orpheus-TTS |
| Spark-TTS 0.5B | ~3.9 GB | en zh | No | Apache code / **CC BY-NC-SA 4.0** | PyTorch | github.com/SparkAudio/Spark-TTS |
| F5-TTS v1 | ~1.35 GB | en zh | No (WER 78%) | MIT / **CC BY-NC 4.0** | PyTorch, GPU | github.com/SWivid/F5-TTS |
| Zonos v0.1 | 1.6B, 3.2 GB | en ja zh fr de | No | Apache-2.0 | PyTorch, GPU | github.com/Zyphra/Zonos |
| Dia 1.6B / Dia2 1B-2B | 6.4 GB / 4.3 GB | en | No | Apache-2.0 | PyTorch, GPU | github.com/nari-labs/dia |
| Qwen3-TTS 0.6B / 1.7B (2026-01-22) | ~2.5 GB (0.6B) | zh en ja ko de fr ru pt es it | No | Apache-2.0 | PyTorch, GPU | huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base |
| OmniVoice 0.6B (2026-03-31) | ~3.3 GB fp32 | 600+ (incl. tr, fil, hi, ar…) | Yes (claimed) | Apache-2.0 (GitHub; HF card has no license field) | PyTorch; community WebGPU ONNX; sherpa request #3651 open | github.com/k2-fsa/OmniVoice |
| VoxCPM2 (2026-04) | 2B, ~5 GB | 30 incl. tr, tl, zh, hi, ar, ru, ja | Yes (base for Trendyol-TTS/Ahenk) | Apache-2.0 | PyTorch, GPU | huggingface.co/openbmb/VoxCPM2 |
| MOSS-TTS-Nano (2026-04-10) | ~100M; ONNX fp32 ≈ 673 MB + 91 MB codec | 20 listed: zh en de es fr ja it hu ko ru fa ar pl pt cs da sv el tr | Yes (claimed, no Turkish evaluation) | Apache-2.0 | ONNX Runtime CPU (Android ORT example), PyTorch, MLX | github.com/OpenMOSS/MOSS-TTS-Nano |
| Phonon (Gradium, 2026-10-20) | 31M en: 55 MB q4k / 65 MB q8 GGUF; 40M: 60–75 MB | 31m: en; 40m: en fr de es pt (multilingual, 102 voices) | No | 31m-en Apache-2.0; 40m models **CC BY-NC 4.0** | Gradium runtime (`xn-ptts`, Rust), npm `phonon-tts`, Python | huggingface.co/gradium/phonon-31m-en |
| Nabra-82M (Arabic MSA, 2026-07) | 78 MB int8 (sherpa) | ar (1 voice) | No | Apache-2.0 (Kokoro fine-tune) | sherpa-onnx (kokoro type) | huggingface.co/oddadmix/Nabra-82M-v0.1 |
| Inflect Nano/Micro v2 (2026-07) | 21 / 40 MB (sherpa) | en | No | **unverified** | sherpa-onnx (VITS) | huggingface.co/owensong/Inflect-Nano-v2 |
| ZipVoice (distill) | 104 MB int8 (sherpa) | zh en (voice cloning) | No | Apache-2.0 (unverified for weights) | sherpa-onnx | github.com/k2-fsa/ZipVoice |
| **Antalia-2 Mini** (2026-10-08) | 7.62M; ~10 MB int8 / ~15 MB fp16 / ~31 MB fp32 ONNX | tr (1 synthetic male voice) | **Yes** (WER ~1.0–1.1%) | Apache-2.0 / Apache-2.0 (CMUdict-derived data, BSD-style) | ONNX Runtime (Web demo), PyTorch | huggingface.co/cloud0day3/antalia-mini |
| **Ahenk Cep** (2026-10-16) | 8.6M; ONNX fp32/fp16/int8 (~34 MB fp32) | tr (1 synthetic female voice) | **Yes** (TR-Zor WER 2.3%) | Apache-2.0 / **CC BY 4.0** | ONNX Runtime (browser demo), PyTorch | github.com/ozguradmin/ahenk-turkish-tts |
| EMA Lightning (2026-10-01) | 8.6M; 34 MB (PyTorch only) | tr (1 synthetic voice) | **Yes** (WER ~0.9–1.0%) | Apache-2.0 | PyTorch (no ONNX published) | huggingface.co/canberkkkkkk/ema-lightning |
| FreyaTTS-small (2026-07) | 183M; 733 MB | tr | Yes (self-reported WER 8%; others measured 12%) | Apache-2.0 | PyTorch | github.com/freyavoiceai/FreyaTTS |
| Trendyol-TTS (2026-06) | 2.38B; ~5 GB | tr | Yes (best naturalness, UTMOS 3.8) | MIT (VoxCPM2 + LoRA) | PyTorch, GPU | huggingface.co/Trendyol/Trendyol-TTS |
| Anka TTS (2026-09) | 336M; 1.35 GB | tr | Yes (WER 1.4–1.7%) | **CC BY-NC 4.0** | PyTorch | huggingface.co/krmkayabasi/Anka-TTS |
| XTTS-v2 (Coqui, legacy) | ~1.9 GB | 17 incl. tr | Yes (WER 3.3–3.7%) | **CPML (non-commercial)**, company closed in 2024 | PyTorch | huggingface.co/coqui/XTTS-v2 |

---

## 1. On-device models in detail

### Mobile speed data that exists

VoicePing benchmark, 2026-02-15, sherpa-onnx, English prompts:

| Device | Model | Median RTF (lower is faster; < 1 is faster than real time) |
|---|---|---|
| Galaxy S10 (Exynos 9820, 4 threads) | Android system TTS | 0.058 |
| | Piper ryan-low / amy-low | 0.077 / 0.076 |
| | Matcha LJSpeech + HiFiGAN | 0.135 |
| | Kitten nano v0.2 fp16 | 0.387 |
| | Kokoro en v0.19 (fp32) | 1.133 |
| | Kokoro int8 multi-lang v1.1 | 2.423 |
| iPad Pro 3rd gen (A12X) | Matcha + Vocos | 0.084 |
| | Kitten nano v0.2 | 0.368 |
| | Kokoro en v0.19 | 0.621 |
| | Kokoro int8 v1.0 / v1.1 | 1.82 / 1.57 |

- int8 Kokoro is *slower* than fp32 on these ARM CPUs, so do not assume int8 means faster. Its only
  advantage is the smaller download.
- Phones from 2024–2026 are probably 2–3 times faster than the S10 (**unverified estimate**). A Reddit report
  says Kokoro ran at 2.8x real time on a Snapdragon 8 Elite (**unverified**).
- Nobody has published phone RTF for Supertonic 3. Desktop figures: about 4.2x real time on an M4 CPU (Yaps,
  third-party) and RTF 0.2 on a 16-thread CPU (Supertonic page, via a search summary, **unverified**). Its
  "4 ONNX graphs" make the cold start slower (community comment).
- sherpa-onnx's own RTF table is for a Raspberry Pi 4 only. Kokoro there: RTF about 3 on 4 threads. Piper:
  about 0.35.

### Model notes

- **Supertonic 3**: 99M params, released 2026-04-29, 31 languages, `lang="na"` handles text in an unknown
  language, 10 inline expression tags, 44.1 kHz, 10 preset voice styles (F1–F5, M1–M5). No voice cloning in
  the open release. The upstream repo is **archived** ("development and support have ended") and has moved
  to `supertone-oss-archive` on GitHub and HF (archived 2026-09). Mirror READMEs say Supertone Inc. decided to
  dissolve on 2026-07-15 and ended its services on 2026-08-31 (**unverified**; supertone.ai now redirects to
  antinodeaudio.com). sherpa-onnx support: `sherpa-onnx-supertonic-3-tts-int8-2026-05-11`, PR #3605, and
  2.0.0 accepts the `na` language tag. Upstream code has examples for Python, Node, Browser (WebGPU), Java,
  C++, C#, Go, Swift, iOS, Rust and Flutter. OpenRAIL-M allows redistribution and commercial use, but the
  use-based restrictions must be passed on to users. **No public Turkish evaluation**, so we must run our own
  listening test against Antalia, Ahenk and Piper dfki.
- **Kokoro-82M**: v1.0 released 2025-01-27, Apache-2.0, StyleTTS2-based, 24 kHz. Voices per locale: en-US 20,
  en-GB 8, ja 5, zh 8, es 3, fr 1, hi 4, it 2, pt-BR 3. Known weaknesses: it struggles with very short
  utterances and rushes utterances over about 400 tokens, so chunk text into sentences. TTS Arena rating about
  1478 (retired, via Yaps). In sherpa-onnx 2.x only the en and zh lexicons ship, and other languages need the
  GPL phonemizer (issue #3731). Bug #4178: long sentences are cut at 400 phonemes. No streaming within a
  sentence.
- **KittenTTS v0.8**: models published 2026-02-19 (nano 15M, micro, mini), 8 English voices (Bella, Jasper,
  Luna, Bruno, Rosie, Hugo, Kiki, Leo), Apache-2.0. Multilingual support is on the roadmap. KittenTTS 2 is a
  different, large model with a restrictive license.
- **Piper**: `rhasspy/piper` was archived in 2025. The continuation is `OHF-Voice/piper1-gpl` (GPL-3.0,
  v1.8.0 on 2026-09-04, still active). There are 180 official voices. Each voice's license follows its
  dataset (see its MODEL_CARD). **Turkish:** the only official voice is `tr_TR-dfki-medium`, whose dataset is
  CC BY-NC-SA 4.0. The `fahrettin` and `fettah` voices were **removed from piper-voices on 2025-12-30 "at
  request of contributors"**, but sherpa-onnx still hosts copies. **Do not offer them.** Their names also
  match public figures on HF voice-clone repos, so their origin is doubtful. Piper is VITS, about 16M params,
  and works as a tiny tier where its license allows.
- **Matcha-TTS**: MIT code. The sherpa models are single speaker (LJSpeech en; Baker zh, whose dataset
  license is probably non-commercial, **unverified**). Very fast (RTF 0.08–0.14 on mobile). A useful
  fallback, but lower quality.
- **MeloTTS**: MIT. sherpa ships the en and zh_en models only. Slow on mobile (iPad int8 RTF 2.87).
  Superseded by Kokoro.
- **MMS-TTS**: VITS, about 36M params per language, 1,100+ languages, character input (no G2P), CC BY-NC 4.0.
  In a 2026 Turkish benchmark it reached WER 6.4% and sounded natural but read poorly. It is the only small
  model that speaks Filipino (tgl). willwade hosts ONNX exports of every language (CC BY-NC).
- **Pocket TTS (Kyutai)**: about 100M params (English), CPU-first, about 6x real time on 2 cores of an M4,
  about 200 ms to first audio, streaming, voice cloning from WAV, 26 voices, CC BY 4.0, gated (you must
  accept terms on HF). Official languages: en, fr, de, pt, it, es. Community models exist for cs, hi, ko, fa,
  id, et, cy and pl. sherpa-onnx has English only (2026-01-26 model). Issue #4148 (open) adds a script for
  multilingual models via `KevinAHM/pocket-tts-onnx`.
- **Chatterbox Multilingual**: MIT, 0.5B T3 LLM plus S3Gen flow decoder, 23 languages including Turkish
  (Turkish WER 1.8–1.9%, UTMOS about 3.5). Measured RTF 2.89 on an L4 GPU, so it is **far too slow for
  phones**. Turbo (350M) and Nano (110M, about 3x real time on 8 CPU cores per Resemble) are English only.
- **NeuTTS** (Neuphonic): Air has 748M params (Qwen 0.5B backbone) and is Apache-2.0. Nano (Nov 2025) and
  2e (Jul 2026) use a custom license (**unverified terms**). They run through llama.cpp GGUF plus the
  NeuCodec ONNX decoder. English, with Nano variants for de, fr and es. No Turkish.
- **VibeVoice, Orpheus, Spark-TTS, F5-TTS, Zonos, Dia, Kyutai TTS 1.6B, Qwen3-TTS, VoxCPM2, OmniVoice**: all
  0.5B–3B, built for GPUs, too heavy for phone CPUs today. Spark-TTS and F5-TTS weights are NC. Of these,
  OmniVoice (600+ languages, Apache-2.0) and VoxCPM2 (30 languages including tr and tl) are the ones to watch
  for a desktop or "high quality" tier. A community WebGPU ONNX of OmniVoice exists, and a sherpa-onnx port
  has been proposed (#3651).
- **MOSS-TTS-Nano** (OpenMOSS, Apache-2.0): 2026-04-10, ONNX CPU release on 2026-04-17, 48 kHz stereo,
  voice-cloning first (built-in voices in the ONNX version), Android ORT example. Not in sherpa yet (#3652).
  About 0.76 GB fp32 download, and no Turkish evaluation.
- **Phonon** (Gradium, 2026-10-20): very small (31–40M) and streams. Only the English 31M model is
  Apache-2.0. The multilingual model covers en, fr, de, es and pt but is NC. It uses its own runtime, so we
  would need a second integration.
- **New Turkish models (all from 2026)**:
  - **EMA Lightning** (Apache-2.0, 8.6M): best Turkish WER on Freya-TR-Eval (0.92%, against 1.43% for
    ElevenLabs v4 and 1.31% for Gemini 3.8 Flash-Lite as the authors measured them). UTMOS 3.30. CPU RTF
    0.166 on a cloud container. Ships PyTorch weights only.
  - **Antalia-2 Mini** (PatientDesk AI, Apache-2.0, 7.62M): WER 1.02–1.09%, UTMOS 3.18. ONNX int8 graphs
    (text, cond, flow, vocoder) total about 10 MB and run in its browser demo through ORT Web, with a JS text
    normaliser for numbers, dates, money and English words. RTF 0.024 on 2 threads of an M5. One synthetic
    male voice, trained without real speakers' recordings.
  - **Ahenk Cep** (CC BY 4.0 weights, Apache-2.0 code, 8.6M): one synthetic female voice. ONNX graphs (text,
    cond, step, decoder) in fp32, fp16 and int8. TR-Zor WER 2.32%. RTF about 0.2 on 2 threads; the author
    says it is "not yet distilled for phone speed". It ships `trnorm` (Python) and `trnorm-js`, Turkish
    normalisers under Apache-2.0.
  - Large models: **Trendyol-TTS** (VoxCPM2 + LoRA, MIT, best naturalness), **Ahenk** (VoxCPM2 LoRA,
    CC BY 4.0, 6 emotions), **FreyaTTS-small** (Apache-2.0, 183M; independent runs measured WER 12%) and
    **Anka TTS** (NC).
  - Known Turkish gaps: questions without "mı" do not rise at the end. Foreign names that are not in the
    lexicon are read as written.

---

## 2. Runtimes

| Runtime | Supports | Platforms / bindings | Fit |
|---|---|---|---|
| **sherpa-onnx 2.0.1** (Apache-2.0) | VITS (Piper, MMS, Coqui, icefall, MeloTTS, Inflect), Matcha, Kokoro (+Nabra), KittenTTS, ZipVoice, Pocket TTS, Supertonic 3 | Android, iOS, Windows, macOS, Linux, HarmonyOS, WASM. C/C++, Kotlin/Java, Swift, Dart/Flutter, Rust, JS/WASM, C#, Go, Python, Pascal. Also an Android "TTS engine" APK (it can register as the system TTS) | **Pick this.** One API for every small model family, plus prebuilt model tarballs |
| ONNX Runtime 1.31.1 (MIT) | Any ONNX graph: Supertonic upstream, Kokoro, MOSS-TTS-Nano, Antalia-2 Mini, Ahenk Cep | Android AAR, iOS pods, desktop, ORT Web (WASM/WebGPU) | Use it for the Turkish custom models. Reuse the onnxruntime shared library that sherpa-onnx already bundles so we don't ship two copies |
| piper-phonemize (csukuangfj fork, GPL-3.0) | espeak-ng phonemes fed into sherpa-onnx 2.x | Android, iOS, Flutter (WASM-backed), Swift, Rust, Node/WASM, C | Optional add-on, and only if the app license is GPL-compatible |
| llama.cpp / GGUF | NeuTTS, KittenTTS 2 (fork), Orpheus | All platforms | Only for the 0.5B+ speech LMs; not needed for the shortlist |
| ExecuTorch 1.5.1 | Few TTS ports (**unverified**) | Android/iOS | Skip |
| MLX (mlx-audio) | Kokoro, Supertonic 3, MOSS-TTS-Nano, Pocket… | Apple only | Skip, since we need one cross-platform integration |
| LiteRT | Community Pocket TTS Android build | Android | Skip |
| Gradium xn runtime | Phonon | Rust, npm, Python | Skip unless an Apache multilingual Phonon appears |

---

## 3. System TTS per platform

| Platform | API | Enumerate voices and languages | Word / sentence callbacks | Notes |
|---|---|---|---|---|
| **Android** | `android.speech.tts.TextToSpeech` | `getEngines()`, `getVoices()` (API 21: `Voice` has locale, quality, latency, `isNetworkConnectionRequired()`, features), `getAvailableLanguages()`, `isLanguageAvailable()`. `Engine.ACTION_INSTALL_TTS_DATA` prompts a voice download. Android 11+ needs `<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>` | `UtteranceProgressListener.onRangeStart(utteranceId, start, end, frame)` (API 26), **called only if the engine reports ranges** (`SynthesisCallback.rangeStart`). Google TTS does (the Narra app relies on it). Also `onBeginSynthesis`/`onAudioAvailable` (API 24) and `onStop` (API 23) | `getMaxSpeechInputLength()` limits each utterance, so queue sentence by sentence. Google TTS covers tr-TR and fil-PH. We could later expose our sherpa voices as a `TextToSpeechService` |
| **iOS / macOS** | `AVSpeechSynthesizer` (AVFAudio) | `AVSpeechSynthesisVoice.speechVoices()`, `.quality` (default / enhanced / premium), `language`. Personal Voice: `requestPersonalVoiceAuthorization` (iOS 17 / macOS 14) | `speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)` (iOS 7 / macOS 10.14). `speechSynthesizer(_:willSpeak: AVSpeechSynthesisMarker, utterance:)` (iOS 17 / macOS 14) gives word, sentence, paragraph, phoneme and bookmark markers. `write(_:toBufferCallback:toMarkerCallback:)` (iOS 16 / macOS 13) renders to buffers with markers | `AVSpeechSynthesisProviderAudioUnit` (iOS 16 / macOS 13) lets an app ship a **system-wide voice**, a future route for our models. iOS has a Turkish voice (Yelda); Filipino voice availability is **unverified** |
| **Windows** | WinRT `Windows.Media.SpeechSynthesis.SpeechSynthesizer` (OneCore voices); classic SAPI 5.4 `ISpVoice` | `SpeechSynthesizer.AllVoices` (WinRT); SAPI token enumeration. Turkish OneCore voice comes with the Turkish speech pack (Settings > Time & language > Speech) | WinRT: `Options.IncludeWordBoundaryMetadata` / `IncludeSentenceBoundaryMetadata` (Win10 1703, contract 15063+) add cues to `SpeechSynthesisStream.TimedMetadataTracks`. SAPI: `SPEI_WORD_BOUNDARY` / `SPEI_SENTENCE_BOUNDARY` events | Windows 11 Narrator "natural" voices are not exposed to third-party apps through WinRT/SAPI (**unverified**) |
| **Linux** | speech-dispatcher (SSIP; `libspeechd`, `spd-say`, python3-speechd); output modules espeak-ng (default), RHVoice, festival, others | `spd_list_synthesis_voices`, `spd_list_modules` | Events: `SPD_EVENT_BEGIN/END/CANCEL/PAUSE/RESUME/INDEX_MARK`. **No word boundaries.** Insert SSML `<mark/>` per word or sentence and read `INDEX_MARK` | Newer: **Spiel** (`project-spiel/libspiel`, LGPL-2.1, D-Bus provider spec, `range-started` signal for spoken ranges); little adoption so far. Desktop default voices sound poor, so on Linux default to a sherpa-onnx voice |
| **Web** | `speechSynthesis` / `SpeechSynthesisUtterance` | `getVoices()` plus the `voiceschanged` event (the list arrives asynchronously) | `boundary` event (`name` = word/sentence, `charIndex`, `charLength` (Chrome 77+)). MDN data: Chrome has a **partial** implementation (it does not fire as expected, crbug 40715888); Firefox 49+, Safari 7+, Edge 14+. **Android WebView: not supported** | If the app shell is a WebView (Capacitor/Tauri), use native TTS through a bridge. On the web, sherpa-onnx WASM or ORT Web models are the offline option |

Highlighting plan: use native word ranges when the system TTS provides them. With sherpa-onnx voices,
highlight the sentence (we synthesize sentence by sentence) and estimate word times from each word's share of
the sentence's characters. For cloud, use the provider's timestamps where they exist (table below).

---

## 4. Cloud TTS with a user-supplied API key

Prices are list prices in USD and may change. Check them again before showing them in the UI.

| Provider | Models (Nov 2026) | Languages | Turkish | Filipino | Streaming | Timestamps for highlighting | Price tier | Docs |
|---|---|---|---|---|---|---|---|---|
| **Google Gemini API TTS** | `gemini-3.8-flash-tts`, `gemini-3.8-flash-lite-tts` (3.1-flash-tts-preview and 2.5 previews being replaced) | 130+ (Flash), 100+ (Lite); 30 prebuilt voices | Yes | Yes | Yes (`stream: true`, raw 24 kHz PCM) | Not documented (**unverified**) | **Free tier**; Flash $0.50 in / $9 out per 1M tokens until 2026-12-31, then $1 / $18; Lite $0.50 / $6, then $1 / $12 | aistudio.google.com/docs/speech-generation |
| **Azure AI Speech** | Neural, Multilingual Neural, Neural HD (MAI-Voice-2 / -Flash, preview) | 140+ (approx., **unverified** count) | Yes: Emel, Ahmet; Aydın, Elif (MAI-Voice-2 HD) | Yes: Blessica, Angelo (+ DragonHD) | Yes (SDK / WebSocket) | **WordBoundary events** (SDK), visemes, SSML bookmarks | Neural about $15–16 per 1M characters, HD about $22 (third-party figures from the Retail Prices API); **free tier 0.5M characters per month** | learn.microsoft.com/azure/ai-services/speech-service |
| **ElevenLabs** | `eleven_v4`, `eleven_v4_turbo`, `eleven_v3`, `eleven_multilingual_v2`, `eleven_flash_v2_5` | 90+ (v4), 70+ (v3), 32 (Flash 2.5) | Yes | Yes | Yes (HTTP stream, WebSocket) | **Character-level** alignment via `/with-timestamps` | Premium, roughly $50–110 per 1M characters (third-party) | elevenlabs.io/docs/overview/models |
| **Google Cloud TTS** | Chirp 3 HD, Neural2, WaveNet, Standard, Studio, Gemini-TTS | 75+ (approx., **unverified**) | Yes: 30 Chirp 3 HD + 5 WaveNet + 5 Standard voices | Yes (Standard, WaveNet, Neural2) | Chirp 3 HD only (`StreamingSynthesize`) | SSML `<mark>` timepoints (not on Chirp 3 HD, which takes no SSML) | Standard/WaveNet $4, Neural2 $16, Chirp 3 HD $30, Studio $160 per 1M characters; free monthly allowance | docs.cloud.google.com/text-to-speech |
| **Amazon Polly** | Standard, Neural, Long-Form, Generative | ~30 languages (42 language variants) | Yes: Filiz (standard), Burcu (neural) | **No** | Yes | **Speech marks** (word, sentence, SSML, viseme) | Standard $4, Neural $16, Generative $30, Long-Form $100 per 1M characters; free tier | docs.aws.amazon.com/polly |
| **OpenAI** | `gpt-4o-mini-tts`, `tts-1`, `tts-1-hd`; **all shut down on 2027-01-06**, replaced by `gpt-realtime-2.1-mini` (Realtime API only) | Follows Whisper languages (~57); 13 voices, "optimized for English" | Yes | Yes (Whisper covers Tagalog, **unverified**) | Chunked HTTP | None | tts-1 $15, tts-1-hd $30 per 1M characters; mini-tts $0.60 in / $12 out per 1M tokens | developers.openai.com/api/docs/guides/text-to-speech |
| **Cartesia** | Sonic 3.6 (`sonic-3.6-2026-08-27`), 3.5, 3 | 44 | Yes | Yes (Tagalog) | Yes (WebSocket) | Word timestamps over WebSocket (**unverified** this session) | Credit-based (**unverified**) | docs.cartesia.ai |
| **Deepgram** | Flux TTS (recommended), Aura-2 (7 languages, no tr) | Flux: count **unverified** | Yes (Flux `flux-{voice}-tr`) | Unverified | Yes (`/v2/speak` WebSocket) | Unverified | Aura-2 $0.030 per 1K characters; Flux **unverified** | developers.deepgram.com/docs/tts-models-languages-overview |
| **Fish Audio** | `s2.1-pro` (+ `s2.1-pro-free` for development), `s2-pro`, `s1` (retires 2026-12-31) | 83 (S2.1-Pro) | **Not confirmed** | Not confirmed | Yes (WebSocket) | Unverified | $15 per 1M UTF-8 bytes (s2-pro / s1) | docs.fish.audio |
| **MiniMax** | `speech-2.8-hd`, `speech-2.8-turbo`, 2.6, 02 | 40 | Yes | Yes | Yes (HTTP stream, WebSocket) | Unverified | About $60 per 1M characters for turbo via resellers (**unverified**) | platform.minimax.io/docs |
| Others (not checked) | Gradium API (5 languages), Inworld, Hume Octave, Mistral Voxtral TTS (open weights are CC BY-NC), Speechify, Sarvam (Indic) | — | — | — | — | — | — | — |

Integration note: many providers and local servers (`supertonic serve`, Kokoro-FastAPI and others) speak the
OpenAI `/v1/audio/speech` shape. Make "OpenAI-compatible" a generic adapter with a configurable base URL, and
keep separate native adapters for Gemini, Azure and ElevenLabs. Store keys in the Android Keystore / iOS
Keychain. Cache synthesized audio per sentence so re-reading a passage costs nothing.

---

## 5. Turkish verdict

| Option | Size | Measured Turkish WER (lower is better) | Naturalness | License | Effort for us |
|---|---|---|---|---|---|
| System TTS (Google / Apple / Microsoft) | 0 | — | OK | — | Lowest; this is the default |
| Supertonic 3 int8 | 122 MB | **Not measured** | Unknown, so test it | OpenRAIL-M | Low (sherpa-onnx) |
| Antalia-2 Mini int8 | ~10 MB | 1.02–1.09% | UTMOS 3.18 | Apache-2.0 | Medium (custom ORT + port the JS normaliser) |
| Ahenk Cep int8 | ~12–17 MB | 2.32% (TR-Zor) | UTMOS 3.44 | CC BY 4.0 | Medium (same pipeline shape as Antalia) |
| EMA Lightning | 34 MB | 0.92% | UTMOS 3.30 | Apache-2.0 | High (needs an ONNX export) |
| Piper dfki-medium | 20 MB | 3.2–3.4% | UTMOS 3.71 | **NC** | Low only with the GPL phonemizer |
| MMS tur | ~100 MB | 6.4% | UTMOS 3.79 | **NC** | Low |
| Chatterbox MTL / KittenTTS 2 / VoxCPM2 / Trendyol | 1–5 GB | 1–2% | High | MIT / restricted / Apache / MIT | Not viable on phones |
| Cloud: Gemini 3.8 Flash / ElevenLabs v4 / Azure | — | 1.2–1.5% (Gemini, ElevenLabs) | High | Paid | Low (adapter) |

Next step: an in-house listening test (10 book paragraphs: dialogue, numbers, foreign names, questions) of
Supertonic 3 (several voices) against Antalia-2 Mini, Ahenk Cep and Google TTS tr-TR, on a mid-range Android
phone, recording the RTF.

---

## Sources

Runtimes and catalogs
- sherpa-onnx repo and README: https://github.com/k2-fsa/sherpa-onnx (release v2.0.1, 2026-10-26)
- sherpa-onnx TTS model release list (646 assets, read through the GitHub API): https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models
- sherpa-onnx TTS docs: https://k2-fsa.github.io/sherpa/onnx/tts/index.html, Kokoro: https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/kokoro.html, RTF table: https://k2-fsa.github.io/sherpa/onnx/tts/pretrained_models/rtf.html, Supertonic: https://k2-fsa.github.io/sherpa/onnx/tts/supertonic.html, Kitten: https://k2-fsa.github.io/sherpa/onnx/tts/kitten.html
- espeak-ng removal: https://github.com/k2-fsa/sherpa-onnx/pull/4055, https://github.com/k2-fsa/sherpa-onnx/issues/3731
- Word-timing request: https://github.com/k2-fsa/sherpa-onnx/issues/3727; OmniVoice request: https://github.com/k2-fsa/sherpa-onnx/issues/3651; MOSS-TTS-Nano request: https://github.com/k2-fsa/sherpa-onnx/issues/3652; multilingual Pocket: https://github.com/k2-fsa/sherpa-onnx/issues/4148
- GPL phonemizer add-on: https://github.com/csukuangfj/piper-phonemize
- ONNX Runtime: https://github.com/microsoft/onnxruntime/releases (v1.31.1); ExecuTorch: https://github.com/pytorch/executorch/releases (v1.5.1)
- Mobile benchmark (VoicePing, 2026-02-15): https://voiceping-landingpage-prod.pages.dev/en/blog/research-offline-tts-eval/
- Overview with licenses (Yaps, 2026-10-10, third-party): https://www.yaps.ai/blog/best-local-tts-models

Models
- Supertonic (archive): https://github.com/supertone-oss-archive/supertonic, https://huggingface.co/supertone-oss-archive/supertonic-3, https://huggingface.co/Supertone/supertonic-3; announcement: https://www.supertone.ai/en/work/faster-and-more-accurate-across-31-languages----introducing-supertonic-3 (redirects to antinodeaudio.com)
- Kokoro: https://huggingface.co/hexgrad/Kokoro-82M, voices: https://huggingface.co/hexgrad/Kokoro-82M/blob/main/VOICES.md, https://huggingface.co/hexgrad/Kokoro-82M-v1.1-zh, https://huggingface.co/onnx-community/Kokoro-82M-v1.0-ONNX
- KittenTTS: https://github.com/KittenML/KittenTTS, https://huggingface.co/KittenML/kitten-tts-nano-0.8, https://huggingface.co/KittenML/kitten-tts-2 (license: LICENSE.md in that repo)
- Piper: https://github.com/OHF-Voice/piper1-gpl, https://huggingface.co/rhasspy/piper-voices (voices.json; commit "Remove fahrettin and fettah voices at request of contributors", 2025-12-30), dfki model card: https://huggingface.co/rhasspy/piper-voices/blob/main/tr/tr_TR/dfki/medium/MODEL_CARD
- Matcha-TTS: https://github.com/shivammehta25/Matcha-TTS; MeloTTS: https://github.com/myshell-ai/MeloTTS
- MMS-TTS: https://huggingface.co/facebook/mms-tts-tur, ONNX exports: https://huggingface.co/willwade/mms-tts-multilingual-models-onnx
- Pocket TTS: https://huggingface.co/kyutai/pocket-tts; Kyutai TTS: https://huggingface.co/kyutai/tts-1.6b-en_fr
- NeuTTS: https://huggingface.co/neuphonic/neutts-air, https://huggingface.co/neuphonic/neutts-nano, https://huggingface.co/neuphonic/neutts-2e
- Chatterbox: https://huggingface.co/ResembleAI/chatterbox, https://huggingface.co/onnx-community/chatterbox-multilingual-ONNX, https://huggingface.co/ResembleAI/chatterbox-turbo, https://huggingface.co/ResembleAI/chatterbox-nano, https://www.resemble.ai/learn/models/chatterbox-nano
- VibeVoice: https://github.com/microsoft/VibeVoice, https://huggingface.co/microsoft/VibeVoice-Realtime-0.5B
- Orpheus: https://github.com/canopyai/Orpheus-TTS; Spark-TTS: https://huggingface.co/SparkAudio/Spark-TTS-0.5B; F5-TTS: https://huggingface.co/SWivid/F5-TTS; Zonos: https://github.com/Zyphra/Zonos; Dia: https://huggingface.co/nari-labs/Dia-1.6B-0626, https://huggingface.co/nari-labs/Dia2-1B
- Qwen3-TTS: https://huggingface.co/Qwen/Qwen3-TTS-12Hz-0.6B-Base; OmniVoice: https://github.com/k2-fsa/OmniVoice, https://huggingface.co/k2-fsa/OmniVoice, https://arxiv.org/abs/2604.00688; VoxCPM2: https://huggingface.co/openbmb/VoxCPM2
- MOSS-TTS-Nano: https://github.com/OpenMOSS/MOSS-TTS-Nano, https://huggingface.co/OpenMOSS-Team/MOSS-TTS-Nano-100M-ONNX
- Phonon: https://huggingface.co/gradium/phonon-31m-en, https://huggingface.co/gradium/phonon-40m-multilingual, https://gradium.ai/blog/gradium-releases-phonon
- Nabra: https://huggingface.co/oddadmix/Nabra-82M-v0.1; Inflect: https://huggingface.co/csukuangfj/vits-inflect-en-nano-v2

Turkish
- Antalia-2 Mini: https://huggingface.co/cloud0day3/antalia-mini, browser demo and ONNX files: https://huggingface.co/spaces/cloud0day3/antalia-mini
- Ahenk / Ahenk Cep: https://github.com/ozguradmin/ahenk-turkish-tts, https://huggingface.co/ozgurguler/ahenk-cep-tr
- EMA Lightning: https://huggingface.co/canberkkkkkk/ema-lightning, normaliser: https://github.com/erdemtuna/normalizer-tr
- FreyaTTS: https://arxiv.org/abs/2607.09530, https://huggingface.co/freyavoice/freya-tts, https://github.com/freyavoiceai/FreyaTTS
- Trendyol-TTS: https://huggingface.co/Trendyol/Trendyol-TTS; Anka TTS: https://huggingface.co/krmkayabasi/Anka-TTS
- Overview list: https://github.com/Rumeysakeskin/free-turkish-tts-models

System TTS
- Android: https://developer.android.com/reference/android/speech/tts/UtteranceProgressListener, https://developer.android.com/reference/android/speech/tts/TextToSpeech
- Apple: https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate, https://developer.apple.com/documentation/avfaudio/avspeechsynthesismarker, https://developer.apple.com/documentation/avfaudio/avspeechsynthesisprovideraudiounit
- Windows: https://learn.microsoft.com/en-us/uwp/api/windows.media.speechsynthesis.speechsynthesizeroptions.includewordboundarymetadata
- Linux: https://github.com/brailcom/speechd, https://github.com/project-spiel/libspiel, https://blog.monotonous.org/2024/introducing-spiel/
- Web: https://developer.mozilla.org/en-US/docs/Web/API/SpeechSynthesisUtterance/boundary_event, compatibility data: https://github.com/mdn/browser-compat-data/blob/main/api/SpeechSynthesisUtterance.json

Cloud
- Gemini TTS: https://aistudio.google.com/docs/speech-generation, pricing: https://aistudio.google.com/docs/pricing
- Google Cloud TTS: https://docs.cloud.google.com/text-to-speech/docs/list-voices-and-types, https://cloud.google.com/text-to-speech/pricing
- Azure: https://learn.microsoft.com/en-us/azure/ai-services/speech-service/language-support?tabs=tts, https://azure.microsoft.com/pricing/details/cognitive-services/speech-services
- ElevenLabs: https://elevenlabs.io/docs/overview/models, https://elevenlabs.io/docs/api-reference/text-to-speech/convert-with-timestamps
- OpenAI: https://developers.openai.com/api/docs/guides/text-to-speech, https://developers.openai.com/api/docs/deprecations, https://developers.openai.com/api/docs/pricing
- Amazon Polly: https://docs.aws.amazon.com/polly/latest/dg/available-voices.html, https://aws.amazon.com/polly/pricing/
- Cartesia: https://docs.cartesia.ai/build-with-cartesia/tts-models/latest
- Deepgram: https://developers.deepgram.com/docs/tts-models-languages-overview, https://www.deepgram.com/TTS
- Fish Audio: https://docs.fish.audio/developer-platform/models-pricing/models-overview
- MiniMax: https://platform.minimax.io/docs/guides/speech-t2a-websocket

---

## 6. Voice cloning (asked for by the user on 2026-11-13)

The user wants people to hear books in their own voice or a loved one's, offline, in Turkish, English and other languages. The project is AGPL-3.0 and will never be commercial.

- **License rule.** Use only weights under MIT, Apache-2.0, CC BY or OpenRAIL. Non-commercial weights stay out: XTTS-v2 (CPML), F5-TTS, Piper `tr_TR-dfki` and MMS. AGPL lets anyone sell the app, so a non-commercial model cannot ship with it, even though we ourselves never sell it. OpenRAIL-M (Supertonic 3) restricts impersonation, so cloning a voice asks the user to confirm the speaker consents.
- **Phone route (to test).** A multilingual TTS gives the language, and a voice converter gives the timbre: Supertonic 3 (31 languages including Turkish) followed by a converter such as OpenVoice v2's tone colour converter (MIT). The converter does not depend on language, so every language the TTS speaks also works in the cloned voice. Speed on phones and quality on Turkish are **unverified**. Generating ahead while charging covers slow phones.
- **Desktop or high-quality route.** Clone directly with Chatterbox Multilingual (MIT, 23 languages including Turkish, RTF 2.89 on an L4 GPU, too slow for phones) or OmniVoice (Apache-2.0, 600+ languages).
- **No famous character voices.** Their voices belong to voice actors (personality rights), and being non-commercial does not change that. Ship original voices instead, and let users add their own recordings.

### 6.1 Automatic voicing, design from the user (2026-11-13)

- A setting like automatic colourization: "Automatic voicing". The user picks a starting buffer (default 3 or 5 pages), and its progress bar shows while it is made. After that, the rest is produced in the background while the user listens, without using up the phone's resources. The user is told when listening catches up with the buffer.
- A range picker (two-handle slider, for example pages 50 to 150) shows the word count and a time estimate for this device, then progress as `%42.17` and `63/100`.
- Buffer maths. Let `g` be the seconds to generate one page and `l` the seconds to listen to it, both measured on the device and refined like `secondsPerPage`. If `g <= l`, one or two pages are enough. Otherwise listening N pages without a stop needs a buffer of `B = ceil(N * (1 - l/g))`.
- Notes added in discussion:
  - Store audio compressed through the platform encoder (AAC). At about 15–30 MB per hour, a 10-hour book is 150–300 MB, so use a cache limit and drop pages already listened to.
  - Key the cache by voice, speed and sentence-text hash, not by page number, so a font change does not throw it away.
  - Run in the background at low priority with 1–2 threads, and slow down on `PowerManager` thermal status or low battery.
  - When listening catches up, offer to wait or to carry on in the system voice.
