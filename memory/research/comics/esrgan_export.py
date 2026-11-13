# Export Real-ESRGAN realesr-animevideov3 (SRVGGNetCompact, BSD-3) to ONNX with dynamic H/W, then benchmark.
import sys, time, torch, numpy as np, onnxruntime as ort
from torch import nn
from torch.nn import functional as F
from PIL import Image
C = sys.argv[1]  # comics-models dir
class SRVGGNetCompact(nn.Module):  # copied from realesrgan/archs/srvgg_arch.py (num_feat=64,num_conv=16,x4,prelu)
    def __init__(s, num_in_ch=3, num_out_ch=3, num_feat=64, num_conv=16, upscale=4):
        super().__init__(); s.upscale = upscale
        s.body = nn.ModuleList([nn.Conv2d(num_in_ch, num_feat, 3, 1, 1), nn.PReLU(num_feat)])
        for _ in range(num_conv): s.body += [nn.Conv2d(num_feat, num_feat, 3, 1, 1), nn.PReLU(num_feat)]
        s.body.append(nn.Conv2d(num_feat, num_out_ch * upscale * upscale, 3, 1, 1)); s.up = nn.PixelShuffle(upscale)
    def forward(s, x):
        out = x
        for m in s.body: out = m(out)
        return s.up(out) + F.interpolate(x, scale_factor=s.upscale, mode='nearest')
m = SRVGGNetCompact()
sd = torch.load(f'{C}/dl/esrgan/realesr-animevideov3.pth', map_location='cpu', weights_only=True)
sd = sd.get('params', sd.get('params_ema', sd))
m.load_state_dict(sd); m.eval()
out = f'{C}/../models-to-upload/realesr-animevideov3-x4.onnx'
torch.onnx.export(m, torch.rand(1, 3, 64, 64), out, input_names=['input'], output_names=['output'], opset_version=17,
                  dynamic_axes={'input': {0: 'n', 2: 'h', 3: 'w'}, 'output': {0: 'n', 2: 'h4', 3: 'w4'}}, dynamo=False)
so = ort.SessionOptions(); so.intra_op_num_threads = 2; so.inter_op_num_threads = 1
s = ort.InferenceSession(out, so, providers=['CPUExecutionProvider'])
print('inputs', [(i.name, i.shape, i.type) for i in s.get_inputs()], 'outputs', [(o.name, o.shape, o.type) for o in s.get_outputs()])
x = torch.rand(1, 3, 128, 128)
with torch.no_grad(): ref = m(x).numpy()
y = s.run(None, {'input': x.numpy()})[0]; print('128 tile out', y.shape, 'max|torch-ort|', float(np.abs(ref - y).max()))
t = []
for _ in range(5): t0 = time.perf_counter(); s.run(None, {'input': x.numpy()}); t.append(time.perf_counter() - t0)
print('ms per 128x128 tile (2 threads, median of 5): %.1f' % (1000 * sorted(t)[2]))
page = Image.open(f'{C}/../wt/comics/app/assets/onboarding/compare-manga-orig.jpg').convert('RGB')
page = page.resize((500, round(page.height * 500 / page.width)), Image.BICUBIC); page.save(f'{C}/out/page_500.png')
a = np.asarray(page, np.float32).transpose(2, 0, 1)[None] / 255.0
t0 = time.perf_counter(); y = s.run(None, {'input': a})[0]; dt = time.perf_counter() - t0
print('whole page', a.shape, '->', y.shape, 'ms %.0f' % (1000 * dt))
# tiled (128 tiles + 18 px halo = receptive field of the 18 3x3 convs, so tiles are exact), as the app would do on a phone
T, P = 128, 18; H, W = a.shape[2:]; o = np.zeros((1, 3, H * 4, W * 4), np.float32); t0 = time.perf_counter(); n = 0
for y0 in range(0, H, T):
    for x0 in range(0, W, T):
        ya, xa, yb, xb = max(y0 - P, 0), max(x0 - P, 0), min(y0 + T + P, H), min(x0 + T + P, W)
        r = s.run(None, {'input': a[:, :, ya:yb, xa:xb]})[0]; n += 1
        h, w = min(T, H - y0), min(T, W - x0)
        o[:, :, y0*4:(y0+h)*4, x0*4:(x0+w)*4] = r[:, :, (y0-ya)*4:(y0-ya+h)*4, (x0-xa)*4:(x0-xa+w)*4]
print('tiled page %d tiles ms %.0f, max|tiled-whole| %.4f' % (n, 1000 * (time.perf_counter() - t0), float(np.abs(o - y).max())))
Image.fromarray((np.clip(o[0].transpose(1, 2, 0), 0, 1) * 255 + 0.5).astype(np.uint8)).save(f'{C}/out/page_upscaled_x4.png')
