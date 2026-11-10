const VERSION = '0.1.0';
const T = {
  en: {
    contents:'Contents',open:'Tap the cover to open',download:'Download for Android',version:'Version',epigraph:'Every book is a universe that fits in your bag.',
    home:'Home',shots:'Screenshots',features:'Features',downloads:'Downloads',changelog:'Changelog',privacy:'Privacy notice',links:'Links',
    home1:'A reader built around how reading feels.',
    home2:'Pages curl under your finger, wherever you take hold of them. Turn on actual book mode and the screen gets paper grain, the shadow of the fold and the stack of pages at the edges.',
    home3:'Black-and-white manga can be coloured on your phone, without the internet. Books can be read aloud in a voice you choose. It is free, it has no ads, and the code is open.',
    dl1:'The Android app is ready to try.',apk:'Download APK',soon:'Later',dl2:'Android will ask you to allow installs from your browser. The app is not on Google Play yet.',source:'Source code',
    models:'Downloadable models',modelsText:'Models are fetched from their authors only when you ask. Manga Light Colorizer (sharky172) is CC BY-NC-SA 4.0, DDColor is Apache-2.0, Supertonic is OpenRAIL-M, Kokoro is Apache-2.0.',
    credits:'Credits',creditsText:'Sample pages: Pepper&Carrot by David Revoy (CC BY 4.0). Give My Regards to Black Jack by SHUHO SATO. Fonts from Fontsource. Cover silhouettes from game-icons.net (CC BY 3.0). EgeBookReader is licensed under AGPL-3.0.',
    colorize:'Colorized on the phone',colorNote:'Original, then model 1 and model 2. Tap to enlarge.',contact:'Contact',bug:'Report a bug',request:'Request a feature',
  },
  tr: {
    contents:'İçindekiler',open:'Açmak için kapağa dokun',download:'Android için indir',version:'Sürüm',epigraph:'Her bir kitap çantanıza sığan bir evrendir.',
    home:'Ana sayfa',shots:'Ekran görüntüleri',features:'Özellikler',downloads:'İndirmeler',changelog:'Değişiklikler',privacy:'Aydınlatma metni',links:'Bağlantılar',
    home1:'Okumanın hissine göre yapılmış bir kitap okuyucu.',
    home2:'Sayfalar, neresinden tutarsan tut parmağının altında kıvrılır. Gerçek kitap modunu açınca ekrana kağıt dokusu, cilt gölgesi ve kenarlarda sayfa yığını gelir.',
    home3:'Siyah beyaz mangalar telefonunda, internetsiz renklenir. Kitaplar seçtiğin sesle okunur. Ücretsizdir, reklam yoktur, kodu açıktır.',
    dl1:'Android uygulaması denemeye hazır.',apk:'APK indir',soon:'Daha sonra',dl2:'Android, tarayıcından yükleme izni isteyecek. Uygulama henüz Google Play\'de değil.',source:'Kaynak kod',
    models:'İndirilebilir modeller',modelsText:'Modeller sadece sen istediğinde, yazarlarının kendi adreslerinden iner. Manga Light Colorizer (sharky172) CC BY-NC-SA 4.0, DDColor Apache-2.0, Supertonic OpenRAIL-M, Kokoro Apache-2.0 lisanslıdır.',
    credits:'Teşekkürler',creditsText:'Örnek sayfalar: David Revoy, Pepper&Carrot (CC BY 4.0). SHUHO SATO, Give My Regards to Black Jack. Fontlar Fontsource\'tan. Kapak siluetleri game-icons.net (CC BY 3.0). EgeBookReader AGPL-3.0 ile lisanslıdır.',
    colorize:'Telefonda renklendirme',colorNote:'Orijinal, model 1 ve model 2. Büyütmek için dokun.',contact:'İletişim',bug:'Hata bildir',request:'Özellik iste',
  },
};
const FEATURES = {
  en:[['Every common format','PDF, EPUB, MOBI, AZW3, FB2, CBZ, CBR, DOCX, RTF, Markdown and more.'],['A page that really turns','Follows your finger, from the corner, the edge or the middle, on one page or two.'],['Your tap zones','Draw rectangles and circles on the screen and decide what each does.'],['Actual book mode','Paper grain, fold, lighting, side pages and a shadow on the table.'],['Themes','Paper, Parchment, OLED, E-ink and your own background, in light and dark.'],['2,100 free fonts','With previews, plus your own by file or URL.'],['On-device colorization','Black-and-white pictures get colour, offline, in the same place at the same size.'],['Read aloud','System voice, downloadable voices in 31 languages, or your own API key.'],['Pinch and pictures','Zoom any page. Tap a picture to open it, switch colour on and off.']],
  tr:[['Tüm yaygın biçimler','PDF, EPUB, MOBI, AZW3, FB2, CBZ, CBR, DOCX, RTF, Markdown ve dahası.'],['Gerçekten dönen sayfa','Parmağını izler; köşeden, kenardan, ortadan, tek ya da çift sayfada.'],['Kendi dokunma alanların','Ekrana dikdörtgen ve daire çiz, her birine ne yapacağını söyle.'],['Gerçek kitap modu','Kağıt dokusu, cilt, ışık, yan sayfalar ve masadaki gölge.'],['Temalar','Kağıt, Parşömen, OLED, E-ink ve kendi arka planın, açık ve koyu.'],['2.100 ücretsiz font','Önizlemeli; dosya veya adresle kendi fontunu da eklersin.'],['Telefonda renklendirme','Siyah beyaz görseller internetsiz, aynı yerde aynı boyutta renklenir.'],['Sesli okuma','Sistem sesi, 31 dilde indirilebilir sesler veya kendi API anahtarın.'],['Zoom ve görseller','Her sayfaya zoom. Görsele dokun, aç, rengi aç kapat.']],
};
const CHANGES = {
  en:[['0.1.0','First public version for Android. Reader, formats, themes, colorization, read aloud, picture viewer, English and Turkish.']],
  tr:[['0.1.0','Android için ilk genel sürüm. Okuyucu, biçimler, temalar, renklendirme, sesli okuma, görsel görüntüleyici, Türkçe ve İngilizce.']],
};
const PRIVACY = {
  en:`<p><b>Who.</b> EgeBookReader is developed by Ege BULUT. Contact: egebulut.iletisim@outlook.com.</p><p><b>What the app collects.</b> Nothing. There is no account, no analytics and no advertising. Your books, settings, bookmarks and coloured pictures stay on your device.</p><p><b>When the app uses the internet.</b> Only when you ask for something that needs it: the font list and fonts come from Fontsource and jsDelivr; colorization models from Hugging Face or Qualcomm; voices from GitHub. Those services see your IP address, as any website does.</p><p><b>API keys.</b> If you add your own read-aloud API key, the text being read is sent to the service you chose, under that service's terms. The key stays on your device.</p><p><b>This website.</b> It is hosted on Vercel, which keeps standard access logs. The site sets no cookies and has no analytics. Fonts load from Google Fonts.</p><p><b>Your rights.</b> Since the app holds no data about you on any server, deleting the app deletes everything. For questions, write to the address above.</p>`,
  tr:`<p><b>Veri sorumlusu.</b> EgeBookReader, Ege BULUT tarafından geliştirilir. İletişim: egebulut.iletisim@outlook.com.</p><p><b>Uygulamanın topladığı veriler.</b> Hiçbiri. Hesap, analiz ve reklam yoktur. Kitapların, ayarların, yer imlerin ve renklendirdiğin görseller cihazında kalır.</p><p><b>Uygulama internete ne zaman çıkar.</b> Sadece sen internet gerektiren bir şey istediğinde: font listesi ve fontlar Fontsource ve jsDelivr'den, renklendirme modelleri Hugging Face veya Qualcomm'dan, sesler GitHub'dan iner. Bu servisler, her web sitesi gibi IP adresini görür.</p><p><b>API anahtarları.</b> Kendi sesli okuma API anahtarını eklersen, okunan metin seçtiğin servise o servisin koşullarıyla gönderilir. Anahtar cihazında kalır.</p><p><b>Bu web sitesi.</b> Vercel'de barındırılır; Vercel standart erişim kayıtları tutar. Site çerez kullanmaz, analiz aracı yoktur. Fontlar Google Fonts'tan yüklenir.</p><p><b>Hakların.</b> Uygulama hiçbir sunucuda senin hakkında veri tutmadığı için uygulamayı silmek her şeyi siler. Soruların için yukarıdaki adrese yazabilirsin.</p>`,
};
const SHOTS = ['library','flip','book','colorize','viewer'];
const COMPARE = ['book','manga'].flatMap(k => ['orig','ddcolor','manga'].map(v => `compare-${k}-${v}`));

