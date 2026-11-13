# usage: python -I asr.py WHISPER_DIR OUT_DIR -> character error rate of every output wav (Whisper large-v3-turbo int8)
import sys, os, glob, re, unicodedata
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sherpa_onnx as so, librosa, numpy as np
from texts import TEXT
w, od = sys.argv[1:3]
def norm(s):
    s = unicodedata.normalize("NFC", s.replace("İ", "i").replace("I", "ı")).lower()
    return re.sub(r"[^\w]+", " ", s).strip()
def cer(a, b):
    p = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        c = [i]
        for j, cb in enumerate(b, 1): c.append(min(p[j] + 1, c[j - 1] + 1, p[j - 1] + (ca != cb)))
        p = c
    return p[-1] / len(a)
assert cer("abc", "abd") == 1 / 3
recs = {l: so.OfflineRecognizer.from_whisper(encoder=f"{w}/turbo-encoder.int8.onnx", decoder=f"{w}/turbo-decoder.int8.onnx",
        tokens=f"{w}/turbo-tokens.txt", language=l, num_threads=4) for l in ("tr", "en")}
for p in sorted(glob.glob(f"{od}/*.wav")):
    l = os.path.basename(p)[:2]; x = librosa.load(p, sr=16000)[0]
    iv = librosa.effects.split(x, top_db=40); cuts = [0] + [(a[1] + b[0]) // 2 for a, b in zip(iv[:-1], iv[1:])] + [len(x)]
    segs, s = [], 0
    for c, n in zip(cuts[1:-1], cuts[2:]):
        if n - s > 20 * 16000: segs.append((s, c)); s = c
    segs.append((s, len(x))); hyp = []
    for a, b in segs:
        st = recs[l].create_stream(); st.accept_waveform(16000, x[a:b]); recs[l].decode_stream(st); hyp.append(st.result.text)
    print(f"{os.path.basename(p):32s} CER={cer(norm(TEXT[l]), norm(' '.join(hyp))):.3f}  {' '.join(hyp)[:90]}")
