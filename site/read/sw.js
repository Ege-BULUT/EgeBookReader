// Keeps the web reader working offline, and takes files from Android's share sheet into the library.
const CACHE = 'ebr-web-1';
const SHELL = ['/read/', '/read/read.css', '/read/boot.js', '/read/app.js', '/read/store.js', '/read/text.js', '/read/pages.js',
  '/read/formats.js', '/read/zip.js', '/read/manifest.webmanifest', '/read/icon-192.png', '/curl.frag.js', '/logo.svg', '/manga/ghost.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(SHELL.map(u => c.add(u).catch(() => {})))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k.startsWith('ebr-web-') && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});

self.addEventListener('fetch', e => {
  const r = e.request, url = new URL(r.url);
  if (r.method === 'POST' && url.pathname === '/read/share') return e.respondWith(share(r));
  if (r.method !== 'GET' || url.origin !== location.origin) return;
  if (r.mode === 'navigate') {
    // The page itself: the network first, so a new version shows at once; the copy kept here when offline.
    e.respondWith(fetch(r).then(res => { const c = res.clone(); caches.open(CACHE).then(k => k.put('/read/', c)); return res; }).catch(() => caches.match('/read/')));
    return;
  }
  if (!url.pathname.startsWith('/read/') && !SHELL.includes(url.pathname) && !url.pathname.startsWith('/manga/')) return;
  e.respondWith(caches.open(CACHE).then(async c => {
    const hit = await c.match(r);
    const net = fetch(r).then(res => { if (res.ok) c.put(r, res.clone()); return res; });
    if (hit) { e.waitUntil(net.catch(() => {})); return hit; }
    return net;
  }));
});

async function share(req) {
  try {
    const files = (await req.formData()).getAll('files').filter(f => f && f.size);
    if (files.length) await new Promise((res, rej) => {
      const o = indexedDB.open('ebr-web', 1);
      o.onupgradeneeded = () => { const d = o.result; d.createObjectStore('books', { keyPath: 'id' }); d.createObjectStore('files'); d.createObjectStore('inbox', { autoIncrement: true }); };
      o.onsuccess = () => { const t = o.result.transaction('inbox', 'readwrite'); t.objectStore('inbox').add(files); t.oncomplete = res; t.onerror = () => rej(t.error); };
      o.onerror = () => rej(o.error);
    });
  } catch (e) {}
  return Response.redirect('/read/?shared=1', 303);
}
