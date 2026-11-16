// EgeBookReader on the web: a library kept in this browser, and a reader for books and comics.
// Nothing is uploaded: files are read here and stored in IndexedDB on this device only.
import * as store from './store.js';
import { TextReader } from './text.js';
import { PageReader } from './pages.js';

const VERSION = 'web-1.0';
const $ = (s, r = document) => r.querySelector(s);
const html = document.documentElement;

// ---- words -------------------------------------------------------------------------------------------------
const T = {
  en: {
    home: 'EgeBookReader home', library: 'Your library', empty: 'Books you open stay here, on this device, with your place in each.',
    heroTitle: 'Read it here.', heroText: 'Open a book or a comic from your device. It opens in the browser, in book or manga style by itself.',
    heroTitleManga: 'Open a volume!', heroTextManga: 'Comics and manga turn page by page, right to left when the book says so. Books get the book style.',
    open: 'Open a file', folder: 'Open a folder of pictures', drop: 'Drop files here', formats: 'EPUB, PDF, MOBI, AZW3, FB2, CBZ, CBR, CB7, DOCX, ODT, RTF, TXT, Markdown, HTML, pictures',
    privacy: 'Your files never leave this device. Nothing is uploaded; the library is kept in this browser.',
    app: 'Get the Android app', remove: 'Remove from library', removed: 'Removed.', undo: 'Undo', opening: 'Opening…', unpacking: 'Unpacking pages…',
    back: 'Library', contents: 'Contents', pagesTab: 'Pages', search: 'Search in the book', settings: 'Reading settings', speak: 'Read aloud', stop: 'Stop reading',
    full: 'Full screen', page: 'Page', of: 'of', left: n => n === 1 ? '1 page left in chapter' : `${n} pages left in chapter`, end: 'The end of the book.', noToc: 'This book has no contents list.',
    theme: 'Theme', paper: 'Paper', sepia: 'Parchment', gray: 'Mist', night: 'Night', oled: 'OLED black',
    size: 'Text size', spacing: 'Line spacing', font: 'Font', serif: 'Serif', sans: 'Sans', classic: 'Classic', mono: 'Mono',
    margin: 'Margins', narrow: 'Narrow', normal: 'Normal', wide: 'Wide', justify: 'Justify text', layout: 'Pages on screen', auto: 'Automatic', one: 'One', two: 'Two',
    dir: 'Reading direction', ltr: 'Left to right', rtl: 'Right to left (manga)', flow: 'Reading flow', paged: 'Page by page', strip: 'One long strip (webtoon)',
    turn: 'Page turn', curl: 'Curl', slide: 'Slide', none: 'None', fit: 'Fit', fitPage: 'Whole page', fitWidth: 'Width',
    voice: 'Voice', rate: 'Speed', sysVoice: 'Default voice', searchHint: 'Type at least two letters', results: 'matches', noResults: 'Nothing found.', more: 'Showing the first 300.',
    mode: 'Style', book: 'Book', manga: 'Manga', on: 'On', off: 'Off', fmt: 'Format', finished: 'Finished', newBook: 'New',
    err: { unknown: 'This file type cannot be opened.', corrupt: 'The file looks damaged and could not be opened.', drm: 'This book is locked with DRM, so it cannot be opened.', huff: 'This Kindle book uses a compression that is not supported yet.', djvu: 'DjVu opens in the Android app, not in the browser yet.', locked: 'This file is password protected.', empty: 'There are no pages in this archive.', old: 'This browser is too old for the reader. Try a current Chrome, Edge, Firefox or Safari.', store: 'The book opened, but there was no room to keep it in the library.' },
    rtlHint: 'Right to left', keys: 'Arrows or space turn pages, F for full screen, Esc to go back.',
  },
  tr: {
    home: 'EgeBookReader ana sayfa', library: 'Kitaplığın', empty: 'Açtığın kitaplar burada, bu cihazda, kaldığın yerle birlikte durur.',
    heroTitle: 'Burada oku.', heroText: 'Cihazından bir kitap ya da çizgi roman aç. Tarayıcıda açılır, türüne göre kitap ya da manga görünümüne kendisi geçer.',
    heroTitleManga: 'Bir cilt aç!', heroTextManga: 'Çizgi roman ve manga sayfa sayfa çevrilir, kitap öyle diyorsa sağdan sola. Kitaplar kitap görünümünde açılır.',
    open: 'Dosya aç', folder: 'Resim klasörü aç', drop: 'Dosyaları buraya bırak', formats: 'EPUB, PDF, MOBI, AZW3, FB2, CBZ, CBR, CB7, DOCX, ODT, RTF, TXT, Markdown, HTML, resimler',
    privacy: 'Dosyaların cihazından çıkmaz. Hiçbir şey yüklenmez; kitaplık bu tarayıcıda saklanır.',
    app: 'Android uygulamasını indir', remove: 'Kitaplıktan kaldır', removed: 'Kaldırıldı.', undo: 'Geri al', opening: 'Açılıyor…', unpacking: 'Sayfalar açılıyor…',
    back: 'Kitaplık', contents: 'İçindekiler', pagesTab: 'Sayfalar', search: 'Kitapta ara', settings: 'Okuma ayarları', speak: 'Sesli oku', stop: 'Okumayı durdur',
    full: 'Tam ekran', page: 'Sayfa', of: '/', left: n => `bölümde ${n} sayfa kaldı`, end: 'Kitabın sonu.', noToc: 'Bu kitapta içindekiler listesi yok.',
    theme: 'Tema', paper: 'Kağıt', sepia: 'Parşömen', gray: 'Sis', night: 'Gece', oled: 'OLED siyah',
    size: 'Yazı boyutu', spacing: 'Satır aralığı', font: 'Yazı tipi', serif: 'Tırnaklı', sans: 'Tırnaksız', classic: 'Klasik', mono: 'Eş aralıklı',
    margin: 'Kenar boşluğu', narrow: 'Dar', normal: 'Normal', wide: 'Geniş', justify: 'İki yana yasla', layout: 'Ekranda sayfa', auto: 'Otomatik', one: 'Tek', two: 'Çift',
    dir: 'Okuma yönü', ltr: 'Soldan sağa', rtl: 'Sağdan sola (manga)', flow: 'Okuma akışı', paged: 'Sayfa sayfa', strip: 'Tek uzun şerit (webtoon)',
    turn: 'Sayfa çevirme', curl: 'Kıvrılma', slide: 'Kaydırma', none: 'Yok', fit: 'Sığdır', fitPage: 'Tüm sayfa', fitWidth: 'Genişlik',
    voice: 'Ses', rate: 'Hız', sysVoice: 'Varsayılan ses', searchHint: 'En az iki harf yaz', results: 'sonuç', noResults: 'Bulunamadı.', more: 'İlk 300 sonuç gösteriliyor.',
    mode: 'Görünüm', book: 'Kitap', manga: 'Manga', on: 'Açık', off: 'Kapalı', fmt: 'Biçim', finished: 'Bitti', newBook: 'Yeni',
    err: { unknown: 'Bu dosya türü açılamıyor.', corrupt: 'Dosya bozuk görünüyor, açılamadı.', drm: 'Bu kitap DRM ile kilitli, açılamıyor.', huff: 'Bu Kindle kitabı henüz desteklenmeyen bir sıkıştırma kullanıyor.', djvu: 'DjVu şimdilik tarayıcıda değil, Android uygulamasında açılıyor.', locked: 'Bu dosya parolayla korunuyor.', empty: 'Bu arşivde sayfa yok.', old: 'Bu tarayıcı okuyucu için çok eski. Güncel bir Chrome, Edge, Firefox ya da Safari dene.', store: 'Kitap açıldı ama kitaplıkta saklamaya yer kalmadı.' },
    rtlHint: 'Sağdan sola', keys: 'Oklar ya da boşluk sayfa çevirir, F tam ekran, Esc geri.',
  },
};
let lang = localStorage.getItem('lang') || (navigator.language.startsWith('tr') ? 'tr' : 'en');
const t = k => k.split('.').reduce((o, p) => o?.[p], T[lang]) ?? k;