let lang = localStorage.getItem('lang') || (navigator.language.startsWith('tr') ? 'tr' : 'en');
const $ = (s, r = document) => r.querySelector(s);
const bookEl = $('#book'), leftSlot = $('#left'), rightSlot = $('#right'), canvas = $('#curl'), coverLeaf = $('#coverleaf'), press = $('#press');
const narrow = () => matchMedia('(max-aspect-ratio:1/1)').matches;
const reduced = matchMedia('(prefers-reduced-motion:reduce)').matches;
const PAPER = [0.968, 0.953, 0.918];

// Paper grain as an opaque tile, so the live page and its picture for the curl look the same.
(function grain() {
  const c = document.createElement('canvas'); c.width = c.height = 180;
  const g = c.getContext('2d'), d = g.createImageData(180, 180);
  for (let i = 0; i < d.data.length; i += 4) { const n = Math.random() * 9 - 6; d.data[i] = 247 + n; d.data[i + 1] = 243 + n; d.data[i + 2] = 234 + n; d.data[i + 3] = 255; }
  g.putImageData(d, 0, 0);
  document.documentElement.style.setProperty('--grain', `url(${c.toDataURL()})`);
})();

function pageEl(id, n) {
  const f = document.createDocumentFragment();
  f.append($('#' + id).content.cloneNode(true));
  const root = f.firstElementChild;
  if (n) { const folio = document.createElement('span'); folio.className = 'folio'; folio.textContent = n; root.append(folio); }
  fill(root);
  return root;
}

