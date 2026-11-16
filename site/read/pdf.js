// PDF through pdf.js (vendor/pdfjs, Apache-2.0). Pages are drawn at the width the viewer asks for.
const base = new URL('./vendor/pdfjs/', import.meta.url).href;
const err = code => Object.assign(new Error(code), { code });

export async function openPdf(file) {
  const pdfjs = await import('./vendor/pdfjs/pdf.min.mjs');
  pdfjs.GlobalWorkerOptions.workerSrc = base + 'pdf.worker.min.mjs';
  let doc, task;
  try {
    task = pdfjs.getDocument({
      data: new Uint8Array(await file.arrayBuffer()),
      cMapUrl: base + 'cmaps/', cMapPacked: true, standardFontDataUrl: base + 'standard_fonts/', wasmUrl: base + 'wasm/',
      isEvalSupported: false, enableScripting: false,
    });
    doc = await task.promise;
  } catch (e) { throw err(e?.name === 'PasswordException' ? 'locked' : 'corrupt'); }
  const info = (await doc.getMetadata().catch(() => null))?.info || {};

  const toc = [];
  try {
    const walk = async (items, depth) => {
      for (const it of items || []) {
        let dest = it.dest;
        if (typeof dest === 'string') dest = await doc.getDestination(dest);
        if (Array.isArray(dest) && dest[0]) {
          const page = typeof dest[0] === 'number' ? dest[0] : await doc.getPageIndex(dest[0]);
          toc.push({ title: it.title, page, depth });
        }
        if (depth < 3) await walk(it.items, depth + 1);
      }
    };
    await walk(await doc.getOutline(), 0);
  } catch (e) {}

  const sizes = [];
  const first = await doc.getPage(1);
  const v0 = first.getViewport({ scale: 1 });
  // Drawn pages are kept for the few pages around the reader, at the largest width asked for.
  const cache = new Map();
  async function page(i, width = 1200) {
    width = Math.min(4096, Math.ceil(width / 256) * 256);
    const hit = cache.get(i);
    if (hit && hit.width >= width) return hit.canvas;
    const p = await doc.getPage(i + 1);
    const v = p.getViewport({ scale: 1 });
    sizes[i] = [v.width, v.height];
    const vp = p.getViewport({ scale: width / v.width });
    const canvas = document.createElement('canvas');
    canvas.width = Math.round(vp.width); canvas.height = Math.round(vp.height);
    const ctx = canvas.getContext('2d');
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, canvas.width, canvas.height);
    await p.render({ canvasContext: ctx, viewport: vp }).promise;
    p.cleanup();
    cache.set(i, { width, canvas });
    for (const k of cache.keys()) if (Math.abs(k - i) > 4) cache.delete(k);
    return canvas;
  }
  async function text(i) {
    const p = await doc.getPage(i + 1);
    return (await p.getTextContent()).items.map(t => t.str + (t.hasEOL ? '\n' : '')).join('');
  }
  return {
    kind: 'pages', format: 'pdf', manga: false, rtl: false,
    title: (/^(about:|https?:|untitled$)/i.test((info.Title || '').trim()) ? '' : (info.Title || '').trim()) || file.name.replace(/\.[^.]+$/, ''), author: (info.Author || '').trim(), lang: '',
    count: doc.numPages, toc, cover: null, aspect: v0.height / v0.width,
    page, text, coverPage: () => page(0, 400),
    dispose() { cache.clear(); task.destroy(); },
  };
}