// ---- settings ----------------------------------------------------------------------------------------------
const DEFAULTS = { theme: 'paper', fontSize: 19, lineHeight: 1.55, font: 'serif', margin: 1, justify: true, spread: 0, fit: 'page', scroll: 0, turn: 'curl', rate: 1, voice: '' };
const settings = { ...DEFAULTS, ...JSON.parse(localStorage.getItem('ebr-web') || '{}') };
const saveSettings = () => localStorage.setItem('ebr-web', JSON.stringify(settings));
const THEMES = { paper: ['#f7f3ea', '#231f1b', '#1c1714'], sepia: ['#efe2c6', '#3b2f22', '#2a2118'], gray: ['#e4e4e0', '#26282a', '#1b1c1d'], night: ['#1f1d1b', '#d9d1c4', '#121110'], oled: ['#000000', '#bfb8ac', '#000000'] };

// ---- style: book or manga ----------------------------------------------------------------------------------
function setMode(mode) {
  html.dataset.mode = mode;
  try { localStorage.setItem('mode', mode); } catch (e) {}
  for (const b of document.querySelectorAll('.modes button')) b.setAttribute('aria-pressed', String(b.dataset.mode === mode));
  if (mode === 'manga') loadMangaFonts();
  renderHero();
}
let mangaFonts;
function loadMangaFonts() {
  if (mangaFonts) return;
  mangaFonts = document.createElement('link');
  mangaFonts.rel = 'stylesheet';
  mangaFonts.href = 'https://fonts.googleapis.com/css2?family=Bangers&family=Shantell+Sans:wght@400;700&display=swap';
  document.head.append(mangaFonts);
}

