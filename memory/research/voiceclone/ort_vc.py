# usage: python -I ort_vc.py ONNX_DIR VC_FILE SRC_WAV REF_WAV OUT_WAV [whole|chunks]
# Runs the exported converter with plain ONNX Runtime (2 threads), no torch.
import sys, time, resource
import numpy as np, onnxruntime as ort, librosa, soundfile as sf
d, vcf, src, ref, out = sys.argv[1:6]; mode = sys.argv[6] if len(sys.argv) > 6 else "chunks"
o = ort.SessionOptions(); o.intra_op_num_threads = 2; o.inter_op_num_threads = 1
t0 = time.time()
se = ort.InferenceSession(f"{d}/se.onnx", o, providers=["CPUExecutionProvider"])
vc = ort.InferenceSession(f"{d}/{vcf}", o, providers=["CPUExecutionProvider"])
load = time.time() - t0
SR = 22050
ld = lambda p: librosa.load(p, sr=SR)[0].astype(np.float32)
x, r = ld(src), ld(ref)
t0 = time.time(); tgt = se.run(None, {"wave": r[None]})[0]; t_ref = time.time() - t0
src_se = se.run(None, {"wave": x[None]})[0]  # once per Supertonic voice in the app, so not timed
def pieces(x, maxlen=8 * SR):
    # cut at the middle of silent gaps, keeping chunks under ~8 s (a sentence each, as the app would send them)
    iv = librosa.effects.split(x, top_db=40, frame_length=1024, hop_length=256)
    cuts = [0] + [(a[1] + b[0]) // 2 for a, b in zip(iv[:-1], iv[1:])] + [len(x)]
    out, start = [], 0
    for c, nxt in zip(cuts[1:-1], cuts[2:]):
        if nxt - start > maxlen: out.append((start, c)); start = c
    return out + [(start, len(x))]
run = lambda w: vc.run(None, {"wave": w[None], "src_se": src_se, "tgt_se": tgt})[0][0, 0]
run(x[:SR * 2])  # warm-up
segs = [(0, len(x))] if mode == "whole" else pieces(x)
t0 = time.time(); y = np.concatenate([run(x[a:b]) for a, b in segs]); dt = time.time() - t0
sf.write(out, y, SR); dur = len(x) / SR
print(f"ort {vcf} {mode}({len(segs)}) src={src.split('/')[-1]} ref={ref.split('/')[-1]} load={load:.2f}s se_ref={t_ref:.2f}s "
      f"audio={dur:.1f}s convert={dt:.2f}s RTF={dt/dur:.3f} peakRSS={resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/2**20:.0f}MB")
