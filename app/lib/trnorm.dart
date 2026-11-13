// Written Turkish to the way it is said, for the Turkish voices (Antalia-2 Mini, Ahenk Cep). A port of the parts
// books need of Antalia-2 Mini's normaliser (antalia_mini/text/normalize.py through its JS port, Apache-2.0,
// PatientDesk AI): numbers, ordinals, Roman numerals, dates, times, money, percentages, units, ranges,
// abbreviations, initialisms and suffixes re-agreed with the spoken number ("5'te" -> "beşte").
// Left out: phone numbers, IBANs, medical shorthand and English respelling (its CMU lexicon is half a megabyte).

const _w = r'[\p{L}\p{N}_]';
const _up = 'A-ZÇĞİÖŞÜQWX';
const _ones = ['sıfır', 'bir', 'iki', 'üç', 'dört', 'beş', 'altı', 'yedi', 'sekiz', 'dokuz'];
const _tens = ['', 'on', 'yirmi', 'otuz', 'kırk', 'elli', 'altmış', 'yetmiş', 'seksen', 'doksan'];
const _months = ['ocak', 'şubat', 'mart', 'nisan', 'mayıs', 'haziran', 'temmuz', 'ağustos', 'eylül', 'ekim', 'kasım', 'aralık'];
const _vowels = 'aeıioöuüAEIİOÖUÜâîû';

/// Python's \b and \w, which see Turkish letters as letters.
RegExp _re(String source, {bool ignoreCase = false}) {
  final out = StringBuffer();
  var inClass = false;
  for (var i = 0; i < source.length; i++) {
    final c = source[i];
    if (c == '\\' && i + 1 < source.length) {
      final e = source[++i];
      out.write(switch (e) {
        'w' => inClass ? r'\p{L}\p{N}_' : _w,
        'b' when !inClass => '(?:(?<=$_w)(?!$_w)|(?<!$_w)(?=$_w))',
        _ => '\\$e',
      });
      continue;
    }
    if (c == '[') inClass = true;
    if (c == ']') inClass = false;
    out.write(c);
  }
  return RegExp(out.toString(), unicode: true, caseSensitive: !ignoreCase);
}

