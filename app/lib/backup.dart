import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'main.dart' show Book, library;

const _device = MethodChannel('egebookreader/volume');

/// The whole library in one zip: each book file, its covers, and the library and lists with paths made relative.
/// Stored, not compressed: books and pictures are compressed already, and storing is fast.
Future<File> writeBackup() async {
  await library.flush();
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final out = File(p.join((await getApplicationCacheDirectory()).path, 'EgeBookReader-$day.ebrbackup'));
  final zip = ZipFileEncoder()..create(out.path, level: 0);
  final books = <Map<String, dynamic>>[];
  var n = 0;
  // Entries get plain numbered names: the zip writer does not mark names as UTF-8, so "Örneği" would not survive.
  // The real names travel in library.json.
  Future<String?> put(String? path, String folder) async {
    if (path == null || !File(path).existsSync()) return null;
    final name = '$folder/${n++}${p.extension(path)}';
    await zip.addFile(File(path), name, 0);
    return name;
  }

  for (final b in library.books) {
    books.add({
      ...b.toJson(),
      'fileName': p.basename(b.path),
      'path': await put(b.path, 'books'),
      'cover': await put(b.coverPath, 'covers'),
      'customCover': await put(b.customCover, 'covers'),
    });
  }
  zip.addArchiveFile(ArchiveFile.string('library.json', jsonEncode(books.where((b) => b['path'] != null).toList())));
  zip.addArchiveFile(ArchiveFile.string('lists.json', jsonEncode(library.listNames)));
  await zip.close();
  return out;
}

/// Lets the reader choose where the backup goes (Android's save dialog) and copies it there. False if they cancelled.
Future<bool> saveBackupAs(File backup) async =>
    await _device.invokeMethod<bool>('saveDocument', {'path': backup.path, 'name': p.basename(backup.path)}) ?? false;

/// Adds the books in a backup that the library does not have yet, with their progress, tags, lists and covers.
/// Books already here (same file name and size) are left as they are. Returns how many were added.
Future<int> restoreBackup(String path) async {
  final input = InputFileStream(path);
  try {
    final zip = ZipDecoder().decodeStream(input);
    ArchiveFile? entry(String name) => zip.files.where((f) => f.name == name).firstOrNull;
    final index = entry('library.json');
    if (index == null) throw const FormatException('Bu dosya bir EgeBookReader yedeği değil.');
    final dir = await getApplicationDocumentsDirectory();

    /// Writes an entry under [folder] as [wanted] (or the entry's own name), changed if a file there has it already.
    Future<String?> take(String? name, String folder, [String? wanted]) async {
      final file = name == null ? null : entry(name);
      if (file == null) return null;
      final ext = p.extension(wanted ?? name!), stem = p.basenameWithoutExtension(wanted ?? name!);
      var to = File(p.join(dir.path, folder, '$stem$ext'));
      for (var n = 2; to.existsSync(); n++) {
        to = File(p.join(dir.path, folder, '$stem ($n)$ext'));
      }
      await to.create(recursive: true);
      final output = OutputFileStream(to.path);
      file.writeContent(output);
      await output.close();
      return to.path;
    }

    var added = 0;
    for (final raw in (jsonDecode(utf8.decode(index.content)) as List<dynamic>).cast<Map<String, dynamic>>()) {
      final name = raw['path'] as String, fileName = raw['fileName'] as String? ?? p.basename(name);
      final size = entry(name)?.size ?? -1;
      final here = library.books.any((b) => p.basename(b.path) == fileName && File(b.path).lengthSync() == size);
      if (here || size < 0) continue;
      final bookPath = await take(name, 'books', fileName);
      library.books.add(Book.fromJson({
        ...raw,
        'path': bookPath,
        'cover': await take(raw['cover'] as String?, 'covers'),
        'customCover': await take(raw['customCover'] as String?, 'covers'),
      }));
      added++;
    }
    final lists = entry('lists.json');
    if (lists != null) {
      for (final name in (jsonDecode(utf8.decode(lists.content)) as List<dynamic>).cast<String>()) {
        if (!library.listNames.contains(name)) library.listNames.add(name);
      }
    }
    library.changed();
    return added;
  } finally {
    await input.close();
  }
}
