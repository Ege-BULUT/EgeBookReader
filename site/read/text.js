// Reflowable books: one chapter at a time, laid out in CSS columns, a column (or two, side by side) per screen.
// A place in the book is a chapter and a character offset in it, so it survives a new font size or window.

const SNAP = 'transform .34s cubic-bezier(.22,.8,.3,1)';

export class TextReader {
  constructor(root, book, hooks) {
    this.book = book; this.hooks = hooks;
    this.root = root;
    root.innerHTML = '<div class="tr-view"><div class="tr-flow"></div></div>';
    this.view = root.firstChild; this.flow = this.view.firstChild;
    // Hyphenation needs a language; a book that names none is taken to be in the reader's own.
    this.flow.lang = book.lang || document.documentElement.lang || 'en'; this.flow.dir = book.dir || 'ltr';
    this.chapter = -1; this.page = 0; this.pages = 1;
    this.texts = []; // chapter plain text, made when first needed
    this.lengths = book.chapters.map(c => textOf(c.html).length);
    this.total = this.lengths.reduce((a, b) => a + b, 0) || 1;
    this.before = []; let s = 0; for (const l of this.lengths) { this.before.push(s); s += l; }
    this.flow.addEventListener('click', e => {
      const a = e.target.closest('a');
      if (!a) return;
      e.preventDefault(); e.stopPropagation();
      if (a.dataset.chapter != null) this.goAnchor(+a.dataset.chapter, a.dataset.anchor || null, true);
      else if (/^https?:/.test(a.getAttribute('href') || '')) open(a.href, '_blank', 'noopener');
    });
    this.ro = new ResizeObserver(() => { clearTimeout(this.rt); this.rt = setTimeout(() => this.relayout(), 120); });
    this.ro.observe(root);
  }

  destroy() { this.ro.disconnect(); this.stopSpeech?.(); CSS.highlights?.delete('ebr-hit'); CSS.highlights?.delete('ebr-tts'); }

  apply(s) {
    const st = this.root.style;
    st.setProperty('--fs', s.fontSize + 'px');
    st.setProperty('--lh', s.lineHeight);
    st.setProperty('--ff', FONTS[s.font] || FONTS.serif);
    st.setProperty('--ta', s.justify ? 'justify' : 'start');
    st.setProperty('--mx', [16, 28, 56][s.margin] + 'px');
    this.spreadSetting = s.spread;
    this.relayout();
  }

  // ---- layout --------------------------------------------------------------------------------------------
  geometry() {
    const r = this.root.getBoundingClientRect();
    const mx = parseFloat(getComputedStyle(this.root).getPropertyValue('--mx')) || 28;
    const two = this.spreadSetting === 2 || (this.spreadSetting !== 1 && r.width >= 900 && r.width > r.height * 1.1);
    const n = two ? 2 : 1, gap = Math.round(mx * 2);
    const avail = Math.min(r.width - mx * 2, two ? 1500 : 760);
    const col = Math.floor((avail - (n - 1) * gap) / n);
    const w = col * n + gap * (n - 1);
    const h = Math.floor(r.height - (r.width < 600 ? 92 : 104));
    return { n, gap, col, w, h, step: w + gap };
  }

  async render(chapter) {
    this.chapter = chapter;
    this.flow.innerHTML = this.book.chapters[chapter].html + '<span class="tr-end"></span>';
    for (const img of this.flow.querySelectorAll('img')) img.loading = 'eager';
    await this.measure();
  }

  async measure() {
    const g = this.g = this.geometry();
    Object.assign(this.view.style, { width: g.w + 'px', height: g.h + 'px' });
    Object.assign(this.flow.style, { width: g.w + 'px', height: g.h + 'px', columnWidth: g.col + 'px', columnGap: g.gap + 'px' });
    this.root.style.setProperty('--ph', g.h + 'px');
    const imgs = [...this.flow.querySelectorAll('img')].filter(i => !i.complete);
    if (imgs.length) await Promise.race([Promise.all(imgs.map(i => i.decode().catch(() => {}))), new Promise(r => setTimeout(r, 1500))]);
    await document.fonts?.ready;
    const end = this.flow.querySelector('.tr-end');
    this.pages = Math.max(1, Math.floor(this.xOf(end.getBoundingClientRect()) / g.step) + 1);
  }

  // Where a rect sits in the flow, from its start edge, whatever the flow is moved by now.
  xOf(rect) { const f = this.flow.getBoundingClientRect(); return this.book.dir === 'rtl' ? f.right - rect.right : rect.left - f.left; }

  // The place is the first character of the page as last shown: a new font or window keeps that character on screen.
  async relayout() {
    if (this.chapter < 0) return;
    const off = this.here ?? 0, my = this.lay = (this.lay || 0) + 1;
    await this.measure();
    // The same character stays the place, so several changes in a row do not drift back page by page.
    if (my === this.lay) { this.show(this.pageOfOffset(off), false); this.here = off; }
  }