function fill(root) {
  root.querySelectorAll('[data-t]').forEach(e => { e.textContent = T[lang][e.dataset.t] ?? e.textContent; });
  const shots = $('#shots', root);
  if (shots) shots.replaceChildren(...SHOTS.map(s => { const i = new Image(); i.src = `shots/${s}.jpg`; i.alt = s; return i; }));
  const cmp = $('#compare', root);
  if (cmp) cmp.replaceChildren(...COMPARE.map(s => { const i = new Image(); i.src = `shots/${s}.jpg`; i.alt = s; return i; }));
  const fl = $('#featurelist', root);
  if (fl) fl.replaceChildren(...FEATURES[lang].flatMap(([a, b]) => { const dt = document.createElement('dt'), dd = document.createElement('dd'); dt.textContent = a; dd.textContent = b; return [dt, dd]; }));
  const ch = $('#changes', root);
  if (ch) ch.innerHTML = CHANGES[lang].map(([v, t]) => `<div class="change"><b>${v}</b><p>${t}</p></div>`).join('');
  const pr = $('#privacy', root);
  if (pr) pr.innerHTML = PRIVACY[lang];
  const v = $('#version', root);
  if (v) v.textContent = VERSION;
}

function zoom(src) {
  const box = document.createElement('div');
  box.id = 'lightbox';
  const i = new Image(); i.src = src;
  box.append(i); box.onclick = () => box.remove();
  document.body.append(box);
}

