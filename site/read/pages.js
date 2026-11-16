// Comics, fixed-layout books and PDFs: pages as pictures. Turns with the app's page curl (WebGL 2, same shader
// as the site), two pages side by side on a wide screen, pinch zoom, and webtoons as one long strip.
/* global CURL_FRAG */

const KEEP = 7; // pages kept decoded on each side of the one shown

export class PageReader {
  constructor(root, book, hooks) {
    this.book = book; this.hooks = hooks; this.root = root;
    root.innerHTML = '<div class="pg-stage"><div class="pg-zoom"><div class="pg-spread"></div></div><canvas class="pg-curl"></canvas></div><div class="pg-strip" hidden></div>';
    this.stage = root.querySelector('.pg-stage'); this.zoomEl = root.querySelector('.pg-zoom');
    this.spread = root.querySelector('.pg-spread'); this.canvas = root.querySelector('.pg-curl');
    this.strip = root.querySelector('.pg-strip');
    this.sizes = []; this.cache = new Map(); this.tex = new Map();
    this.at = 0; this.views = []; this.zoom = { s: 1, x: 0, y: 0 };
    this.s = { spread: 0, fit: 'page', scroll: 0, turn: 'curl', rtl: book.rtl };
    this.ro = new ResizeObserver(() => { clearTimeout(this.rt); this.rt = setTimeout(() => this.layout(true), 100); });
    this.ro.observe(root);
    this.gestures();
  }
  destroy() {
    this.ro.disconnect(); this.io?.disconnect();
    for (const c of this.cache.values()) if (c.url) URL.revokeObjectURL(c.url);
    this.cache.clear();
    if (this.gl) { this.gl.getExtension('WEBGL_lose_context')?.loseContext(); }
  }

  apply(s) {
    const scrollWas = this.scrolling;
    Object.assign(this.s, s);
    this.root.style.setProperty('--pg-bg', s.bg || '#111');
    this.layout(scrollWas !== this.isScroll());
  }
  isScroll() { return this.s.scroll === 2 || (this.s.scroll === 0 && this.webtoon); }

  // ---- pictures ------------------------------------------------------------------------------------------
  aspect(i) { const z = this.sizes[i]; return z ? z[1] / z[0] : (this.book.aspect || this.guess || 1.42); }
  load(i, width) {
    if (i < 0 || i >= this.book.count) return Promise.resolve(null);
    const hit = this.cache.get(i);
    if (hit && (this.book.format !== 'pdf' || !width || hit.width >= width)) return hit.p;
    const p = (async () => {
      const src = await this.book.page(i, width);
      let el;
      if (src instanceof Blob) {
        const url = URL.createObjectURL(src);
        el = new Image(); el.decoding = 'async'; el.src = url; el.draggable = false; el.alt = '';
        await el.decode().catch(() => {});
        const c = this.cache.get(i); if (c) c.url = url;
      } else el = src;
      const w = el.naturalWidth || el.width, h = el.naturalHeight || el.height;
      if (w && h) {
        const known = !!this.sizes[i];
        this.sizes[i] = [w, h];
        if (!known) this.sizeLearned(i, w, h);
      }
      return el;
    })();
    const old = hit;
    this.cache.set(i, { p, width: width || 0 });
    if (old?.url) p.then(() => URL.revokeObjectURL(old.url));
    p.catch(() => this.cache.delete(i));
    for (const [k, c] of this.cache) if (Math.abs(k - i) > KEEP * 2 && Math.abs(k - this.first()) > KEEP) { if (c.url) URL.revokeObjectURL(c.url); this.cache.delete(k); this.tex.delete(k); }
    return p;
  }
  sizeLearned(i, w, h) {
    if (!this.guess) this.guess = h / w;
    if (this.sizes.filter(Boolean).length === Math.min(4, this.book.count) && this.webtoon == null) {
      const tall = this.sizes.filter(Boolean).map(([a, b]) => b / a).sort((a, b) => a - b);
      this.webtoon = tall[tall.length >> 1] > 2.1;
      if (this.webtoon && this.s.scroll === 0) this.layout(true);
    }
    if (w > h * 1.15 && !this.isScroll()) { clearTimeout(this.lt); this.lt = setTimeout(() => this.layout(false), 50); }
  }