const _abbreviations = {
  'dr.': 'doktor', 'prof.': 'profesör', 'vb.': 've benzeri', 'vs.': 'vesaire', 'örn.': 'örneğin', 'no.': 'numara',
  'mg': 'miligram', 'kg': 'kilogram', 'gr': 'gram', 'km': 'kilometre', 'cm': 'santimetre', 'mm': 'milimetre',
  'lt': 'litre', 'ml': 'mililitre', 'kb': 'kilobayt', 'mb': 'megabayt', 'gb': 'gigabayt', 'tb': 'terabayt', 'tl': 'lira',
  'doç.': 'doçent', 'uzm.': 'uzman', 'op.': 'operatör', 'yrd.': 'yardımcı', 'öğr. üyesi': 'öğretim üyesi',
  'öğr. gör.': 'öğretim görevlisi', 'dt.': 'diş hekimi', 'psk.': 'psikolog', 'av.': 'avukat', 'müh.': 'mühendis',
  'hz.': 'hazreti', 'bkz.': 'bakınız', 'vd.': 've diğerleri', 'mah.': 'mahallesi', 'cad.': 'caddesi', 'cd.': 'caddesi',
  'sok.': 'sokak', 'sk.': 'sokak', 'bul.': 'bulvarı', 'apt.': 'apartmanı', 'ltd. şti.': 'limited şirketi', 'şti.': 'şirketi',
};
const _beforeAWord = {'doç.', 'uzm.', 'op.', 'yrd.', 'dt.', 'psk.', 'av.', 'müh.', 'hz.', 'mah.', 'cad.', 'cd.', 'sok.', 'sk.', 'bul.', 'apt.'};
const _units = {
  'm': 'metre', 'g': 'gram', 'cc': 'sisi', 'mcg': 'mikrogram', 'kcal': 'kilokalori', 'dk': 'dakika', 'sn': 'saniye',
  'sa': 'saat', 'ms': 'milisaniye', 'dl': 'desilitre',
};
const _capsLexicon = {
  'SMS': 'esemes', 'NTV': 'entivi', 'YÖK': 'yök', 'BİM': 'bim', 'ŞOK': 'şok', 'COVID': 'kovid', 'MEB': 'meb', 'İTÜ': 'itü',
  'IBAN': 'iban', 'ALO': 'alo', 'MİT': 'mit', 'OK': 'okey', 'CEO': 'siio', 'PR': 'piar', 'DJ': 'dijey', 'TV': 'tivi',
  'FBI': 'efbiay', 'CNN': 'sienen', 'VIP': 'viaypi', 'HD': 'heyçdi',
};
const _letterNames = {
  'A': 'a', 'B': 'be', 'C': 'ce', 'Ç': 'çe', 'D': 'de', 'E': 'e', 'F': 'fe', 'G': 'ge', 'Ğ': 'yumuşak ge', 'H': 'he',
  'I': 'ı', 'İ': 'i', 'J': 'je', 'K': 'ke', 'L': 'le', 'M': 'me', 'N': 'ne', 'O': 'o', 'Ö': 'ö', 'P': 'pe', 'R': 're',
  'S': 'se', 'Ş': 'şe', 'T': 'te', 'U': 'u', 'Ü': 'ü', 'V': 've', 'Y': 'ye', 'Z': 'ze', 'Q': 'kü', 'W': 'dabılyu', 'X': 'iks',
};
final _initialismLetters = {..._letterNames}..addAll({'K': 'ka', 'I': 'i'});
const _ordinalExceptions = {
  'bir': 'birinci', 'iki': 'ikinci', 'üç': 'üçüncü', 'dört': 'dördüncü', 'beş': 'beşinci', 'altı': 'altıncı',
  'yedi': 'yedinci', 'sekiz': 'sekizinci', 'dokuz': 'dokuzuncu', 'on': 'onuncu', 'yirmi': 'yirminci', 'otuz': 'otuzuncu',
  'kırk': 'kırkıncı', 'elli': 'ellinci', 'altmış': 'altmışıncı', 'yetmiş': 'yetmişinci', 'seksen': 'sekseninci',
  'doksan': 'doksanıncı', 'yüz': 'yüzüncü', 'bin': 'bininci', 'milyon': 'milyonuncu', 'milyar': 'milyarıncı',
};
const _roman = '(?:XX|XIX|XVIII|XVII|XVI|XV|XIV|XIII|XII|XI|IX|VIII|VII|VI|IV|III|II)';
const _ordinalHeads = 'Dünya|Lig|Ordu|Kolordu|Tümen|Dönem|Meclis|Kurultay|Kongre|Uluslararası|Ulusal|Olağan|Olağanüstü'
    '|Yıl|Yüzyıl|Sınıf|Kat|Blok|Etap|Bölge|Selim|Murat|Murad|Mehmet|Mehmed|Mahmut|Mahmud|Ahmet|Ahmed|Osman|Bayezid'
    '|Beyazıt|Süleyman|Mustafa|Abdülhamid|Abdülmecid|Louis|Henry|Napolyon';

final _spokenStems = <String>{
  ..._ones, ..._tens.skip(1), 'yüz', 'bin', 'milyon', 'milyar', 'trilyon', 'lira', 'kuruş', 'dolar', 'avro', 'sent',
  'sterlin', 'peni', 'saniye', 'dakika', 'saat', 'buçuk', 'metrekare', 'metreküp', 'kilometrekare', 'santimetrekare',
  'kilometreküp', 'santimetreküp', 'derece', 'yüzde',
  for (final v in _abbreviations.values) v.split(' ').last,
  for (final v in _units.values) v.split(' ').last,
  ..._ordinalExceptions.values,
}.toList()
  ..sort((a, b) => b.length - a.length);

final _abbreviationRules = [
  for (final a in _abbreviations.keys.toList()..sort((a, b) => b.length - a.length))
    if (a.endsWith('.')) ...[
      (_re('(?<!\\w)${RegExp.escape(a)}\\s*(?=\\w)', ignoreCase: true), '${_abbreviations[a]} '),
      if (!_beforeAWord.contains(a)) (_re('(?<!\\w)${RegExp.escape(a)}', ignoreCase: true), _abbreviations[a]!),
    ] else
      (_re('(?<!\\w)${RegExp.escape(a)}(?!\\w)', ignoreCase: true), _abbreviations[a]!),
];

