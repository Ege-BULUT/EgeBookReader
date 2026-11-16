// The browser reader's format layer: turns dropped files into a Book (reflowable text or fixed pages).
// Ported from app/lib/formats.dart and app/lib/sources.dart.

import { openZip } from './zip.js';

const err = (code, cause) => Object.assign(new Error(code, { cause }), { code });
const LIMIT = 200_000; // chapters bigger than this (HTML chars) are cut at block boundaries for the paginator
const collate = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' }).compare;
const IMAGE = /\.(jpe?g|png|gif|webp|avif|bmp)$/i;
const JUNK = /(^|\/)(__MACOSX\/|\.)|(^|\/)thumbs\.db$/i;
const MIME = { jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', avif: 'image/avif', bmp: 'image/bmp', svg: 'image/svg+xml' };
const mimeOf = name => MIME[/\.(\w+)$/.exec(name)?.[1].toLowerCase()] ?? '';
const RTL = /^(ar|he|iw|fa|ur|ps|sd|ug|yi|dv|ckb)\b/i;
const baseName = path => path.split('/').pop().replace(/\.[^.]+$/, '').replace(/_/g, ' ');
const textOf = el => el?.textContent.replace(/\s+/g, ' ').trim() ?? '';
// a heading made of several lines (FB2 titles) reads "Chapter 1 The Beginning", not "Chapter 1The Beginning"
const headingText = h => [...h.childNodes].map(n => /^(DIV|P|BR)$/.test(n.nodeName) ? ` ${n.textContent} ` : n.textContent).join('').replace(/\s+/g, ' ').trim();
const tags = (doc, name) => [...doc.getElementsByTagNameNS('*', name)];
const first = (doc, name) => tags(doc, name).map(textOf).find(Boolean) ?? '';
const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const decodeUri = s => { try { return decodeURIComponent(s); } catch { return s; } };

/** An attribute by local name, whatever its namespace prefix (href, xlink:href, l:href, epub:type, xml:lang). */
function attr(el, name) {
  for (const a of el.attributes) if (a.localName === name || a.name.endsWith(':' + name)) return a.value;
  return null;
}

// ---------------------------------------------------------------------------------------------------------
// Text decoding

function decodeBytes(b, label) {
  if (b[0] === 0xef && b[1] === 0xbb && b[2] === 0xbf) return new TextDecoder().decode(b);
  if (b[0] === 0xff && b[1] === 0xfe) return new TextDecoder('utf-16le').decode(b);
  if (b[0] === 0xfe && b[1] === 0xff) return new TextDecoder('utf-16be').decode(b);
  try {
    return new TextDecoder(label || 'utf-8').decode(b);
  } catch {
    return new TextDecoder().decode(b);
  }
}

const head = (b, n) => String.fromCharCode(...b.subarray(0, n));
const xmlCharset = b => /^[^>]*encoding\s*=\s*["']([\w.:-]+)/.exec(head(b, 200))?.[1];
const htmlCharset = b => xmlCharset(b) ?? /<meta[^>]+charset\s*=\s*["']?([\w-]+)/i.exec(head(b, 2048))?.[1];

/** Plain text of unknown encoding: UTF-8 if it is valid, else Cyrillic cp1251, Turkish cp1254 or Western cp1252. */
function guessText(b) {
  if ((b[0] === 0xef && b[1] === 0xbb) || b[0] === 0xff || b[0] === 0xfe) return decodeBytes(b);
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(b);
  } catch {}
  let high = 0, ascii = 0, turkish = 0;
  for (const c of b.subarray(0, 1 << 20)) {
    if (c >= 0xc0) high++;
    else if ((c | 0x20) >= 0x61 && (c | 0x20) <= 0x7a) ascii++;
    // ğ Ğ ı İ ş Ş; in cp1252 these bytes are Icelandic letters, which Turkish books outnumber by far
    if (c === 0xf0 || c === 0xd0 || c === 0xfd || c === 0xdd || c === 0xfe || c === 0xde) turkish++;
  }
  // Russian text is almost all high bytes; Turkish has a few per word.
  return new TextDecoder(high > ascii ? 'windows-1251' : turkish ? 'windows-1254' : 'windows-1252').decode(b);
}

function parseXml(text) {
  const p = new DOMParser();
  let d = p.parseFromString(text, 'application/xml');
  if (d.getElementsByTagName('parsererror').length) {
    // the usual breakage is a bare & in text
    d = p.parseFromString(text.replace(/&(?!#?\w+;)/g, '&amp;'), 'application/xml');
    if (d.getElementsByTagName('parsererror').length) throw err('corrupt');
  }
  return d;
}

const xmlBytes = b => parseXml(decodeBytes(b, xmlCharset(b)));

/** XHTML as XML first, since self-closing tags matter there; the HTML parser when it is not well formed. */
function parseXhtml(text) {
  const p = new DOMParser();
  const d = p.parseFromString(text, 'application/xhtml+xml');
  return d.getElementsByTagName('parsererror').length ? p.parseFromString(text, 'text/html') : d;
}
const bodyOf = d => d.body ?? tags(d, 'body')[0] ?? d.documentElement;

// ---------------------------------------------------------------------------------------------------------
// Sanitizing: every chapter goes through clean() before it reaches the page

const ALLOWED = new Set('p h1 h2 h3 h4 h5 h6 em i b strong u s sub sup small br hr blockquote ul ol li dl dt dd table thead tbody tr th td caption img a figure figcaption pre code span div section article aside header footer ruby rt rp abbr cite q mark'.split(' '));
const DROP = new Set('script style link meta iframe object embed form input button select textarea option noscript template head title audio video source track canvas map area applet base math param svg'.split(' '));
const ALIAS = { center: 'div', main: 'div', nav: 'div', address: 'div', del: 's', strike: 's', ins: 'u', tt: 'code', kbd: 'code', samp: 'code', var: 'i', dfn: 'i', big: 'span', font: 'span', tfoot: 'tbody' };
const SAFE_URL = /^(blob:|data:image\/)/i;

/**
 * Rebuilds [nodes] through the allowlist as an HTML string.
 * resolve(src) maps an image source to a blob:/data: URL; link(href) maps an internal link to {part, id};
 * rename(el) maps a non-HTML element (FB2, DOCX, ODT) to an HTML tag, '' to drop it with its content;
 * every id gets [prefix] so chapters can share one document.
 */
function clean(nodes, { prefix = '', resolve = () => null, link = () => null, rename } = {}) {
  const out = [];
  let headings = 0;
  const image = el => {
    const src = el.getAttribute('src') ?? attr(el, 'href');
    const url = src && (resolve(src) ?? src);
    if (!url || !SAFE_URL.test(url)) return;
    const alt = el.getAttribute('alt');
    const id = el.getAttribute('id');
    out.push(`<img src="${esc(url)}"${alt ? ` alt="${esc(alt)}"` : ''}${id ? ` id="${esc(prefix + id)}"` : ''}>`);
  };
  const walk = n => {
    if (n.nodeType === 3 || n.nodeType === 4) return void out.push(esc(n.data));
    if (n.nodeType !== 1) return;
    const local = n.localName.toLowerCase();
    const tag = rename?.(n) ?? ALIAS[local] ?? local;
    if (tag === 'img' || tag === 'image') return image(n);
    if (tag === 'svg') {
      const inner = tags(n, 'image');
      if (inner.length === 1) image(inner[0]);
      return;
    }
    if (tag === '' || DROP.has(tag)) return;
    if (!ALLOWED.has(tag)) return n.childNodes.forEach(walk);
    let a = '';
    let id = n.getAttribute('id') ?? (local === 'a' ? n.getAttribute('name') : null);
    if (!id && /^h[1-6]$/.test(tag)) id = `_h${++headings}`; // so the toc can point at every heading
    if (id) a += ` id="${esc(prefix + id)}"`;
    const dir = n.getAttribute('dir');
    if (dir === 'rtl' || dir === 'ltr' || dir === 'auto') a += ` dir="${dir}"`;
    const lang = attr(n, 'lang');
    if (lang && /^[a-z]{2,3}(-[a-z0-9]{1,8})*$/i.test(lang)) a += ` lang="${lang}"`;
    for (const k of ['colspan', 'rowspan']) {
      const v = n.getAttribute(k);
      if (v && /^\d{1,3}$/.test(v)) a += ` ${k}="${v}"`;
    }
    for (const k of ['title', 'alt']) {
      const v = n.getAttribute(k);
      if (v) a += ` ${k}="${esc(v)}"`;
    }
    if (tag === 'a') {
      const href = attr(n, 'href')?.trim();
      if (href && /^https?:\/\//i.test(href)) a += ` href="${esc(href)}" target="_blank" rel="noopener noreferrer"`;
      else if (href) {
        const t = link(href);
        if (t) a += ` data-chapter="${t.part}"` + (t.id ? ` data-anchor="${esc(`c${t.part}-${t.id}`)}"` : '');
      }
    }
    out.push(`<${tag}${a}>`);
    if (tag === 'br' || tag === 'hr') return;
    n.childNodes.forEach(walk);
    out.push(`</${tag}>`);
  };
  for (const n of [...nodes]) walk(n);
  return out.join('');
}

/** Safe HTML from untrusted HTML. Image sources go through [resolve]; only blob: and data:image/ survive. */
export function sanitize(html, resolve = () => null) {
  return clean(new DOMParser().parseFromString(html, 'text/html').body.childNodes, { resolve });
}

// ---------------------------------------------------------------------------------------------------------
// Book shapes

function pagesBook({ format, title, author = '', lang = '', rtl = false, toc = [], count, page, cover }) {
  return { kind: 'pages', format, title, author, lang, manga: true, rtl, count, cover, toc, page, dispose() {} };
}

/** Blob URLs for a text book's pictures, made once per picture and revoked by dispose(). */
function imageUrls() {
  const urls = new Map();
  return {
    urls,
    get: key => urls.get(key) ?? null,
    async load(root, keyOf, load) {
      for (const el of root.querySelectorAll('img, image')) {
        const key = keyOf(el.getAttribute('src') ?? attr(el, 'href') ?? '');
        if (key == null || urls.has(key)) continue;
        const b = await load(key).catch(() => null);
        urls.set(key, b ? URL.createObjectURL(b) : null);
      }
    },
    put(key, blob) {
      if (!urls.has(key)) urls.set(key, blob ? URL.createObjectURL(blob) : null);
      return urls.get(key);
    },
  };
}

/** Top-level nodes of a chapter, looking inside wrappers that are too big or that hold the headings. */
function* blocks(el, byHeadings, onWrapper) {
  for (const n of [...el.childNodes]) {
    if (n.nodeType === 1 && /^(DIV|SECTION|ARTICLE)$/.test(n.nodeName) &&
      (n.outerHTML.length > LIMIT || (byHeadings && n.querySelector(':scope > h1, :scope > h2, :scope > h3')))) {
      onWrapper(n);
      yield* blocks(n, byHeadings, onWrapper);
    } else yield n;
  }
}

/**
 * parts: [{html (cleaned, ids prefixed c<part>-), title}]; toc: [{title, part, id, depth}] or null to build it from headings.
 * byHeadings: the source is one long document, so start a chapter at each top-level heading.
 */
function textBook(meta, parts, toc, byHeadings, images) {
  const chapters = [], firstOf = [], where = new Map(), found = [];
  parts.forEach((part, pi) => {
    firstOf[pi] = chapters.length;
    if (!byHeadings && toc && part.html.length <= LIMIT) return void chapters.push({ html: part.html, title: part.title ?? '' });
    const body = new DOMParser().parseFromString(part.html, 'text/html').body;
    const nodes = [...blocks(body, byHeadings, w => w.id && where.set(esc(w.id), chapters.length))];
    // Split at the highest heading level that occurs more than once (a lone h1 is usually the book's title).
    const levels = nodes.map(n => /^H([1-6])$/.exec(n.nodeName)?.[1]).filter(Boolean).map(Number).sort();
    const level = byHeadings ? levels.find((l, i) => levels[i + 1] === l) ?? levels[0] : 0;
    let chunk = [], size = 0, title = '';
    const flush = force => {
      if (!force && !chunk.some(s => s.trim())) return;
      chapters.push({ html: chunk.join(''), title: title || (chapters.length === firstOf[pi] ? part.title ?? '' : '') });
      chunk = []; size = 0; title = '';
    };
    for (const n of nodes) {
      const h = +(/^H([1-6])$/.exec(n.nodeName)?.[1] ?? 0);
      const s = n.nodeType === 1 ? n.outerHTML : esc(n.textContent);
      if ((h && h <= level) || size + s.length > LIMIT) flush();
      chunk.push(s); size += s.length;
      if (n.nodeType !== 1) continue;
      for (const e of [n, ...n.querySelectorAll('[id]')]) if (e.id) where.set(esc(e.id), chapters.length);
      for (const e of [n, ...n.querySelectorAll('h1, h2, h3')]) {
        const l = +(/^H([1-3])$/.exec(e.nodeName)?.[1] ?? 0);
        const text = l && headingText(e);
        if (!text) continue;
        title ||= text;
        found.push({ title: text, chapter: chapters.length, anchor: e.id || null, level: l });
      }
    }
    flush(chapters.length === firstOf[pi]); // every part keeps at least one chapter
  });

  if (chapters.length !== parts.length) {
    const fix = html => html.replace(/data-chapter="(\d+)"( data-anchor="([^"]*)")?/g,
      (_, c, a = '', id) => `data-chapter="${(id && where.get(id)) ?? firstOf[c]}"${a}`);
    for (const c of chapters) c.html = fix(c.html);
  }
  let entries;
  if (toc) {
    entries = toc.map(t => {
      const anchor = t.id ? `c${t.part}-${t.id}` : null;
      return { title: t.title, chapter: (anchor && where.get(esc(anchor))) ?? firstOf[t.part], anchor, depth: t.depth };
    });
  } else {
    const top = Math.min(...found.map(f => f.level));
    entries = found.map(({ title, chapter, anchor, level }) => ({ title, chapter, anchor, depth: level - top }));
  }
  const named = new Set();
  for (const t of entries) if (chapters[t.chapter] && !named.has(t.chapter)) { named.add(t.chapter); chapters[t.chapter].title = t.title; }
  const lang = meta.lang || '';
  return {
    kind: 'text', format: meta.format, title: meta.title, author: meta.author || '', lang,
    dir: meta.rtl || RTL.test(lang) ? 'rtl' : 'ltr', cover: meta.cover ?? null, chapters, toc: entries,
    dispose() {
      for (const u of images?.urls.values() ?? []) if (u) URL.revokeObjectURL(u);
    },
  };
}

const sameDoc = h => h.startsWith('#') && h.length > 1 ? { part: 0, id: decodeUri(h.slice(1)) } : null;

/** One long HTML document (DOCX, ODT, HTML, Markdown, TXT, RTF): chapters come from its headings. */
const singleDoc = (meta, nodes, opts = {}, images) =>
  textBook(meta, [{ html: clean(nodes, { prefix: 'c0-', link: sameDoc, ...opts }), title: '' }], null, true, images);

const htmlNodes = html => new DOMParser().parseFromString(html, 'text/html').body.childNodes;

// ---------------------------------------------------------------------------------------------------------
// Opening

export function sniffKind(name = '', b = new Uint8Array()) {
  const ext = (/\.([^./]+)$/.exec(name)?.[1] ?? '').toLowerCase();
  const s = head(b, Math.min(b.length, 1024));
  if (s.includes('%PDF-')) return 'pdf';
  if (s.startsWith('PK\x03\x04')) {
    if (s.slice(30, 38) === 'mimetype') {
      if (s.startsWith('application/epub+zip', 38)) return 'epub';
      if (s.startsWith('application/vnd.oasis.opendocument.text', 38)) return 'odt';
    }
    return { epub: 'epub', docx: 'docx', odt: 'odt', fbz: 'fbz', cbz: 'cbz', cbr: 'cbz', cb7: 'cbz' }[ext] ?? 'zip';
  }
  if (s.startsWith('Rar!\x1a\x07')) return 'rar';
  if (s.startsWith('7z\xbc\xaf\x27\x1c')) return '7z';
  if (s.startsWith('AT&TFORM')) return 'djvu';
  if (s.slice(60, 68) === 'BOOKMOBI' || s.slice(60, 68) === 'TEXtREAd') return 'mobi';
  if (s.startsWith('{\\rtf')) return 'rtf';
  if (/^(\xff\xd8\xff|\x89PNG|GIF8|RIFF....WEBP|....ftypavi[fs])/s.test(s)) return 'image';
  const t = decodeBytes(b.subarray(0, 1024)).replace(/^﻿/, '').trimStart();
  if (t.startsWith('<') && t.includes('<FictionBook')) return 'fb2';
  if (/^(<\?xml[^>]*>\s*)?(<!--[\s\S]*?-->\s*)*(<!doctype html|<html)/i.test(t)) return 'html';
  return {
    epub: 'epub', cbz: 'cbz', zip: 'zip', cbr: 'rar', rar: 'rar', cb7: '7z', '7z': '7z', djvu: 'djvu', djv: 'djvu',
    mobi: 'mobi', azw: 'mobi', azw3: 'mobi', prc: 'mobi', pdb: 'mobi', fb2: 'fb2', fbz: 'fbz', docx: 'docx', odt: 'odt',
    rtf: 'rtf', md: 'md', markdown: 'md', txt: 'txt', text: 'txt', html: 'html', htm: 'html', xhtml: 'html', pdf: 'pdf',
    jpg: 'image', jpeg: 'image', png: 'image', gif: 'image', webp: 'image', avif: 'image', bmp: 'image',
  }[ext] ?? null;
}

export async function openFiles(files, onProgress) {
  files = [...files];
  const path = f => f.webkitRelativePath || f.name;
  const images = files.filter(f => IMAGE.test(f.name) && !JUNK.test(path(f)));
  if (files.length > 1 && images.length) return imageSet(images.sort((a, b) => collate(path(a), path(b))));
  const file = files[0];
  if (!file) throw err('unknown');
  const kind = sniffKind(file.name, new Uint8Array(await file.slice(0, 4096).arrayBuffer()));
  if (kind === 'pdf') return (await import('./pdf.js')).openPdf(file);
  if (kind === 'rar' || kind === '7z') return (await import('./archive.js')).openArchive(file, onProgress);
  if (kind === 'djvu') throw err('djvu');
  if (!kind) throw err('unknown');
  try {
    return await open(kind, file, onProgress);
  } catch (e) {
    throw e.code ? e : err('corrupt', e);
  }
}

async function open(kind, file, onProgress) {
  const title = baseName(file.name);
  const bytes = async () => new Uint8Array(await file.arrayBuffer());
  switch (kind) {
    case 'image': return imageSet([file]);
    case 'epub': case 'cbz': case 'zip': case 'docx': case 'odt': case 'fbz': return zipBook(kind, await openZip(file), file.name, onProgress);
    case 'mobi': return mobi(await bytes(), title);
    case 'fb2': return fb2(await bytes(), title);
    case 'rtf': return rtf(await bytes(), title);
    case 'md': return singleDoc({ format: 'md', title }, htmlNodes(markdown(guessText(await bytes()))));
    case 'txt': return singleDoc({ format: 'txt', title }, htmlNodes(plainHtml(guessText(await bytes()))));
    case 'html': return html(await bytes(), title);
  }
  throw err('unknown');
}

function imageSet(files) {
  const folder = files[0].webkitRelativePath?.split('/').slice(-2, -1)[0];
  const page = async i => files[i].type ? files[i] : new Blob([files[i]], { type: mimeOf(files[i].name) });
  return page(0).then(cover => pagesBook({ format: 'images', title: folder || baseName(files[0].name), count: files.length, page, cover }));
}

async function zipBook(kind, zip, fileName, onProgress) {
  const read = async (name, need = true) => {
    const b = await zip.bytes(zip.get(name));
    if (!b && need) throw err('corrupt');
    return b;
  };
  if (kind === 'epub' || (kind === 'zip' && zip.get('META-INF/container.xml'))) return epub(zip, baseName(fileName));
  if (kind === 'docx' || (kind === 'zip' && zip.get('word/document.xml'))) return docx(zip, read, baseName(fileName));
  if (kind === 'odt') return odt(zip, read, baseName(fileName));
  const real = zip.entries.filter(e => !JUNK.test(e.name));
  const images = real.filter(e => IMAGE.test(e.name));
  if (kind !== 'cbz' && kind !== 'fbz' && images.length * 2 < real.length) {
    // A zip around one book: open the biggest book file in it.
    const books = real.filter(e => !/^(image|zip|cbz)$/.test(sniffKind(e.name) ?? 'zip')).sort((a, b) => b.usize - a.usize);
    if (books[0]) {
      const name = books[0].name.split('/').pop();
      return openFiles([new File([await zip.blob(books[0])], name)], onProgress);
    }
  }
  if (kind === 'fbz') {
    const fb = real.find(e => /\.fb2$/i.test(e.name));
    if (fb) return Object.assign(fb2(await zip.bytes(fb), baseName(fileName)), { format: 'fbz' });
  }
  if (!images.length) throw err(kind === 'cbz' ? 'corrupt' : 'unknown');
  return comic(kind, zip, images.sort((a, b) => collate(a.name, b.name)), baseName(fileName));
}

async function comic(format, zip, images, fallback) {
  let title = '', author = '', lang = '', rtl = false;
  const toc = [];
  const info = zip.entries.find(e => /(^|\/)comicinfo\.xml$/i.test(e.name));
  if (info) {
    const d = xmlBytes(await zip.bytes(info));
    const g = n => first(d, n);
    title = g('Title') || [g('Series'), g('Number') && '#' + g('Number')].filter(Boolean).join(' ');
    author = g('Writer');
    lang = g('LanguageISO');
    rtl = g('Manga') === 'YesAndRightToLeft';
    for (const p of tags(d, 'Page')) {
      const mark = p.getAttribute('Bookmark'), at = +p.getAttribute('Image');
      if (mark && at >= 0 && at < images.length) toc.push({ title: mark, page: at, depth: 0 });
    }
  }
  const page = i => zip.blob(images[i], mimeOf(images[i].name));
  return pagesBook({ format, title: title || fallback, author, lang, rtl, toc, count: images.length, page, cover: await page(0) });
}

// ---------------------------------------------------------------------------------------------------------
// EPUB

const dirOf = p => p.slice(0, p.lastIndexOf('/') + 1);
function joinPath(dir, href) {
  const out = dir.split('/').filter(Boolean);
  for (const s of href.split('/')) s === '..' ? out.pop() : s && s !== '.' && out.push(s);
  return out.join('/');
}

async function epub(zip, fallback) {
  const read = async path => {
    const b = await zip.bytes(zip.get(path));
    if (!b) throw err('corrupt');
    return b;
  };
  const enc = zip.get('META-INF/encryption.xml');
  if (enc) {
    // Font obfuscation lives in encryption.xml too and is harmless (fonts are not used); anything else is DRM.
    const d = xmlBytes(await zip.bytes(enc));
    if (tags(d, 'CipherReference').some(c => !/\.(ttf|otf|woff2?|ttc)$/i.test(c.getAttribute('URI') ?? ''))) throw err('drm');
  }
  const opfPath = decodeUri(tags(xmlBytes(await read('META-INF/container.xml')), 'rootfile')[0]?.getAttribute('full-path') ?? '');
  const opf = xmlBytes(await read(opfPath));
  const base = dirOf(opfPath);
  const items = new Map();
  for (const it of tags(opf, 'item')) {
    items.set(it.getAttribute('id'), {
      id: it.getAttribute('id'), path: joinPath(base, decodeUri(it.getAttribute('href') ?? '')),
      type: it.getAttribute('media-type') ?? '', props: it.getAttribute('properties') ?? '',
    });
  }
  const spineEl = tags(opf, 'spine')[0];
  const spine = tags(opf, 'itemref').map(r => items.get(r.getAttribute('idref'))).filter(it => it && zip.get(it.path));
  const index = new Map(spine.map((it, i) => [it.path, i]));
  const metas = tags(opf, 'meta');
  const coverId = metas.find(m => m.getAttribute('name') === 'cover')?.getAttribute('content');
  const coverItem = [...items.values()].find(it => it.props.split(/\s+/).includes('cover-image')) ??
    items.get(coverId) ?? [...items.values()].find(it => it.path === joinPath(base, coverId ?? '') && it.type.startsWith('image/'));
  const meta = {
    format: 'epub', title: first(opf, 'title') || fallback, author: first(opf, 'creator'), lang: first(opf, 'language'),
    rtl: spineEl?.getAttribute('page-progression-direction') === 'rtl',
    cover: coverItem ? await zip.blob(zip.get(coverItem.path), coverItem.type || mimeOf(coverItem.path)) : null,
  };

  const target = (href, dir, self) => {
    const [file, frag] = href.split('#');
    const part = file ? index.get(joinPath(dir, decodeUri(file))) : index.get(self);
    return part === undefined ? null : { part, id: frag ? decodeUri(frag) : null };
  };
  const toc = [];
  const nav = [...items.values()].find(it => it.props.split(/\s+/).includes('nav'));
  const ncx = items.get(spineEl?.getAttribute('toc')) ?? [...items.values()].find(it => it.type === 'application/x-dtbncx+xml');
  if (nav && zip.get(nav.path)) {
    const d = parseXhtml(decodeBytes(await read(nav.path)));
    const navs = tags(d, 'nav');
    const list = navs.find(n => attr(n, 'type') === 'toc') ?? navs[0];
    const walk = (ol, depth) => {
      for (const li of ol?.children ?? []) {
        if (li.localName !== 'li') continue;
        const a = [...li.children].find(c => c.localName === 'a' || c.localName === 'span');
        const t = a?.getAttribute('href') && target(a.getAttribute('href'), dirOf(nav.path), nav.path);
        if (t && textOf(a)) toc.push({ title: textOf(a), ...t, depth });
        walk([...li.children].find(c => c.localName === 'ol'), depth + 1);
      }
    };
    if (list) walk([...list.children].find(c => c.localName === 'ol'), 0);
  }
  if (!toc.length && ncx && zip.get(ncx.path)) {
    const d = xmlBytes(await read(ncx.path));
    const walk = (parent, depth) => {
      for (const np of parent?.children ?? []) {
        if (np.localName !== 'navPoint') continue;
        const label = textOf([...np.children].find(c => c.localName === 'navLabel'));
        const src = [...np.children].find(c => c.localName === 'content')?.getAttribute('src');
        const t = src && target(src, dirOf(ncx.path), ncx.path);
        if (t && label) toc.push({ title: label, ...t, depth });
        walk(np, depth + 1);
      }
    };
    walk(tags(d, 'navMap')[0], 0);
  }

  const docs = [];
  const docOf = async i => {
    if (spine[i].type.startsWith('image/')) return null;
    const b = await read(spine[i].path);
    return docs[i] ??= parseXhtml(decodeBytes(b, xmlCharset(b)));
  };
  const fixed = metas.some(m => m.getAttribute('property') === 'rendition:layout' && textOf(m) === 'pre-paginated');
  if (fixed && spine.length) {
    // Fixed layout (manga and picture books): each spine page wraps one picture, which becomes the page.
    const pages = [];
    for (const [i, it] of spine.entries()) {
      if (it.type.startsWith('image/')) { pages.push(it.path); continue; }
      const d = await docOf(i);
      const srcs = new Set([...d.querySelectorAll('img, image')].map(e => joinPath(dirOf(it.path), decodeUri(e.getAttribute('src') ?? attr(e, 'href') ?? ''))));
      if (srcs.size !== 1 || !zip.get([...srcs][0])) break;
      pages.push([...srcs][0]);
    }
    if (pages.length === spine.length) {
      const page = i => zip.blob(zip.get(pages[i]), mimeOf(pages[i]));
      return pagesBook({
        ...meta, count: pages.length, page, cover: meta.cover ?? await page(0),
        toc: toc.map(t => ({ title: t.title, page: t.part, depth: t.depth })),
      });
    }
  }

  const images = imageUrls();
  const parts = [];
  for (const [i, it] of spine.entries()) {
    const dir = dirOf(it.path);
    const key = src => joinPath(dir, decodeUri(src));
    const d = await docOf(i);
    if (!d) {
      const url = images.put(it.path, await zip.blob(zip.get(it.path), it.type));
      parts.push({ html: url ? `<img src="${esc(url)}">` : '' });
      continue;
    }
    const body = bodyOf(d);
    await images.load(body, key, p => zip.blob(zip.get(p), mimeOf(p)));
    parts.push({ html: clean(body.childNodes, { prefix: `c${i}-`, resolve: src => images.get(key(src)), link: h => target(h, dir, it.path) }) });
  }
  return textBook(meta, parts, toc.length ? toc : null, false, images);
}

// ---------------------------------------------------------------------------------------------------------
// Kindle: MOBI, AZW, AZW3 (PalmDoc compression; Huffman-compressed books are refused)

function palmDecompress(input) {
  const out = new Uint8Array(Math.max(4096 * 2, input.length * 8));
  let o = 0, i = 0;
  while (i < input.length && o < out.length) {
    const c = input[i++];
    if (c >= 1 && c <= 8) for (let n = 0; n < c && i < input.length; n++) out[o++] = input[i++];
    else if (c <= 0x7f) out[o++] = c;
    else if (c >= 0xc0) { out[o++] = 0x20; out[o++] = c ^ 0x80; }
    else if (i < input.length) {
      const pair = (c << 8) | input[i++];
      const distance = (pair & 0x3fff) >> 3, length = (pair & 7) + 3;
      for (let n = 0; n < length && distance > 0 && o - distance >= 0; n++, o++) out[o] = out[o - distance];
    }
  }
  return out.subarray(0, o);
}

/** Text record length without the extra bytes the format appends; [flags] says which kinds are there. */
function trailing(r, flags) {
  let size = r.length;
  for (let bits = flags >> 1; bits; bits >>= 1) {
    if (!(bits & 1)) continue;
    let value = 0, shift = 0;
    while (size > 0) {
      const byte = r[--size];
      value |= (byte & 0x7f) << shift;
      shift += 7;
      if (byte & 0x80 || shift >= 28) break;
    }
    // The read above already stepped over the size bytes, which count within value.
    size = size + shift / 7 - value;
    if (size <= 0) return 0;
  }
  if (flags & 1 && size > 0) size -= (r[size - 1] & 3) + 1;
  return Math.max(0, size);
}

const imageType = b => b[0] === 0xff ? 'image/jpeg' : b[0] === 0x89 ? 'image/png' : b[0] === 0x47 ? 'image/gif' : '';

function mobi(d, fallback) {
  if (d.length < 80) throw err('corrupt');
  const v = new DataView(d.buffer, d.byteOffset, d.byteLength);
  const count = v.getUint16(76);
  const off = i => (i < count ? v.getUint32(78 + 8 * i) : d.length);
  const record = i => d.subarray(off(i), off(i + 1));
  const r0 = record(0), h = new DataView(r0.buffer, r0.byteOffset, r0.byteLength);
  const compression = h.getUint16(0), textRecords = h.getUint16(8);
  const join = (flags, decode) => {
    const parts = [];
    for (let i = 1; i <= textRecords && i < count; i++) {
      const r = record(i).subarray(0, trailing(record(i), flags));
      parts.push(compression === 2 ? palmDecompress(r) : r);
    }
    const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
    parts.reduce((at, p) => (all.set(p, at), at + p.length), 0);
    return new TextDecoder(decode).decode(all);
  };
  if (head(d.subarray(60, 68), 8) === 'TEXtREAd') {
    const title = new TextDecoder('windows-1252').decode(d.subarray(0, 32)).replace(/\0.*$/s, '');
    return singleDoc({ format: 'mobi', title: title || fallback }, htmlNodes(plainHtml(join(0, 'windows-1252'))));
  }
  if (h.getUint16(12) !== 0) throw err('drm');
  if (compression === 17480) throw err('huff');
  const headerLength = h.getUint32(20), encoding = h.getUint32(28), firstImage = h.getUint32(108);
  const flags = headerLength >= 0xe4 ? h.getUint16(0xf2) : 0;
  const utf8 = b => new TextDecoder().decode(b);
  let title = utf8(r0.subarray(h.getUint32(84), h.getUint32(84) + h.getUint32(88))), author = '', lang = '', cover = null;
  const imageRecord = i => (i >= 0 && firstImage + i < count ? record(firstImage + i) : null);
  if (h.getUint32(128) & 0x40) {
    let at = 16 + headerLength;
    const total = h.getUint32(at + 8);
    at += 12;
    for (let i = 0; i < total && at + 8 <= r0.length; i++) {
      const type = h.getUint32(at), size = h.getUint32(at + 4), body = r0.subarray(at + 8, at + size);
      if (type === 100 && !author) author = utf8(body);
      if (type === 503) title = utf8(body);
      if (type === 524) lang = utf8(body);
      if (type === 201 && body.length === 4) {
        const img = imageRecord(new DataView(body.buffer, body.byteOffset, 4).getUint32(0));
        if (img) cover = new Blob([img], { type: imageType(img) });
      }
      at += size;
    }
  }
  const text = join(flags, encoding === 65001 ? 'utf-8' : 'windows-1252').replace(/recindex=["']?(\d+)["']?/gi, 'src="rec:$1"');
  const images = imageUrls();
  const resolve = src => {
    const m = /^rec:(\d+)/.exec(src), k = /kindle:embed:([0-9A-V]+)/i.exec(src);
    const i = m ? +m[1] - 1 : k ? parseInt(k[1], 32) - 1 : -1;
    const img = imageRecord(i);
    return img ? images.put(i, new Blob([img], { type: imageType(img) })) : null;
  };
  // MOBI chapters end at page breaks; links are file positions, which cannot be followed here, so they are dropped.
  const pieces = text.split(/<mbp:pagebreak[^>]*>/i);
  const parts = pieces.map((p, i) => ({ html: clean(htmlNodes(p), { prefix: `c${i}-`, resolve }) }));
  return textBook({ format: 'mobi', title: title || fallback, author, lang, cover }, parts, null, parts.length === 1, images);
}

// ---------------------------------------------------------------------------------------------------------
// FictionBook

function fb2Tag(el) {
  switch (el.localName) {
    case 'title': {
      let depth = 0, body = el.parentElement;
      for (; body && body.localName !== 'body'; body = body.parentElement) if (body.localName === 'section') depth++;
      // note numbers in the notes body must not flood the toc
      if (/notes|comments/.test(body?.getAttribute('name') ?? '')) return depth ? 'h6' : 'h2';
      return 'h' + Math.min(depth + 1, 6);
    }
    case 'subtitle': return 'h6';
    case 'p': return el.parentElement.localName === 'title' ? 'div' : 'p';
    case 'v': case 'text-author': return 'p';
    case 'epigraph': case 'cite': return 'blockquote';
    case 'poem': case 'stanza': return 'div';
    case 'emphasis': return 'em';
    case 'strikethrough': return 's';
    case 'empty-line': return 'br';
    case 'style': return 'span';
    case 'binary': case 'description': return '';
  }
}

function fb2(bytes, fallback) {
  const d = xmlBytes(bytes);
  const binaries = new Map(tags(d, 'binary').map(b => [b.getAttribute('id'), b]));
  const images = imageUrls();
  const resolve = href => {
    const id = href.replace(/^#/, '');
    return images.urls.has(id) ? images.get(id) : images.put(id, dataBlob(binaries.get(id)));
  };
  const info = tags(d, 'title-info')[0] ?? d;
  const who = tags(info, 'author')[0];
  const coverPage = tags(info, 'coverpage')[0];
  const coverId = coverPage && tags(coverPage, 'image').map(e => attr(e, 'href'))[0]?.replace(/^#/, '');
  const groups = [];
  for (const body of tags(d, 'body')) {
    if (/notes|comments/.test(body.getAttribute('name') ?? '')) { groups.push([body]); continue; }
    let lead = [];
    for (const n of body.childNodes) {
      if (n.localName === 'section') {
        if (lead.some(x => x.nodeType === 1)) groups.push(lead);
        lead = [];
        groups.push([n]);
      } else lead.push(n);
    }
    if (lead.some(x => x.nodeType === 1)) groups.push(lead);
  }
  const owner = new Map();
  groups.forEach((g, i) => g.forEach(n => n.nodeType === 1 && [n, ...n.querySelectorAll('[id]')].forEach(e => e.getAttribute('id') && owner.set(e.getAttribute('id'), i))));
  const link = h => {
    const id = h.startsWith('#') ? h.slice(1) : null;
    return owner.has(id) ? { part: owner.get(id), id } : null;
  };
  const parts = groups.map((g, i) => ({ html: clean(g, { prefix: `c${i}-`, resolve, link, rename: fb2Tag }) }));
  const meta = {
    format: 'fb2', title: first(info, 'book-title') || fallback, lang: first(info, 'lang'),
    author: who ? ['first-name', 'middle-name', 'last-name'].map(n => first(who, n)).filter(Boolean).join(' ') || first(who, 'nickname') : '',
    cover: coverId ? dataBlob(binaries.get(coverId)) : null,
  };
  return textBook(meta, parts, null, false, images);
}

function dataBlob(b) {
  try {
    const raw = atob(b.textContent.replace(/\s/g, ''));
    return new Blob([Uint8Array.from(raw, c => c.charCodeAt(0))], { type: b.getAttribute('content-type') ?? '' });
  } catch {
    return null; // one bad picture should not lose the book
  }
}

// ---------------------------------------------------------------------------------------------------------
// Office documents

const on = el => el && !/^(0|false|off|none)$/.test(attr(el, 'val') ?? '');
const child = (el, name) => el && [...el.children].find(c => c.localName === name);

async function docx(zip, read, fallback) {
  const doc = xmlBytes(await read('word/document.xml'));
  const rels = new Map();
  const relXml = await read('word/_rels/document.xml.rels', false);
  if (relXml) for (const r of tags(xmlBytes(relXml), 'Relationship')) rels.set(r.getAttribute('Id'), r);
  const levels = new Map();
  const styles = await read('word/styles.xml', false);
  if (styles) {
    for (const s of tags(xmlBytes(styles), 'style')) {
      // Built-in style names stay English ("heading 1") whatever the language of Word.
      const name = attr(child(s, 'name') ?? s, 'val') ?? '';
      const outline = attr(child(child(s, 'pPr'), 'outlineLvl') ?? s, 'val');
      const level = /^heading (\d)$/i.exec(name)?.[1] ?? (/^title$/i.test(name) ? 1 : outline != null && +outline < 6 ? +outline + 1 : 0);
      if (+level) levels.set(attr(s, 'styleId'), +level);
    }
  }
  const core = await read('docProps/core.xml', false);
  const props = core ? xmlBytes(core) : null;

  for (const el of tags(doc, '*')) {
    const name = el.localName;
    if (name === 'tab' && el.parentElement?.localName === 'r') el.replaceWith(' ');
    else if (name === 'drawing' || name === 'pict') {
      const ref = tags(el, 'blip').map(b => attr(b, 'embed'))[0] ?? tags(el, 'imagedata').map(b => attr(b, 'id'))[0];
      const target = rels.get(ref)?.getAttribute('Target');
      const img = doc.createElementNS(null, 'img');
      if (target) img.setAttribute('src', target.startsWith('/') ? target.slice(1) : joinPath('word', target));
      el.replaceWith(img);
    } else if (name === 'hyperlink') {
      const r = rels.get(attr(el, 'id'));
      const anchor = attr(el, 'anchor');
      el.setAttribute('href', r?.getAttribute('TargetMode') === 'External' ? r.getAttribute('Target') : anchor ? '#' + anchor : '');
    } else if (name === 'bookmarkStart') el.setAttribute('id', attr(el, 'name') ?? '');
  }
  const rename = el => {
    switch (el.localName) {
      case 'p': {
        const pPr = child(el, 'pPr');
        const level = levels.get(attr(child(pPr, 'pStyle') ?? el, 'val')) ??
          +(/(?:heading|başlık|balk)\s*(\d)/i.exec(attr(child(pPr, 'pStyle') ?? el, 'val') ?? '')?.[1] ?? 0);
        return level ? 'h' + Math.min(level, 6) : 'p';
      }
      case 'r': {
        const rPr = child(el, 'rPr');
        return on(child(rPr, 'b')) ? 'b' : on(child(rPr, 'i')) ? 'i' : 'run';
      }
      case 'tbl': return 'table';
      case 'tc': return 'td';
      case 'tr': case 'br': return el.localName;
      case 'hyperlink': return 'a';
      case 'bookmarkStart': return 'span';
      case 'img': return 'img';
      case 'instrText': case 'delText': case 'del': case 'Fallback': case 'pPr': case 'rPr': case 'tblPr': case 'sectPr': return '';
      default: return 'unwrap';
    }
  };
  const images = imageUrls();
  const body = tags(doc, 'body')[0];
  if (!body) throw err('corrupt');
  await images.load(body, src => src, p => zip.blob(zip.get(p), mimeOf(p)));
  const meta = { format: 'docx', title: props && first(props, 'title') || fallback, author: props ? first(props, 'creator') : '', lang: props ? first(props, 'language') : '' };
  return singleDoc(meta, body.childNodes, { resolve: src => images.get(src), rename }, images);
}

async function odt(zip, read, fallback) {
  const doc = xmlBytes(await read('content.xml'));
  const m = await read('meta.xml', false), st = await read('styles.xml', false);
  const metaXml = m ? xmlBytes(m) : null;
  for (const el of tags(doc, '*')) if (el.localName === 's' || el.localName === 'tab') el.replaceWith(' ');
  // LibreOffice often writes headings as paragraphs in a heading style, or in an automatic style based on one.
  const styles = [...tags(doc, 'style'), ...(st ? tags(xmlBytes(st), 'style') : [])];
  const byName = new Map(styles.map(x => [attr(x, 'name'), x]));
  const own = x => +(attr(x, 'default-outline-level') || /^Heading_20_(\d)$/.exec(attr(x, 'name'))?.[1] || 0);
  const levels = new Map();
  for (const x of styles) {
    let level = own(x);
    for (let p = x, k = 0; !level && k < 5 && (p = byName.get(attr(p, 'parent-style-name'))); k++) level = own(p);
    if (level) levels.set(attr(x, 'name'), level);
  }
  const rename = el => {
    switch (el.localName) {
      case 'h': return 'h' + Math.min(+(attr(el, 'outline-level') || 1), 6);
      case 'p': return levels.has(attr(el, 'style-name')) ? 'h' + Math.min(levels.get(attr(el, 'style-name')), 6) : 'p';
      case 'list': return 'ul';
      case 'list-item': return 'li';
      case 'table-row': return 'tr';
      case 'table-cell': return 'td';
      case 'line-break': return 'br';
      case 'note-citation': return 'sup';
      case 'note-body': return 'small';
      case 'tracked-changes': case 'annotation': case 'sequence-decls': case 'table-columns': case 'table-column': return '';
      case 'a': case 'span': case 'table': case 'image': case 'section': return el.localName;
      default: return 'unwrap';
    }
  };
  const body = tags(doc, 'text')[0];
  if (!body) throw err('corrupt');
  const images = imageUrls();
  await images.load(body, src => decodeUri(src), p => zip.blob(zip.get(p), mimeOf(p)));
  const meta = {
    format: 'odt', title: metaXml && first(metaXml, 'title') || fallback, lang: metaXml ? first(metaXml, 'language') : '',
    author: metaXml ? first(metaXml, 'creator') || first(metaXml, 'initial-creator') : '',
  };
  return singleDoc(meta, body.childNodes, { resolve: src => images.get(decodeUri(src)), rename }, images);
}

// ---------------------------------------------------------------------------------------------------------
// HTML, Markdown, RTF, plain text

function html(bytes, fallback) {
  const d = new DOMParser().parseFromString(decodeBytes(bytes, htmlCharset(bytes)), 'text/html');
  const meta = {
    format: 'html', title: textOf(d.querySelector('title')) || fallback, lang: d.documentElement.getAttribute('lang') ?? '', rtl: d.documentElement.dir === 'rtl',
    author: d.querySelector('meta[name="author" i]')?.getAttribute('content') ?? '',
  };
  return singleDoc(meta, d.body.childNodes);
}

// Chapter headings in plain text: "Chapter 3", "Bölüm 3", "3. Bölüm", "BİRİNCİ BÖLÜM", "Глава 3", "XII", "12".
const HEADING = /^(?:(?:chapter|part|book|prologue|epilogue|introduction|bölüm|kısım|kitap|önsöz|sonsöz|giriş|глава|часть|книга|пролог|эпилог)(?!\p{L}).*|[\p{L}\d]+\.?\s+(?:bölüm|kısım|kitap)|[IVXLCDM]+\.?|\d{1,3}\.?)$/iu;

function plainHtml(text) {
  text = text.replace(/\r\n?/g, '\n');
  let paragraphs = text.split(/\n[ \t]*\n/);
  const lines = text.split('\n').length;
  // No blank lines between paragraphs: then every line is one.
  if (paragraphs.length < 3 || paragraphs.length * 30 < lines) paragraphs = text.split('\n');
  return paragraphs.map(p => p.trim()).filter(Boolean)
    .map(p => !p.includes('\n') && p.length < 80 && HEADING.test(p) ? `<h2>${esc(p)}</h2>` : `<p>${esc(p).replace(/\s*\n\s*/g, ' ')}</p>`)
    .join('\n');
}

function markdown(src) {
  const inline = s => esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/!\[([^\]]*)\]\(([^)\s]+)[^)]*\)/g, '<img alt="$1" src="$2">')
    .replace(/\[([^\]]+)\]\(([^)\s]+)[^)]*\)/g, '<a href="$2">$1</a>')
    .replace(/\*\*(.+?)\*\*|__(.+?)__/g, '<strong>$1$2</strong>')
    .replace(/\*(.+?)\*|(^|\W)_(.+?)_(?!\w)/g, (_, a, pre, b) => a ? `<em>${a}</em>` : `${pre}<em>${b}</em>`);
  const out = [];
  let para = [], list = null, fence = null;
  const flush = () => { if (para.length) out.push(`<p>${inline(para.join(' '))}</p>`); para = []; };
  const close = () => { flush(); if (list) out.push(`</${list}>`); list = null; };
  for (const raw of src.replace(/\r\n?/g, '\n').split('\n')) {
    const line = raw.trim();
    let m;
    if (fence) {
      if (/^(```|~~~)/.test(line)) { out.push(`<pre><code>${esc(fence.join('\n'))}</code></pre>`); fence = null; } else fence.push(raw);
    } else if (/^(```|~~~)/.test(line)) { close(); fence = []; }
    else if (!line) close();
    else if ((m = /^(#{1,6})\s+(.*?)\s*#*$/.exec(line))) { close(); out.push(`<h${m[1].length}>${inline(m[2])}</h${m[1].length}>`); }
    else if (/^(=+|-+)$/.test(line) && para.length) { const p = para.join(' '); para = []; close(); out.push(line[0] === '=' ? `<h1>${inline(p)}</h1>` : `<h2>${inline(p)}</h2>`); }
    else if (/^([-*_])(\s*\1){2,}$/.test(line)) { close(); out.push('<hr>'); }
    else if ((m = /^([-*+]|\d+[.)])\s+(.*)$/.exec(line))) {
      flush();
      const t = /\d/.test(m[1]) ? 'ol' : 'ul';
      if (list !== t) { close(); out.push(`<${t}>`); list = t; }
      out.push(`<li>${inline(m[2])}</li>`);
    } else if ((m = /^>\s?(.*)$/.exec(line))) { close(); out.push(`<blockquote><p>${inline(m[1])}</p></blockquote>`); }
    else { if (list) close(); para.push(line); }
  }
  if (fence) out.push(`<pre><code>${esc(fence.join('\n'))}</code></pre>`);
  close();
  return out.join('\n');
}

const RTF_SKIP = new Set(['fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'header', 'footer', 'headerl', 'headerr', 'footerl', 'footerr', 'listtable', 'listoverridetable', 'rsidtbl', 'xmlnstbl', 'themedata', 'colorschememapping', 'latentstyles', 'datastore', 'object', 'fldinst', 'generator']);
const RTF_CHAR = { tab: '\t', emdash: '—', endash: '–', lquote: '‘', rquote: '’', ldblquote: '“', rdblquote: '”', bullet: '•', cell: ' ', '*': '', '~': ' ', '_': '‑', '-': '' };

function rtf(bytes, fallback) {
  const page = /\\ansicpg(\d+)/.exec(head(bytes, 4096))?.[1];
  let decoder;
  try { decoder = new TextDecoder(page ? 'windows-' + page : 'windows-1252'); } catch { decoder = new TextDecoder('windows-1252'); }
  // The code page is ASCII-compatible, so the markup reads the same; raw 8-bit text comes out right too.
  const s = decoder.decode(bytes);
  let out = '', pending = [], depth = 0, skip = -1, uc = 1;
  const flush = () => { if (pending.length) out += decoder.decode(Uint8Array.from(pending)); pending = []; };
  const word = /\\([a-zA-Z]+)(-?\d+)? ?|\\'([0-9a-fA-F]{2})|\\(.)/y;
  for (let i = 0; i < s.length;) {
    const c = s[i];
    if (c === '{') { depth++; i++; if (s.startsWith('\\*', i) && skip < 0) skip = depth - 1; continue; }
    if (c === '}') { depth--; if (depth <= skip) skip = -1; i++; continue; }
    if (c !== '\\') {
      if (skip < 0 && c !== '\r' && c !== '\n') { flush(); out += c; }
      i++;
      continue;
    }
    word.lastIndex = i;
    const m = word.exec(s);
    if (!m) { i++; continue; }
    i = word.lastIndex;
    if (skip >= 0) continue;
    if (m[3]) pending.push(parseInt(m[3], 16));
    else if (m[4] != null) { flush(); out += RTF_CHAR[m[4]] ?? (m[4] === '\n' || m[4] === '\r' ? '\n\n' : m[4]); }
    else if (m[1] === 'par' || m[1] === 'line' || m[1] === 'sect' || m[1] === 'page' || m[1] === 'row') { flush(); out += '\n\n'; }
    else if (m[1] === 'uc') uc = +(m[2] ?? 1);
    else if (m[1] === 'u') {
      flush();
      const v = +(m[2] ?? 0);
      out += String.fromCharCode(v < 0 ? v + 65536 : v);
      // skip the fallback characters that follow \u
      for (let n = 0; n < uc && i < s.length; n++) i = s[i] === '\\' && s[i + 1] === "'" ? i + 4 : s[i] === '\\' || s[i] === '{' || s[i] === '}' ? i : i + 1;
    } else if (RTF_CHAR[m[1]]) { flush(); out += RTF_CHAR[m[1]]; }
    else if (RTF_SKIP.has(m[1])) skip = depth - 1;
  }
  flush();
  return singleDoc({ format: 'rtf', title: fallback }, htmlNodes(plainHtml(out.replace(/\n\n+/g, '\n\n'))));
}