// ---- the book ---------------------------------------------------------------------------------------
const IDS = ['endpaper', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'back'];
let views = [];         // each view is what lies open: {left, right} ids (left is null on one-page screens)
let at = -1;            // view on show; -1 is the closed cover
let busy = false;
const textures = {};    // page id -> GL texture
const elements = {};    // page id -> the page's element for the press

function buildViews() {
  views = [];
  if (narrow()) IDS.slice(1, 9).forEach(id => views.push({ left: null, right: id }));
  else for (let i = 0; i + 1 < IDS.length; i += 2) views.push({ left: IDS[i], right: IDS[i + 1] });
}

function numbered(id) { const m = /^p(\d)$/.exec(id); return m ? +m[1] : 0; }

function makePage(id) { return pageEl(id, numbered(id)); }

function showView() {
  const v = views[at];
  leftSlot.replaceChildren(...(v && v.left ? [makePage(v.left)] : []));
  rightSlot.replaceChildren(...(v ? [makePage(v.right)] : []));
  wirePage(leftSlot); wirePage(rightSlot);
  bookEl.classList.toggle('closed', at < 0 && !narrow());
  $('#controls').hidden = at < 0;
}

function wirePage(root) {
  root.querySelectorAll('[data-go]').forEach(a => a.onclick = e => { e.stopPropagation(); goTo(+a.dataset.go); });
  root.querySelectorAll('.shots img,.compare img').forEach(i => i.onclick = e => { e.stopPropagation(); zoom(i.src); });
}

// Long pages shrink until they fit, because a page in a book does not scroll.
function fit(el) {
  let scale = 1;
  const base = parseFloat(getComputedStyle(el).fontSize);
  while (el.scrollHeight > el.clientHeight + 1 && scale > .62) { scale -= .03; el.style.fontSize = base * scale + 'px'; }
}

// ---- pictures of the pages, for the curl -------------------------------------------------------------
async function pressPage(id) {
  const el = makePage(id);
  const box = document.createElement('div');
  box.append(el); press.append(box);
  fit(el);
  await Promise.all([...el.querySelectorAll('img')].map(i => i.decode().catch(() => {})));
  const c = await html2canvas(box, { scale: Math.min(2, devicePixelRatio || 1), backgroundColor: '#f7f3ea', logging: false, useCORS: true });
  box.remove();
  // the same fold shadow the live page has
  const g = c.getContext('2d');
  const onLeft = views.some(v => v.left === id);
  const grad = g.createLinearGradient(onLeft ? c.width : 0, 0, onLeft ? c.width * .87 : c.width * .13, 0);
  grad.addColorStop(0, 'rgba(40,25,10,.34)'); grad.addColorStop(.38, 'rgba(40,25,10,.09)'); grad.addColorStop(1, 'rgba(40,25,10,0)');
  g.fillStyle = grad; g.fillRect(0, 0, c.width, c.height);
  upload(id, c);
}

let pressing = Promise.resolve();
function pressAll() { for (const id of IDS.slice(0, -1).concat('back')) pressing = pressing.then(() => pressPage(id)); return pressing; }

