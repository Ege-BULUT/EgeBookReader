// Before the first paint: the style (book or manga) and the language the site last used.
try {
  var m = new URLSearchParams(location.search).get('mode') || localStorage.getItem('mode');
  if (m === 'manga') document.documentElement.dataset.mode = 'manga';
  var l = localStorage.getItem('lang') || (navigator.language.indexOf('tr') === 0 ? 'tr' : 'en');
  document.documentElement.lang = l;
} catch (e) {}
