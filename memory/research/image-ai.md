# Image AI and filters: on-device colorization, upscaling, classic filters

Research date: 2026-11-10. Scope: images inside books (manga/comics first), Android first, then iOS, Windows,
macOS, Linux, web.

Legend: **verified** means checked today against the official repo, model card, release or docs. **est.** is
my own estimate from parameter counts or similar models. **unverified** means I found a claim but could not
confirm it. All license facts come from the GitHub API (`license.spdx_id`), the LICENSE file or the model card.

---

## 1. Recommendation (read this first)

### What to ship first

| Role | Pick | Size | License (code / weights) | Runtime | Why |
|---|---|---|---|---|---|
| Colorizer (optional download) | **DDColor-tiny** (`ddcolor_paper_tiny`, ICCV 2023, Alibaba DAMO) | 56.3M params. fp32 ~215 MB, fp16 ~110 MB (est.), int8 w8a8 54.8 MB (Qualcomm AI Hub) | Apache-2.0 / Apache-2.0 | ONNX Runtime | It is the only lightweight automatic colorizer whose code and weights are both permissively licensed and ready to run on phones. Qualcomm AI Hub ships ONNX/TFLite/QNN exports (~24–83 ms on Snapdragon NPUs at 224², verified). A Core ML port exists (203 MB, iOS 17+). It predicts only the chroma (ab), and the original luminance is kept, so the output is exactly the original's size and the line art stays untouched. |
| Upscale, real-time (no download) | **Anime4K CNN x2 (S/M/L)** for line art, plus **FSR 1 EASU+RCAS** or **Snapdragon GSR 1** for photos | Shader source only, a few KB | MIT / MIT / BSD-3-Clause | GPU fragment shaders | Runs at display time on every GPU and needs no runtime or storage. It never changes the source image. |
| Upscale, neural (optional download) | **realesr-animevideov3** (SRVGGNetCompact, x2/x3/x4) | 2.5 MB fp32 (.pth), ~1.2 MB fp16 | BSD-3-Clause / BSD-3-Clause | ONNX Runtime (NPU/GPU only) | It is very small, built for anime and line art, and already proven in the Mihon Upscale fork on Vulkan and on Qualcomm and MediaTek NPUs. |
| Neural alternative for B&W pages | **Real-CUGAN SE up2x** (with denoise levels) | ~2.6 MB fp16 (ncnn bin) | MIT / MIT | same | It has better JPEG/noise cleanup on manga pages. Offer it as a second choice. |
| Photos in books | **Real-ESRGAN general-x4v3** | 4.9 MB fp32, 1.21M params | BSD-3-Clause | same | ~3.5 ms per 128² tile on a Snapdragon 8 Elite NPU (verified, Qualcomm AI Hub). |

**Runtime:** ship **ONNX Runtime (MIT)** with one `.onnx` file per model on all six platforms:
- Android: XNNPACK on the CPU, plus the QNN EP for Snapdragon NPUs. The NNAPI EP is only a legacy fallback, because Android 15 deprecated NNAPI.
- iOS and macOS: the CoreML EP.
- Windows: DirectML or the WebGPU plugin EP.
- Linux: CPU or the WebGPU plugin EP.
- Web: `onnxruntime-web` with WebGPU, falling back to WASM.

ONNX Runtime's weak spot is Android GPUs on non-Snapdragon phones (Mali, Exynos, Tensor, MediaTek), where it runs CPU only. Add **ncnn (Vulkan, BSD-3)** or **LiteRT GPU (Apache-2.0)** as a second Android backend only if a benchmark gate on a Mali device says so (section 5.8). The prior-art Mihon Upscale fork uses ncnn Vulkan for exactly this reason.

**Rule:** neural upscaling runs only where an NPU or GPU backend exists. On CPU, a full-page neural upscale takes an estimated 10–30 s, so those devices get only the shader upscaler. Colorization runs everywhere, because it works on a single 512² input, not on full resolution.

### The manga-quality problem, stated plainly

- **manga-colorization-v2** (qweasdd, 2022) is the best-known lightweight manga colorizer. It is what manga-image-translator ("mc2"), the BinitDOX extension and FlamboyantEntertainment's self-hosted app all use. Its repository, however, has **no license file at all** (verified via the GitHub API and the repo contents).
- License requests have gone unanswered as of 2026-11-10: issue #13 (2024-05), #41 (2026-04) and #44 (2026-09).
- Without a license the work is all rights reserved. **EgeBookReader must not bundle, host or auto-download it.** That includes the ONNX re-uploads on Hugging Face that label it "MIT" or "Apache" (Faridzar, ifritraen). Those labels are not valid, because the uploader cannot relicense someone else's work.
- DDColor is trained on ImageNet photos. On manga it gives plausible but muted, photo-like colors. No one has published a head-to-head on screentone pages (unverified either way). **We must A/B it ourselves** (see the benchmark plan in 5.8).
- Options to get manga-grade color, in order of preference:
  1. **Keep DDColor-tiny as the default.** Add an "Import model…" setting: the user picks an `.onnx` file they obtained themselves, and the app documents the I/O contract (section 2.3). The app never ships or fetches the file, so any license risk stays with the user.
  2. **Fine-tune our own permissive manga colorizer** later. Start from DDColor-tiny (Apache-2.0) and train on CC-licensed color comics converted to grayscale, for example Pepper&Carrot (CC BY 4.0). This is the only clean route to a redistributable manga model.
  3. **Offer the non-commercial "Manga Light Colorizer"** (CC BY-NC-SA 4.0 weights, 2026-04) as a separately licensed optional download. Only do this if the app is never monetized. It is also heavy: ~300 MB fp32 (191 MB generator + 109 MB SAM 2.1 encoder).
  4. **Keep asking qweasdd** for an MIT or Apache license. If he grants one, mc2 becomes the manga default: fp16 ONNX is ~62 MB and the input is 576² (pad to a multiple of 32).

### API fallback (only if ever needed)

