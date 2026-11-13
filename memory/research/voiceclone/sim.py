# usage: python -I sim.py REF_DIR OUT_DIR  -> resemblyzer cosine of every output wav against each reference
import sys, glob, os, numpy as np
from resemblyzer import VoiceEncoder, preprocess_wav
enc = VoiceEncoder("cpu", verbose=False)
emb = lambda p: enc.embed_utterance(preprocess_wav(p))
refs = {os.path.basename(p)[4:-4]: emb(p) for p in sorted(glob.glob(f"{sys.argv[1]}/ref_*.wav"))}
names = list(refs)
print(f"{'file':40s}" + "".join(f"{n:>16s}" for n in names))
print(f"{'(ref vs ref)':40s}" + "".join(f"{float(refs[names[0]] @ refs[n]):16.3f}" for n in names))
for p in sorted(glob.glob(f"{sys.argv[2]}/*.wav")):
    e = emb(p); print(f"{os.path.basename(p):40s}" + "".join(f"{float(e @ refs[n]):16.3f}" for n in names))
