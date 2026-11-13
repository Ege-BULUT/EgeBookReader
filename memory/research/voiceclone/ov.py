# usage: python -I ov.py OPENVOICE_CODE_DIR CKPT_DIR SRC_WAV REF_WAV OUT_WAV
import sys, time, resource
code, ck, src, ref, out = sys.argv[1:6]
sys.path.append(code)
import torch, librosa, soundfile as sf
from openvoice import utils
from openvoice.models import SynthesizerTrn
from openvoice.mel_processing import spectrogram_torch
torch.set_num_threads(2)
t0 = time.time()
hps = utils.get_hparams_from_file(f"{ck}/converter/config.json")
m = SynthesizerTrn(0, hps.data.filter_length // 2 + 1, n_speakers=0, **hps.model).eval()
miss, unexp = m.load_state_dict(torch.load(f"{ck}/converter/checkpoint.pth", map_location="cpu")["model"], strict=False)
load = time.time() - t0
sr = hps.data.sampling_rate
def spec(path):
    y = torch.tensor(librosa.load(path, sr=sr)[0]).unsqueeze(0)
    return y.shape[1] / sr, spectrogram_torch(y, 1024, sr, 256, 1024, center=False)
@torch.no_grad()
def se(path):
    return m.ref_enc(spec(path)[1].transpose(1, 2)).unsqueeze(-1)
t0 = time.time(); tgt = se(ref); t_ref = time.time() - t0
t0 = time.time(); src_se = se(src); t_src = time.time() - t0
dur, s = spec(src)
with torch.no_grad():
    m.voice_conversion(s[:, :, :200], torch.LongTensor([200]), src_se, tgt, tau=0.3)  # warm-up
    t0 = time.time()
    o = m.voice_conversion(s, torch.LongTensor([s.size(-1)]), src_se, tgt, tau=0.3)[0][0, 0].numpy()
    dt = time.time() - t0
sf.write(out, o, sr)
print(f"openvoice-torch src={src.split('/')[-1]} ref={ref.split('/')[-1]} load={load:.2f}s missing={len(miss)} unexpected={len(unexp)} "
      f"se_ref={t_ref:.2f}s se_src={t_src:.2f}s audio={dur:.1f}s convert={dt:.2f}s RTF={dt/dur:.3f} peakRSS={resource.getrusage(resource.RUSAGE_SELF).ru_maxrss/2**20:.0f}MB")