Offline works everywhere, so no cloud path is required. If one is added, it must be opt-in, use the user's own API key, show a privacy warning, and never be the default.
- **Gemini image models** are manga-aware and generative. Official pricing page, read 2026-11-10: Nano Banana 2.1 `gemini-nano-banana-2.1` is $0.0336 per 1K image. `gemini-3.1-flash-lite-image` is $0.0336 per 1K image. Neither has a free tier.
- Because a generative model can move lines, **always merge chroma only**: keep the original luminance at the original size and take only the a/b channels from the cloud result (section 5.2). This guarantees exact placement whatever the model returns.
- **Replicate `piddnad/ddcolor`** costs ~$0.001 per run (L40S, under 1 s). It is the same model as offline, so it helps only very weak devices. It is no quality upgrade.

---

## 2. Model tables

### 2.1 Colorization

Columns: Ckpt = checkpoint. Redistribute = whether an open-source app can host or offer the model as a download.

| Model | Official URL | Date | Size | Input | Code license | Weights license | Redistribute? | Manga quality | Mobile speed | Formats available |
|---|---|---|---|---|---|---|---|---|---|---|
| **DDColor-tiny** (`ddcolor_paper_tiny`) | github.com/piddnad/DDColor · hf.co/piddnad/ddcolor_paper_tiny | Ckpt 2023-12. Repo active (2026-01). | 56.3M params. .bin 220 MB fp32. w8a8 54.8 MB. fp16 ~110 MB (est.) | 512² (default). Stretched to a square. Predicts ab, then merges with the original L at full size. Qualcomm export is 224². | Apache-2.0 | Apache-2.0 (model card) | **Yes** (keep LICENSE and attribution). Trained on ImageNet; the dataset terms are research-only, but the weights are widely redistributed (Qualcomm AI Hub, Core ML zoo). Low risk; note it. | Photo-trained. Expect muted or realistic colors on line art (unverified; must test). | NPU at 224²: 23.8–34.6 ms (8 Elite, TFLite/QNN), 41–49 ms (8 Gen 3), 69–83 ms (8 Gen 1) (verified). Peak RAM up to ~0.5–1.2 GB on some devices (verified). CPU at 512²: ~1–4 s (est.). | ONNX export script in the repo (`scripts/export_onnx.py`). Qualcomm ONNX/TFLite/QNN DLC (v0.66.0). Core ML `.mlpackage` (mlboydaisuke, 2026-08; iOS 17+, ~400 MB RAM; FP16 attention-overflow pitfalls noted). MLX fp16 ports. |
| DDColor-L (`modelscope`, `artistic`, `paper`) | same | 2023-09 | ~228M params. 912 MB fp32. ~230 MB int8 (est.) | 512² | Apache-2.0 | Apache-2.0 | Yes | `artistic` was trained with extra artistic images and may suit comics better (unverified) | Too heavy for phones. A desktop option. | PyTorch. ONNX export works with the same script. |
| **manga-colorization-v2** (mc2) | github.com/qweasdd/manga-colorization-v2 | 2022-06. Last push 2025-03. | Generator ~31M params. ONNX fp32 123 MB, fp16 62 MB (third-party). FFDNet denoiser 3.4 MB. | 576² default (multiple of 32; "≤576 gives best results"). RGB output. Optional color hints. | **none** | **none** (Google Drive; mirrored in manga-image-translator releases) | **No** (all rights reserved; issues #13, #41, #44 unanswered) | The best of the light models on manga. The WACV 2025 paper praises its structure preservation. Soft anime palette; colors change between pages. | Desktop CPU 10–20 s/page and 8 GB GPU ~0.5 s/page, including the denoiser (FlamboyantEntertainment README). Phone CPU ~20–60 s (est.). | Third-party ONNX on HF (Faridzar fp16, ifritraen fp32, Tinigon). The "MIT/Apache" labels on them are invalid. |
| Manga Light Colorizer v6 | hf.co/sharky172/manga-light-colorizer | 2026-04 | 191 MB generator + 109 MB SAM 2.1 encoder (fp32 ONNX) | Trained at 512². Default inference 768². Resized back to the original size. | GPL-3.0 | **CC BY-NC-SA 4.0** | Only for non-commercial use, as a separately licensed download | Gallery uses the same pages as mc2 for comparison (not checked by me) | Heavy (FastViT-SA36 + SAM 2.1). CPU several seconds per page (est.). | ONNX (CPU/CUDA) |
| Sana Manga Coloring (+ int8 ONNX) | hf.co/masterofaudio2077/sana-manga-coloring(-onnx-int8) | 2026-10 / 2026-11 | 2.7 GB download, ~4 GB peak RAM | Short side 512. 20-step flow sampler. Controls for mood, palette and time of day. | Apache-2.0 (card) | Apache-2.0 (card). Base Sana 600M card says Apache-2.0. Trained on ~60 GB of manga pages; data rights unverified. | Card says yes; data provenance is a risk | Diffusion model. Steerable palettes. Looks strong in its own gallery (unverified). | 36–44 s/page on a Ryzen AI 7 350 (16 threads). **Not for phones.** | ONNX int8 (CPU) |
| DeOldify (Artistic / Stable) | github.com/jantic/DeOldify | 2018–2019. **Archived 2024-10.** | Artistic generator 255 MB fp32 | `render_factor` × 16 (e.g., 35 → 560²) | MIT | MIT (README says weights are MIT) | Yes | Photo-oriented and saturated, with known color blotches. Weak on manga. | Heavy ResNet-34/101 U-Net. Seconds on a phone (est.). | Community ONNX ports (AXERA, others) |
| BigColor | github.com/KIMGEONUNG/BigColor | ECCV 2022 | BigGAN-based. Large. | 256² plus arbitrary-resolution mode | MIT | Google Drive; built on BigGAN pretrain. License not stated for the ckpts (unverified). | Unclear | Photo/ImageNet | Too heavy | PyTorch only |
| Zhang et al. ECCV16 / SIGGRAPH17 | github.com/richzhang/colorization | 2016–2017 | ~130 MB | 256² (L → ab) | BSD-2-Clause | BSD-2-Clause | Yes | Desaturated, sepia-like. Poor on manga. | Fast; also runs in OpenCV DNN | Caffe/PyTorch, ONNX ports |
| ColorMNet | github.com/yyang181/colormnet | ECCV 2024 | DINOv2 + memory | Video, exemplar-based | **CC BY-NC-SA 4.0** | same | Non-commercial only | Needs a colored reference frame | Heavy | PyTorch |
| MangaNinja | github.com/ali-vilab/MangaNinjia | CVPR 2025 | SD 1.5 + ControlNet + CLIP-L (GBs) | Reference-based line-art colorization | **CC BY-NC 4.0** | same plus SD 1.5 terms | Non-commercial only | Excellent with a reference image | Desktop GPU only | PyTorch |
| Cobra | github.com/zhuang2002/Cobra | SIGGRAPH 2025 (weights 2025-04) | 4.8 GB (HF) | Reference-based, many references | Apache-2.0 | Apache-2.0 (HF card) | Yes | Strong comic colorization with references | Desktop GPU only | PyTorch / diffusers |
| ColorFlow | github.com/TencentARC/ColorFlow | 2024-12 | SD-based, GBs | Reference-based image sequences | **Tencent "Academic Software Licence"** | same | No (academic only) | Good identity consistency across pages | Desktop GPU only | PyTorch |
| FLUX.2-klein-9B manga-by-reference LoRA | hf.co/thedeoxen/FLUX.2-klein-9B-manga-colorization-by-reference-LORA | 2026-06 | 9B base | Prompt plus reference | LoRA card says Apache-2.0 | **Base FLUX.2 klein 9B: FLUX Non-Commercial License** | No | Strong | Desktop GPU only | diffusers |
| Style2Paints V4.5 / V5 | github.com/lllyasviel/style2paints | V4.5 2019. V5 preview never released. | Windows exe | Interactive | Apache-2.0 (code) | **"We preserve all rights on all pretrained models"** | No | Good for sketches | Desktop only | Bundled exe |
| AnimeColorDeOldify | github.com/Dakini/AnimeColorDeOldify | 2019–2024 | DeOldify-sized | | none | none | No | Anime-tuned DeOldify | | |

### 2.2 Upscaling and restoration

Columns: Type: N = neural, S = shader.

| Model | URL | Type | Size | Code / weights license | Best for | Phone speed | Runtime path |
|---|---|---|---|---|---|---|---|
| **realesr-animevideov3** | github.com/xinntao/Real-ESRGAN (v0.2.5.0, 2022-04) | N, SRVGGNetCompact (64 feat, 16 conv) | 2.5 MB fp32 | BSD-3 / BSD-3 | Anime and line art, x2/x3/x4 | NPU: about half of general-x4v3's cost (est. ~2 ms per 128² tile on 8 Elite). CPU: ~1.2 MFLOP per input pixel, so a 1.5 MP page needs ~1.8 TFLOP, i.e., 15–30 s (est.). | ONNX, ncnn (official models), QNN/TFLite (Mihon fork) |
| Real-ESRGAN general-x4v3 | same | N, compact (32 conv) | 4.9 MB fp32, 1.21M params, w8a8 1.25 MB | BSD-3 / BSD-3 | Photos, mixed content | NPU 128² tile: 3.5 ms float / 0.95 ms w8a8 (8 Elite). 9.6 / 2.6 ms (8 Gen 1) (verified). | ONNX/TFLite/QNN (Qualcomm AI Hub), ncnn |
| RealESRGAN_x4plus_anime_6B | same (v0.2.2.4) | N, RRDB with 6 blocks | 17.9 MB fp32, 4.47M params | BSD-3 / BSD-3 | High-quality anime stills | Several times heavier than compact. NPU only. | ONNX, ncnn |
| Real-ESRGAN x4plus | same | N, RRDB 23 blocks | 64 MB, 16.7M params | BSD-3 | Photos (heavy) | 39.8 ms per 128² tile, NPU float (8 Elite) (verified) | ONNX/TFLite/QNN |
| **Real-CUGAN** SE/Pro (up2x/3x/4x, denoise 1–3, conservative) | github.com/bilibili/ailab/tree/main/Real-CUGAN · github.com/nihui/realcugan-ncnn-vulkan | N, U-Net | up2x ~2.6 MB (ncnn fp16) | MIT (Real-CUGAN folder LICENSE) / MIT | B&W manga, JPEG cleanup | Similar to or heavier than compact. Used in Mihon fork on Vulkan and NPU. | ncnn (official), ONNX ports, QNN (Mihon fork) |
| waifu2x (cunet, upconv_7) | github.com/nagadomi/waifu2x · github.com/nagadomi/nunif · github.com/nihui/waifu2x-ncnn-vulkan (rel. 2025-09-15) | N | cunet 2.8 MB, upconv_7 1.1 MB (ncnn fp16) | MIT / MIT | Art/anime and noise. nunif adds swin_unet art and photo models. | cunet is heavy; upconv_7 is fast | ncnn, ONNX (nunif ships ONNX for in-browser use) |
| APISR (GRL 4x, RRDB 2x/4x, DAT-S 4x) | github.com/Kiteretsu77/APISR | N (CVPR 2024) | GRL 6.5 MB, RRDB 18 MB, DAT 87 MB | **GPL-3.0** | Degraded anime | RRDB-class cost | PyTorch. ONNX possible. GPL makes it a poor fit unless the app is GPL. |
| SPAN / SPAN-F | github.com/hongyuanyu/SPAN | N (NTIRE ESR winner 2024, 2nd place 2025) | ~0.4M params (est.) | Apache-2.0 / Apache-2.0 (Google Drive ckpts are bicubic-SR, not anime) | Efficient SR backbone | Very fast | ONNX. Community model `2x-NomosUni-span-multijpg-ldl` is **CC-BY-4.0** (OpenModelDB). |
| Other permissive community models | openmodeldb.info | N | compact or SPAN | `4x-animerd-v1` CC0 (compact). `1x-span-anime-pretrain` CC0. `2x-Futsuu-Anime` WTFPL (compact). `4x-wtp-manga-p-omni` CC-BY-4.0 (OmniSR). | Candidates to evaluate | | via spandrel (MIT), then ONNX |
| MangaJaNai / IllustrationJaNai (V3 2025-11) | github.com/the-database/MangaJaNai | N, ESRGAN/DAT | V1 ONNX 422 MB set. V3 fp16 ONNX 113 MB set. | **CC BY-NC 4.0** | Best-in-class manga upscaling, height-specific models | Desktop GPU | Not shippable (NC). Most manga-specific OpenModelDB models (MangaScaleV3, MangaJPEG*, FSManga, eula-digimanga) are also CC BY-NC-SA. |
| QuickSRNet / XLSR / SESR-M5 | Qualcomm AI Hub | N, tiny | 28K–343K params | BSD-3 (cards) | Fast generic SR (bicubic-trained, soft on manga) | 0.25–1.4 ms per 128² tile on NPU (verified) | ONNX/TFLite/QNN |
| **Anime4K v4.0.1** | github.com/bloc97/Anime4K | S, GLSL (mpv hook format) | KB | MIT | Real-time line-art upscaling and restore: CNN x2 S/M/L/VL/UL, GAN x2–x4, Restore, Denoise | Real-time on desktop GPUs. M/S variants are used on phones via mpv-android (unverified on low-end GPUs). | Port the passes to plain fragment shaders. Existing ports: Anime4K-WebGPU (MIT, WGSL), Anime4KMetal (Apache-2.0). Avoid Anime4KCPP (GPL-3.0). |
| FSR 1 (EASU + RCAS), CAS | github.com/GPUOpen-Effects/FidelityFX-FSR · FidelityFX-CAS | S | KB | MIT | Generic upscale and sharpen | Under 1 ms at phone resolution (est.) | GLSL ES / Metal / WGSL. One pass each. |
| Snapdragon GSR 1 | github.com/SnapdragonGameStudios/snapdragon-gsr | S | KB | BSD-3-Clause | Single-pass 12-tap Lanczos-like upscale with adaptive sharpening, designed for mobile GPUs | Mobile-tuned | GLSL |

### 2.3 I/O contracts (for the app's model loader and the "Import model…" feature)

- **DDColor:**
  - Input: `[1,3,S,S]` float32 RGB. It is the grayscale L of the source, converted back to RGB with a=b=0 (see `ddcolor/pipeline.py`).
  - Output: `[1,2,S,S]` ab.
  - Post-processing: resize ab to the original H×W (use bilinear; the repo's default `F.interpolate` mode is nearest), concatenate with the original L, then convert Lab → sRGB.
- **manga-colorization-v2 (user-supplied file only):**
  - Input: `[1,5,H,W]` float32. Channel 0 is grayscale 0..1. Channels 1–3 are the color hint ((c−0.5)/0.5), 0 if none. Channel 4 is the hint mask. H and W are multiples of 32, padded via `resize_pad`.
  - Output: RGB in −1..1 (×0.5+0.5).
  - Post-processing: crop the pad, then apply the chroma-only merge (5.2).
- **Super-resolution models:** input `[1,3,h,w]` in 0..1, output `[1,3,h·s,w·s]`. Use fixed tile shapes for NPUs (5.1).

---

## 3. Classic filters worth offering

All of them are **display-time, non-destructive**. Parameters are stored per book or per page, and the source pixels are never rewritten. A "Reset" option always works. Most of them are a few lines of shader code. Run them in one fused fragment pass over the page texture.

| Filter | Formula / method | Where to run | Cost | Notes |
|---|---|---|---|---|
| Saturation | `c' = mix(vec3(luma(c)), c, s)` (Rec.709 luma) | GPU shader, or a 4×5 color matrix | ~free | Android API < 33 can use `ColorMatrixColorFilter`. Web: CSS `saturate()`. |
| Vibrance | Saturation scaled by `(1 − sat(c))`, so already-saturated pixels move less (skin stays sane) | GPU | ~free | Core Image has `CIVibrance` |
| Contrast / brightness / levels | `c' = pow(clamp((c − black)/(white − black)), 1/γ)` | GPU (matrix + pow) | ~free | Auto levels: take the 0.5% and 99.5% luminance percentiles from a 256-bin histogram on a downscaled copy (CPU, under 2 ms). |
| Gamma / "darken text" for e-ink | Mid-tone gamma γ ≈ 1.5–2.2 plus a contrast boost. Optional 16-level quantization with ordered (Bayer) dithering. | GPU | ~free | KOReader-style contrast. Dithering prevents banding on 16-gray panels. |
| Sharpen | RCAS/CAS (MIT) or an unsharp mask (Gaussian radius r, amount a, threshold) | GPU | 1–2 passes | Prefer CAS/RCAS: no halos, contrast-adaptive |
| Denoise / de-JPEG | Bilateral or guided filter (classic). Real-CUGAN denoise / waifu2x noise models (neural). | GPU (classic), NPU (neural) | Classic is cheap; neural goes to the background queue | Screentones look like noise to a classic denoiser. Keep the strength low on B&W manga. |
| Despeckle (scans) | 3×3 median (GPU). Or, on a binarized copy, remove connected components smaller than N px (CPU). | GPU / CPU | cheap | For dirty scans only |
| Descreen (color scans, moiré) | Gaussian low-pass tuned to the halftone frequency, or an FFT notch | GPU / CPU | medium | Rarely needed for digital comics |
| Dewarp (photographed pages) | Classic: page_dewarp (MIT, OpenCV cubic sheet model). Neural: UVDoc (MIT). | CPU / NPU, once per page | heavy, offline | Out of scope for v1. Useful only for camera-captured books. |
| Auto-crop margins | On a 1/4-scale luminance thumbnail, find the bounding box of pixels darker than (paper − δ). Ignore components under ~0.2% of the area. Add padding. Cache the rect. | CPU | under 5 ms per page | Store the crop rect, not cropped pixels. Apply it as a view transform. |
| Night / sepia / invert | Color matrix | GPU | free | Invert only luminance (keep hue) for colored pages |

**Where shaders live:** this depends on the UI toolkit (a separate research topic).
- Android: AGSL `RuntimeShader` on API 33+, `RenderEffect` on API 31+, color matrix below that.
- iOS: Core Image or Metal.
- Compose Multiplatform: Skia `RuntimeEffect` (SkSL) on iOS, desktop and web.
- Flutter: `FragmentProgram` on all six platforms.
- Web: WebGL2 or WebGPU.

Keep one GLSL ES 3.0 source per filter and translate it per platform, by hand or via SPIRV-Cross or naga, so the six targets don't drift apart.

---

## 4. Mobile inference runtimes (status 2026-11-10)

| Runtime | Latest | License | Android | iOS / macOS | Windows / Linux | Web | Model format, conversion |
|---|---|---|---|---|---|---|---|
| **ONNX Runtime** | 1.31.1 (2026-10-26). Maven `onnxruntime-android` 1.31.1; `onnxruntime-android-qnn` 1.29.0. | MIT | CPU with XNNPACK. **QNN EP** (Snapdragon HTP NPU, with an EPContext cache for compiled graphs). NNAPI EP (works, but Android 15 deprecated NNAPI itself). WebGPU plugin EP lists an Android/Vulkan backend via Dawn but has no Android package (unverified in practice). | **CoreML EP** (ANE/GPU; 1.31 added `PREFER_NPU` device selection). WebGPU plugin (Metal). | CPU, DirectML, CUDA plugin, WebGPU plugin (D3D12/Vulkan), OpenVINO | `onnxruntime-web`: WebGPU and WASM SIMD | `.onnx`. Export: PyTorch `torch.onnx.export` / dynamo. fp16 via `onnxconverter-common`, int8 via `quantize_dynamic`/`quantize_static`. |
| **LiteRT** (formerly TFLite) | 2.3.2 (2026-10-26) | Apache-2.0 | CPU (XNNPACK). **GPU on all vendors** (OpenCL/OpenGL; `litert-gpu` Maven). **NPU**: Qualcomm, MediaTek, Google Tensor, Samsung Exynos (`litert-npu-runtime-*`). CompiledModel API. minSdk 24. | Metal GPU. Swift package new in 2.3, but the docs still call the Swift runtime pre-release. No NPU on iOS. | C++/Python. WebGPU/OpenCL GPU. Intel/Qualcomm NPU on Windows. | LiteRT.js with WebGPU | `.tflite`. Convert with `litert-torch` (formerly ai-edge-torch, v0.10.0 2026-10-20). |
| **ncnn** | 20261020 | BSD-3-Clause | CPU and **Vulkan GPU on all vendors**. Proven for SR (waifu2x/Real-CUGAN/Real-ESRGAN-ncnn-vulkan, Mihon fork). | Vulkan through MoltenVK | Vulkan (all GPUs) | WASM, CPU only | `.param` + `.bin`. Convert with **pnnx** (PyTorch/ONNX). Transformer ops (DDColor decoder) are less battle-tested (unverified). |
| **MNN** | 3.6.2 (2026-10-29) | Apache-2.0 | CPU, OpenCL, Vulkan, NNAPI/QNN (per docs) | Metal, CoreML | CPU, CUDA, Vulkan | WASM (limited) | `.mnn`. Converter from ONNX/TF/TorchScript. |
| **ExecuTorch** | 1.5.1 (2026-09-23) | BSD-3 (NOASSERTION in API) | XNNPACK. Vulkan GPU. Qualcomm, MediaTek, Samsung Exynos, Arm VGF backends. | XNNPACK. Core ML. MLX (experimental). | XNNPACK, OpenVINO. CUDA/Vulkan (experimental). | WASM and WebGPU (experimental) | `.pte`, but **one per backend** ("a `.pte` built for one hardware target…"), so not one file everywhere |

**Which runtime covers Android, iOS and desktop with one model file?**
- **ONNX Runtime** covers all six platforms with the same `.onnx` file, and it has the most mature iOS, desktop and web stories. It is also the format upstream projects and Qualcomm AI Hub publish.
- **LiteRT** also covers all six with `.tflite`, and it has the best Android GPU and NPU coverage. Its iOS and desktop bindings are younger.
- **ncnn** covers all native platforms with Vulkan, but on the web it runs CPU only.
- **ExecuTorch** needs one `.pte` per backend.

**Conversion path (the source of truth is the PyTorch checkpoint):**
1. `torch.onnx.export` (opset 17+, static shapes for NPUs), then `onnxsim`.
2. Make fp16 and int8 variants. The ONNX file is the shipped artifact.
3. From the same ONNX, if ever needed: `pnnx` → ncnn, `onnx2tf` or `litert-torch` (from PyTorch) → `.tflite`, `coremltools` → `.mlpackage`, Qualcomm AI Hub → QNN context binaries.

Validate every converted model against the PyTorch output, for example mean ΔE < 1 on a fixed page set. Watch for FP16 overflow in attention layers: the DDColor Core ML notes report it on GPU/ANE.

---

## 5. Engineering strategy

### 5.1 Tiling for large pages
- **Colorization: do not tile.** The model needs global context. Downscale the whole image to the model input: DDColor 512² (stretched), mc2 576 (padded). Chroma is low-frequency, so a 512² ab map upsampled to a 2000-px page looks right.
- Upsample ab bilinearly, or with a joint-bilateral filter guided by L to stop color bleeding across ink lines (upgrade path).
- **Very tall images** (webtoon strips, aspect > 2.5:1): split them vertically into near-square segments with ~15% overlap and blend ab across the overlaps with a linear ramp. Colors may still shift between segments (a known limitation).
- **Super-resolution: always tile.**
  - Use fixed input tiles of 128² or 256². NPU graphs need static shapes; the Qualcomm exports are 128².
  - Overlap tiles by 8–16 px (receptive field), drop the overlap from each output tile, and write into the destination bitmap.
  - Process tiles row by row. Between tiles, check the cancel flag, the scroll state and the thermal state. This bounds memory to one tile plus the output.
- **Cap the upscale target** at what the screen needs (screen height × max zoom, e.g., 2×). Don't run 4× when 1.6× is displayed: run 2× and let the shader do the rest.
- **Decode for the model** with downsampling (`ImageDecoder.setTargetSize` / `BitmapFactory.inSampleSize`; on iOS `CGImageSourceCreateThumbnailAtIndex`). Never build an fp32 tensor of a full page: a 2000×3000 RGB page is 72 MB in fp32.

### 5.2 Exact size and exact place
- **Chroma-only merge** (the default for every colorizer, local or cloud):
  `out(x) = Lab→sRGB( L_original(x), upsample(ab_model)(x) )`.
  The output has the original W×H by construction. Line art, screentones and text keep their exact pixels, because luminance never passes through the model. This is how manual colorists work ("multiply" layers), and it is what DDColor's own pipeline does.
- **Normalize once, before hashing and inference:** apply EXIF orientation, convert ICC profiles to sRGB, handle CMYK JPEGs and grayscale with alpha (keep alpha separately and re-attach it), and premultiplied alpha. Do the same normalization for the original and the derived image.
- **The layout never changes.** The renderer keeps using the original's intrinsic size, crop rect and layout box. It only swaps the texture, which can have a higher resolution in the upscale case. Crossfade 150–200 ms. Store `(width, height)` in the cache row and refuse a cached result whose size does not match.
- **Skip images that are already color:** compute the mean chroma (Lab a/b magnitude) on a 64² thumbnail. Above a threshold, hide the colorize icon and skip the image in auto mode. Also skip tiny images (under ~200 px: icons, ornaments).

### 5.3 Caching
- **Identity:**
  - `book_id` = SHA-256 of the file (hash the first and last 1 MB plus the size for an instant id, and compute the full hash lazily).
  - `image_id` = the archive entry path, the EPUB manifest id, or the PDF page plus XObject index.
  - `image_hash` = SHA-256 of the normalized image bytes. This is the storage key, so the same image in another edition or archive reuses its result.
  - `model_key` = e.g. `ddcolor-tiny@1/512/fp16/chroma-v1`. Bump it on any change to the model or post-processing.
- **One SQLite table:** `derived(book_id, image_id, image_hash, kind{color,sr}, model_key, w, h, path, bytes, created, last_used)`. Look up by (book_id, image_id) on open; that is a hit without decoding anything.
- **Storage v1:** full-resolution WebP (q≈90) in app-private cache (`noBackupFilesDir`, iOS Caches, desktop cache dir, OPFS on the web). This is ~0.3–0.6 MB per page (est.). Use an LRU with a user-set cap (default 1 GB), "keep for this book" pinning, and delete on book removal.
  - **ponytail:** full-res RGB costs ~100 MB per 200-page book. Upgrade path: store only the model-resolution ab map (~50–150 KB) and do the chroma merge in the display shader.
- **On-demand mode:** besides the cache, export the merged full-resolution image to the gallery.
  - Android: MediaStore `Pictures/EgeBookReader` (API 29+ needs no permission for the app's own files).
  - iOS: `PHPhotoLibrary` add-only access (`NSPhotoLibraryAddUsageDescription`).
  - Desktop: `~/Pictures/EgeBookReader`.
  - Web: download, or an in-app gallery in OPFS.
  - Also, or instead, keep an in-app gallery view if "the app's image gallery" means inside the app.

### 5.4 Queue, priorities, first N pages
- **One inference worker** (models are memory-heavy; run one at a time) with a priority queue:
  - **P0:** the user tapped the colorize icon (on demand).
  - **P1:** first open, the first N images in reading order (setting, default 3).
  - **P2:** visible page ±2.
  - **P3:** the rest of the book in reading order, re-prioritized when the user jumps.
- **First open:** show the original pages immediately. Never block page rendering on AI. Start P1 right after the reader opens, show a small "Colorizing 1/3" chip, and crossfade each page when it is ready.
  - Optional setting "wait for color before showing" if the user prefers a delay to a visible swap. That matches "first open may take a bit longer".
  - Later opens hit the cache and show color instantly.
- **Load the model lazily** once per reader session and release it when the reader closes.
  - The first NPU use compiles the graph, which can take seconds. Persist the compiled context: ORT QNN `EPContext` / `ep.context_enable`, LiteRT compilation cache, and the Core ML compiled `.mlmodelc`.
- **Device gate:** 64-bit and ≥ 4 GB RAM for DDColor (Qualcomm measured peaks up to ~0.5–1.2 GB). Below that, offer on-demand mode only, at a 384² input.

### 5.5 Thermal and battery awareness

**Android:**
- `PowerManager.addThermalStatusListener` (API 29) and `getCurrentThermalStatus()`.
- `getThermalHeadroom(forecastSeconds)` (API 30): call it **at most once every 10 s** from one thread; it returns NaN if called too often. 0.0 means no throttling and 1.0 means `THERMAL_STATUS_SEVERE`.
- Policy for P3: pause at headroom ≥ 0.85 or status ≥ LIGHT. Stop the whole background queue at ≥ 0.95 or status ≥ MODERATE. Resume below 0.7. Google's documentation mentions that some devices always report `NONE`, so trust headroom over status.
- Also pause when `PowerManager.isPowerSaveMode` is on, or when the battery is below 20% and not charging (`BatteryManager`).

**iOS:**
- `ProcessInfo.thermalState` with `thermalStateDidChangeNotification`: P3 runs only at `.nominal`, pauses at `.fair`, and everything stops at `.serious` and `.critical`.
- Pause when `ProcessInfo.isLowPowerModeEnabled` is true.

**Duty cycling, so the phone stays cool rather than just unthrottled:**
- After each P3 image, sleep 1–3× the time the inference took.
- Run P3 on the NPU/ANE when available (best performance per watt). Otherwise use 1–2 CPU threads at background priority.
- P0 and P1 may use all accelerators.

**When the app goes to the background (v1: stop; results persist and work resumes on the next open):**
- Optional later "Colorize whole book while charging": a WorkManager `OneTimeWorkRequest` with `setRequiresCharging(true)` and `setRequiresBatteryNotLow(true)`. One worker run is limited to ~10 min, so chain workers.
- A foreground service of type `mediaProcessing` (Android 15+) is limited to 6 h per 24 h and must handle `Service.onTimeout`. Avoid it.
- iOS: `BGProcessingTaskRequest(requiresExternalPower: true)` runs when the system decides. iOS 26 `BGContinuedProcessingTask` handles user-started jobs, but background GPU works only on iPad (Apple DTS reply). Backgrounding an app with GPU work in flight can crash it (whisper.cpp issue).

### 5.6 Keeping the UI at 60/120 fps
- Never run inference or full-image work on the UI thread.
  - Android: `Process.THREAD_PRIORITY_BACKGROUND` on the worker, or `Dispatchers.Default.limitedParallelism(1)`.
  - iOS: QoS `.utility` for P0/P1 and `.background` for P3.
  - Web: a Web Worker with OffscreenCanvas.
- **Avoid GPU contention:** the GPU also draws the UI.
  - Background work goes to the NPU (QNN/ANE) or the CPU.
  - On Apple platforms set Core ML `computeUnits = .cpuAndNeuralEngine` for P3.
  - If the GPU must be used, keep each submission small (SR tiles of ~4–6 ms) and **pause the queue during scroll, fling and page-turn animations**. Resume after ~300–500 ms of idle.
- **Limit CPU threads** (ORT `intra_op_num_threads`): 2 for background work, 4 for P0, so the big cores stay available for rendering.
- Decode with hardware bitmaps for display. Reuse tensor buffers. Swap the result in atomically. Because the result has the same size, there is no relayout and no jank.

### 5.7 Model download
- **AI packs are optional downloads.**
  - Before downloading, show the size and license.
  - Wi-Fi only by default. Downloads are resumable and checked against a SHA-256 manifest.
  - Store them in no-backup app storage. Each model can be deleted on its own.
- **Hosting:** Apache, MIT and BSD weights can be re-hosted with LICENSE and NOTICE, on a Hugging Face model repo or GitHub Releases (2 GB per file).
- **Google Play:** "Play for On-device AI" AI packs are still beta. Reported limits are 1.5 GB per pack and 4 GB total (unverified). F-Droid builds must use the direct download.

### 5.8 Benchmark gate before committing (because many speed numbers above are est.)
1. **Test set:** ~30 pages. Use CC-licensed color comics such as Pepper&Carrot (CC BY 4.0), converted to grayscale, so ground truth exists. Add screentone-heavy B&W pages we are allowed to use, and a few photos.
2. **Metrics:**
   - Colorizers (DDColor-tiny, DDColor-artistic on desktop, and mc2 locally for reference only, never shipped): mean ΔE (CIEDE2000) against ground truth plus a blind preference vote.
   - Upscalers: visual check on screentones (moiré) and text edges.
3. **Devices:** one low-end Mali phone, one mid-range MediaTek phone, one Snapdragon 8-series phone, one iPhone, one desktop.
4. **Decision rules:**
   - If DDColor-tiny on CPU is > 5 s per page on the mid-range phone, use a 384² input for P3.
   - If neural SR on the Mali GPU through ORT (CPU only there) is unusable but ncnn Vulkan gives < 2 s per page, add ncnn as the Android GPU backend for SR only.

---

## 6. Existing apps and prior art

- **Mihon Upscale** (github.com/HaoweiLi97/mihon_img_upscale, Apache-2.0, v1.3.17 released 2026-11-01). This is the closest prior art.
  - A Mihon fork with Vulkan GPU via ncnn, a Qualcomm NPU backend (QNN/HTP v69–v81, FP16 DLCs compiled on device and cached), and a MediaTek NPU backend (LiteRT/NeuroPilot, untested).
  - Models: Real-CUGAN, Real-ESRGAN animevideov3 and general-x4v3, waifu2x, SPAN NomosUni and others.
  - Visible pages get priority over preloads. Results are cached, with the filter settings included in the cache key. If the NPU fails, the original image stays readable.
  - **It has no colorization.**
- **manga-image-translator** (github.com/zyddnys/manga-image-translator, GPL-3.0, active 2026-10). It has an mc2 colorizer, mirrors the mc2 weights in its releases, and includes ESRGAN and waifu2x upscalers. Cotrans (cotrans.touhou.ai) is its hosted demo.
- **FlamboyantEntertainment/manga-colorizer** (GPL-3.0, 2026-10): a self-hosted Docker web app plus a browser extension using mc2. Weights download from the manga-image-translator mirror on first run. It asked the author for permission in issue #44, still unanswered.
- **BinitDOX/Manga-Colorizer** (MIT): a browser extension plus a self-hosted mc2 server on the LAN.
- **Komx: Comic Reader & Colorizer** (Android, first released 2026-04-30). The listing claims local ONNX and TensorFlow colorization and a PRO subscription. The models are undisclosed and ~800 installs are reported (unverified).
- **MangaColorizerPro** (Firefox add-on, v1.0.2 2025-12) and **Chromanga** (Chrome extension, claims fully on-device). Neither discloses its models (unverified).
- **Mihon / Tachiyomi:** no colorization extension found in the official app or its extensions.

---

## 7. Sources

Colorization
- DDColor: https://github.com/piddnad/DDColor · model zoo https://github.com/piddnad/DDColor/blob/master/MODEL_ZOO.md · pipeline https://github.com/piddnad/DDColor/blob/master/ddcolor/pipeline.py · weights https://huggingface.co/piddnad/ddcolor_paper_tiny · paper https://arxiv.org/abs/2212.11613
- DDColor on Qualcomm AI Hub (sizes, NPU timings, v0.66.0): https://huggingface.co/qualcomm/DDColor · https://aihub.qualcomm.com/models/ddcolor
- DDColor Core ML: https://huggingface.co/mlboydaisuke/DDColor-Tiny-CoreML · conversion notes https://github.com/john-rocky/CoreML-Models
- manga-colorization-v2: https://github.com/qweasdd/manga-colorization-v2 · license issues https://github.com/qweasdd/manga-colorization-v2/issues/13 · /issues/41 · /issues/44
- mc2 ONNX re-uploads (license claims invalid): https://huggingface.co/Faridzar/manga-colorization-v2-onnx · https://huggingface.co/ifritraen/manga-colorization-v2-fp32 · https://huggingface.co/Tinigon/manga-colorizer-onnx
- WACV 2025 manga colorization paper (Golyadkin et al.): https://openaccess.thecvf.com/content/WACV2025/html/Golyadkin_Closing_the_Domain_Gap_in_Manga_Colorization_via_Aligned_Paired_WACV_2025_paper.html
- Manga Light Colorizer: https://huggingface.co/sharky172/manga-light-colorizer
- Sana Manga Coloring: https://huggingface.co/masterofaudio2077/sana-manga-coloring · https://huggingface.co/masterofaudio2077/sana-manga-coloring-onnx-int8
- DeOldify: https://github.com/jantic/DeOldify
- BigColor: https://github.com/KIMGEONUNG/BigColor
- Zhang colorization: https://github.com/richzhang/colorization
- ColorMNet: https://github.com/yyang181/colormnet
- MangaNinja: https://github.com/ali-vilab/MangaNinjia · https://arxiv.org/abs/2501.08332
- Cobra: https://github.com/zhuang2002/Cobra · https://huggingface.co/JunhaoZhuang/Cobra
- ColorFlow: https://github.com/TencentARC/ColorFlow
- FLUX.2 klein manga LoRA: https://huggingface.co/thedeoxen/FLUX.2-klein-9B-manga-colorization-by-reference-LORA · base https://huggingface.co/black-forest-labs/FLUX.2-klein-base-9B
- Style2Paints: https://github.com/lllyasviel/style2paints
- AnimeColorDeOldify: https://github.com/Dakini/AnimeColorDeOldify

Upscaling and shaders
- Real-ESRGAN: https://github.com/xinntao/Real-ESRGAN · releases https://github.com/xinntao/Real-ESRGAN/releases · anime video model doc https://github.com/xinntao/Real-ESRGAN/blob/master/docs/anime_video_model.md · ncnn https://github.com/xinntao/Real-ESRGAN-ncnn-vulkan
- Qualcomm AI Hub SR cards: https://huggingface.co/qualcomm/Real-ESRGAN-General-x4v3 · https://huggingface.co/qualcomm/Real-ESRGAN-x4plus · https://huggingface.co/qualcomm/QuickSRNetSmall · https://huggingface.co/qualcomm/XLSR · https://huggingface.co/qualcomm/SESR-M5
- Real-CUGAN: https://github.com/bilibili/ailab/tree/main/Real-CUGAN · https://github.com/nihui/realcugan-ncnn-vulkan
- waifu2x: https://github.com/nagadomi/waifu2x · https://github.com/nagadomi/nunif · https://github.com/nihui/waifu2x-ncnn-vulkan
- APISR: https://github.com/Kiteretsu77/APISR
- SPAN: https://github.com/hongyuanyu/SPAN
- OpenModelDB (licenses per model): https://openmodeldb.info · data https://github.com/OpenModelDB/open-model-database
- MangaJaNai: https://github.com/the-database/MangaJaNai
- spandrel (load community SR architectures): https://github.com/chaiNNer-org/spandrel
- Anime4K: https://github.com/bloc97/Anime4K · WebGPU port https://github.com/Anime4KWebBoost/Anime4K-WebGPU · Metal port https://github.com/imxieyi/Anime4KMetal · Anime4KCPP (GPL) https://github.com/TianZerL/Anime4KCPP
- FSR 1: https://github.com/GPUOpen-Effects/FidelityFX-FSR · CAS https://github.com/GPUOpen-Effects/FidelityFX-CAS
- Snapdragon GSR: https://github.com/SnapdragonGameStudios/snapdragon-gsr

Filters
- page_dewarp: https://github.com/mzucker/page_dewarp · UVDoc: https://github.com/tanguymagne/UVDoc

Runtimes
- ONNX Runtime releases: https://github.com/microsoft/onnxruntime/releases (v1.31.0 notes: CoreML device selection, ACL deprecation) · EPs https://onnxruntime.ai/docs/execution-providers/ · NNAPI EP https://onnxruntime.ai/docs/execution-providers/NNAPI-ExecutionProvider.html · WebGPU EP https://onnxruntime.ai/docs/execution-providers/WebGPU-ExecutionProvider.html · Maven https://repo1.maven.org/maven2/com/microsoft/onnxruntime/
- NNAPI deprecation and migration: https://developer.android.com/ndk/guides/neuralnetworks/migration-guide
- LiteRT: https://github.com/google-ai-edge/LiteRT/releases/tag/v2.3.0 · overview https://developers.google.com/edge/litert/overview · Maven group https://dl.google.com/android/maven2/com/google/ai/edge/litert/group-index.xml · litert-torch https://github.com/google-ai-edge/litert-torch
- ncnn: https://github.com/Tencent/ncnn
- MNN: https://github.com/alibaba/MNN
- ExecuTorch: https://github.com/pytorch/executorch

Platform background-work and thermal APIs
- Android Thermal API (ADPF): https://developer.android.com/games/optimize/adpf/thermal
- Android FGS timeouts (dataSync / mediaProcessing 6 h per 24 h): https://developer.android.com/develop/background-work/services/fgs/timeout
- iOS BGContinuedProcessingTask GPU limits: https://developer.apple.com/forums/thread/816774 · entitlement https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.background-tasks.continued-processing.gpu · crash report https://github.com/ggml-org/whisper.cpp/issues/3531
- Play for On-device AI (beta): https://developer.android.com/google/play/on-device-ai

Prior art
- Mihon Upscale fork: https://github.com/HaoweiLi97/mihon_img_upscale · Mihon https://github.com/mihonapp/mihon
- manga-image-translator: https://github.com/zyddnys/manga-image-translator
- FlamboyantEntertainment manga-colorizer: https://github.com/FlamboyantEntertainment/manga-colorizer
- BinitDOX Manga-Colorizer: https://github.com/BinitDOX/Manga-Colorizer
- Komx (AppGoblin listing): https://appgoblin.info/apps/com.cosmomime.komxreader
- MangaColorizerPro: https://addons.mozilla.org/firefox/addon/mangacolorizerpro/
- Chromanga: https://www.chromeboard.com/extension/chromanga-ai-manga-colori-hbichaopnldpkigehphmopeanhgofbek

Cloud fallback
- Gemini API pricing (read 2026-11-10): https://aistudio.google.com/docs/pricing
- Replicate DDColor: https://replicate.com/piddnad/ddcolor
