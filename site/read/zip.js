// A small ZIP reader. Entries are read from the Blob only when asked for, so a 500 MB comic never sits in memory.

const CP437 = 'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';

const bytesOf = async b => new Uint8Array(await b.arrayBuffer());
const u64 = (v, at) => Number(v.getBigUint64(at, true));

function decodeName(raw, utf8Flag) {
  if (utf8Flag || raw.every(c => c < 0x80)) return new TextDecoder().decode(raw);
  try {
    // Many tools write UTF-8 names without setting the flag.
    return new TextDecoder('utf-8', { fatal: true }).decode(raw);
  } catch {
    return String.fromCharCode(...raw).replace(/[\x80-\xff]/g, c => CP437[c.charCodeAt(0) - 0x80]);
  }
}

export async function openZip(file) {
  const tail = await bytesOf(file.slice(Math.max(0, file.size - 65557)));
  let e = tail.length - 22;
  while (e >= 0 && !(tail[e] === 0x50 && tail[e + 1] === 0x4b && tail[e + 2] === 5 && tail[e + 3] === 6)) e--;
  if (e < 0) throw new Error('not a zip file');
  const t = new DataView(tail.buffer);
  let count = t.getUint16(e + 10, true), size = t.getUint32(e + 12, true), start = t.getUint32(e + 16, true);
  if ((count === 0xffff || size === 0xffffffff || start === 0xffffffff) && e >= 20 && t.getUint32(e - 20, true) === 0x07064b50) {
    const at = u64(t, e - 12);
    const z = new DataView((await bytesOf(file.slice(at, at + 56))).buffer);
    count = u64(z, 32); size = u64(z, 40); start = u64(z, 48);
  }
  const cd = await bytesOf(file.slice(start, start + size));
  const v = new DataView(cd.buffer);
  const entries = [];
  for (let p = 0; p + 46 <= cd.length && v.getUint32(p, true) === 0x02014b50;) {
    const flags = v.getUint16(p + 8, true), n = v.getUint16(p + 28, true), x = v.getUint16(p + 30, true), c = v.getUint16(p + 32, true);
    const entry = {
      name: decodeName(cd.subarray(p + 46, p + 46 + n), flags & 0x800),
      method: v.getUint16(p + 10, true),
      csize: v.getUint32(p + 20, true),
      usize: v.getUint32(p + 24, true),
      offset: v.getUint32(p + 42, true),
      encrypted: flags & 1,
    };
    for (let q = p + 46 + n; q + 4 <= p + 46 + n + x; q += 4 + v.getUint16(q + 2, true)) {
      if (v.getUint16(q, true) !== 1) continue;
      let r = q + 4; // ZIP64 extra: only the fields that overflowed are here, in this order
      for (const k of ['usize', 'csize', 'offset']) if (entry[k] === 0xffffffff) { entry[k] = u64(v, r); r += 8; }
    }
    if (!entry.name.endsWith('/')) entries.push(entry);
    p += 46 + n + x + c;
  }
  const byName = new Map(entries.map(en => [en.name, en]));
  const byLower = new Map(entries.map(en => [en.name.toLowerCase(), en]));

  async function blob(en, type = '') {
    if (!en) return null;
    if (en.encrypted) throw Object.assign(new Error('encrypted zip entry'), { code: 'drm' });
    const h = new DataView(await file.slice(en.offset, en.offset + 30).arrayBuffer());
    if (h.getUint32(0, true) !== 0x04034b50) throw new Error('bad zip entry ' + en.name);
    const from = en.offset + 30 + h.getUint16(26, true) + h.getUint16(28, true);
    const data = file.slice(from, from + en.csize, type);
    if (en.method === 0) return data;
    if (en.method !== 8) throw new Error('unsupported zip method ' + en.method);
    const out = await new Response(data.stream().pipeThrough(new DecompressionStream('deflate-raw'))).blob();
    return type ? new Blob([out], { type }) : out;
  }

  return {
    entries,
    get: name => name == null ? undefined : byName.get(name) ?? byLower.get(name.toLowerCase()),
    blob,
    bytes: async en => en ? bytesOf(await blob(en)) : null,
  };
}