  show(page, animate, from) {
    this.page = Math.max(0, Math.min(this.pages - 1, page));
    const f = this.flow.style;
    f.transition = animate ? SNAP : 'none';
    f.transform = `translateX(${-this.page * this.g.step * (this.book.dir === 'rtl' ? -1 : 1)}px)`;
    if (from != null) {
      this.flow.animate([{ opacity: 0, translate: (from > 0 ? 40 : -40) + 'px 0' }, { opacity: 1, translate: '0 0' }], { duration: 260, easing: 'ease-out' });
    }
    this.here = this.offset();
    this.hooks.onMove?.(this.info());
  }

  // ---- places --------------------------------------------------------------------------------------------
  textNodes() {
    const w = document.createTreeWalker(this.flow, NodeFilter.SHOW_TEXT), out = [];
    let at = 0;
    for (let n; (n = w.nextNode());) { out.push([n, at]); at += n.length; }
    return out;
  }
  // The first character on the page shown now.
  offset() {
    if (this.chapter < 0) return 0;
    // Only text that is drawn: the line breaks between blocks have no box, and would break the search.
    const nodes = this.textNodes().filter(([n]) => /\S/.test(n.data)), x0 = this.page * this.g.step;
    const range = document.createRange();
    const xAt = (node, i) => { range.setStart(node, i); range.setEnd(node, Math.min(node.length, i + 1)); const r = range.getClientRects()[0]; return r ? this.xOf(r) : null; };
    let lo = 0, hi = nodes.length - 1, best = nodes.length;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1, [n] = nodes[mid];
      const x = n.length ? xAt(n, n.length - 1) : null;
      if (x != null && x >= x0 - 1) { best = mid; hi = mid - 1; } else lo = mid + 1;
    }
    if (best >= nodes.length) return this.lengths[this.chapter];
    const [n, at] = nodes[best];
    let a = 0, b = n.length - 1;
    while (a < b) { const m = (a + b) >> 1, x = xAt(n, m); if (x != null && x >= x0 - 1) b = m; else a = m + 1; }
    return at + a;
  }
  pageOfOffset(off) {
    if (off <= 0) return 0;
    // From an offset in blank text between blocks, the next drawn character.
    for (const [n, at] of this.textNodes()) if (at + n.length > off) { const i = n.data.slice(Math.max(0, off - at)).search(/\S/); if (i >= 0) { off = Math.max(off, at) + i; break; } }
    const r = this.rangeAt(off, 1);
    const rect = r?.getClientRects()[0];
    return rect ? Math.floor((this.xOf(rect) + 1) / this.g.step) : (off >= this.lengths[this.chapter] ? this.pages - 1 : 0);
  }
  rangeAt(off, len) {
    const nodes = this.textNodes();
    const find = o => { for (const [n, at] of nodes) if (o < at + n.length || n === nodes.at(-1)?.[0]) return [n, Math.min(n.length, Math.max(0, o - at))]; return null; };
    const s = find(off), e = find(off + len);
    if (!s || !e) return null;
    const r = document.createRange(); r.setStart(...s); r.setEnd(...e);
    return r;
  }

  info() {
    const ch = this.chapter, off = this.here ?? this.offset();
    const percent = Math.min(1, (this.before[ch] + off) / this.total);
    let title = '';
    for (const t of this.book.toc) if (t.chapter <= ch) title = t.title;
    const atEnd = ch === this.book.chapters.length - 1 && this.page === this.pages - 1;
    return { chapter: ch, page: this.page, pages: this.pages, offset: off, percent: atEnd ? 1 : percent, title, atEnd };
  }
  position() { return { chapter: this.chapter, offset: this.here ?? 0 }; }

  // ---- moving --------------------------------------------------------------------------------------------
  async open(pos) {
    const ch = Math.max(0, Math.min(this.book.chapters.length - 1, pos?.chapter || 0));
    await this.render(ch);
    this.show(this.pageOfOffset(pos?.offset || 0), false);
  }
  async next() {
    if (this.page < this.pages - 1) return this.show(this.page + 1, true);
    if (this.chapter < this.book.chapters.length - 1) { await this.render(this.chapter + 1); this.show(0, false, 1); }
    else this.show(this.page, true);
  }
  async prev() {
    if (this.page > 0) return this.show(this.page - 1, true);
    if (this.chapter > 0) { await this.render(this.chapter - 1); this.show(this.pages - 1, false, -1); }
    else this.show(0, true);
  }
  async goPercent(p) {
    const target = p * this.total;
    let ch = this.before.findLastIndex(b => b <= target);
    if (ch < 0) ch = 0;
    if (ch !== this.chapter) await this.render(ch);
    this.show(this.pageOfOffset(Math.round(target - this.before[ch])), false);
  }
  async goAnchor(ch, anchor, flash) {
    if (ch !== this.chapter) await this.render(ch);
    const el = anchor && this.flow.querySelector('#' + CSS.escape(anchor));
    this.show(el ? Math.floor((this.xOf(el.getBoundingClientRect()) + 1) / this.g.step) : 0, false, flash ? 1 : null);
  }
  // Follows a finger: dx in pixels, done=true when it lets go.
  drag(dx, done, velocity = 0) {
    const sign = this.book.dir === 'rtl' ? -1 : 1, base = -this.page * this.g.step * sign;
    if (!done) { this.flow.style.transition = 'none'; this.flow.style.transform = `translateX(${base + dx * .9}px)`; return; }
    const far = Math.abs(dx) > this.g.w * .18 || Math.abs(velocity) > .45;
    if (far && dx * sign < 0) this.next(); else if (far && dx * sign > 0) this.prev(); else this.show(this.page, true);
  }

  // ---- search --------------------------------------------------------------------------------------------
  text(ch) { return this.texts[ch] ??= textOf(this.book.chapters[ch].html); }
  search(q, max = 300) {
    const hits = [], needle = fold(q);
    if (needle.length < 2) return hits;
    for (let ch = 0; ch < this.book.chapters.length && hits.length < max; ch++) {
      const t = this.text(ch), f = fold(t);
      for (let i = f.indexOf(needle); i >= 0 && hits.length < max; i = f.indexOf(needle, i + needle.length)) {
        hits.push({ chapter: ch, offset: i, length: needle.length, before: t.slice(Math.max(0, i - 40), i), match: t.slice(i, i + needle.length), after: t.slice(i + needle.length, i + needle.length + 60) });
      }
    }
    return hits;
  }
  async goHit(h) {
    if (h.chapter !== this.chapter) await this.render(h.chapter);
    const r = this.rangeAt(h.offset, h.length);
    if (r && CSS.highlights) CSS.highlights.set('ebr-hit', new Highlight(r));
    this.show(this.pageOfOffset(h.offset), false, 1);
  }
  clearHit() { CSS.highlights?.delete('ebr-hit'); }

  // ---- reading aloud with the browser's voices -----------------------------------------------------------
  speak(rate, voiceName, onState) {
    const synth = speechSynthesis;
    this.stopSpeech();
    let stopped = false, ch = this.chapter, off = this.offset();
    const seg = typeof Intl.Segmenter === 'function' ? new Intl.Segmenter(this.book.lang || undefined, { granularity: 'sentence' }) : null;
    const sentences = (t, from) => {
      const out = [];
      if (seg) for (const s of seg.segment(t.slice(from))) out.push([from + s.index, s.segment]);
      else for (const m of t.slice(from).matchAll(/[^.!?…]+[.!?…]*\s*/g)) out.push([from + m.index, m[0]]);
      return out.filter(([, s]) => s.trim());
    };
    const voice = () => { const vs = synth.getVoices(); return vs.find(v => v.name === voiceName) || vs.find(v => this.book.lang && v.lang.toLowerCase().startsWith(this.book.lang.slice(0, 2).toLowerCase())) || null; };
    let queue = sentences(this.text(ch), off), i = 0;
    const say = async () => {
      if (stopped) return;
      if (i >= queue.length) {
        if (ch >= this.book.chapters.length - 1) { onState(false); return this.stopSpeech(); }
        ch++; await this.render(ch); this.show(0, false, 1); queue = sentences(this.text(ch), 0); i = 0;
      }
      const [at, s] = queue[i];
      if (this.chapter !== ch) { await this.render(ch); }
      const r = this.rangeAt(at, s.trimEnd().length);
      if (r && CSS.highlights) CSS.highlights.set('ebr-tts', new Highlight(r));
      const p = this.pageOfOffset(at);
      if (p !== this.page) this.show(p, true);
      const u = new SpeechSynthesisUtterance(s);
      u.rate = rate; u.lang = this.book.lang || document.documentElement.lang;
      const v = voice(); if (v) u.voice = v;
      u.onend = () => { i++; say(); };
      u.onerror = e => { if (e.error !== 'interrupted' && e.error !== 'canceled') { i++; say(); } };
      synth.speak(u);
    };
    this.stopSpeech = () => { stopped = true; synth.cancel(); CSS.highlights?.delete('ebr-tts'); this.stopSpeech = () => {}; onState(false); };
    onState(true);
    say();
  }
  stopSpeech() {}
}

export const FONTS = {
  serif: 'Newsreader, "Iowan Old Style", Georgia, serif',
  sans: '"IBM Plex Sans", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  classic: 'Georgia, "Times New Roman", serif',
  mono: 'ui-monospace, Menlo, Consolas, monospace',
};

function textOf(html) { const t = document.createElement('template'); t.innerHTML = html; return t.content.textContent; }
// Case and Turkish dotted/dotless i folded, same length as the input so offsets still match.
function fold(s) { return s.replace(/[İIı]/g, 'i').toLowerCase(); }