  // ---- views: which pages are on the screen together -----------------------------------------------------
  twoUp() {
    const r = this.root.getBoundingClientRect();
    if (this.s.spread === 1) return false;
    if (this.s.spread === 2) return true;
    return r.width > r.height * 1.05 && r.width >= 700 && this.aspect(this.first() || 1) > 1;
  }
  first() { return this.views[this.at]?.find(x => x != null) ?? 0; }
  buildViews() {
    const n = this.book.count, v = [];
    if (!this.two) { for (let i = 0; i < n; i++) v.push([null, i]); return v; }
    const wide = i => { const z = this.sizes[i]; return z && z[0] > z[1] * 1.15; };
    v.push([null, 0]);
    for (let i = 1; i < n;) {
      if (wide(i)) { v.push([i, 'wide']); i++; continue; }
      if (i + 1 < n && !wide(i + 1)) { v.push([i, i + 1]); i += 2; } else { v.push([i, null]); i++; }
    }
    return v;
  }
  viewOf(page) { return Math.max(0, this.views.findIndex(v => v.includes(page))); }

  layout(rebuild) {
    const keep = this.first();
    this.scrolling = this.isScroll();
    this.stage.hidden = this.scrolling; this.strip.hidden = !this.scrolling;
    if (this.scrolling) return this.buildStrip(keep);
    this.two = this.twoUp();
    this.views = this.buildViews();
    this.at = this.viewOf(keep);
    this.tex.clear();
    this.resetZoom();
    this.show();
  }

  geometry() {
    const r = this.stage.getBoundingClientRect();
    const a = this.aspect(this.views[this.at]?.find(x => typeof x === 'number') ?? 0);
    const cols = this.two ? 2 : 1;
    let pw, ph;
    if (this.s.fit === 'width' && !this.two) { pw = r.width; ph = pw * a; }
    else { pw = Math.min(r.width / cols, r.height / a); ph = pw * a; }
    return { W: pw * cols, H: ph, pw, ph, top: Math.max(0, (r.height - ph) / 2), left: (r.width - pw * cols) / 2 };
  }

  async show(fromDir = 0) {
    const v = this.views[this.at]; if (!v) return;
    const g = this.g = this.geometry();
    Object.assign(this.spread.style, { width: g.W + 'px', height: g.H + 'px', marginTop: g.top + 'px' });
    this.stage.classList.toggle('tall', g.H > this.stage.clientHeight + 1);
    const token = this.token = {};
    const slots = v[1] === 'wide' ? [['wide', v[0]]] : this.two ? [['l', v[0]], ['r', v[1]]] : [['one', v[1]]];
    const order = this.s.rtl ? slots.slice().reverse() : slots;
    const want = Math.ceil(g.pw * Math.min(2, devicePixelRatio || 1) * (v[1] === 'wide' ? 2 : 1));
    const els = await Promise.all(order.map(([, i]) => i == null ? null : this.load(i, this.book.format === 'pdf' ? want : 0).catch(() => null)));
    if (token !== this.token) return;
    this.spread.replaceChildren(...order.map(([k, i], n) => {
      const d = document.createElement('div');
      d.className = 'pg-slot ' + (k === 'wide' ? 'wide' : this.two ? ((n === 0) ? 'l' : 'r') : 'one');
      if (els[n]) d.append(els[n]);
      else if (i != null) d.classList.add('missing');
      return d;
    }));
    if (fromDir && this.s.turn !== 'none' && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      const dx = (this.s.rtl ? -1 : 1) * fromDir * 46;
      this.spread.animate([{ transform: `translateX(${dx}px)`, opacity: .35 }, { transform: 'none', opacity: 1 }], { duration: 240, easing: 'cubic-bezier(.22,.8,.3,1)' });
    }
    this.hooks.onMove?.(this.info());
    // Warm the pages on both sides so a turn never waits.
    for (const d of [1, -1, 2, -2]) for (const i of this.views[this.at + d] || []) if (typeof i === 'number') this.load(i, this.book.format === 'pdf' ? want : 0).catch(() => {});
    if (this.s.turn === 'curl') setTimeout(() => { if (token === this.token && !this.turn) { this.prepareCurl(1).catch(() => {}); this.prepareCurl(-1).catch(() => {}); } }, 120);
  }