final _r = (
  word: _re(r'\b\p{L}{2,}\b'),
  capsWord: _re('\\b[$_up]{2,}\\b'),
  romanOrdinal: _re('\\b($_roman|I(?=\\.\\s+Dünya))\\.\\s+(?=\\p{L})'),
  romanAfterTitle: _re('\\b([A-ZÇĞİÖŞÜ]\\p{L}*\\s+)($_roman)\\b(?![.\']?\\p{L})'),
  quoteCaps: _re(r"'([A-ZÇĞİÖŞÜ]+)\b"),
  noNumber: _re(r'\bno\s*[:.]\s*(?=\d)', ignoreCase: true),
  sayfa: _re(r'\bs\.\s*(?=\d)'),
  email: _re(r'\b[\w.+-]+@[\w-]+(?:\.[\w-]+)+\b'),
  url: _re(r'\b(?:https?://)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|net|org|gov|edu|info|io|ai|tr)\b(?:/[\w./-]*)?', ignoreCase: true),
  degree: _re(r'(?<=\d)\s?°\s?C?(?!\p{L})'),
  plus: _re(r'(?<=\d)\s?\+\s?(?=\d)|(?<=\s)\+(?=\s)'),
  equals: _re(r'(?<=[\d\s])=(?=[\d\s])'),
  emphasis: _re(r'\*+|_{2,}'),
  drop: _re(r'[\p{So}\p{Cs}\p{Co}️‍]'),
  dotted: _re('\\b(?:[A-ZÇĞİÖŞÜ]\\.){2,}'),
  times: _re(r'\b(\d+)\s?[xX×]\s?(\d+)\b'),
  kmh: _re(r'(?<![\d.,])(\d+(?:,\d+)?)\s?km/(?:sa|s|h)\b'),
  area: _re(r'(?<=\d) ?(km|cm|m)([23²³])(?!\w)'),
  units: _re('(?<=\\d) ?(${_units.keys.join('|')})(?![\\w/])'),
  litre: _re(r"(?<=\d) L\b(?![/'])(?!\s*\d)"),
  currencySymbol: _re(r'([₺$€£])\s*((?:\d{1,3}(?:\.\d{3})+)|\d+)(?:[,.](\d{1,2}))?'),
  currencyAfter: _re(r'(?<![\d.,])((?:\d{1,3}(?:\.\d{3})+)|\d+)(?:,(\d{1,2}))?\s?(?:([₺$€£])|(TL|USD|EUR|GBP)\b)'),
  code: _re('(?<=\\d)[$_up]{1,6}(?=\\d|\\b)|\\b[$_up]{1,6}(?=\\d)|(?<=\\d )[$_up]{2,6}(?= \\d)'),
  letterThenDigit: _re(r'(?<=\p{L})(?=\d)'),
  digitThenLetter: _re(r'(?<=\d)(?=\p{L})'),
  letterDash: _re(r'(?<=\p{L})-(?=\d)'),
  loneLetterByDigit: _re('\\b([$_up])(?= \\d)|(?<=\\d )([$_up])\\b'),
  date: _re(r'\b(\d{1,2})[./-](\d{1,2})[./-](\d{4})\b'),
  isoDate: _re(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b'),
  percentBefore: _re(r'%\s*(\d+(?:[,.]\d+)?)'),
  percentAfter: _re(r'(?<![\d.,])(\d+(?:,\d+)?)\s?%'),
  range: _re(r'(?<![\d\-–])(\d[\d.:,]*)\s*[-–]\s*(\d[\d.:,]*)(?![\d\-–])'),
  minus: _re(r'(?<![\w.,:)\]])-(?=\d)'),
  duration: _re(r'\b(\d{1,2}):([0-5]\d):([0-5]\d)\b'),
  time: _re(r'\b([01]?\d|2[0-3])[:.]([0-5]\d)\b'),
  slashPair: _re(r'\b(\d{1,2})/(\d{1,2})\b'),
  slash: _re(r'\b(\d+)/(\d+)\b'),
  thousands: _re(r'\b\d{1,3}(?:\.\d{3})+(?:,\d+)?\b'),
  decimal: _re(r'\b(\d+)[,.](\d+)\b'),
  ordinalSuffix: _re(r"\b(\d+)'?(?:inci|ıncı|üncü|uncu|nci|ncı|ncü|ncu)\b"),
  ordinalDotWord: _re(r'\b(\d+)\.(?=[a-zçğıöşü])'),
  ordinalDot: _re('\\b([1-9]\\d*)\\.(?=\\s+(?:[a-zçğıöşü]|(?:$_ordinalHeads)\\b))'),
  longDigits: _re(r'\b\d{5,}\b'),
  zeroDigits: _re(r'\b0\d+\b'),
  digits: _re(r'\b\d+\b'),
  perUnit: _re(r'(?<=\w)/(sn|sa|dk)\b', ignoreCase: true),
  unitPer: _re(r'\b(mg|kg|g|km|m|cm|ml)/(kg|g|m|l|lt|ml|saat|gün)\b'),
  sayin: _re('\\bSn\\.\\s*(?=[A-ZÇĞİÖŞÜ])'),
  initialism: _re('\\b[$_up]{2,6}\\b'),
  loneLetter: _re("(?<![\\w.'-])([$_up])(\\.(?=\\s+[a-zçğıöşü]))?(?![\\w-])"),
  stemSuffix: _re("\\b(${_spokenStems.map(RegExp.escape).join('|')}|\\w+(?:inci|ıncı|üncü|uncu|nci|ncı|ncü|ncu))'([a-zçğıöşü]+)\\b"),
  spacedSlash: _re(r'\s+/\s+'),
  wordSlash: _re(r'(?<=\p{L})/(?=\p{L})'),
  spaceBeforePunct: _re(r'\s+([,.;:!?])'),
  leading: _re(r'^[\s,]+|(?<=[,.;:!?])\s*,'),
  space: _re(r'\s+'),
  threeConsonants: _re('[^AEIİOÖUÜ]{3}'),
);

/// Turkish lower case: I is ı and İ is i.
String turkishLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase().replaceAll('̇', '');

String numberToWords(int n) {
  if (n < 0) return 'eksi ${numberToWords(-n)}';
  if (n < 10) return _ones[n];
  if (n < 100) return n % 10 == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]} ${_ones[n % 10]}';
  if (n < 1000) {
    final head = n ~/ 100 == 1 ? 'yüz' : '${_ones[n ~/ 100]} yüz';
    return n % 100 == 0 ? head : '$head ${numberToWords(n % 100)}';
  }
  for (final (scale, name) in [(1000000000000, 'trilyon'), (1000000000, 'milyar'), (1000000, 'milyon'), (1000, 'bin')]) {
    if (n >= scale) {
      final head = scale == 1000 && n ~/ scale == 1 ? name : '${numberToWords(n ~/ scale)} $name';
      return n % scale == 0 ? head : '$head ${numberToWords(n % scale)}';
    }
  }
  return ''; // not reached
}

