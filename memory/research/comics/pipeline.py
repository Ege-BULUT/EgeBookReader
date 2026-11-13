# Whole offline balloon pipeline: det -> group -> rec -> translate. Prints every intermediate output.
# usage: pipeline.py <C> <image> <en|ja>
import sys, re, time
sys.path.insert(0, sys.argv[1] + '/scripts')
from ocr import session, load_rgb, detect, recognize, load_dict, group, join_lines
from translate import Marian
C, img, lang = sys.argv[1], sys.argv[2], sys.argv[3]
D, U = f'{C}/dl', f'{C}/../models-to-upload'

def sentence_case(s):
    """All-caps comic lettering -> sentence case (Opus-MT translates ALL CAPS badly)."""
    if re.search('[a-z]', s) or not re.search('[A-Z]', s): return s
    s = s.lower()
    s = re.sub(r"(^|[.!?]\s+)([a-z])", lambda m: m.group(1) + m.group(2).upper(), s)
    return re.sub(r"\bi\b", "I", s)

def sentences(s):
    """Opus-MT drops sentences when fed several at once: split after . ! ? 。 ！ ？ when the next char starts a sentence."""
    return [x for x in re.split(r'(?<=[.!?。！？])\s*(?=[A-Z"\u3000-\u9fff\uff00-\uffef])', s) if x.strip()]

def tr_all(m, s):
    t0 = time.perf_counter(); out = ' '.join(m.translate(x)[0] for x in sentences(s)); return out, 1000 * (time.perf_counter() - t0)

det = session(f'{D}/ocr/ch_PP-OCRv5_det_mobile.onnx')
rk = 'en_PP-OCRv5_rec_mobile' if lang == 'en' else 'ch_PP-OCRv5_rec_mobile'
rec, chars = session(f'{D}/ocr/{rk}.onnx'), load_dict(f'{D}/ocr/{rk}_dict.txt')
en_tr = Marian(f'{U}/opus-mt-tiny-en-tr.encoder.int8.onnx', f'{U}/opus-mt-tiny-en-tr.decoder.int8.onnx', f'{U}/opus-mt-tiny-en-tr.tokenizer.json')
if lang == 'ja':
    ja_en = Marian(f'{D}/xen-ja-en/onnx/encoder_model_quantized.onnx', f'{D}/xen-ja-en/onnx/decoder_model_quantized.onnx', f'{U}/opus-mt-ja-en.tokenizer.json')
    ja_tr = Marian(f'{U}/opus-mt-ja-tr.encoder.int8.onnx', f'{U}/opus-mt-ja-tr.decoder.int8.onnx', f'{U}/opus-mt-ja-tr.tokenizer.json')

rgb = load_rgb(img)
T0 = time.perf_counter()
boxes, det_ms, shp = detect(det, rgb, limit_type='max', limit_side=1280)
print(f'# {img.split("/")[-1]} {rgb.shape[1]}x{rgb.shape[0]} lang={lang} rec={rk}')
print(f'det input {shp[3]}x{shp[2]} {det_ms:.0f} ms, {len(boxes)} boxes (thresh 0.3, box_thresh 0.6, unclip 1.5)')
lines = []
for b in boxes:
    t, c, ms, xs = recognize(rec, rgb, b, chars)
    lines.append((b, t, c))
H = sorted(b[3] - b[1] if (b[3] - b[1]) < 1.5 * (b[2] - b[0]) else b[2] - b[0] for b, _, _ in lines)
med = H[len(H) // 2] if H else 0
keep = []
for b, t, c in sorted(lines, key=lambda l: (l[0][1], l[0][0])):
    thick = min(b[2] - b[0], b[3] - b[1])
    ok = c >= 0.6 and t.strip() and thick >= 0.5 * med and re.search(r'\w', t)
    print(f'  box [{b[0]:.0f},{b[1]:.0f},{b[2]:.0f},{b[3]:.0f}] det {b[4]:.2f}  rec {t!r} {c:.2f}' + ('' if ok else '  -> dropped'))
    if ok: keep.append((b, t))
print(f'kept {len(keep)} lines (rec conf >= 0.6, thickness >= 0.5 x median {med:.0f}px, has a letter/digit)')
for n, (ids, vertical) in enumerate(group([b for b, _ in keep])):
    text = join_lines([keep[i][1] for i in ids], vertical)
    bb = [min(keep[i][0][k] for i in ids) if k < 2 else max(keep[i][0][k] for i in ids) for k in range(4)]
    print(f'\n balloon {n + 1} [{bb[0]:.0f},{bb[1]:.0f},{bb[2]:.0f},{bb[3]:.0f}] {"vertical" if vertical else "horizontal"} {len(ids)} lines')
    print(f'   text   : {text!r}')
    if lang == 'en':
        src = sentence_case(text)
        if src != text: print(f'   cased  : {src!r}')
        print(f'   split  : {sentences(src)}')
        tr, ms = tr_all(en_tr, src); print(f'   en->tr : {tr!r}  ({ms:.0f} ms)')
        if src != text: tr2, _ = tr_all(en_tr, text); print(f'   (raw ALL CAPS en->tr: {tr2!r})')
    else:
        print(f'   split  : {sentences(text)}')
        en, ms1 = tr_all(ja_en, text); print(f'   ja->en : {en!r}  ({ms1:.0f} ms)')
        tr, ms2 = tr_all(en_tr, en); print(f'   ja->en->tr : {tr!r}  ({ms2:.0f} ms)')
        tr3, ms3 = tr_all(ja_tr, text); print(f'   ja->tr direct : {tr3!r}  ({ms3:.0f} ms)')
print(f'\npage total {1000 * (time.perf_counter() - T0):.0f} ms (2 threads, this Mac)')