// ---- the library -------------------------------------------------------------------------------------------
const lib = $('#library'), shelf = $('#shelf'), grid = $('#grid');
function renderHero() {
  const m = html.dataset.mode === 'manga';
  $('#heroTitle').textContent = t(m ? 'heroTitleManga' : 'heroTitle');
  $('#heroText').textContent = t(m ? 'heroTextManga' : 'heroText');
}
function labels() {
  html.lang = lang;
  for (const e of document.querySelectorAll('[data-t]')) e.textContent = t(e.dataset.t);
  for (const e of document.querySelectorAll('[data-tl]')) { e.setAttribute('aria-label', t(e.dataset.tl)); e.title = t(e.dataset.tl); }
  for (const b of document.querySelectorAll('.lang')) b.textContent = lang === 'tr' ? 'EN' : 'TR';
  for (const b of document.querySelectorAll('.modes button')) b.textContent = t(b.dataset.mode);
  renderHero();
}
async function renderShelf() {
  const all = (await store.books().catch(() => [])).sort((a, b) => (b.opened || 0) - (a.opened || 0));
  shelf.hidden = false;
  $('#emptyNote').hidden = all.length > 0;
  grid.replaceChildren(...all.map(card));
}
const thumbs = new Map();
function card(b) {
  const el = document.createElement('article');
  el.className = 'card' + (b.manga ? ' comic' : '');
  const btn = document.createElement('button');
  btn.className = 'open'; btn.setAttribute('aria-label', b.title);
  const cover = document.createElement('div');
  cover.className = 'cover';
  if (b.thumb) {
    const img = new Image(); img.alt = ''; img.loading = 'lazy';
    let url = thumbs.get(b.id); if (!url) { url = URL.createObjectURL(b.thumb); thumbs.set(b.id, url); }
    img.src = url; cover.append(img);
  } else {
    cover.classList.add('plain');
    const h = document.createElement('span'); h.className = 'ct'; h.textContent = b.title; cover.append(h);
    cover.style.setProperty('--hue', [...b.title].reduce((a, c) => a + c.charCodeAt(0), 0) % 360);
  }
  const bar = document.createElement('div'); bar.className = 'bar'; bar.style.setProperty('--p', Math.round((b.progress || 0) * 100) + '%');
  cover.append(bar);
  const fmt = document.createElement('span'); fmt.className = 'fmt'; fmt.textContent = (b.format || '').toUpperCase(); cover.append(fmt);
  const meta = document.createElement('div'); meta.className = 'meta';
  const ti = document.createElement('h3'); ti.textContent = b.title;
  const au = document.createElement('p'); au.textContent = [b.author, b.progress >= .995 ? t('finished') : b.progress ? '%' + Math.round(b.progress * 100) : t('newBook')].filter(Boolean).join(' · ');
  if (lang === 'en' && b.progress && b.progress < .995) au.textContent = [b.author, Math.round(b.progress * 100) + '%'].filter(Boolean).join(' · ');
  meta.append(ti, au);
  btn.append(cover, meta);
  btn.onclick = () => openStored(b.id);
  const del = document.createElement('button');
  del.className = 'del'; del.setAttribute('aria-label', t('remove')); del.title = t('remove');
  del.innerHTML = ICON.x;
  del.onclick = async () => {
    const files = await store.files(b.id);
    await store.remove(b.id); renderShelf();
    toast(t('removed'), t('undo'), async () => { await store.addFiles(b.id, files); await store.putBook(b); renderShelf(); });
  };
  el.append(btn, del);
  return el;
}

// ---- opening -----------------------------------------------------------------------------------------------
let current = null; // { id, rec, book, reader }
async function openFiles(list, stored) {
  list = [...list].filter(f => f && f.size !== 0);
  if (!list.length) return;
  if (typeof DecompressionStream === 'undefined') return toast(t('err.old'));
  busy(t('opening'));
  const id = store.idOf(list);
  let book, opening = true;
  try {
    const formats = await import('./formats.js');
    book = await formats.openFiles(list, p => { if (opening) busy(t('unpacking'), p); });
    opening = false;
  } catch (e) {
    opening = false; busy(false);
    if (!e?.code) console.error(e);
    return toast(T[lang].err[e?.code] || T[lang].err.corrupt);
  }
  let rec = await store.book(id).catch(() => null);
  const first = !rec;
  rec = { ...(rec || {}), id, name: list[0].name, title: book.title || list[0].name, author: book.author || '', format: book.format, kind: book.kind, manga: !!book.manga, opened: Date.now(), added: rec?.added || Date.now() };
  if (rec.rtl == null) rec.rtl = !!book.rtl;
  if (!stored) {
    try { await store.addFiles(id, list); if (navigator.storage?.persist) navigator.storage.persist().catch(() => {}); }
    catch (e) { toast(t('err.store')); }
  }
  if (first || !rec.thumb) rec.thumb = await makeThumb(book).catch(() => null);
  await store.putBook(rec).catch(() => {});
  busy(false);
  startReader(id, rec, book);
}
async function openStored(id) {
  const files = await store.files(id).catch(() => null);
  if (!files) { toast(T[lang].err.corrupt); return renderShelf(); }
  openFiles(files, true);
}
async function makeThumb(book) {
  let src = book.cover;
  if (!src && book.kind === 'pages') src = await (book.coverPage ? book.coverPage() : book.page(0, 400));
  if (!src) return null;
  const bmp = src instanceof Blob ? await createImageBitmap(src) : src;
  const w = 320, h = Math.round(w * (bmp.height / bmp.width));
  const c = document.createElement('canvas'); c.width = w; c.height = Math.min(h, 640);
  c.getContext('2d').drawImage(bmp, 0, 0, w, h);
  return new Promise(r => c.toBlob(r, 'image/jpeg', .82));
}

