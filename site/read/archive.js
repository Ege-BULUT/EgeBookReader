// RAR, RAR5 and 7z comics (.cbr, .cb7) through libarchive compiled to WebAssembly (vendor/libarchive, MIT).
// libarchive reads a solid archive from the start for every single file, so every page is unpacked in one pass and kept;
// a page asked for before the pass reaches it waits for it.
import { Archive } from './vendor/libarchive/libarchive.js';

const IMG = /\.(jpe?g|png|gif|webp|avif|bmp)$/i;
const natural = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' });
const err = code => Object.assign(new Error(code), { code });

export async function openArchive(file, onProgress) {
  let a;
  try { a = await Archive.open(file); } catch (e) { throw err('corrupt'); }
  if (await a.hasEncryptedData().catch(() => false)) throw err('locked');
  const list = await a.getFilesArray();
  const all = list.map(e => (e.path || '') + e.file.name);
  const names = all.filter(n => IMG.test(n) && !/(^|\/)(__MACOSX\/|\.)/.test(n)).sort(natural.compare);
  if (!names.length) throw err('empty');
  const info = list.find(e => /^comicinfo\.xml$/i.test(e.file.name));

  const waiting = new Map(), got = new Map();
  const ready = name => got.has(name) ? Promise.resolve(got.get(name))
    : new Promise((res, rej) => { const w = waiting.get(name) || []; w.push({ res, rej }); waiting.set(name, w); });
  let done = 0, failed = null;
  const pass = a.extractFiles(entry => {
    // The callback's path already ends with the file name; the listing's path is only the folder.
    const path = entry.path || '', name = path.endsWith(entry.file.name) ? path : path + entry.file.name;
    got.set(name, entry.file);
    for (const w of waiting.get(name) || []) w.res(entry.file);
    waiting.delete(name);
    if (IMG.test(name)) onProgress?.(++done / names.length);
  }).then(() => setTimeout(() => {
    // The last files can arrive just after the pass reports it is done; what is still missing later is not there.
    for (const [, ws] of waiting) for (const w of ws) w.rej(err('corrupt'));
    waiting.clear();
  }, 3000), e => { failed = e; for (const [, ws] of waiting) for (const w of ws) w.rej(err('corrupt')); waiting.clear(); });

  let meta = {};
  if (info) {
    const path = (info.path || '') + info.file.name;
    try {
      const x = new DOMParser().parseFromString(await (await ready(path)).text(), 'application/xml');
      const t = q => x.querySelector(q)?.textContent?.trim() || '';
      meta = { title: [t('Series'), t('Number') && '#' + t('Number')].filter(Boolean).join(' ') || t('Title'), author: t('Writer'), lang: t('LanguageISO'), rtl: /righttoleft/i.test(t('Manga')) };
    } catch (e) {}
  }
  const page = i => { if (failed) return Promise.reject(err('corrupt')); return ready(names[i]); };
  return {
    kind: 'pages', format: /\.7z$|\.cb7$/i.test(file.name) ? 'cb7' : 'cbr', manga: true,
    title: meta.title || file.name.replace(/\.[^.]+$/, ''), author: meta.author || '', lang: meta.lang || '', rtl: !!meta.rtl,
    count: names.length, toc: [], cover: null,
    page, coverPage: () => page(0),
    dispose() { pass.catch(() => {}); got.clear(); },
  };
}