// ---- WebGL ------------------------------------------------------------------------------------------
const gl = canvas.getContext('webgl2', { premultipliedAlpha: false, antialias: false });
let uni = {}, blank;
function initGL() {
  if (!gl) return;
  const compile = (type, src) => { const s = gl.createShader(type); gl.shaderSource(s, src); gl.compileShader(s); if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) console.error(gl.getShaderInfoLog(s)); return s; };
  const p = gl.createProgram();
  gl.attachShader(p, compile(gl.VERTEX_SHADER, `#version 300 es
    out vec2 v; void main(){ vec2 c=vec2((gl_VertexID<<1)&2, gl_VertexID&2); v=vec2(c.x,c.y); gl_Position=vec4(c.x*2.-1., 1.-c.y*2., 0.,1.); }`));
  gl.attachShader(p, compile(gl.FRAGMENT_SHADER, CURL_FRAG));
  gl.linkProgram(p); gl.useProgram(p);
  for (const n of ['uSize', 'uHinge', 'uPageW', 'uT', 'uR', 'uShowThrough', 'uN', 'uPaper', 'uFront', 'uBack', 'uUnder', 'uLeft']) uni[n] = gl.getUniformLocation(p, n);
  gl.bindVertexArray(gl.createVertexArray());
  gl.uniform1i(uni.uFront, 0); gl.uniform1i(uni.uBack, 1); gl.uniform1i(uni.uUnder, 2); gl.uniform1i(uni.uLeft, 3);
  blank = gl.createTexture(); gl.bindTexture(gl.TEXTURE_2D, blank);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([247, 243, 234, 255]));
}
function upload(id, source) {
  if (!gl) return;
  const t = textures[id] || gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, t);
  gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, source);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  textures[id] = t;
}

// ---- the turn: same geometry as the app (lib/curl.dart) -----------------------------------------------
let turn = null;
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

function metrics() {
  const b = bookEl.getBoundingClientRect();
  const spread = !narrow();
  return { W: b.width, H: b.height, spread, hinge: spread ? b.width / 2 : 0, pageW: spread ? b.width / 2 : b.width, left: b.left, top: b.top };
}

function draw() {
  const { n, t, r } = computeFold(turn.grab, turn.f, turn.m.hinge, turn.m.pageW, Math.min(turn.m.pageW, turn.m.H) * .14, turn.tilt);
  const dpr = canvas.width / turn.m.W;
  gl.viewport(0, 0, canvas.width, canvas.height);
  gl.uniform2f(uni.uSize, turn.m.W, turn.m.H);
  gl.uniform1f(uni.uHinge, turn.m.hinge); gl.uniform1f(uni.uPageW, turn.m.pageW);
  gl.uniform2f(uni.uN, n[0], n[1]); gl.uniform1f(uni.uT, t); gl.uniform1f(uni.uR, r);
  gl.uniform1f(uni.uShowThrough, turn.m.spread ? 0 : 1);
  gl.uniform3f(uni.uPaper, ...PAPER);
  gl.drawArrays(gl.TRIANGLES, 0, 3);
  return dpr;
}

function bind(unit, id) { gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, id && textures[id] ? textures[id] : blank); }

function beginTurn(dir, touchY) {
  if (!gl || turn || busy) return false;
  const base = dir > 0 ? at : at - 1;
  const cur = views[base], next = views[base + 1];
  if (!cur || !next) return false;
  if ([cur.right, next.right, next.left, cur.left].some(id => id && !textures[id])) return false;
  const m = metrics();
  const dpr = Math.min(2, devicePixelRatio || 1);
  canvas.width = Math.round(m.W * dpr); canvas.height = Math.round(m.H * dpr);
  bind(0, cur.right); bind(1, m.spread ? next.left : cur.right); bind(2, next.right); bind(3, cur.left);
  const band = m.H * .2, corner = touchY < band || touchY > m.H - band;
  const y = touchY < band ? 0 : (touchY > m.H - band ? m.H : touchY);
  const grab = [m.hinge + m.pageW, y], turned = [m.hinge - m.pageW, y];
  turn = { dir, m, grab, turned, f: dir > 0 ? grab.slice() : turned.slice(), tilt: corner ? 1 : .22 };
  draw();
  canvas.style.visibility = 'visible';
  (dir > 0 ? rightSlot : leftSlot); leftSlot.style.visibility = rightSlot.style.visibility = 'hidden';
  return true;
}

function endTurn(complete) {
  const dir = turn.dir;
  if (complete) at += dir;
  turn = null;
  leftSlot.style.visibility = rightSlot.style.visibility = '';
  showView();
  fitLive();
  canvas.style.visibility = 'hidden';
  busy = false;
}