  info() {
    const v = this.views[this.at] || [], nums = v.filter(x => typeof x === 'number');
    const page = nums[0] ?? 0, last = nums.at(-1) ?? 0;
    let title = '';
    for (const t of this.book.toc) if (t.page <= page) title = t.title;
    return { page, last, pages: this.book.count, percent: this.book.count > 1 ? last / (this.book.count - 1) : 1, title, atEnd: last >= this.book.count - 1 };
  }
  position() { return { page: this.first() }; }

  // ---- moving --------------------------------------------------------------------------------------------
  open(pos) { this.views = []; this.layout(true); this.goPage(pos?.page || 0); }
  goPage(p) {
    p = Math.max(0, Math.min(this.book.count - 1, p | 0));
    if (this.scrolling) return this.scrollTo(p);
    this.at = this.viewOf(p); this.resetZoom(); this.show();
  }
  goPercent(x) { this.goPage(Math.round(x * (this.book.count - 1))); }
  async next() { return this.step(1); }
  async prev() { return this.step(-1); }
  turnRight() { return this.step(this.s.rtl ? -1 : 1); }
  turnLeft() { return this.step(this.s.rtl ? 1 : -1); }
  async step(dir) {
    if (this.scrolling) { this.strip.scrollBy({ top: dir * this.strip.clientHeight * .85, behavior: 'smooth' }); return; }
    if (this.busy || this.turn) return;
    const to = this.at + dir;
    if (to < 0 || to >= this.views.length) { this.bump(dir); return; }
    if (this.zoom.s > 1.01) this.resetZoom();
    const tex = this.s.turn === 'curl' && await this.prepareCurl(dir);
    if (tex && this.beginTurn(dir, this.g.H * .93, tex)) {
      this.land(true, this.g.pw * 1.6);
      return;
    }
    this.at = to; this.show(dir);
  }
  bump(dir) { this.spread.animate([{ transform: 'none' }, { transform: `translateX(${(this.s.rtl ? 1 : -1) * dir * 14}px)` }, { transform: 'none' }], { duration: 260 }); if (dir > 0) this.hooks.onEnd?.(); }