// ---- the reader --------------------------------------------------------------------------------------------
const rd = $('#reader'), surface = $('#surface');
let chromeTimer, wake;
function startReader(id, rec, book) {
  closeReader(true);
  setMode(book.manga ? 'manga' : 'book');
  lib.hidden = true; rd.hidden = false;
  rd.dataset.kind = book.kind;
  document.title = rec.title + ' · EgeBookReader';
  $('#rtitle').textContent = rec.title;
  const hooks = { onMove: moved, onCenter: () => chrome(!rd.classList.contains('chrome')), onEnd: () => toast(t('end')) };
  const reader = book.kind === 'text' ? new TextReader(surface, book, hooks) : new PageReader(surface, book, hooks);
  current = { id, rec, book, reader };
  $('#speak').hidden = !(book.kind === 'text' && 'speechSynthesis' in window);
  $('#find').hidden = !(book.kind === 'text' || book.text);
  applySettings();
  reader.open(rec.pos);
  if (location.search !== '?book=' + encodeURIComponent(id)) history.pushState({ book: id }, '', '?book=' + encodeURIComponent(id));
  chrome(true); chromeTimer = setTimeout(() => chrome(false), 2600);
  if (book.kind === 'pages' && rec.rtl) hint(t('rtlHint'));
  navigator.wakeLock?.request('screen').then(w => { wake = w; }).catch(() => {});
  surface.focus({ preventScroll: true });
}
function closeReader(silent) {
  if (!current) return;
  savePos(true);
  current.reader.stopSpeech?.();
  current.reader.destroy(); current.book.dispose?.();
  current = null;
  surface.replaceChildren();
  closePanel();
  wake?.release().catch(() => {}); wake = null;
  if (!silent) {
    rd.hidden = true; lib.hidden = false; document.title = 'EgeBookReader Web';
    if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
    renderShelf();
  }
}
let saveT;
function moved(info) {
  if (!current) return;
  current.info = info;
  const scrub = $('#scrub');
  if (!scrub.matches(':active')) scrub.value = Math.round(info.percent * 1000);
  const pct = Math.round(info.percent * 100);
  let pos;
  if (current.book.kind === 'text') {
    const left = info.pages - info.page - 1;
    pos = `${pct}%` + (left > 0 ? ' · ' + T[lang].left(left) : '');
    $('#folioTop').textContent = info.title || current.rec.title;
    $('#folioBottom').textContent = `${info.page + 1} / ${info.pages} · ${pct}%`;
  } else {
    pos = info.last > info.page ? `${info.page + 1}–${info.last + 1} / ${info.pages}` : `${info.page + 1} / ${info.pages}`;
  }
  $('#where').textContent = pos;
  $('#chap').textContent = info.title || '';
  clearTimeout(saveT); saveT = setTimeout(() => savePos(), 500);
  if (info.atEnd) savePos();
  if (!$('#panel').hidden && $('#panel').dataset.kind === 'toc') markToc();
}
function savePos() {
  if (!current) return;
  const { rec, reader } = current;
  rec.pos = reader.position(); rec.progress = current.info?.atEnd ? 1 : current.info?.percent || 0; rec.opened = Date.now();
  store.putBook(rec).catch(() => {});
}
function chrome(on) {
  clearTimeout(chromeTimer);
  rd.classList.toggle('chrome', on);
  if (!on) closePanel();
}
function applySettings() {
  if (!current) return;
  const [bg, ink, table] = THEMES[settings.theme] || THEMES.paper;
  rd.dataset.theme = settings.theme;
  rd.style.setProperty('--r-bg', bg); rd.style.setProperty('--r-ink', ink); rd.style.setProperty('--r-table', table);
  const { book, reader, rec } = current;
  if (book.kind === 'text') reader.apply({ ...settings, spread: settings.spread });
  else reader.apply({ spread: settings.spread, fit: settings.fit, scroll: settings.scroll, turn: settings.turn, rtl: rec.rtl, paper: bg, bg: html.dataset.mode === 'manga' && settings.theme === 'paper' ? '#0b0b0b' : table });
}