function land(complete, velocity) {
  busy = true;
  const toTurned = complete === (turn.dir > 0);
  const from = turn.f.slice(), to = (toTurned ? turn.turned : turn.grab).slice();
  // Critically damped spring, starting with the speed of the swipe.
  const k = 260, w = Math.sqrt(k), span = Math.max(1, Math.hypot(to[0] - from[0], to[1] - from[1]));
  const v0 = Math.min(12, velocity / span);
  const t0 = performance.now();
  (function step(now) {
    const t = (now - t0) / 1000;
    const x = 1 - (1 + (w - v0) * t) * Math.exp(-w * t);
    const done = Math.abs(1 - x) < .002 || t > 2;
    const e = done ? 1 : Math.max(0, Math.min(1, x));
    turn.f = clampFinger([from[0] + (to[0] - from[0]) * e, from[1] + (to[1] - from[1]) * e], turn.grab, turn.m.hinge, turn.m.H);
    draw();
    if (done) return endTurn(complete);
    requestAnimationFrame(step);
  })(t0);
}

function auto(dir, speed = 1.5) {
  return new Promise(resolve => {
    if (reduced || !gl) { at += dir; showView(); fitLive(); return resolve(); }
    const m = metrics();
    if (!beginTurn(dir, m.H * .93)) return resolve();
    land(true, m.pageW * speed);
    const wait = () => (turn || busy) ? requestAnimationFrame(wait) : resolve();
    wait();
  });
}

// ---- moving through the book ---------------------------------------------------------------------------
function openCover() {
  if (busy) return;
  busy = true;
  at = 0; showView(); fitLive();
  if (narrow()) coverLeaf.style.opacity = 0;
  coverLeaf.classList.add('open');
  setTimeout(() => { busy = false; coverLeaf.style.visibility = 'hidden'; coverLeaf.style.opacity = ''; }, reduced ? 0 : 900);
  if (narrow()) coverLeaf.style.transition = 'transform .9s cubic-bezier(.45,.05,.3,1), opacity .5s .35s';
}

function closeCover() {
  if (busy) return;
  busy = true;
  coverLeaf.style.visibility = '';
  requestAnimationFrame(() => requestAnimationFrame(() => {
    coverLeaf.classList.remove('open');
    at = -1; bookEl.classList.toggle('closed', !narrow());
    $('#controls').hidden = true;
    setTimeout(() => { busy = false; showView(); }, reduced ? 0 : 900);
  }));
}

async function step(dir) {
  if (busy || turn) return;
  if (at < 0) { if (dir > 0) openCover(); return; }
  if (at === 0 && dir < 0) return closeCover();
  if (at + dir >= views.length) return;
  await auto(dir);
}

async function goTo(page) {
  const id = 'p' + page;
  const want = views.findIndex(v => v.left === id || v.right === id);
  if (want < 0) return;
  while (at !== want) {
    const before = at;
    await auto(want > at ? 1 : -1, Math.abs(want - at) > 1 ? 5 : 1.5);
    if (at === before) break;
  }
}

function fitLive() { for (const s of [leftSlot, rightSlot]) { const p = s.firstElementChild; if (p) fit(p); } }