/// "5" is beş; a number too long for an int is read digit by digit.
String _int(String digits) => digits.length > 15 ? _digitByDigit(digits) : numberToWords(int.parse(digits));

String _digitByDigit(String digits) => [for (final d in digits.split('')) _ones[int.parse(d)]].join(' ');

/// "05" is sıfır beş.
String _digitGroup(String digits) {
  final rest = digits.replaceFirst(RegExp('^0+'), '');
  return [for (var i = rest.length; i < digits.length; i++) 'sıfır', if (rest.isNotEmpty) _int(rest)].join(' ');
}

String ordinalToWords(int n) {
  final words = numberToWords(n).split(' ');
  words.last = _ordinalExceptions[words.last] ?? '${words.last}inci';
  return words.join(' ');
}

String _lastVowel(String s) {
  for (var i = s.length - 1; i >= 0; i--) {
    if (_vowels.contains(s[i])) return s[i];
  }
  return 'e';
}

String _dative(String words) {
  if (words.endsWith('dört')) return '${words.substring(0, words.length - 1)}de';
  final v = 'aıou'.contains(_lastVowel(words)) ? 'a' : 'e';
  return '$words${_vowels.contains(words[words.length - 1]) ? 'y' : ''}$v';
}

String _locative(String words) {
  final v = 'aıou'.contains(_lastVowel(words)) ? 'a' : 'e';
  return '$words${'çfhkpsşt'.contains(words[words.length - 1]) ? 't' : 'd'}$v';
}