  // ---- the curl ------------------------------------------------------------------------------------------
  initGL() {
    if (this.gl !== undefined) return this.gl;
    const gl = this.canvas.getContext('webgl2', { premultipliedAlpha: false, antialias: false });
    this.gl = gl || null;
    if (!gl || typeof CURL_FRAG === 'undefined') return (this.gl = null);
    const compile = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); return s; };
    const p = gl.createProgram();
    gl.attachShader(p, compile(gl.VERTEX_SHADER, `#version 300 es
      out vec2 v; void main(){ vec2 c=vec2((gl_VertexID<<1)&2, gl_VertexID&2); v=c; gl_Position=vec4(c.x*2.-1., 1.-c.y*2., 0.,1.); }`));
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, CURL_FRAG));
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) return (this.gl = null);
    gl.useProgram(p);
    this.uni = {};
    for (const n of ['uSize', 'uHinge', 'uPageW', 'uT', 'uR', 'uShowThrough', 'uN', 'uPaper', 'uFront', 'uBack', 'uUnder', 'uLeft']) this.uni[n] = gl.getUniformLocation(p, n);
    gl.bindVertexArray(gl.createVertexArray());
    gl.uniform1i(this.uni.uFront, 0); gl.uniform1i(this.uni.uBack, 1); gl.uniform1i(this.uni.uUnder, 2); gl.uniform1i(this.uni.uLeft, 3);
    return gl;
  }
  bg() { return hex(this.s.bg || '#111111'); }
  // A page drawn at its slot's size, as the shader wants it; mirrored in right-to-left books, since the
  // canvas is mirrored back.
  async texture(i, side) {
    const key = i + ':' + side;
    if (this.tex.has(key)) return this.tex.get(key);
    const gl = this.gl, g = this.g, dpr = Math.min(2, devicePixelRatio || 1);
    const c = document.createElement('canvas');
    c.width = Math.max(2, Math.round(g.pw * dpr)); c.height = Math.max(2, Math.round(g.ph * dpr));
    const x = c.getContext('2d');
    const [r, gg, b] = this.bg(); x.fillStyle = `rgb(${r},${gg},${b})`; x.fillRect(0, 0, c.width, c.height);
    if (i != null) {
      const el = await this.load(i, this.book.format === 'pdf' ? c.width : 0).catch(() => null);
      if (el) {
        const w = el.naturalWidth || el.width, h = el.naturalHeight || el.height, k = Math.min(c.width / w, c.height / h);
        const dw = w * k, dh = h * k;
        // Pages meet at the fold, as on paper.
        let dx = (c.width - dw) / 2;
        if (side === 'l') dx = c.width - dw; else if (side === 'r') dx = 0;
        if (this.s.rtl) { x.translate(c.width, 0); x.scale(-1, 1); dx = c.width - dx - dw; }
        x.drawImage(el, dx, (c.height - dh) / 2, dw, dh);
      }
    }
    const t = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, t);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, c);
    for (const [k, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, k, v);
    this.tex.set(key, t);
    return t;
  }
  // Logical (left-to-right) pages of a view: [left, right]; right-to-left books are the mirror image.
  sides(v) { if (!v || v[1] === 'wide') return null; return this.two ? [v[0], v[1]] : [null, v[1]]; }
  async prepareCurl(dir) {
    if (matchMedia('(prefers-reduced-motion: reduce)').matches || this.g.H > this.stage.clientHeight + 1) return false;
    if (!this.initGL()) return false;
    const base = dir > 0 ? this.at : this.at - 1, cur = this.sides(this.views[base]), next = this.sides(this.views[base + 1]);
    if (!cur || !next) return false;
    const side = this.two ? ['l', 'r'] : ['one', 'one'];
    const [cl, cr, nl, nr] = await Promise.all([this.texture(cur[0], side[0]), this.texture(cur[1], side[1]), this.texture(next[0], side[0]), this.texture(next[1], side[1])]);
    return { front: cr, back: this.two ? nl : cr, under: nr, left: cl };
  }
  beginTurn(dir, touchY, tex) {
    const gl = this.gl, g = this.g;
    if (!gl || this.turn || this.busy) return false;
    const m = { W: g.W, H: g.H, spread: this.two, hinge: this.two ? g.pw : 0, pageW: g.pw };
    const dpr = Math.min(2, devicePixelRatio || 1);
    const sr = this.spread.getBoundingClientRect(), st = this.stage.getBoundingClientRect();
    Object.assign(this.canvas.style, { left: sr.left - st.left + 'px', top: sr.top - st.top + 'px', width: g.W + 'px', height: g.H + 'px', transform: this.s.rtl ? 'scaleX(-1)' : 'none' });
    this.canvas.width = Math.round(g.W * dpr); this.canvas.height = Math.round(g.H * dpr);
    const bind = (u, t) => { gl.activeTexture(gl.TEXTURE0 + u); gl.bindTexture(gl.TEXTURE_2D, t); };
    bind(0, tex.front); bind(1, tex.back); bind(2, tex.under); bind(3, tex.left);
    const band = g.H * .2, corner = touchY < band || touchY > g.H - band;
    const y = touchY < band ? 0 : (touchY > g.H - band ? g.H : touchY);
    const grab = [m.hinge + m.pageW, y], turned = [m.hinge - m.pageW, y];
    this.turn = { dir, m, grab, turned, f: dir > 0 ? grab.slice() : turned.slice(), tilt: corner ? 1 : .22 };
    this.draw();
    this.canvas.style.visibility = 'visible';
    this.spread.style.visibility = 'hidden';
    return true;
  }
  draw() {
    const gl = this.gl, t = this.turn, u = this.uni;
    const { n, t: tt, r } = computeFold(t.grab, t.f, t.m.hinge, t.m.pageW, Math.min(t.m.pageW, t.m.H) * .14, t.tilt);
    gl.viewport(0, 0, this.canvas.width, this.canvas.height);
    gl.uniform2f(u.uSize, t.m.W, t.m.H);
    gl.uniform1f(u.uHinge, t.m.hinge); gl.uniform1f(u.uPageW, t.m.pageW);
    gl.uniform2f(u.uN, n[0], n[1]); gl.uniform1f(u.uT, tt); gl.uniform1f(u.uR, r);
    gl.uniform1f(u.uShowThrough, t.m.spread ? 0 : 1);
    gl.uniform3f(u.uPaper, ...hex(this.s.paper || '#f5f2ea').map(x => x / 255));
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }
  land(complete, velocity) {
    this.busy = true;
    const t = this.turn, toTurned = complete === (t.dir > 0);
    const from = t.f.slice(), to = (toTurned ? t.turned : t.grab).slice();
    const k = 260, w = Math.sqrt(k), span = Math.max(1, Math.hypot(to[0] - from[0], to[1] - from[1]));
    const v0 = Math.min(12, velocity / span), t0 = performance.now();
    const step = now => {
      const s = (now - t0) / 1000;
      const x = 1 - (1 + (w - v0) * s) * Math.exp(-w * s);
      const done = Math.abs(1 - x) < .002 || s > 2;
      const e = done ? 1 : Math.max(0, Math.min(1, x));
      t.f = clampFinger([from[0] + (to[0] - from[0]) * e, from[1] + (to[1] - from[1]) * e], t.grab, t.m.hinge, t.m.H);
      this.draw();
      if (done) return this.endTurn(complete);
      requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }
  async endTurn(complete) {
    const dir = this.turn.dir;
    this.turn = null;
    if (complete) this.at += dir;
    await this.show();
    this.spread.style.visibility = '';
    this.canvas.style.visibility = 'hidden';
    this.busy = false;
  }

  // ---- fingers, mouse and wheel --------------------------------------------------------------------------
  gestures() {
    const el = this.stage, pts = new Map();
    let press = null, pinch = null, lastTap = 0;
    const local = e => { const r = this.spread.getBoundingClientRect(); let x = e.clientX - r.left; if (this.s.rtl) x = r.width - x; return [x, e.clientY - r.top]; };
    el.addEventListener('pointerdown', e => {
      if (e.button > 0) return;
      el.setPointerCapture?.(e.pointerId);
      pts.set(e.pointerId, [e.clientX, e.clientY]);
      if (pts.size === 2) {
        const [a, b] = [...pts.values()];
        pinch = { d: Math.hypot(a[0] - b[0], a[1] - b[1]), s: this.zoom.s, cx: (a[0] + b[0]) / 2, cy: (a[1] + b[1]) / 2, x: this.zoom.x, y: this.zoom.y };
        if (this.turn && !this.busy) this.land(false, 0);
        press = null; return;
      }
      press = { x: e.clientX, y: e.clientY, l: local(e), id: e.pointerId, moved: false, samples: [], zx: this.zoom.x, zy: this.zoom.y, t: performance.now() };
    });
    el.addEventListener('pointermove', e => {
      if (!pts.has(e.pointerId)) return;
      pts.set(e.pointerId, [e.clientX, e.clientY]);
      if (pinch && pts.size === 2) {
        const [a, b] = [...pts.values()], d = Math.hypot(a[0] - b[0], a[1] - b[1]);
        const s = Math.max(1, Math.min(6, pinch.s * d / pinch.d));
        const cx = (a[0] + b[0]) / 2, cy = (a[1] + b[1]) / 2;
        this.setZoom(s, pinch.x + (cx - pinch.cx), pinch.y + (cy - pinch.cy), pinch.cx, pinch.cy, pinch.s, pinch.x, pinch.y);
        return;
      }
      if (!press || e.pointerId !== press.id) return;
      const dx = e.clientX - press.x, dy = e.clientY - press.y;
      press.samples.push([performance.now(), e.clientX]); if (press.samples.length > 6) press.samples.shift();
      if (Math.hypot(dx, dy) > 8) press.moved = true;
      if (this.zoom.s > 1.01) { this.panTo(press.zx + dx, press.zy + dy); return; }
      if (this.scrolling || this.busy) return;
      if (!this.turn && !press.drag) {
        if (Math.abs(dx) < 10 || Math.abs(dy) > Math.abs(dx) * 1.3) return;
        const ldx = this.s.rtl ? -dx : dx, dir = ldx < 0 ? 1 : -1;
        const to = this.at + dir;
        if (to < 0 || to >= this.views.length) { press.drag = 'none'; return; }
        press.drag = 'pending';
        const go = tex => { if (press && press.drag === 'pending') press.drag = tex && this.beginTurn(dir, press.l[1], tex) ? 'curl' : 'slide'; };
        if (this.s.turn === 'curl') this.prepareCurl(dir).then(go); else press.drag = 'slide';
        press.dir = dir;
      }
      if (this.turn && !this.busy) {
        const t = this.turn, ldx = this.s.rtl ? -dx : dx;
        const raw = t.dir > 0 ? [t.grab[0] + ldx, t.grab[1] + dy] : [t.turned[0] + ldx * (t.m.spread ? 1 : 2), press.l[1] + dy];
        t.f = clampFinger(raw, t.grab, t.m.hinge, t.m.H);
        this.draw();
      } else if (press.drag === 'slide') this.spread.style.transform = `translateX(${dx * .6}px)`;
    });
    const up = e => {
      if (!pts.has(e.pointerId)) return;
      pts.delete(e.pointerId);
      if (pinch) { if (pts.size < 2) { pinch = null; this.sharpen(); } press = null; return; }
      if (!press || e.pointerId !== press.id) return;
      const p = press; press = null;
      const sm = p.samples, dt = sm.length > 1 ? (sm.at(-1)[0] - sm[0][0]) / 1000 : 1;
      let vx = sm.length > 1 ? (sm.at(-1)[1] - sm[0][1]) / Math.max(dt, .001) : 0;
      if (this.turn && !this.busy) {
        if (this.s.rtl) vx = -vx;
        const m = this.turn.m, projected = this.turn.f[0] + vx * .18;
        const middle = this.turn.dir > 0 ? m.W * (m.spread ? .6 : .55) : (m.spread ? m.W * .4 : 0);
        const toward = projected < middle;
        this.land(this.turn.dir > 0 ? toward : !toward, Math.abs(vx));
        return;
      }
      if (p.drag === 'slide') {
        this.spread.style.transform = '';
        const dx = e.clientX - p.x;
        if (Math.abs(dx) > 60 || Math.abs(vx) > 500) { this.at += p.dir; this.show(p.dir); }
        return;
      }
      if (p.drag === 'pending') { if (Math.abs(e.clientX - p.x) > 40) this.step(p.dir); return; }
      if (p.moved) return;
      const now = performance.now();
      if (now - lastTap < 300 && !this.scrolling) { lastTap = 0; clearTimeout(this.tapT); this.doubleTap(e.clientX, e.clientY); return; }
      lastTap = now;
      const r = this.root.getBoundingClientRect(), fx = (e.clientX - r.left) / r.width;
      clearTimeout(this.tapT);
      this.tapT = setTimeout(() => {
        if (this.zoom.s > 1.01 || this.scrolling) return this.hooks.onCenter?.();
        if (fx < .3) this.turnLeft(); else if (fx > .7) this.turnRight(); else this.hooks.onCenter?.();
      }, this.scrolling ? 0 : 230);
    };
    el.addEventListener('pointerup', up); el.addEventListener('pointercancel', up);
    el.addEventListener('wheel', e => {
      if (e.ctrlKey) { e.preventDefault(); const s = Math.max(1, Math.min(6, this.zoom.s * Math.exp(-e.deltaY / 200))); this.zoomAt(s, e.clientX, e.clientY); clearTimeout(this.wz); this.wz = setTimeout(() => this.sharpen(), 250); return; }
      if (this.zoom.s > 1.01) { e.preventDefault(); this.panTo(this.zoom.x - e.deltaX, this.zoom.y - e.deltaY); return; }
      if (this.stage.classList.contains('tall')) return;
      e.preventDefault();
      const now = performance.now();
      if (now - (this.lastWheel || 0) < 420 || Math.abs(e.deltaY) + Math.abs(e.deltaX) < 12) return;
      this.lastWheel = now;
      this.step((Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY) > 0 ? 1 : -1);
    }, { passive: false });
    // The strip: tap in the middle for the menu.
    this.strip.addEventListener('click', () => this.hooks.onCenter?.());
  }

  // ---- zoom ----------------------------------------------------------------------------------------------
  setZoom(s, x, y, cx, cy, s0, x0, y0) {
    // Keep the point between the fingers where it was.
    const r = this.stage.getBoundingClientRect(), ox = cx - r.left - r.width / 2, oy = cy - r.top - r.height / 2;
    const k = s / s0;
    this.zoom.s = s;
    this.panTo(x0 * k + ox * (1 - k) + (x - x0), y0 * k + oy * (1 - k) + (y - y0));
  }
  zoomAt(s, cx, cy) { this.setZoom(s, this.zoom.x, this.zoom.y, cx, cy, this.zoom.s, this.zoom.x, this.zoom.y); }
  panTo(x, y) {
    const s = this.zoom.s, r = this.stage.getBoundingClientRect();
    const mx = Math.max(0, (this.g.W * s - r.width) / 2), my = Math.max(0, (this.g.H * s - r.height) / 2);
    this.zoom.x = s <= 1.001 ? 0 : Math.max(-mx, Math.min(mx, x));
    this.zoom.y = s <= 1.001 ? 0 : Math.max(-my, Math.min(my, y));
    if (s <= 1.001) this.zoom.s = 1;
    this.zoomEl.style.transform = this.zoom.s === 1 ? '' : `translate(${this.zoom.x}px,${this.zoom.y}px) scale(${this.zoom.s})`;
    this.stage.classList.toggle('zoomed', this.zoom.s > 1);
  }
  resetZoom() { this.zoom = { s: 1, x: 0, y: 0 }; this.zoomEl.style.transform = ''; this.stage.classList.remove('zoomed'); }
  doubleTap(cx, cy) {
    this.zoomEl.style.transition = 'transform .25s ease';
    if (this.zoom.s > 1.01) this.resetZoom(); else this.zoomAt(2.5, cx, cy);
    setTimeout(() => { this.zoomEl.style.transition = ''; this.sharpen(); }, 260);
  }
  // A zoomed PDF page is drawn again at the new size.
  async sharpen() {
    if (this.book.format !== 'pdf' || this.zoom.s < 1.3) return;
    const width = Math.ceil(this.g.pw * this.zoom.s * Math.min(2, devicePixelRatio || 1));
    const v = this.views[this.at] || [];
    for (const i of v) if (typeof i === 'number') this.cache.delete(i);
    const token = this.token;
    await Promise.all(v.filter(i => typeof i === 'number').map(i => this.load(i, width)));
    if (token === this.token) { const z = { ...this.zoom }; await this.show(); this.zoom = z; this.panTo(z.x, z.y); }
  }

  // ---- webtoon strip -------------------------------------------------------------------------------------
  buildStrip(keep) {
    this.io?.disconnect();
    const w = Math.min(this.strip.clientWidth || innerWidth, 900);
    const frag = document.createDocumentFragment();
    for (let i = 0; i < this.book.count; i++) {
      const d = document.createElement('div');
      d.className = 'pg-cell'; d.dataset.i = i; d.style.height = Math.round(w * this.aspect(i)) + 'px';
      frag.append(d);
    }
    this.strip.replaceChildren(frag);
    this.io = new IntersectionObserver(es => {
      for (const e of es) {
        const d = e.target, i = +d.dataset.i;
        if (e.isIntersecting && !d.firstChild) this.load(i, this.book.format === 'pdf' ? w * 2 : 0).then(el => {
          if (!el || d.firstChild) return;
          const c = el.cloneNode ? (el instanceof HTMLCanvasElement ? el : el.cloneNode()) : el;
          d.append(c); d.style.height = '';
        }).catch(() => {});
      }
    }, { root: this.strip, rootMargin: '150% 0px' });
    for (const d of this.strip.children) this.io.observe(d);
    this.strip.onscroll = () => {
      clearTimeout(this.st);
      this.st = setTimeout(() => {
        const top = this.strip.getBoundingClientRect().top + 4;
        let p = 0;
        for (const d of this.strip.children) { if (d.getBoundingClientRect().bottom > top) { p = +d.dataset.i; break; } }
        this.stripAt = p;
        this.hooks.onMove?.({ page: p, last: p, pages: this.book.count, percent: this.book.count > 1 ? p / (this.book.count - 1) : 1, title: '', atEnd: p >= this.book.count - 1 });
      }, 90);
    };
    requestAnimationFrame(() => this.scrollTo(keep));
  }
  scrollTo(p) { this.strip.children[p]?.scrollIntoView({ block: 'start' }); this.stripAt = p; this.strip.onscroll?.(); }
}