// ---- fingers --------------------------------------------------------------------------------------------
let press0 = null;
bookEl.addEventListener('pointerdown', e => {
  if (e.target.closest('a,button')) return;
  const b = bookEl.getBoundingClientRect();
  press0 = { x: e.clientX - b.left, y: e.clientY - b.top, id: e.pointerId, moved: false, samples: [] };
});
addEventListener('pointermove', e => {
  if (!press0 || e.pointerId !== press0.id || at < 0) return;
  const b = bookEl.getBoundingClientRect();
  const x = e.clientX - b.left, y = e.clientY - b.top, dx = x - press0.x, dy = y - press0.y;
  press0.samples.push([performance.now(), x]);
  if (press0.samples.length > 6) press0.samples.shift();
  if (!turn && !busy) {
    if (Math.abs(dx) < 9 || Math.abs(dy) > Math.abs(dx) * 1.4) return;
    press0.moved = true;
    const dir = dx < 0 ? 1 : -1;
    if (dir < 0 && at === 0) return;
    if (!beginTurn(dir, press0.y)) return;
  }
  if (turn && !busy) {
    const raw = turn.dir > 0 ? [turn.grab[0] + dx, turn.grab[1] + dy] : [turn.turned[0] + dx * (turn.m.spread ? 1 : 2), press0.y + dy];
    turn.f = clampFinger(raw, turn.grab, turn.m.hinge, turn.m.H);
    draw();
  }
});
addEventListener('pointerup', e => {
  if (!press0 || e.pointerId !== press0.id) return;
  const p = press0; press0 = null;
  if (turn && !busy) {
    const s = p.samples, dt = s.length > 1 ? (s[s.length - 1][0] - s[0][0]) / 1000 : 1;
    const vx = s.length > 1 ? (s[s.length - 1][1] - s[0][1]) / Math.max(dt, .001) : 0;
    const m = turn.m, projected = turn.f[0] + vx * .18;
    const middle = turn.dir > 0 ? m.W * (m.spread ? .6 : .55) : (m.spread ? m.W * .4 : 0);
    const toward = projected < middle;
    land(turn.dir > 0 ? toward : !toward, Math.abs(vx));
    return;
  }
  if (p.moved || e.target.closest('a,button,#lightbox')) return;
  if (at < 0) return openCover();
  const b = bookEl.getBoundingClientRect();
  const dir = (e.clientX - b.left) > b.width * (narrow() ? .5 : .5) ? 1 : -1;
  step(dir);
});

$('#next').onclick = () => step(1);
$('#prev').onclick = () => step(-1);
$('#toc').onclick = () => goTo(1);
addEventListener('keydown', e => { if (e.key === 'ArrowRight') step(1); if (e.key === 'ArrowLeft') step(-1); });

function applyLang() { document.documentElement.lang = lang; $('#lang').textContent = lang === 'tr' ? 'EN' : 'TR'; }
$('#lang').onclick = () => { lang = lang === 'tr' ? 'en' : 'tr'; localStorage.setItem('lang', lang); applyLang(); rebuild(); };

// ---- the cover: only the silhouettes and the title's typeface change --------------------------------------
let rafId = 0, sceneTimer = 0;
function ribbonPath(t) {
  const top = 124, h = 30, x0 = 156, len = 146, steps = 24;
  const y = x => { const u = (x - x0) / len; return Math.sin(u * 7 - t * 3.6) * 11 * u + Math.sin(u * 13 - t * 5.1) * 3 * u; };
  let d = `M${x0} ${top + y(x0)}`;
  for (let i = 1; i <= steps; i++) { const x = x0 + len * i / steps; d += `L${x} ${top + y(x)}`; }
  const end = x0 + len;
  d += `L${end - 15} ${top + h / 2 + y(end - 15)}`;
  for (let i = steps; i >= 0; i--) { const x = x0 + len * i / steps; d += `L${x} ${top + h + y(x)}`; }
  return d + 'Z';
}
const NS = 'http://www.w3.org/2000/svg';
const el = (tag, attrs) => { const e = document.createElementNS(NS, tag); for (const k in attrs) e.setAttribute(k, attrs[k]); return e; };

function figure(f) {
  const outer = el('g', { class: 'fig' });
  const scale = f.s / 512;
  const place = el('g', { transform: `translate(${f.m ? f.x + f.s : f.x} ${f.y}) scale(${f.m ? -scale : scale} ${scale})` });
  const idle = el('g', { class: 'idle ' + f.a });
  idle.append(el('path', { d: f.d, fill: 'currentColor', opacity: f.o, stroke: 'var(--cover)', 'stroke-width': 14, 'paint-order': 'stroke', 'stroke-linejoin': 'round' }));
  place.append(idle); outer.append(place);
  return outer;
}

