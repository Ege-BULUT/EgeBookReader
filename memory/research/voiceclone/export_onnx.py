# usage: python -I export_onnx.py OPENVOICE_CODE_DIR CKPT_DIR OUT_DIR
# Exports OpenVoice v2's tone colour converter as two ONNX graphs that take raw 22.05 kHz audio:
#   se.onnx: wave[1,T] -> speaker embedding [1,256,1]
#   vc.onnx: wave[1,T], src_se, tgt_se -> wave[1,1,T']   (tau fixed at 0.3)
import sys, torch, torch.nn.functional as F
code, ck, out = sys.argv[1:4]
sys.path.append(code)
from openvoice import utils
from openvoice.models import SynthesizerTrn
hps = utils.get_hparams_from_file(f"{ck}/converter/config.json")
m = SynthesizerTrn(0, 513, n_speakers=0, **hps.model).eval()
m.load_state_dict(torch.load(f"{ck}/converter/checkpoint.pth", map_location="cpu")["model"], strict=False)
m.dec.remove_weight_norm()
m.requires_grad_(False)
N, H = 1024, 256
basis = torch.view_as_real(torch.fft.fft(torch.eye(N)))[:N // 2 + 1].permute(2, 0, 1).reshape(-1, 1, N) * torch.hann_window(N)
def spec(y):  # conv STFT, same as OpenVoice's spectrogram_torch_conv (center=False)
    y = F.pad(y.unsqueeze(1), ((N - H) // 2, (N - H) // 2), mode="reflect")
    s = F.conv1d(y, basis, stride=H)
    return torch.sqrt(s[:, :N // 2 + 1] ** 2 + s[:, N // 2 + 1:] ** 2 + 1e-6)
class SE(torch.nn.Module):
    def __init__(self): super().__init__(); self.m = m
    def forward(self, wave): return self.m.ref_enc(spec(wave).transpose(1, 2)).unsqueeze(-1)
class VC(torch.nn.Module):
    def __init__(self): super().__init__(); self.m = m
    def forward(self, wave, src_se, tgt_se):
        s = spec(wave)
        return self.m.voice_conversion(s, torch.full((1,), s.size(2), dtype=torch.long), src_se, tgt_se, tau=0.3)[0]
w = torch.randn(1, 22050 * 3) * 0.1
g = torch.randn(1, 256, 1)
kw = dict(opset_version=17, dynamo=False)
torch.onnx.export(SE(), (w,), f"{out}/se.onnx", input_names=["wave"], output_names=["se"], dynamic_axes={"wave": {1: "T"}}, **kw)
torch.onnx.export(VC(), (w, g, g), f"{out}/vc.onnx", input_names=["wave", "src_se", "tgt_se"], output_names=["out"],
                  dynamic_axes={"wave": {1: "T"}, "out": {2: "T2"}}, **kw)
from onnxruntime.quantization import quantize_dynamic, QuantType
quantize_dynamic(f"{out}/vc.onnx", f"{out}/vc.int8.onnx", weight_type=QuantType.QInt8)
print("ok")