// ---- panels: contents, settings, search ----------------------------------------------------------------
const panel = $('#panel'), sheet = $('#sheet');
function openPanel(kind) {
  if (!current) return;
  if (!panel.hidden && panel.dataset.kind === kind) return closePanel();
  clearTimeout(chromeTimer);
  panel.dataset.kind = kind; panel.hidden = false;
  renderPanel(kind);
  for (const b of document.querySelectorAll('.rbar [data-panel]')) b.setAttribute('aria-expanded', String(b.dataset.panel === kind));
}
function renderPanel(kind) { sheet.replaceChildren(); ({ toc: tocPanel, settings: settingsPanel, search: searchPanel })[kind](); }
function closePanel() {
  panel.hidden = true;
  for (const b of document.querySelectorAll('.rbar [data-panel]')) b.setAttribute('aria-expanded', 'false');
  current?.reader.clearHit?.();
}
function h(tag, props = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) { if (k.startsWith('on')) e[k] = v; else if (k === 'text') e.textContent = v; else if (v !== false && v != null) e.setAttribute(k, v === true ? '' : v); }
  e.append(...kids.filter(k => k != null));
  return e;
}
function tocPanel() {
  const { book, reader } = current;
  const tabs = book.kind === 'pages' ? h('div', { class: 'tabs', role: 'tablist' }) : null;
  const body = h('div', { class: 'toc' });
  sheet.append(h('h2', { text: t('contents') }), tabs, body);
  const list = () => {
    body.replaceChildren();
    if (!book.toc.length) { body.append(h('p', { class: 'muted', text: t('noToc') })); return; }
    body.append(...book.toc.map((e, n) => h('button', { class: 'toc-e', style: `--d:${e.depth || 0}`, 'data-n': n, onclick: () => {
      if (book.kind === 'text') reader.goAnchor(e.chapter, e.anchor); else reader.goPage(e.page);
      closePanel(); chrome(false);
    } }, h('span', { text: e.title }))));
    markToc();
  };
  const pages = () => {
    body.replaceChildren();
    const g = h('div', { class: 'thumbs' });
    body.append(g);
    const io = new IntersectionObserver(es => es.forEach(async en => {
      if (!en.isIntersecting || en.target.dataset.done) return;
      en.target.dataset.done = 1;
      const i = +en.target.dataset.i, src = await book.page(i, 240).catch(() => null);
      if (!src) return;
      if (src instanceof Blob) { const img = new Image(); img.src = URL.createObjectURL(src); img.onload = () => URL.revokeObjectURL(img.src); en.target.prepend(img); }
      else { const c = document.createElement('canvas'); c.width = 160; c.height = Math.round(160 * src.height / src.width); c.getContext('2d').drawImage(src, 0, 0, c.width, c.height); en.target.prepend(c); }
    }), { root: sheet, rootMargin: '300px' });
    const cur = current.info?.page ?? 0;
    for (let i = 0; i < book.count; i++) {
      const b = h('button', { class: 'thumb' + (i === cur ? ' on' : ''), 'data-i': i, onclick: () => { reader.goPage(i); closePanel(); chrome(false); } }, h('span', { text: String(i + 1) }));
      g.append(b); io.observe(b);
    }
    requestAnimationFrame(() => g.querySelector('.on')?.scrollIntoView({ block: 'center' }));
  };
  if (tabs) {
    const mk = (k, fn) => h('button', { role: 'tab', 'aria-selected': 'false', text: t(k), onclick: e => { tabs.querySelectorAll('button').forEach(b => b.setAttribute('aria-selected', String(b === e.currentTarget))); fn(); } });
    const a = mk('contents', list), b = mk('pagesTab', pages);
    tabs.append(a, b);
    (book.toc.length ? a : b).click();
  } else list();
}
function markToc() {
  if (!current) return;
  const { book } = current, info = current.info || {};
  let on = -1;
  book.toc.forEach((e, n) => { if (book.kind === 'text' ? e.chapter <= info.chapter : e.page <= info.page) on = n; });
  sheet.querySelectorAll('.toc-e').forEach(b => b.classList.toggle('on', +b.dataset.n === on));
  sheet.querySelector('.toc-e.on')?.scrollIntoView({ block: 'nearest' });
}
function settingsPanel() {
  const { book, rec } = current;
  const set = (k, v) => { settings[k] = v; saveSettings(); applySettings(); settingsPanelRefresh(); };
  const choice = (label, key, opts, value = settings[key], onPick = v => set(key, v)) => h('div', { class: 'row' }, h('span', { class: 'lbl', text: t(label) }),
    h('div', { class: 'seg', role: 'radiogroup', 'aria-label': t(label) }, ...opts.map(([v, l]) => h('button', { role: 'radio', 'aria-checked': String(v === value), text: t(l), onclick: () => onPick(v) }))));
  const themes = h('div', { class: 'row' }, h('span', { class: 'lbl', text: t('theme') }), h('div', { class: 'swatches' }, ...Object.entries(THEMES).map(([k, [bg, ink]]) =>
    h('button', { class: 'sw', style: `--bg:${bg};--ink:${ink}`, 'aria-label': t(k), title: t(k), 'aria-pressed': String(settings.theme === k), onclick: () => set('theme', k) }, h('span', { text: 'Aa' })))));
  sheet.append(h('h2', { text: t('settings') }), themes);
  if (book.kind === 'text') {
    sheet.append(
      h('div', { class: 'row' }, h('span', { class: 'lbl', text: t('size') }), h('div', { class: 'stepper' },
        h('button', { 'aria-label': '−', text: 'A−', onclick: () => set('fontSize', Math.max(12, settings.fontSize - 1)) }),
        h('output', { text: String(settings.fontSize) }),
        h('button', { 'aria-label': '+', text: 'A+', onclick: () => set('fontSize', Math.min(40, settings.fontSize + 1)) }))),
      h('div', { class: 'row' }, h('label', { class: 'lbl', for: 'lh', text: t('spacing') }), h('input', { id: 'lh', type: 'range', min: 1.1, max: 2.2, step: .05, value: settings.lineHeight, onchange: e => set('lineHeight', +e.target.value) })),
      choice('font', 'font', [['serif', 'serif'], ['sans', 'sans'], ['classic', 'classic'], ['mono', 'mono']]),
      choice('margin', 'margin', [[0, 'narrow'], [1, 'normal'], [2, 'wide']]),
      choice('justify', 'justify', [[true, 'on'], [false, 'off']]),
      choice('layout', 'spread', [[0, 'auto'], [1, 'one'], [2, 'two']]),
    );
    if ('speechSynthesis' in window) {
      const voices = speechSynthesis.getVoices().filter(v => !book.lang || v.lang.toLowerCase().startsWith(book.lang.slice(0, 2).toLowerCase()) || v.name === settings.voice);
      const sel = h('select', { id: 'vc', onchange: e => set('voice', e.target.value) }, h('option', { value: '', text: t('sysVoice') }), ...voices.map(v => h('option', { value: v.name, text: v.name, selected: v.name === settings.voice })));
      sheet.append(h('div', { class: 'row' }, h('label', { class: 'lbl', for: 'vc', text: t('voice') }), sel),
        h('div', { class: 'row' }, h('label', { class: 'lbl', for: 'rt', text: t('rate') + ' ' + settings.rate.toFixed(2).replace(/0$/, '') + '×' }), h('input', { id: 'rt', type: 'range', min: .5, max: 3, step: .25, value: settings.rate, onchange: e => set('rate', +e.target.value) })));
    }
  } else {
    sheet.append(
      choice('dir', 'rtl', [[false, 'ltr'], [true, 'rtl']], !!rec.rtl, v => { rec.rtl = v; store.putBook(rec); applySettings(); settingsPanelRefresh(); }),
      choice('flow', 'scroll', [[0, 'auto'], [1, 'paged'], [2, 'strip']]),
      choice('layout', 'spread', [[0, 'auto'], [1, 'one'], [2, 'two']]),
      choice('turn', 'turn', [['curl', 'curl'], ['slide', 'slide'], ['none', 'none']]),
      choice('fit', 'fit', [['page', 'fitPage'], ['width', 'fitWidth']]),
    );
  }
  sheet.append(h('p', { class: 'muted small', text: t('keys') }));
}
function settingsPanelRefresh() { const y = sheet.scrollTop; renderPanel('settings'); sheet.scrollTop = y; }
function searchPanel() {
  const { book, reader } = current;
  const input = h('input', { type: 'search', placeholder: t('search'), 'aria-label': t('search'), enterkeyhint: 'search', autocomplete: 'off' });
  const out = h('div', { class: 'hits', 'aria-live': 'polite' });
  sheet.append(h('h2', { text: t('search') }), input, out);
  let token = 0;
  const run = async () => {
    const q = input.value.trim(), my = ++token;
    out.replaceChildren();
    if (q.length < 2) { out.append(h('p', { class: 'muted', text: t('searchHint') })); return; }
    let hits;
    if (book.kind === 'text') hits = reader.search(q);
    else {
      hits = [];
      const n = q.toLocaleLowerCase(lang);
      for (let i = 0; i < book.count && hits.length < 300; i++) {
        const tx = await book.text(i).catch(() => '');
        if (my !== token) return;
        const f = tx.toLocaleLowerCase(lang);
        for (let k = f.indexOf(n); k >= 0 && hits.length < 300; k = f.indexOf(n, k + n.length)) hits.push({ page: i, before: tx.slice(Math.max(0, k - 40), k), match: tx.slice(k, k + n.length), after: tx.slice(k + n.length, k + n.length + 60) });
      }
    }
    if (my !== token) return;
    out.append(h('p', { class: 'muted', text: hits.length ? `${hits.length} ${t('results')}` + (hits.length >= 300 ? ' · ' + t('more') : '') : t('noResults') }));
    out.append(...hits.map(x => h('button', { class: 'hit', onclick: () => { if (book.kind === 'text') reader.goHit(x); else reader.goPage(x.page); if (innerWidth < 760) { panel.hidden = true; } } },
      h('span', { text: '…' + x.before.replace(/\s+/g, ' ') }), h('mark', { text: x.match }), h('span', { text: x.after.replace(/\s+/g, ' ') + '…' }),
      book.kind === 'pages' ? h('small', { text: ` · ${t('page')} ${x.page + 1}` }) : null)));
  };
  let deb;
  input.oninput = () => { clearTimeout(deb); deb = setTimeout(run, 250); };
  input.onkeydown = e => { if (e.key === 'Enter') { clearTimeout(deb); run(); } };
  setTimeout(() => input.focus(), 50);
}

