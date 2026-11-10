const VERSION = '0.1.0';
const T = {
  en: {
    contents:'Contents',open:'Tap the cover to open',download:'Download for Android',version:'Version',epigraph:'A book is a place you can carry.',
    home:'Home',shots:'Screenshots',features:'Features',downloads:'Downloads',changelog:'Changelog',privacy:'Privacy notice',links:'Links',
    home1:'A reader built around how reading feels.',
    home2:'Pages curl under your finger, wherever you take hold of them. Turn on actual book mode and the screen gets paper grain, the shadow of the fold and the stack of pages at the edges.',
    home3:'Black-and-white manga can be coloured on your phone, without the internet. Books can be read aloud in a voice you choose. It is free, it has no ads, and the code is open.',
    dl1:'The Android app is ready to try.',apk:'Download APK',soon:'Later',dl2:'Android will ask you to allow installs from your browser. The app is not on Google Play yet.',source:'Source code',
    models:'Downloadable models',modelsText:'Models are fetched from their authors only when you ask. Manga Light Colorizer (sharky172) is CC BY-NC-SA 4.0, DDColor is Apache-2.0, Supertonic is OpenRAIL-M, Kokoro is Apache-2.0.',
    credits:'Credits',creditsText:'Sample pages: Pepper&Carrot by David Revoy (CC BY 4.0). Give My Regards to Black Jack by SHUHO SATO. Fonts from Fontsource. EgeBookReader is licensed under AGPL-3.0.',
    contact:'Contact',bug:'Report a bug',request:'Request a feature',
  },
  tr: {
    contents:'İçindekiler',open:'Açmak için kapağa dokun',download:'Android için indir',version:'Sürüm',epigraph:'Kitap, yanında taşıyabildiğin bir yerdir.',
    home:'Ana sayfa',shots:'Ekran görüntüleri',features:'Özellikler',downloads:'İndirmeler',changelog:'Değişiklikler',privacy:'Aydınlatma metni',links:'Bağlantılar',
    home1:'Okumanın hissine göre yapılmış bir kitap okuyucu.',
    home2:'Sayfalar, neresinden tutarsan tut parmağının altında kıvrılır. Gerçek kitap modunu açınca ekrana kağıt dokusu, cilt gölgesi ve kenarlarda sayfa yığını gelir.',
    home3:'Siyah beyaz mangalar telefonunda, internetsiz renklenir. Kitaplar seçtiğin sesle okunur. Ücretsizdir, reklam yoktur, kodu açıktır.',
    dl1:'Android uygulaması denemeye hazır.',apk:'APK indir',soon:'Daha sonra',dl2:'Android, tarayıcından yükleme izni isteyecek. Uygulama henüz Google Play\'de değil.',source:'Kaynak kod',
    models:'İndirilebilir modeller',modelsText:'Modeller sadece sen istediğinde, yazarlarının kendi adreslerinden iner. Manga Light Colorizer (sharky172) CC BY-NC-SA 4.0, DDColor Apache-2.0, Supertonic OpenRAIL-M, Kokoro Apache-2.0 lisanslıdır.',
    credits:'Teşekkürler',creditsText:'Örnek sayfalar: David Revoy, Pepper&Carrot (CC BY 4.0). SHUHO SATO, Give My Regards to Black Jack. Fontlar Fontsource\'tan. EgeBookReader AGPL-3.0 ile lisanslıdır.',
    contact:'İletişim',bug:'Hata bildir',request:'Özellik iste',
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
const SHOTS = ['library','reader','flip','book','spread','colorize','viewer','settings','onboarding'];

let lang = localStorage.getItem('lang') || (navigator.language.startsWith('tr') ? 'tr' : 'en');
const $ = (s, r = document) => r.querySelector(s);
const book = $('#book');
const narrow = () => matchMedia('(max-aspect-ratio:1/1)').matches;
const reduced = matchMedia('(prefers-reduced-motion:reduce)').matches;

function pageEl(id, n) {
  const f = document.createDocumentFragment();
  f.append($('#' + id).content.cloneNode(true));
  const root = f.firstElementChild;
  if (n) { const folio = document.createElement('span'); folio.className = 'folio'; folio.textContent = n; root.append(folio); }
  return root;
}

function fill(root) {
  root.querySelectorAll('[data-t]').forEach(e => { e.textContent = T[lang][e.dataset.t] ?? e.textContent; });
  const shots = $('#shots', root);
  if (shots) shots.replaceChildren(...SHOTS.map(s => { const i = new Image(); i.src = `shots/${s}.jpg`; i.alt = s; i.loading = 'lazy'; i.onclick = e => { e.stopPropagation(); zoom(i.src); }; return i; }));
  const fl = $('#featurelist', root);
  if (fl) fl.replaceChildren(...FEATURES[lang].flatMap(([a, b]) => { const dt = document.createElement('dt'), dd = document.createElement('dd'); dt.textContent = a; dd.textContent = b; return [dt, dd]; }));
  const ch = $('#changes', root);
  if (ch) ch.innerHTML = CHANGES[lang].map(([v, t]) => `<div class="change"><b>${v}</b><p>${t}</p></div>`).join('');
  const pr = $('#privacy', root);
  if (pr) pr.innerHTML = PRIVACY[lang];
  const v = $('#version', root);
  if (v) v.textContent = VERSION;
  root.querySelectorAll('[data-go]').forEach(a => a.onclick = e => { e.stopPropagation(); goTo(+a.dataset.go); });
}

function zoom(src) {
  const box = document.createElement('div');
  box.id = 'lightbox';
  const i = new Image(); i.src = src;
  box.append(i); box.onclick = () => box.remove();
  document.body.append(box);
}

// Book: leaves stacked at the spine. leafIndex = how many have been turned.
let leaves = [], turned = 0, busy = false, pageOfLeaf = [];

function makeLeaf(front, back) {
  const leaf = document.createElement('div');
  leaf.className = 'leaf static';
  const f = document.createElement('div'); f.className = 'face f'; f.append(front);
  const b = document.createElement('div'); b.className = 'face b'; b.append(back);
  leaf.append(f, b);
  return leaf;
}

function build() {
  stopScenes();
  book.replaceChildren();
  const sh = document.createElement('div'); sh.className = 'shadow'; book.append(sh);
  const list = ['p1','p2','p3','p4','p5','p6','p7','p8'];
  const pages = list.map((id, i) => pageEl(id, i + 1));
  const cover = pageEl('cover');
  const out = [];
  pageOfLeaf = [];
  if (narrow()) {
    out.push(makeLeaf(cover, pageEl('endpaper')));
    pageOfLeaf.push(0);
    pages.forEach((p, i) => { out.push(makeLeaf(p, pageEl('back'))); pageOfLeaf.push(i + 1); });
  } else {
    out.push(makeLeaf(cover, pageEl('endpaper')));
    pageOfLeaf.push(0);
    for (let i = 0; i < pages.length; i += 2) {
      out.push(makeLeaf(pages[i], pages[i + 1] ?? pageEl('back')));
      pageOfLeaf.push(i + 1);
    }
  }
  leaves = out;
  leaves.forEach(l => { fill(l); book.append(l); });
  layout();
  startScenes();
}

function layout() {
  leaves.forEach((l, i) => {
    const done = i < turned;
    // A turned leaf faces away, so its own z axis points into the table.
    l.style.transform = `rotateY(${done ? -180 : 0}deg) translateZ(${done ? -i * .3 : (leaves.length - i) * .3}px)`;
    l.style.zIndex = done ? i : leaves.length - i;
    l.style.visibility = (i >= (narrow() ? turned : turned - 2) && i <= turned + 1) ? 'visible' : 'hidden';
  });
  book.classList.toggle('closed', turned === 0);
  book.classList.toggle('open', turned > 0);
  $('#controls').hidden = turned === 0;
}

// While it turns, the leaf is cut into strips hinged to each other, so the paper can bend.
const STRIPS = 14;
function bendLeaf(leaf) {
  const w = leaf.offsetWidth, h = leaf.offsetHeight, sw = w / STRIPS;
  const [ff, bf] = [leaf.querySelector('.face.f'), leaf.querySelector('.face.b')];
  const frontHTML = ff.innerHTML, backHTML = bf.innerHTML;
  const bg = [getComputedStyle(ff.firstElementChild).backgroundColor, getComputedStyle(bf.firstElementChild).backgroundColor];
  ff.style.visibility = bf.style.visibility = 'hidden';
  const strips = [];
  let parent = leaf;
  for (let i = 0; i < STRIPS; i++) {
    const s = document.createElement('div');
    s.className = 'strip';
    s.style.width = sw + .6 + 'px';
    s.style.left = (i ? sw : 0) + 'px';
    const mk = (cls, html, x, b) => {
      const c = document.createElement('div'); c.className = 'clip ' + cls; c.style.background = b;
      const inner = document.createElement('div'); inner.className = 'inner'; inner.style.width = w + 'px'; inner.style.left = x + 'px'; inner.innerHTML = html;
      const shade = document.createElement('div'); shade.className = 'shade';
      c.append(inner, shade); return c;
    };
    s.append(mk('f', frontHTML, -i * sw, bg[0]), mk('b', backHTML, -(STRIPS - 1 - i) * sw, bg[1]));
    parent.append(s); parent = s; strips.push(s);
  }
  return {
    strips,
    set(p) {
      const hinge = -180 * p;
      const curl = Math.sin(Math.PI * p) * 34 / STRIPS * 1.9;
      strips.forEach((s, i) => {
        const a = i === 0 ? 0 : -curl * (i / STRIPS + .35);
        s.style.transform = `rotateY(${a}deg)`;
        const light = Math.abs(Math.sin(Math.PI * p)) * (.1 + i / STRIPS * .24);
        s.querySelectorAll(':scope>.clip>.shade').forEach(x => x.style.opacity = light);
      });
      leaf.style.transform = `rotateY(${hinge}deg) translateZ(1px)`;
    },
    done() { strips[0].remove(); ff.style.visibility = bf.style.visibility = ''; },
  };
}

function flip(dir, ms = 760) {
  return new Promise(resolve => {
    const i = dir > 0 ? turned : turned - 1;
    const leaf = leaves[i];
    if (!leaf || busy) return resolve();
    if (reduced) { turned += dir; layout(); return resolve(); }
    busy = true;
    leaf.classList.remove('static');
    leaf.style.zIndex = leaves.length + 5;
    leaf.style.visibility = 'visible';
    (leaves[i + 1] || {style:{}}).style.visibility = 'visible';
    (leaves[i - 1] || {style:{}}).style.visibility = 'visible';
    if (i === 0 && dir > 0) book.classList.add('open'), book.classList.remove('closed');
    const bend = bendLeaf(leaf);
    const from = dir > 0 ? 0 : 1, to = dir > 0 ? 1 : 0, t0 = performance.now();
    const ease = x => x < .5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2;
    (function tick(now) {
      const x = Math.min(1, (now - t0) / ms), p = from + (to - from) * ease(x);
      bend.set(p);
      if (x < 1) return requestAnimationFrame(tick);
      bend.done();
      leaf.classList.add('static');
      turned += dir;
      busy = false;
      layout();
      resolve();
    })(t0);
  });
}

async function goTo(page) {
  // page numbers are the folios printed on the pages
  let target = pageOfLeaf.findIndex((first, i) => i > 0 && page >= first && page < (pageOfLeaf[i + 1] ?? 99));
  if (target < 0) return;
  target = narrow() ? target + 0 : target;
  const want = narrow() ? target : (page % 2 === 0 ? target + 1 : target);
  while (turned !== want && turned >= 0) await flip(want > turned ? 1 : -1, Math.abs(want - turned) > 1 ? 420 : 760);
}

document.addEventListener('click', e => {
  if (e.target.closest('a,button,#lightbox')) return;
  if (turned === 0) return flip(1, 900);
  const r = book.getBoundingClientRect();
  if (e.clientX > r.left + r.width / 2 || narrow() && e.clientX > innerWidth / 2) flip(1);
  else flip(-1);
});
$('#next').onclick = () => flip(1);
$('#prev').onclick = () => flip(-1);
$('#toc').onclick = () => goTo(1);
addEventListener('keydown', e => { if (e.key === 'ArrowRight') flip(1); if (e.key === 'ArrowLeft') flip(-1); });
let touchX = null;
addEventListener('touchstart', e => { touchX = e.touches.length === 1 ? e.touches[0].clientX : null; }, {passive:true});
addEventListener('touchend', e => {
  if (touchX === null) return;
  const dx = e.changedTouches[0].clientX - touchX;
  if (Math.abs(dx) > 48) flip(dx < 0 ? 1 : -1);
}, {passive:true});

$('#lang').onclick = () => { lang = lang === 'tr' ? 'en' : 'tr'; localStorage.setItem('lang', lang); applyLang(); const was = turned; build(); turned = was; layout(); };
function applyLang() { document.documentElement.lang = lang; $('#lang').textContent = lang === 'tr' ? 'EN' : 'TR'; }

// Cover animation: the ribbon flies like a flag, the scene folds back into the page and the next one stands up.
let rafId = 0, sceneTimer = 0;
function ribbonPath(t) {
  const top = 136, h = 38, x0 = 30, len = 240, steps = 28;
  const y = x => { const u = (x - x0) / len; return Math.sin(u * 7 - t * 3.6) * 13 * u + Math.sin(u * 13 - t * 5.1) * 4 * u; };
  let d = `M${x0} ${top + y(x0)}`;
  for (let i = 1; i <= steps; i++) { const x = x0 + len * i / steps; d += `L${x} ${top + y(x)}`; }
  const end = x0 + len;
  d += `L${end - 26} ${top + h / 2 + y(end - 26)}`;
  for (let i = steps; i >= 0; i--) { const x = x0 + len * i / steps; d += `L${x} ${top + h + y(x)}`; }
  return d + 'Z';
}
function setScene(name, up) {
  const g = $('#scene');
  g.replaceChildren(...SCENES[name].map(([d, opacity]) => {
    const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', d); p.setAttribute('class', 'fig'); p.style.opacity = opacity; return p;
  }));
  if (up) requestAnimationFrame(() => requestAnimationFrame(() => {
    [...g.children].forEach((p, i) => setTimeout(() => p.classList.add('up'), i * 110));
  }));
}
function startScenes() {
  const ribbon = $('#ribbon'), cover = $('.cover'), title = $('#title');
  if (!ribbon) return;
  let i = 0;
  cover.dataset.scene = SCENE_ORDER[0];
  setScene(SCENE_ORDER[0], true);
  (function frame(now) { ribbon.setAttribute('d', ribbonPath(reduced ? 1 : now / 1000)); rafId = requestAnimationFrame(frame); })(performance.now());
  if (reduced) return;
  sceneTimer = setInterval(() => {
    if (turned !== 0 || busy) return;
    const figs = [...$('#scene').children];
    figs.forEach((p, n) => setTimeout(() => { p.classList.remove('up'); p.classList.add('down'); }, n * 80));
    title.classList.add('swap');
    setTimeout(() => {
      i = (i + 1) % SCENE_ORDER.length;
      cover.dataset.scene = SCENE_ORDER[i];
      setScene(SCENE_ORDER[i], true);
      title.classList.remove('swap');
    }, 620 + figs.length * 80);
  }, 5200);
}
function stopScenes() { cancelAnimationFrame(rafId); clearInterval(sceneTimer); }

let wasNarrow = narrow();
addEventListener('resize', () => { if (narrow() !== wasNarrow) { wasNarrow = narrow(); turned = 0; build(); } });
applyLang();
build();