String _decimal(String value) {
  final at = value.indexOf(RegExp('[,.]'));
  final whole = value.substring(0, at), fraction = value.substring(at + 1);
  if (fraction == '5' && int.parse(whole) != 0) return '${_int(whole)} buçuk';
  return '${_int(whole)} virgül ${fraction.length <= 2 ? _digitGroup(fraction) : _digitByDigit(fraction)}';
}

/// "1.250,75", "3,5" or "12".
String _numeric(String value) {
  if (RegExp(r'^\d{1,3}(?:\.\d{3})+(?:,\d+)?$').hasMatch(value)) {
    final plain = value.replaceAll('.', '');
    return plain.contains(',') ? _decimal(plain) : _int(plain);
  }
  return value.contains(RegExp('[,.]')) ? _decimal(value) : _int(value);
}

String _money(String symbol, String whole, String? fraction) {
  final (unit, sub) = switch (symbol) { '₺' => ('lira', 'kuruş'), r'$' => ('dolar', 'sent'), '€' => ('avro', 'sent'), _ => ('sterlin', 'peni') };
  var out = '${_int(whole.replaceAll('.', ''))} $unit';
  final cents = fraction == null ? 0 : int.parse(fraction.padRight(2, '0'));
  if (cents != 0) out += ' ${numberToWords(cents)} $sub';
  return out;
}

int _romanValue(String numeral) {
  const values = {'I': 1, 'V': 5, 'X': 10};
  var total = 0;
  for (var i = 0; i < numeral.length; i++) {
    final v = values[numeral[i]]!;
    total += i + 1 < numeral.length && values[numeral[i + 1]]! > v ? -v : v;
  }
  return total;
}

bool _pronounceable(String word) {
  if (word.length < 4) return false;
  final vowels = word.split('').where(_vowels.contains).length;
  return vowels / word.length >= 0.3 && !_r.threeConsonants.hasMatch(word);
}

/// Re-agrees a written suffix with the spoken stem: ("beş", "de") -> "beşte", ("doksan", "lı") -> "doksanlı".
String _attach(String stem, String suffix) {
  var s = suffix;
  if (!_vowels.contains(stem[stem.length - 1]) && s.length > 1 && 'yns'.contains(s[0]) && _vowels.contains(s[1])) s = s.substring(1);
  if (_vowels.contains(s[0])) stem = stem.replaceFirst(RegExp(r'buçuk$'), 'buçuğ').replaceFirst(RegExp(r'dört$'), 'dörd');
  var vowel = _lastVowel(stem);
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    var c = s[i];
    if ('ae'.contains(c)) {
      c = 'aıou'.contains(vowel) ? 'a' : 'e';
    } else if ('ıiuü'.contains(c)) {
      final back = 'aıou'.contains(vowel), round = 'ouöü'.contains(vowel);
      c = back ? (round ? 'u' : 'ı') : (round ? 'ü' : 'i');
    } else if (i == 0 && 'dt'.contains(c)) {
      c = 'çfhkpsşt'.contains(stem[stem.length - 1]) ? 't' : 'd';
    }
    if (_vowels.contains(c)) vowel = c;
    out.write(c);
  }
  return '$stem$out';
}

String _address(String address) {
  const pieces = {'.': 'nokta', '@': 'et', '/': 'bölü', '_': 'alt tire', '-': 'tire'};
  const words = {'www': 'dabılyu dabılyu dabılyu', 'com': 'kom', 'gmail': 'cimeyl', 'hotmail': 'hotmeyl', 'outlook': 'autluk'};
  final a = address.replaceFirst(RegExp('^https?://', caseSensitive: false), '').replaceFirst(RegExp(r'/+$'), '');
  return [
    for (final part in a.splitMapJoin(RegExp(r'[.@/_-]'), onMatch: (m) => '\u0000${m[0]}\u0000', onNonMatch: (s) => s).split('\u0000'))
      if (part.isNotEmpty)
        pieces[part] ??
            words[part.toLowerCase()] ??
            (part.length <= 2 && RegExp(r'^\p{L}+$', unicode: true).hasMatch(part)
                ? [for (final c in turkishLower(part).split('')) _letterNames[c == 'i' ? 'İ' : c == 'ı' ? 'I' : c.toUpperCase()] ?? c].join(' ')
                : part),
  ].join(' ');
}