// ---- reading aloud -----------------------------------------------------------------------------------------
function toggleSpeech() {
  const { reader } = current || {};
  if (!reader?.speak) return;
  const b = $('#speak');
  if (b.getAttribute('aria-pressed') === 'true') return reader.stopSpeech();
  reader.speak(settings.rate, settings.voice, on => { b.setAttribute('aria-pressed', String(on)); b.innerHTML = on ? ICON.stop : ICON.speak; b.setAttribute('aria-label', t(on ? 'stop' : 'speak')); });
}

// ---- input -------------------------------------------------------------------------------------------------
function textGestures() {
  let p = null, lastWheel = 0;
  surface.addEventListener('pointerdown', e => {
    if (!current || current.book.kind !== 'text' || e.button > 0 || e.target.closest('a')) return;
    p = { x: e.clientX, y: e.clientY, id: e.pointerId, moved: false, s: [[performance.now(), e.clientX]] };
  });
  surface.addEventListener('pointermove', e => {
    if (!p || e.pointerId !== p.id) return;
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    p.s.push([performance.now(), e.clientX]); if (p.s.length > 6) p.s.shift();
    if (!p.moved && Math.abs(dx) > 10 && Math.abs(dx) > Math.abs(dy)) { p.moved = true; surface.setPointerCapture?.(e.pointerId); }
    if (p.moved) current.reader.drag(dx, false);
  });
  const up = e => {
    if (!p || e.pointerId !== p.id) return;
    const q = p; p = null;
    const dx = e.clientX - q.x;
    if (q.moved) { const dt = (q.s.at(-1)[0] - q.s[0][0]) / 1000 || 1; current.reader.drag(dx, true, (q.s.at(-1)[1] - q.s[0][1]) / dt / 1000); return; }
    if (e.type === 'pointercancel' || Math.abs(e.clientY - q.y) > 12) return;
    const r = surface.getBoundingClientRect(), fx = (e.clientX - r.left) / r.width;
    const rtl = current.book.dir === 'rtl';
    if (fx < .3) rtl ? current.reader.next() : current.reader.prev();
    else if (fx > .7) rtl ? current.reader.prev() : current.reader.next();
    else chrome(!rd.classList.contains('chrome'));
  };
  surface.addEventListener('pointerup', up); surface.addEventListener('pointercancel', up);
  surface.addEventListener('wheel', e => {
    if (!current || current.book.kind !== 'text' || e.ctrlKey) return;
    e.preventDefault();
    const now = performance.now(), d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    if (now - lastWheel < 380 || Math.abs(d) < 10) return;
    lastWheel = now;
    d > 0 ? current.reader.next() : current.reader.prev();
  }, { passive: false });
}
addEventListener('keydown', e => {
  if (!current || e.target.closest('input,select,textarea')) return;
  const r = current.reader, text = current.book.kind === 'text', rtl = text && current.book.dir === 'rtl';
  const right = () => text ? (rtl ? r.prev() : r.next()) : r.turnRight();
  const left = () => text ? (rtl ? r.next() : r.prev()) : r.turnLeft();
  const k = e.key;
  if (k === 'Escape') { if (!panel.hidden) closePanel(); else if (document.fullscreenElement) document.exitFullscreen(); else history.back(); }
  else if (k === 'ArrowRight') right();
  else if (k === 'ArrowLeft') left();
  else if (k === ' ' || k === 'PageDown' || (k === 'ArrowDown' && !(r.scrolling))) e.shiftKey ? r.prev() : r.next();
  else if (k === 'PageUp' || (k === 'ArrowUp' && !r.scrolling)) r.prev();
  else if (k === 'Home') text ? r.goPercent(0) : r.goPage(0);
  else if (k === 'End') text ? r.goPercent(.9999) : r.goPage(current.book.count - 1);
  else if (k === 'f' || k === 'F') fullscreen();
  else return;
  e.preventDefault();
});
function fullscreen() { if (document.fullscreenElement) document.exitFullscreen(); else rd.requestFullscreen?.().catch(() => {}); }

