# PP-OCRv5 det + rec with plain numpy pre/post-processing (written to be ported to Dart line by line).
import math, time, numpy as np, onnxruntime as ort
from collections import deque
from PIL import Image

def session(path, threads=2):
    so = ort.SessionOptions(); so.intra_op_num_threads = threads; so.inter_op_num_threads = 1
    return ort.InferenceSession(path, so, providers=['CPUExecutionProvider'])

def load_rgb(path):
    return np.asarray(Image.open(path).convert('RGB'))  # HxWx3 uint8 RGB

# ---------------- detection ----------------
DET_MEAN = np.array([0.485, 0.456, 0.406], np.float32)
DET_STD = np.array([0.229, 0.224, 0.225], np.float32)

def det_preprocess(rgb, limit_side=960, limit_type='max'):
    h, w = rgb.shape[:2]
    if limit_type == 'max':   # shrink so the long side <= limit_side (never enlarge)
        r = min(1.0, limit_side / max(h, w))
    else:                     # 'min': enlarge so the short side >= limit_side (PaddleOCR 3.x default 64)
        r = max(1.0, limit_side / min(h, w))
    rh = max(32, int(round(h * r / 32)) * 32); rw = max(32, int(round(w * r / 32)) * 32)
    img = np.asarray(Image.fromarray(rgb).resize((rw, rh), Image.BILINEAR), np.float32)
    bgr = img[:, :, ::-1] / 255.0                      # model was trained on BGR
    x = (bgr - DET_MEAN) / DET_STD                     # mean/std applied in B,G,R channel order as listed
    return x.transpose(2, 0, 1)[None].astype(np.float32), (h / rh, w / rw)

def components(binary):
    """4-connected components by BFS. Returns list of (ys, xs) pixel index lists."""
    H, W = binary.shape; seen = np.zeros_like(binary, bool); out = []
    for y0, x0 in zip(*np.nonzero(binary)):
        if seen[y0, x0]: continue
        q = deque([(y0, x0)]); seen[y0, x0] = True; ys = []; xs = []
        while q:
            y, x = q.popleft(); ys.append(y); xs.append(x)
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < H and 0 <= nx < W and binary[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True; q.append((ny, nx))
        out.append((ys, xs))
    return out

def det_postprocess(prob, scale, thresh=0.3, box_thresh=0.6, unclip_ratio=1.5, min_size=3):
    """prob: HxW float map. Returns boxes [x0,y0,x1,y1,score] in original image pixels."""
    boxes = []
    for ys, xs in components(prob > thresh):
        x0, x1, y0, y1 = min(xs), max(xs) + 1, min(ys), max(ys) + 1
        w, h = x1 - x0, y1 - y0
        if min(w, h) < min_size: continue
        score = float(prob[ys, xs].mean())             # mean prob over the component's own pixels
        if score < box_thresh: continue
        d = w * h * unclip_ratio / (2 * (w + h))       # DB unclip distance for a rectangle: area*ratio/perimeter
        sy, sx = scale
        boxes.append([max(0, (x0 - d) * sx), max(0, (y0 - d) * sy), (x1 + d) * sx, (y1 + d) * sy, score])
    return boxes

def detect(sess, rgb, **kw):
    x, scale = det_preprocess(rgb, **{k: kw.pop(k) for k in list(kw) if k.startswith('limit')})
    t0 = time.perf_counter(); prob = sess.run(None, {'x': x})[0][0, 0]; ms = 1000 * (time.perf_counter() - t0)
    H, W = rgb.shape[:2]
    b = [[min(x0, W), min(y0, H), min(x1, W), min(y1, H), s] for x0, y0, x1, y1, s in det_postprocess(prob, scale, **kw)]
    return b, ms, x.shape

# ---------------- recognition ----------------
def load_dict(path):
    lines = open(path, encoding='utf-8').read().split('\n')
    if lines and lines[-1] == '': lines.pop()          # trailing newline only
    return lines

def rec_preprocess(crop_rgb, H=48, min_w=320):
    h, w = crop_rgb.shape[:2]
    if h / w >= 1.5: crop_rgb = np.rot90(crop_rgb); h, w = w, h   # vertical text: rotate 90 deg counter-clockwise
    rw = max(1, int(math.ceil(H * w / h)))
    W = max(min_w, rw)                                 # pad to at least 320 px wide like PaddleOCR
    img = np.asarray(Image.fromarray(np.ascontiguousarray(crop_rgb)).resize((rw, H), Image.BILINEAR), np.float32)
    x = (img[:, :, ::-1] / 255.0 - 0.5) / 0.5          # BGR, [-1,1]
    out = np.zeros((1, 3, H, W), np.float32); out[0, :, :, :rw] = x.transpose(2, 0, 1)  # right pad with 0
    return out

def ctc_decode(probs, chars):
    """probs: T x C. class 0 = blank, 1..N = chars[i-1], N+1 = ' '."""
    idx = probs.argmax(1); text = []; conf = []; prev = -1
    for t, i in enumerate(idx):
        if i != prev and i != 0:
            text.append(chars[i - 1] if i <= len(chars) else ' '); conf.append(probs[t, i])
        prev = i
    return ''.join(text), float(np.mean(conf)) if conf else 0.0

def recognize(sess, rgb, box, chars):
    x0, y0, x1, y1 = [int(round(v)) for v in box[:4]]
    x = rec_preprocess(rgb[y0:y1, x0:x1])
    t0 = time.perf_counter(); p = sess.run(None, {'x': x})[0][0]; ms = 1000 * (time.perf_counter() - t0)
    t, c = ctc_decode(p, chars)
    return t, c, ms, x.shape

# ---------------- grouping into balloons ----------------
def group(boxes, grow=0.6):
    """Union boxes whose rects, grown by grow*min(w,h) (~ half a line height) on each side, overlap."""
    n = len(boxes); parent = list(range(n))
    def find(i):
        while parent[i] != i: parent[i] = parent[parent[i]]; i = parent[i]
        return i
    def grown(b):
        g = grow * min(b[2] - b[0], b[3] - b[1]); return b[0] - g, b[1] - g, b[2] + g, b[3] + g
    G = [grown(b) for b in boxes]
    for i in range(n):
        for j in range(i + 1, n):
            a, b = G[i], G[j]
            if a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]: parent[find(i)] = find(j)
    groups = {}
    for i in range(n): groups.setdefault(find(i), []).append(i)
    out = []
    for ids in groups.values():
        vertical = sum((boxes[i][3] - boxes[i][1]) / max(1, boxes[i][2] - boxes[i][0]) >= 1.5 for i in ids) * 2 > len(ids)
        ids.sort(key=(lambda i: -boxes[i][0]) if vertical else (lambda i: boxes[i][1]))  # columns R->L, lines T->B
        out.append((ids, vertical))
    out.sort(key=lambda g: (min(boxes[i][1] for i in g[0])))  # balloons in page order: top to bottom
    return out

def join_lines(lines, vertical):
    if vertical: return ''.join(lines)
    s = ''
    for l in lines:
        l = l.strip()
        if not l: continue
        if s.endswith('-') and len(s) > 1 and s[-2].isalpha(): s = s[:-1] + l   # de-hyphenate across lines
        elif s and (ord(s[-1]) >= 0x3000 or ord(l[0]) >= 0x3000): s += l           # CJK: no space between lines
        else: s = (s + ' ' + l) if s else l
    return s