const hex = c => { const m = /^#?(..)(..)(..)$/.exec(c.length === 4 ? '#' + [...c.slice(1)].map(x => x + x).join('') : c); return m ? m.slice(1).map(h => parseInt(h, 16)) : [17, 17, 17]; };

// Same geometry as the app (lib/curl.dart) and the site.
const dot = (a, b) => a[0] * b[0] + a[1] * b[1];
function clampFinger(f, grab, hinge, h) {
  for (const anchor of [[hinge, 0], [hinge, h]]) {
    const max = Math.hypot(grab[0] - anchor[0], grab[1] - anchor[1]);
    const dx = f[0] - anchor[0], dy = f[1] - anchor[1], d = Math.hypot(dx, dy);
    if (d > max) f = [anchor[0] + dx / d * max, anchor[1] + dy / d * max];
  }
  return f;
}
function computeFold(grab, f, hinge, pageW, maxR, maxTilt) {
  const dx = grab[0] - f[0], dy = grab[1] - f[1], dist = Math.hypot(dx, dy);
  let n = dist < 1e-3 ? [1, 0] : [dx / dist, dy / dist];
  const tilt = Math.max(-maxTilt, Math.min(maxTilt, Math.atan2(n[1], Math.max(n[0], 1e-6))));
  n = [Math.cos(tilt), Math.sin(tilt)];
  const toEnd = Math.hypot(f[0] - (hinge - pageW), f[1] - grab[1]);
  const r = Math.max(.5, Math.min(maxR, dist / Math.PI, toEnd / 2));
  return { n, t: (dot(f, n) + dot(grab, n) - Math.PI * r) / 2, r };
}
