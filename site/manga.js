// Manga mode: the book's content as a manga volume, read right to left.
// Every word comes from T, FEATURES, CHANGES, PRIVACY, SHOTS, COMPARE and the page templates in index.html.
(() => {
const html = document.documentElement, host = $('#manga'), table = $('#table');
const tpl = id => $('#' + id).content;
const t = k => T[lang][k];
const ART = [
  ['Hokusai Manga 03', 'https://commons.wikimedia.org/wiki/File:Hokusai_Manga_03.jpg'],
  ['Hokusai Manga 04', 'https://commons.wikimedia.org/wiki/File:Hokusai_Manga_04.jpg'],
  ['Hokusai Manga 05', 'https://commons.wikimedia.org/wiki/File:Hokusai_Manga_05.jpg'],
  ['Hokusai sketches, vol. 6', 'https://commons.wikimedia.org/wiki/File:Hokusai_sketches_-_hokusai_manga_vol6.jpg'],
];
// Japanese lettering, so the font request carries only these glyphs.
const JP = '目次ドンバパラシーゴキャカチジャンッザワドキつづく右から左へ巻';

// ---- small builders ---------------------------------------------------------------------------------
function h(tag, cls, ...kids) {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  for (const k of kids.flat(9)) if (k != null && k !== false) e.append(k);
  return e;
}
const link = (href, ...kids) => { const a = h('a', '', ...kids); a.href = href; return a; };
const bal = (text, tail = 'bl', cls = '') => h('p', `bal t-${tail} ${text.length > 70 ? 'long' : ''} ${cls}`, text);
const cap = (cls, ...kids) => h('div', 'cap ' + cls, ...kids);
const ttl = (key, cls = '') => h('h2', 'ttl ' + cls, t(key));
const shout = (...kids) => h('div', 'shout', h('div', 'shout-in', ...kids));
const sfx = (jp, en, css) => { const e = h('div', 'sfx', h('b', '', jp), en && h('i', '', en)); e.setAttribute('aria-hidden', 'true'); e.style.cssText = css; return e; };
const img = (src, cls, pos) => { const i = h('img', cls); i.src = src; i.alt = ''; i.decoding = 'async'; i.draggable = false; if (pos) i.style.objectPosition = pos; return i; };
const shot = (name, pos) => { const i = img(`shots/${name}.jpg`, 'shot', pos); i.alt = name; return i; };
const hk = (name, cls = '', pos) => img(`manga/${name}.png`, 'hk ' + cls, pos);
function svg(viewBox, d, cls) {
  const s = document.createElementNS(NS, 'svg'); s.setAttribute('viewBox', viewBox); s.setAttribute('class', cls); s.setAttribute('aria-hidden', 'true');
  const p = document.createElementNS(NS, 'path'); p.setAttribute('d', d); p.setAttribute('fill', 'currentColor'); s.append(p);
  return s;
}
const sil = (scene, i, cls) => svg('0 0 512 512', SCENES[scene][i].d, 'sil ' + cls);
const logo = cls => svg('-4 -4 330 264', tpl('cover').querySelector('#logo path').getAttribute('d'), 'mlogo ' + cls);
const DL = () => tpl('cover').querySelector('.dl').getAttribute('href');
const dl = (key = 'download') => { const a = link(DL(), t(key)); a.className = 'mdl'; return a; };
const P = (w, s, o = {}) => ({ w, s, ...o });
const R = (hh, s, ...cols) => ({ h: hh, s, cols });

// ---- the volume: one entry per page ----------------------------------------------------------------
function volume() {
  const F = FEATURES[lang], C = CHANGES[lang], cover = tpl('cover');
  const box = h('div'); box.innerHTML = PRIVACY[lang];
  const pr = [...box.children];
  const words = [...cover.querySelectorAll('#title span')].map(s => s.textContent);
  const github = cover.querySelector('.ver a').href;
  const feat = ([a, b], tail) => [h('h3', 'tab', a), bal(b, tail)];
  const change = ([v, text]) => [h('h3', 'tab ver', v), cap('', text)];
  const toc = h('ol', 'mtoc', [...tpl('p1').querySelectorAll('[data-go] span')].map((s, i) => {
    const b = h('button', '', h('i', '', '#' + (i + 1)), h('span', '', t(s.dataset.t)), h('em', '', ''));
    b.dataset.sec = s.dataset.t;
    return h('li', '', b);
  }));
  const plat = tpl('p5').querySelector('.dltable').cloneNode(true); plat.className = 'mplat'; fill(plat);
  const src = tpl('p5').querySelector('p.small:last-child').cloneNode(true); fill(src);
  const links = [...tpl('p8').querySelectorAll('.linklist li')].map(li => { const c = li.cloneNode(true); fill(c); return c; });
  const lk = (i, tail) => [cap('ink', c(links[i].firstElementChild)), h('p', `bal t-${tail} lk`, c(links[i].lastElementChild))];
  function c(n) { return n.cloneNode(true); }

  return [
    { sec: 'cover', bleed: true, rows: [R(100, 0, P(100, 0, { cls: 'ink focus', at: 'mcover', bg: [sil('fantasy', 2, 'knight'), h('div', 'tone-band')],
      c: [h('div', 'vol', h('b', '', 'VOL.'), VERSION),
        logo('big'),
        h('h1', 'mtitle', words.map((w, i) => h('span', 'w' + i, w))),
        cap('mauthor', cover.querySelector('.author').textContent),
        shout(dl()),
        h('p', 'imp', t('version') + ' ' + VERSION + ' · ', link(github, 'GitHub')),
        h('p', 'rtl', h('b', '', '←'), ' 右から左へ · ' + t('rtl'))],
      fx: [sfx('ドン', 'DON', 'top:24%;left:6%;--r:-14deg;--s:3.2')] }))] },

    { sec: 'epigraph', rows: [
      R(56, 8, P(100, 0, { cls: 'ink stars', at: 'mid', bg: [h('div', 'glow'), openBook()], fx: [sfx('キラ', 'SHINE', 'top:6%;right:5%;--r:10deg;--s:2.2')] })),
      R(null, 0, P(58, -10, { cls: 'focus', at: 'mid', c: [bal(t('epigraph'), 'br', 'big'), cap('ink cite', 'Ege Bulut')] }), P(null, 0, { bg: [hk('dance', '', '50% 30%')] }))] },

    { sec: 'contents', rows: [
      R(18, 6, P(100, 0, { cls: 'speed', at: 'mid', c: [ttl('contents')], fx: [sfx('目次', '', 'top:12%;right:5%;--r:0deg;--s:2.4')] })),
      R(null, 0, P(62, 8, { cls: 'tone-b', c: [toc] }), P(null, 0, { cls: 'ink', bg: [hk('faces', 'inv', '0 0')] }))] },

    { sec: 'home', rows: [
      R(34, 7, P(58, 9, { cls: 'focus', at: 'mid', c: [ttl('home', 'sm'), bal(t('home1'), 'br', 'big')] }), P(null, 0, { bg: [shot('flip', '50% 45%')] })),
      R(36, -6, P(40, -7, { bg: [shot('book', '50% 30%')] }), P(null, 0, { cls: 'tone', at: 'mid', c: [bal(t('home2'), 'tl')] })),
      R(null, 0, P(60, 7, { cls: 'speed', at: 'mid', c: [cap('', t('home3'))] }), P(null, 0, { cls: 'ink focus', at: 'mid', c: [shout(dl())], fx: [sfx('バン', 'BAM', 'top:4%;left:6%;--r:-12deg;--s:1.8')] }))] },

    { sec: 'shots', rows: [
      R(13, 4, P(100, 0, { cls: 'speed', at: 'mid', c: [ttl('shots')], fx: [sfx('パシャ', 'SNAP', 'top:10%;left:5%;--r:-8deg;--s:1.9')] })),
      R(45, -5, ...SHOTS.slice(0, 4).map((s, i) => P(i < 3 ? 25 : null, i % 2 ? -5 : 5, { bg: [shot(s)] }))),
      R(null, 0, ...SHOTS.slice(4).map((s, i) => P(i < 2 ? 33 : null, i % 2 ? 6 : -6, { bg: [shot(s)] }))) ] },

    { sec: 'colorize', rows: [
      R(17, 4, P(100, 0, { cls: 'tone', at: 'mid', c: [ttl('colorize', 'sm'), cap('', t('colorNote'))] })),
      R(24, -4, ...COMPARE.slice(0, 3).map((s, i) => P(i < 2 ? 33 : null, 4, { bg: [shot(s, '50% 50%')] }))),
      R(null, 0, ...COMPARE.slice(3).map((s, i) => P(i < 2 ? 33 : null, -4, { bg: [shot(s, '50% 0')] }))) ] },

    { sec: 'features', rows: [
      R(12, 4, P(100, 0, { cls: 'speed', at: 'mid', c: [ttl('features')], fx: [sfx('キラーン', 'KIRAN', 'top:12%;left:4%;--r:-6deg;--s:1.7')] })),
      R(29, 6, P(55, 8, { cls: 'tone', c: feat(F[0], 'br') }), P(null, 0, { cls: 'focus', at: 'bot', c: feat(F[1], 'tl') })),
      R(29, -6, P(45, -7, { cls: 'ink', at: 'bot', bg: [sil('fantasy', 1, 'drag')], c: feat(F[2], 'tr') }), P(null, 0, { cls: 'speed-r', c: feat(F[3], 'bl') })),
      R(null, 0, P(58, 6, { cls: 'tone-b', c: feat(F[4], 'br') }), P(null, 0, { cls: 'focus', at: 'bot', c: feat(F[5], 'tl') }))] },

    { sec: 'features', rows: [
      R(34, -6, P(62, 7, { cls: 'focus', c: feat(F[6], 'bl') }), P(null, 0, { cls: 'ink', at: 'bot', bg: [hk('dance', 'inv faint', '50% 20%')], c: feat(F[7], 'tl') })),
      R(32, 6, P(40, -8, { cls: 'tone', at: 'bot', c: feat(F[8], 'tr') }), P(null, 0, { cls: 'speed', c: feat(F[9], 'bl') })),
      R(null, 0, P(52, 8, { cls: 'tone-b', c: feat(F[10], 'br') }), P(null, 0, { cls: 'focus', at: 'bot', c: feat(F[11], 'tl') }))] },

    { sec: 'features', rows: [
      R(30, 5, P(46, -6, { cls: 'speed-r', c: feat(F[12], 'br') }), P(null, 0, { cls: 'tone', c: feat(F[13], 'bl') })),
      R(36, -5, P(60, 7, { cls: 'focus', at: 'bot', c: feat(F[14], 'tr') }), P(null, 0, { cls: 'ink', at: 'bot', bg: [sil('scifi', 3, 'robot')], c: feat(F[15], 'tl') })),
      R(null, 0, P(42, -6, { cls: 'tone-b', c: feat(F[16], 'br') }), P(null, 0, { cls: 'speed', c: feat(F[17], 'bl') }))] },

    { sec: 'downloads', rows: [
      R(44, 8, P(58, 10, { cls: 'ink focus', at: 'mid', c: [ttl('downloads', 'sm'), shout(h('p', '', t('dl1')), dl('apk'))] }), P(null, 0, { bg: [hk('fight', '', '30% 10%')], fx: [sfx('バン', 'BAM', 'bottom:6%;right:6%;--r:12deg;--s:2.2')] })),
      R(28, -5, P(100, 0, { cls: 'tone', at: 'mid', c: [plat] })),
      R(null, 0, P(62, -7, { cls: 'speed', at: 'mid', c: [cap('', t('dl2')), cap('ink', [...src.childNodes])] }), P(null, 0, { cls: 'ink focus', fx: [sfx('ゴゴゴ', '', 'top:12%;left:14%;--r:-8deg;--s:2.3')] }))] },

    { sec: 'changelog', rows: [
      R(12, 4, P(100, 0, { cls: 'speed', at: 'mid', c: [ttl('changelog')], fx: [sfx('ジャーン', 'TA-DA', 'top:12%;left:4%;--r:-6deg;--s:1.7')] })),
      R(36, -5, P(100, 0, { cls: 'tone-b', c: change(C[0]) })),
      R(28, 5, P(100, 0, { cls: 'focus', c: change(C[1]) })),
      R(null, 0, P(64, -6, { cls: 'speed-r', c: change(C[2]) }), P(null, 0, { cls: 'ink', at: 'mid', c: [cap('', link(RELEASES, t('earlier')))] }))] },

    { sec: 'changelog', rows: [
      R(48, -6, P(64, 7, { cls: 'tone', c: [ttl('models', 'sm'), cap('', t('modelsText'))] }), P(null, 0, { cls: 'ink stars', bg: [sil('scifi', 2, 'ufo')] })),
      R(null, 0, P(36, -7, { bg: [hk('faces', '', '30% 0')] }), P(null, 0, { cls: 'speed-r', c: [ttl('credits', 'sm'), cap('', t('creditsText')),
        cap('art', t('mangaArt'), ' ', ART.map(([n, u], i) => [i ? ', ' : '', link(u, n)]), '.')] }))] },

    { sec: 'privacy', rows: [
      R(22, 6, P(56, 7, { cls: 'tone', at: 'mid', c: [ttl('privacy', 'sm')] }), P(null, 0, { cls: 'ink', bg: [hk('ghost', 'inv', '50% 12%')] })),
      R(25, -5, P(46, -6, { cls: 'speed', c: [cap('', pr[0])] }), P(null, 0, { cls: 'tone-b', c: [cap('', pr[1])] })),
      R(null, 0, P(100, 0, { cls: 'focus', c: [cap('', pr[2])], fx: [sfx('シーン', '', 'bottom:4%;right:4%;--r:0deg;--s:1.6')] }))] },

    { sec: 'privacy', rows: [
      R(34, 5, P(60, 7, { cls: 'tone', c: [cap('', pr[3])] }), P(null, 0, { cls: 'ink focus', fx: [sfx('カチッ', 'CLICK', 'top:30%;left:12%;--r:-10deg;--s:2')] })),
      R(30, -5, P(100, 0, { cls: 'speed-r', c: [cap('', pr[4])] })),
      R(null, 0, P(40, -7, { bg: [hk('ghost', '', '30% 85%')] }), P(null, 0, { cls: 'tone-b', at: 'mid', c: [cap('', pr[5])] }))] },

    { sec: 'links', rows: [
      R(14, 5, P(100, 0, { cls: 'speed', at: 'mid', c: [ttl('links')], fx: [sfx('ザワ', 'BUZZ', 'top:12%;left:5%;--r:-8deg;--s:1.9')] })),
      R(28, -5, P(50, -7, { cls: 'focus', at: 'mid', c: lk(0, 'tl') }), P(null, 0, { cls: 'tone', at: 'mid', c: lk(1, 'tr') })),
      R(26, 5, P(100, 0, { cls: 'speed-r', at: 'mid', c: lk(2, 'bl') })),
      R(null, 0, P(50, 7, { cls: 'tone-b', at: 'mid', c: lk(3, 'tr') }), P(null, 0, { cls: 'focus', at: 'mid', c: lk(4, 'tl') }))] },

    { sec: 'back', bleed: true, rows: [R(100, 0, P(100, 0, { cls: 'ink focus', at: 'mback', bg: [hk('ghost', 'inv faint', '50% 0')],
      c: [h('p', 'tsuzuku', 'つづく'), h('p', 'mend', t('end')), logo('tiny'), shout(dl()),
        h('p', 'imp', t('version') + ' ' + VERSION + ' · ', link(github, 'GitHub'), ' · ' + cover.querySelector('.author').textContent)] }))] },
  ];
}

// An open book giving off light, for the epigraph.
function openBook() {
  return svg('0 0 200 120', 'M100 30C80 18 46 14 14 20v84c32-6 66-2 86 10 20-12 54-16 86-10V20c-32-6-66-2-86 10zm-4 74C76 94 50 92 24 95V29c26-4 52-1 72 9zm8 0V38c20-10 46-13 72-9v66c-26-3-52-1-72 9z', 'obook');
}

// ---- cutting a page into panels ----------------------------------------------------------------------
// Rows run down the page and panels across each row, in reading order; boundaries may slant.
// The page is drawn left to right and then mirrored, so panels read from the right like a manga.
function page(pg, n, W, H) {
  const el = h('section', 'mp' + (pg.bleed ? ' bleed' : ''));
  el.style.width = W + 'px'; el.style.height = H + 'px';
  el.dataset.sec = pg.sec;
  const m = pg.bleed ? 0 : Math.round(W * .045), g = Math.max(6, Math.round(W * .017));
  const x0 = m, x1 = W - m, y0 = m, y1 = H - (pg.bleed ? 0 : Math.round(m * 1.7)), iw = x1 - x0, ih = y1 - y0;
  if (!pg.bleed) {
    const f = h('div', 'field'), b = Math.round(g * .7);
    Object.assign(f.style, { left: x0 - b + 'px', top: y0 - b + 'px', width: iw + 2 * b + 'px', height: ih + 2 * b + 'px' });
    el.append(f, h('span', 'mfolio', String(n)));
  }
  const frames = document.createElementNS(NS, 'svg');
  frames.setAttribute('class', 'frames'); frames.setAttribute('viewBox', `0 0 ${W} ${H}`);
  const across = (yl, yr) => { const b = (yr - yl) / iw; return { a: yl - b * x0, b }; };
  const yAt = (L, x) => L.a + L.b * x;
  const hit = (L, V) => { const x = (V.c + V.d * L.a) / (1 - V.d * L.b); return [x, L.a + L.b * x]; };
  const rest = list => 100 - list.reduce((s, r) => s + (r.h ?? r.w ?? 0), 0);
  const rows = pg.rows.map(r => ({ ...r, h: r.h ?? rest(pg.rows) }));
  const bounds = [across(y0, y0)];
  let cum = 0;
  rows.forEach((r, i) => {
    cum += r.h;
    const s = i < rows.length - 1 ? (r.s || 0) : 0, y = i < rows.length - 1 ? y0 + cum / 100 * ih : y1;
    bounds.push(across(y + s / 200 * ih, y - s / 200 * ih));
  });
  rows.forEach((r, i) => {
    const top = i ? { a: bounds[i].a + g / 2, b: bounds[i].b } : bounds[i];
    const bot = i < rows.length - 1 ? { a: bounds[i + 1].a - g / 2, b: bounds[i + 1].b } : bounds[i + 1];
    const yT = yAt(top, W / 2), yB = yAt(bot, W / 2);
    const cols = r.cols.map(p => ({ ...p, w: p.w ?? rest(r.cols) }));
    const vb = [{ c: x0, d: 0 }];
    let cc = 0;
    cols.forEach((p, j) => {
      cc += p.w;
      if (j === cols.length - 1) return vb.push({ c: x1, d: 0 });
      const xT = x0 + (cc + (p.s || 0) / 2) / 100 * iw, xB = x0 + (cc - (p.s || 0) / 2) / 100 * iw, d = (xB - xT) / (yB - yT);
      vb.push({ c: xT - d * yT, d });
    });
    cols.forEach((p, j) => {
      const L = j ? { c: vb[j].c + g / 2, d: vb[j].d } : vb[j];
      const Rt = j < cols.length - 1 ? { c: vb[j + 1].c - g / 2, d: vb[j + 1].d } : vb[j + 1];
      let pts = [hit(top, L), hit(top, Rt), hit(bot, Rt), hit(bot, L)];
      let safe = [Math.max(pts[0][0], pts[3][0]), Math.max(pts[0][1], pts[1][1]), Math.min(pts[1][0], pts[2][0]), Math.min(pts[2][1], pts[3][1])];
      pts = pts.map(([x, y]) => [W - x, y]);
      safe = [W - safe[2], safe[1], W - safe[0], safe[3]];
      panel(el, frames, p, pts, safe);
    });
  });
  el.append(frames);
  return el;
}

function panel(el, frames, p, pts, [l, t, r, b]) {
  const xs = pts.map(q => q[0]), ys = pts.map(q => q[1]);
  const bx = Math.min(...xs), by = Math.min(...ys), bw = Math.max(...xs) - bx, bh = Math.max(...ys) - by;
  const pn = h('div', 'pn ' + (p.cls || ''), p.bg, p.fx);
  Object.assign(pn.style, { left: bx + 'px', top: by + 'px', width: bw + 'px', height: bh + 'px',
    clipPath: `polygon(${pts.map(([x, y]) => `${(x - bx).toFixed(1)}px ${(y - by).toFixed(1)}px`).join(',')})` });
  el.append(pn);
  if (p.c) {
    const pc = h('div', 'pc ' + (p.at || ''), p.c);
    Object.assign(pc.style, { left: l + 'px', top: t + 'px', width: r - l + 'px', height: b - t + 'px' });
    el.append(pc);
  }
  const poly = document.createElementNS(NS, 'polygon');
  poly.setAttribute('points', pts.map(q => q.map(v => v.toFixed(1)).join(',')).join(' '));
  frames.append(poly);
}

// Text that does not fit gets smaller, as lettering would; past that its panel scrolls.
function fit(el, base) {
  let scale = 1;
  const over = () => [...el.querySelectorAll('.pc')].filter(c => c.scrollHeight > c.clientHeight + 1 || c.scrollWidth > c.clientWidth + 1);
  el.style.fontSize = base + 'px';
  while (over().length && scale > .74) { scale -= .04; el.style.fontSize = base * scale + 'px'; }
  over().forEach(c => c.classList.add('scroll'));
}

// ---- the reader --------------------------------------------------------------------------------------
let W, H, single, els = [], views = [], at = 0, busy = false, built = false, dirty = false;
const stage = h('div', 'mstage'), vol = h('div', 'mvol'), slotL = h('div', 'mslot l'), slotR = h('div', 'mslot r'), measure = h('div', 'mmeasure');
const btnNext = h('button', 'next', h('b', '', '◀'), h('span', '')), btnPrev = h('button', 'prev', h('span', ''), h('b', '', '▶'));
const btnToc = h('button', 'tocb', ''), count = h('span', 'mcount');
count.setAttribute('aria-live', 'polite');
vol.append(slotL, slotR); stage.append(vol);
host.append(stage, h('nav', 'mnav', btnNext, count, btnToc, btnPrev), measure);

function size() {
  single = narrow();
  const vh = innerHeight - 116;
  if (single) { W = Math.min(innerWidth - 32, vh * .74); H = Math.min(vh, W / .48); }
  else { H = Math.min(vh, (innerWidth - 48) / 2 / .7); W = H * .7; }
  W = Math.floor(W); H = Math.floor(H);
  host.style.setProperty('--pw', W + 'px'); host.style.setProperty('--ph', H + 'px');
  host.classList.toggle('single', single);
}

function render() {
  const keep = views[at] ? (views[at].r ?? views[at].l) : 0;
  size();
  const base = W * (single ? .038 : .0275);
  els = volume().map((pg, i) => page(pg, i, W, H));
  for (const e of els) { measure.append(e); fit(e, base); e.remove(); }
  els.forEach(e => e.querySelectorAll('[data-sec]').forEach(b => { if (b.tagName === 'BUTTON') { const i = els.findIndex(x => x.dataset.sec === b.dataset.sec); b.lastChild.textContent = i; b.onclick = () => goPage(i); } }));
  views = [];
  if (single) els.forEach((_, i) => views.push({ r: i }));
  else {
    views.push({ l: 0 });
    for (let i = 1; i < els.length - 1; i += 2) views.push({ r: i, l: i + 1 });
    if (els.length % 2 === 0) views.push({ r: els.length - 1 });
  }
  at = Math.max(0, views.findIndex(v => v.r === keep || v.l === keep));
  btnNext.lastChild.textContent = t('next'); btnPrev.firstChild.textContent = t('prev'); btnToc.textContent = t('contents');
  btnNext.setAttribute('aria-label', t('next')); btnPrev.setAttribute('aria-label', t('prev'));
  stage.setAttribute('aria-label', 'EgeBookReader');
  built = true; dirty = false;
  show();
}

const put = (slot, i) => slot.replaceChildren(...(i == null ? [] : [els[i]]));
function show() {
  const v = views[at];
  put(slotL, v.l); put(slotR, v.r);
  shift(v);
  const pages = [v.r, v.l].filter(i => i != null);
  count.textContent = pages.join('–') + ' / ' + (els.length - 1);
  btnNext.disabled = at >= views.length - 1; btnPrev.disabled = at <= 0;
}
// A lone cover or back cover sits in the middle, as a closed book would.
function shift(v) { vol.style.transform = single ? '' : v.r == null ? `translateX(${W / 2}px)` : v.l == null ? `translateX(${-W / 2}px)` : ''; }

function go(to) {
  if (busy || to === at || to < 0 || to >= views.length) return;
  const from = views[at], next = views[to], fwd = to > at;
  at = to;
  if (reduced) return show();
  busy = true;
  const face = (i, back) => { const f = h('div', 'face' + (back ? ' back' : '')); if (i != null) f.append(els[i].cloneNode(true)); return f; };
  const leaf = h('div', 'leaf');
  leaf.setAttribute('aria-hidden', 'true');
  let end = 'rotateY(0deg)';
  if (single) {
    // forward, the page lifts from its left edge and swings off to the right; back, it swings in again
    leaf.style.transformOrigin = '100% 50%';
    if (fwd) { leaf.append(face(from.r)); put(slotR, next.r); end = 'rotateY(178deg)'; }
    else { leaf.append(face(next.r)); leaf.style.transform = 'rotateY(178deg)'; }
  } else if (fwd) {
    leaf.append(face(from.l), face(next.r, true));
    leaf.style.left = '0'; leaf.style.transformOrigin = '100% 50%';
    put(slotL, next.l); end = 'rotateY(180deg)';
  } else {
    leaf.append(face(from.r), face(next.l, true));
    leaf.style.left = W + 'px'; leaf.style.transformOrigin = '0 50%';
    put(slotR, next.r); end = 'rotateY(-180deg)';
  }
  vol.append(leaf);
  const pop = sfx('パラ', 'FLIP', ''); pop.className = 'sfx flipfx' + (fwd ? '' : ' back'); stage.append(pop);
  leaf.getBoundingClientRect();
  leaf.style.transform = end;
  shift(next);
  let done = false;
  const finish = () => { if (done) return; done = true; leaf.remove(); pop.remove(); busy = false; show(); };
  leaf.addEventListener('transitionend', finish, { once: true });
  setTimeout(finish, 1000);
}
const step = d => go(at + d);
const goPage = i => go(views.findIndex(v => v.r === i || v.l === i));

btnNext.onclick = () => step(1);
btnPrev.onclick = () => step(-1);
btnToc.onclick = () => goPage(els.findIndex(e => e.dataset.sec === 'contents'));

// Right to left: the left page, a swipe to the right and the left arrow all go forward.
let down = null;
stage.addEventListener('pointerdown', e => { down = { x: e.clientX, y: e.clientY, id: e.pointerId }; });
stage.addEventListener('pointerup', e => {
  if (!down || down.id !== e.pointerId) return;
  const dx = e.clientX - down.x, dy = e.clientY - down.y; down = null;
  if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.3) return step(dx > 0 ? 1 : -1);
  if (Math.abs(dx) > 8 || Math.abs(dy) > 8 || e.target.closest('a,button,img.shot')) return;
  const b = vol.getBoundingClientRect(), mid = single ? b.left + b.width / 2 : b.left + W;
  step(e.clientX < mid ? 1 : -1);
});
stage.addEventListener('click', e => { const i = e.target.closest('img.shot'); if (i) zoom(i.src); });

addEventListener('keydown', e => {
  if (html.dataset.mode !== 'manga') return;
  if (e.target.closest && e.target.closest('a,button,input') && (e.key === ' ' || e.key === 'Enter')) return;
  const keys = { ArrowLeft: 1, PageDown: 1, ArrowRight: -1, PageUp: -1, ' ': e.shiftKey ? -1 : 1 };
  if (e.key in keys) { e.preventDefault(); step(keys[e.key]); }
  else if (e.key === 'Home') go(0);
  else if (e.key === 'End') go(views.length - 1);
  else return;
  e.stopImmediatePropagation();
}, true);

// ---- switching -------------------------------------------------------------------------------------------
let fontsAsked = false;
function fonts() {
  if (fontsAsked) return;
  fontsAsked = true;
  const hrefs = ['https://fonts.googleapis.com/css2?family=Bangers&family=Shantell+Sans:wght@400;700&display=swap',
    'https://fonts.googleapis.com/css2?family=Dela+Gothic+One&display=swap&text=' + encodeURIComponent(JP)];
  const loads = hrefs.map(href => new Promise(ok => { const l = h('link'); l.rel = 'stylesheet'; l.href = href; l.onload = l.onerror = ok; document.head.append(l); }));
  Promise.all(loads)
    .then(() => Promise.all(['1em Bangers', '1em "Shantell Sans"', 'bold 1em "Shantell Sans"', '1em "Dela Gothic One"'].map(f => document.fonts.load(f, 'Aa' + JP).catch(() => {}))))
    .then(() => { if (html.dataset.mode === 'manga') render(); else dirty = true; });
}

function setMode(mode, save) {
  html.dataset.mode = mode;
  const manga = mode === 'manga';
  table.inert = manga;
  host.inert = !manga;
  $('#mode').querySelectorAll('button').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.mode === mode)));
  if (save) {
    try { localStorage.setItem('mode', mode); } catch (e) {}
    try { const u = new URL(location.href); if (manga) u.searchParams.set('mode', 'manga'); else u.searchParams.delete('mode'); history.replaceState(null, '', u); } catch (e) {}
  }
  if (manga) { fonts(); if (!built || dirty) render(); }
}

function labels() {
  const g = $('#mode');
  g.setAttribute('aria-label', t('mode'));
  g.querySelectorAll('button').forEach(b => { b.textContent = t(b.dataset.mode); });
}

$('#mode').addEventListener('click', e => { const b = e.target.closest('button'); if (b) setMode(b.dataset.mode, true); });
$('#lang').addEventListener('click', () => { labels(); if (html.dataset.mode === 'manga') render(); else dirty = true; });
let raf = 0;
addEventListener('resize', () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(() => { if (html.dataset.mode === 'manga') render(); else dirty = true; }); });

// The shout balloon's jagged edge, drawn once.
host.style.setProperty('--burst', 'polygon(' + Array.from({ length: 30 }, (_, i) => {
  const a = i / 30 * Math.PI * 2, r = i % 2 ? 37 + (i * 7 % 5) : 50;
  return `${(50 + Math.cos(a) * r).toFixed(1)}% ${(50 + Math.sin(a) * r).toFixed(1)}%`;
}).join(',') + ')');

labels();
setMode(html.dataset.mode === 'manga' ? 'manga' : 'book', false);
})();