/// Written Turkish in its spoken form, case and punctuation kept.
String normalizeTurkish(String text) {
  String sub(String s, RegExp re, String Function(Match m) f) => s.replaceAllMapped(re, f);
  final r = _r;
  var n = text.replaceAll('−', '-').replaceAll(RegExp('[’‘`´]'), "'").replaceAll(RegExp('["“”„«»]'), '').replaceAll("''", '');
  n = n.replaceAll(r.space, ' ').trim();

  // A shouted text is read as ordinary words.
  final words = [for (final m in r.word.allMatches(n)) m[0]!];
  final capitals = words.where((w) => RegExp('^[$_up]{2,}\$').hasMatch(w)).toList();
  if (capitals.where(_pronounceable).length >= 3 && capitals.length >= 0.7 * words.length) n = turkishLower(n);

  n = sub(n, r.romanOrdinal, (m) => '${ordinalToWords(_romanValue(m[1]!))} ');
  n = sub(n, r.romanAfterTitle, (m) => '${m[1]}${numberToWords(_romanValue(m[2]!))}');
  n = sub(n, r.quoteCaps, (m) => "'${turkishLower(m[1]!)}");
  n = n.replaceAll(r.noNumber, 'numara ').replaceAll(r.sayfa, 'sayfa ');
  n = sub(n, r.email, (m) => _address(m[0]!));
  n = sub(n, r.url, (m) => _address(m[0]!));
  n = n.replaceAll(r.degree, ' derece').replaceAll(r.plus, ' artı ').replaceAll(r.equals, ' eşittir ').replaceAll(r.emphasis, '');
  n = n.replaceAll('&', ' ve ').replaceAll(RegExp('[•▪►→⇒]'), ' , ').replaceAll(r.drop, '');
  n = sub(n, r.dotted, (m) => [for (final c in m[0]!.split('')) if (c != '.') _initialismLetters[c]].join());
  n = sub(n, r.times, (m) => '${_dative(_int(m[1]!))} ${_int(m[2]!)}');
  n = sub(n, r.kmh, (m) => 'saatte ${_numeric(m[1]!)} kilometre');
  n = sub(n, r.area, (m) => ' ${{'m': 'metre', 'km': 'kilometre', 'cm': 'santimetre'}[m[1]]}${'2²'.contains(m[2]!) ? 'kare' : 'küp'}');
  n = sub(n, r.units, (m) => ' ${_units[m[1]]}');
  n = n.replaceAll(r.litre, ' litre');
  n = sub(n, r.currencySymbol, (m) => _money(m[1]!, m[2]!, m[3]));
  n = sub(n, r.currencyAfter, (m) => _money(m[3] ?? {'TL': '₺', 'USD': r'$', 'EUR': '€', 'GBP': '£'}[m[4]]!, m[1]!, m[2]));
  n = sub(n, r.code, (m) => _capsLexicon.containsKey(m[0]) || _pronounceable(m[0]!) ? m[0]! : ' ${[for (final c in m[0]!.split('')) _initialismLetters[c]].join(' ')} ');
  n = n.replaceAll(r.letterThenDigit, ' ').replaceAll(r.digitThenLetter, ' ').replaceAll(r.letterDash, ' ');
  n = sub(n, r.loneLetterByDigit, (m) => _letterNames[m[1] ?? m[2]]!);
  String date(String d, String mo, String y, String original) {
    final day = int.parse(d), month = int.parse(mo);
    return day < 1 || day > 31 || month < 1 || month > 12 ? original : '${numberToWords(day)} ${_months[month - 1]} ${_int(y)}';
  }

  n = sub(n, r.date, (m) => date(m[1]!, m[2]!, m[3]!, m[0]!));
  n = sub(n, r.isoDate, (m) => date(m[3]!, m[2]!, m[1]!, m[0]!));
  n = sub(n, r.percentBefore, (m) => 'yüzde ${_numeric(m[1]!)}');
  n = sub(n, r.percentAfter, (m) => 'yüzde ${_numeric(m[1]!)}');
  n = sub(n, r.range, (m) {
    final a = m[1]!, b = m[2]!;
    final digits = RegExp(r'^\d+$');
    if (RegExp(r'^\d{4}$').hasMatch(a) && RegExp(r'^\d{2}$').hasMatch(b) && int.parse(b) == (int.parse(a) + 1) % 100) return '$a $b';
    if (digits.hasMatch(a) && digits.hasMatch(b) && a.length < 16 && b.length < 16 && int.parse(a) > int.parse(b)) return '$a $b';
    return '$a ile $b';
  });
  n = n.replaceAll(r.minus, 'eksi ');
  n = sub(n, r.duration, (m) {
    final [h, mi, s] = [for (final g in [m[1], m[2], m[3]]) int.parse(g!)];
    final parts = [if (h > 0) '${numberToWords(h)} saat', if (mi > 0) '${numberToWords(mi)} dakika'];
    return [...parts, if (s > 0 || parts.isEmpty) '${numberToWords(s)} saniye'].join(' ');
  });
  n = sub(n, r.time, (m) {
    final minute = m[2]!;
    final h = numberToWords(int.parse(m[1]!));
    return int.parse(minute) == 0 ? h : '$h ${minute.startsWith('0') ? _digitByDigit(minute) : numberToWords(int.parse(minute))}';
  });
  n = sub(n, r.slashPair, (m) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    if (0 < a && a < b && b <= 10) return '${_locative(numberToWords(b))} ${numberToWords(a)}';
    if ((a == 7 && b == 24) || (a == 24 && b == 7)) return '${numberToWords(a)} ${numberToWords(b)}';
    return '${numberToWords(a)} bölü ${numberToWords(b)}';
  });
  n = sub(n, r.slash, (m) => '${m[1]} bölü ${m[2]}');
  n = sub(n, r.thousands, (m) => _numeric(m[0]!));
  n = sub(n, r.decimal, (m) => _decimal(m[0]!));
  for (final re in [r.ordinalSuffix, r.ordinalDotWord, r.ordinalDot]) {
    n = sub(n, re, (m) => m[1]!.length > 15 ? _digitByDigit(m[1]!) : ordinalToWords(int.parse(m[1]!)));
  }
  n = sub(n, r.longDigits, (m) => _digitByDigit(m[0]!));
  n = sub(n, r.zeroDigits, (m) => _digitGroup(m[0]!));
  n = sub(n, r.digits, (m) => _int(m[0]!));
  n = sub(n, r.perUnit, (m) => ' bölü ${{'sn': 'saniye', 'sa': 'saat', 'dk': 'dakika'}[m[1]!.toLowerCase()]}');
  n = sub(n, r.unitPer, (m) => '${m[1]} bölü ${m[2]}');
  n = n.replaceAll(r.sayin, 'sayın ');
  for (final (re, expansion) in _abbreviationRules) {
    n = n.replaceAll(re, expansion);
  }
  n = sub(n, r.initialism, (m) {
    final word = m[0]!;
    return _capsLexicon[word] ?? (_pronounceable(word) ? word : [for (final c in word.split('')) _initialismLetters[c]].join());
  });
  n = sub(n, r.loneLetter, (m) {
    final letter = m[1]!;
    final following = m.end < m.input.length ? m.input[m.end] : '';
    if ('OI'.contains(letter) || ('AE'.contains(letter) && ',!?'.contains(following) && following.isNotEmpty)) return m[0]!;
    return (m[2] != null || following == '.' ? _initialismLetters : _letterNames)[letter]!;
  });
  n = sub(n, r.stemSuffix, (m) => _attach(m[1]!, m[2]!));
  n = n.replaceAll(r.spacedSlash, ', ').replaceAll(r.wordSlash, ' ');
  n = sub(n, r.spaceBeforePunct, (m) => m[1]!);
  n = n.replaceAll(r.leading, '').replaceAll(r.space, ' ').trim();
  // Initialisms left in capitals are read as words; the voices take lower case only.
  return sub(n, r.capsWord, (m) => turkishLower(m[0]!));
}
