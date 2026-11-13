# usage: python -I supertonic.py MODEL_DIR LANG OUT_WAV [SID]
import sys, time, resource, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sherpa_onnx as so, soundfile as sf, numpy as np
from texts import TEXT
d, lang, out = sys.argv[1:4]; sid = int(sys.argv[4]) if len(sys.argv) > 4 else 4
t0 = time.time()
mc = so.OfflineTtsModelConfig(num_threads=2, supertonic=so.OfflineTtsSupertonicModelConfig(
    f"{d}/duration_predictor.int8.onnx", f"{d}/text_encoder.int8.onnx", f"{d}/vector_estimator.int8.onnx",
    f"{d}/vocoder.int8.onnx", f"{d}/tts.json", f"{d}/unicode_indexer.bin", f"{d}/voice.bin"))
tts = so.OfflineTts(so.OfflineTtsConfig(model=mc)); load = time.time() - t0
def gen(text):
    g = so.GenerationConfig(); g.sid = sid; g.speed = 1.0; g.extra = {"lang": lang}
    return tts.generate(text, g)
gen("Kısa bir ısınma cümlesi." if lang == "tr" else "A short warm-up sentence.")
t0 = time.time(); a = gen(TEXT[lang]); dt = time.time() - t0
s = np.array(a.samples, dtype=np.float32); dur = len(s) / a.sample_rate
sf.write(out, s, a.sample_rate)
print(f"supertonic lang={lang} sid={sid} words={len(TEXT[lang].split())} load={load:.2f}s audio={dur:.1f}s synth={dt:.2f}s RTF={dt/dur:.3f} peakRSS={resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/2**20:.0f}MB")