// Small touches that make each scene alive: fire, laser fire and beams, rain and a flickering lamp.
function effects(name) {
  const g = el('g', { class: 'fig fx' });
  if (name === 'fantasy') for (let i = 0; i < 7; i++) {
    const c = el('circle', { cx: 196 + i, cy: 68, r: 1.6 + i % 3 * .8, class: 'ember' });
    c.style.animationDelay = -i * .19 + 's'; g.append(c);
  }
  if (name === 'scifi') {
    g.append(el('path', { d: 'M208 116h24l26 126h-76z', class: 'beam' }));
    [[92, 92, 60, 76], [262, 106, -70, 74], [104, 88, 90, 70]].forEach(([x, y, dx, dy], i) => {
      const l = el('line', { x1: x, y1: y, x2: x + dx * .14, y2: y + dy * .14, class: 'bolt' });
      l.style.setProperty('--dx', dx + 'px'); l.style.setProperty('--dy', dy + 'px'); l.style.animationDelay = -i * .32 + 's'; g.append(l);
    });
  }
  if (name === 'noir') {
    g.append(el('path', { d: 'M118 128l-40 116h130z', class: 'cone' }));
    for (let i = 0; i < 22; i++) {
      const x = 30 + (i * 53) % 270, y = 20 + (i * 97) % 210;
      const l = el('line', { x1: x, y1: y, x2: x - 5, y2: y + 15, class: 'rain' });
      l.style.animationDelay = -(i % 7) * .09 + 's'; g.append(l);
    }
  }
  return g;
}

function setScene(name) {
  const g = $('#scene');
  g.style.color = 'var(--ink)';
  g.replaceChildren(effects(name), ...SCENES[name].map(figure));
  requestAnimationFrame(() => requestAnimationFrame(() => {
    [...g.children].forEach((p, i) => setTimeout(() => p.classList.add('up'), i * 110));
  }));
}

function startScenes() {
  const ribbon = $('#ribbon'), cover = $('.cover'), title = $('#title');
  if (!ribbon) return;
  let i = 0;
  cover.dataset.scene = SCENE_ORDER[0];
  setScene(SCENE_ORDER[0]);
  cancelAnimationFrame(rafId);
  (function frame(now) { ribbon.setAttribute('d', ribbonPath(reduced ? 1 : now / 1000)); rafId = requestAnimationFrame(frame); })(performance.now());
  clearInterval(sceneTimer);
  if (reduced) return;
  sceneTimer = setInterval(() => {
    if (at >= 0 || busy) return;
    const figs = [...$('#scene').children];
    figs.forEach((p, n) => setTimeout(() => { p.classList.remove('up'); p.classList.add('down'); }, n * 80));
    title.classList.add('swap');
    setTimeout(() => {
      i = (i + 1) % SCENE_ORDER.length;
      cover.dataset.scene = SCENE_ORDER[i];
      setScene(SCENE_ORDER[i]);
      title.classList.remove('swap');
    }, 620 + figs.length * 80);
  }, 6400);
}

function rebuild() {
  buildViews();
  coverLeaf.querySelector('.front').replaceChildren(pageEl('cover'));
  coverLeaf.querySelector('.rear').replaceChildren(pageEl('endpaper'));
  if (at >= views.length) at = views.length - 1;
  showView(); fitLive();
  startScenes();
  document.fonts.ready.then(() => { press.replaceChildren(); pressAll(); });
}

let wasNarrow = narrow();
addEventListener('resize', () => {
  if (narrow() === wasNarrow) return;
  wasNarrow = narrow(); at = -1;
  coverLeaf.classList.remove('open'); coverLeaf.style.visibility = '';
  rebuild();
});
applyLang();
initGL();
rebuild();