// Drag and drop anywhere, a file or a folder of pictures.
addEventListener('dragover', e => { if ([...e.dataTransfer.types].includes('Files')) { e.preventDefault(); html.classList.add('dropping'); } });
addEventListener('dragleave', e => { if (!e.relatedTarget) html.classList.remove('dropping'); });
addEventListener('drop', async e => {
  e.preventDefault(); html.classList.remove('dropping');
  const items = [...e.dataTransfer.items].map(i => i.webkitGetAsEntry?.()).filter(Boolean);
  if (items.some(i => i.isDirectory)) {
    const out = [];
    const walk = async en => {
      if (en.isFile) out.push(await new Promise((r, j) => en.file(r, j)));
      else { const rd = en.createReader(); let batch; do { batch = await new Promise((r, j) => rd.readEntries(r, j)); for (const x of batch) await walk(x); } while (batch.length); }
    };
    for (const i of items) await walk(i);
    openFiles(out);
  } else openFiles(e.dataTransfer.files);
});

// ---- small things ------------------------------------------------------------------------------------------
let toastT;
function toast(msg, action, fn) {
  const el = $('#toast');
  el.replaceChildren(h('span', { text: msg }), action ? h('button', { text: action, onclick: () => { el.hidden = true; fn(); } }) : null);
  el.hidden = false;
  clearTimeout(toastT); toastT = setTimeout(() => { el.hidden = true; }, action ? 6000 : 4200);
}
function busy(msg, p) {
  const el = $('#busy');
  if (msg === false) { el.hidden = true; return; }
  el.hidden = false; $('#busyText').textContent = msg;
  const bar = $('#busyBar'); bar.hidden = p == null; if (p != null) bar.value = p;
}
let hintT;
function hint(msg) { const el = $('#hint'); el.textContent = msg; el.hidden = false; clearTimeout(hintT); hintT = setTimeout(() => { el.hidden = true; }, 2200); }

