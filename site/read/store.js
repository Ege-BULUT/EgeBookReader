// The web library, in this browser's IndexedDB. Books never leave the device.
const DB = 'ebr-web', V = 1;
let db;
function open() {
  return db ??= new Promise((res, rej) => {
    const r = indexedDB.open(DB, V);
    r.onupgradeneeded = () => {
      const d = r.result;
      d.createObjectStore('books', { keyPath: 'id' });
      d.createObjectStore('files');
      d.createObjectStore('inbox', { autoIncrement: true });
    };
    r.onsuccess = () => res(r.result);
    r.onerror = () => rej(r.error);
  });
}
async function tx(store, mode, fn) {
  const d = await open();
  return new Promise((res, rej) => {
    const t = d.transaction(store, mode), s = t.objectStore(store);
    let out;
    Promise.resolve(fn(s)).then(r => { out = r; });
    t.oncomplete = () => res(out instanceof IDBRequest ? out.result : out);
    t.onerror = t.onabort = () => rej(t.error);
  });
}
export const books = () => tx('books', 'readonly', s => s.getAll());
export const book = id => tx('books', 'readonly', s => s.get(id));
export const putBook = b => tx('books', 'readwrite', s => s.put(b));
export const files = id => tx('files', 'readonly', s => s.get(id));
export async function addFiles(id, list) {
  await tx('files', 'readwrite', s => s.put(list, id));
}
export async function remove(id) {
  await tx('books', 'readwrite', s => s.delete(id));
  await tx('files', 'readwrite', s => s.delete(id));
}
// Files shared to the installed app (share target) wait here until the page picks them up.
export async function takeInbox() {
  const d = await open();
  return new Promise((res, rej) => {
    const t = d.transaction('inbox', 'readwrite'), s = t.objectStore('inbox'), all = s.getAll();
    all.onsuccess = () => s.clear();
    t.oncomplete = () => res(all.result || []);
    t.onerror = () => rej(t.error);
  });
}
// A stable id for a file, so opening the same book again finds its place.
export function idOf(list) {
  const f = list[0];
  return list.length > 1 ? 'set:' + f.name + ':' + list.length + ':' + list.reduce((a, x) => a + x.size, 0)
    : f.name + ':' + f.size;
}