const ICON = {
  back: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M15 5l-7 7 7 7"/></svg>',
  toc: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h10"/></svg>',
  find: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="10.5" cy="10.5" r="6"/><path d="M15 15l5 5"/></svg>',
  aa: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 18l5-12 5 12M5 14h6M15 18l3.5-8 3.5 8M16 15.5h5"/></svg>',
  speak: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9v6h4l5 4V5L8 9zM16 9a4 4 0 010 6M18.5 6.5a7.5 7.5 0 010 11"/></svg>',
  stop: '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="1.5"/></svg>',
  full: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/></svg>',
  x: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>',
};

// ---- wiring ------------------------------------------------------------------------------------------------
for (const [id, icon] of [['rback', 'back'], ['rtoc', 'toc'], ['find', 'find'], ['raa', 'aa'], ['speak', 'speak'], ['rfull', 'full']]) $('#' + id).innerHTML = ICON[icon];
$('#rback').onclick = () => history.back();
$('#rtoc').onclick = () => openPanel('toc');
$('#find').onclick = () => openPanel('search');
$('#raa').onclick = () => openPanel('settings');
$('#speak').onclick = toggleSpeech;
$('#rfull').onclick = fullscreen;
$('#panelClose').onclick = closePanel;
$('#scrub').oninput = e => { if (current) current.reader.goPercent(e.target.value / 1000); };
$('#pick').onchange = e => { openFiles(e.target.files); e.target.value = ''; };
$('#pickDir').onchange = e => { openFiles([...e.target.files].filter(f => /\.(jpe?g|png|gif|webp|avif|bmp)$/i.test(f.name))); e.target.value = ''; };
$('#openBtn').onclick = () => $('#pick').click();
$('#dirBtn').onclick = () => $('#pickDir').click();
if (!('webkitdirectory' in document.createElement('input')) || /Android|iPhone|iPad/i.test(navigator.userAgent)) $('#dirBtn').hidden = true;
for (const b of document.querySelectorAll('.lang')) b.onclick = () => { lang = lang === 'tr' ? 'en' : 'tr'; localStorage.setItem('lang', lang); labels(); renderShelf(); if (current && !panel.hidden) renderPanel(panel.dataset.kind); };
for (const g of document.querySelectorAll('.modes')) g.onclick = e => { const b = e.target.closest('button'); if (b) { setMode(b.dataset.mode); applySettings(); } };
rd.addEventListener('mousemove', e => { if (matchMedia('(hover: hover)').matches && (e.clientY < 70 || e.clientY > innerHeight - 70)) { if (!rd.classList.contains('chrome')) chrome(true); } });
document.addEventListener('visibilitychange', () => { if (document.hidden) savePos(); else if (current && !wake) navigator.wakeLock?.request('screen').then(w => { wake = w; }).catch(() => {}); });
addEventListener('pagehide', () => savePos());
addEventListener('popstate', () => {
  const id = new URLSearchParams(location.search).get('book');
  if (id && (!current || current.id !== id)) openStored(id); else if (!id && current) closeReader();
});
// Voices arrive late in some browsers; the settings list fills in when they do.
if ('speechSynthesis' in window) speechSynthesis.onvoiceschanged = () => { if (current && !panel.hidden && panel.dataset.kind === 'settings') settingsPanelRefresh(); };
textGestures();
labels();
setMode(html.dataset.mode === 'manga' ? 'manga' : 'book');
renderShelf();
$('#ver').textContent = VERSION;

// A book in the address (a reload), files handed over by the installed app or by Android's share sheet.
(async () => {
  const q = new URLSearchParams(location.search);
  if (q.get('shared')) { const got = await store.takeInbox().catch(() => []); history.replaceState(null, '', location.pathname); if (got.length) return openFiles(got.flat()); }
  if (q.get('book')) { const id = q.get('book'); history.replaceState(null, '', location.pathname); openStored(id); }
})();
if ('launchQueue' in window) launchQueue.setConsumer(async p => { if (p.files?.length) openFiles(await Promise.all(p.files.map(f => f.getFile()))); });
if ('serviceWorker' in navigator && isSecureContext) navigator.serviceWorker.register('/read/sw.js', { scope: '/read/' }).catch(() => {});
