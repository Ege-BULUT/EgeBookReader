import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'main.dart' show Book, library, settings;
import 'settings.dart' show appVersion;

const _device = MethodChannel('egebookreader/volume');

/// The whole library in one zip: each book file, its covers, and the library and lists with paths made relative.
/// Stored, not compressed: books and pictures are compressed already, and storing is fast. The zip is written on
/// another isolate, so a large library never holds up the screen.
// ponytail: the zip is made in the cache and then copied, so a backup briefly needs the library's size free twice.
Future<File> writeBackup() async {
  await library.flush();
  final out = File(p.join((await getApplicationCacheDirectory()).path, backupName(DateTime.now())));
  final books = <Map<String, dynamic>>[];
  final files = <(String, String)>[];
  // Entries get plain numbered names: the zip writer does not mark names as UTF-8, so "Örneği" would not survive.
  // The real names travel in library.json.
  String? put(String? path, String folder) {
    if (path == null || !File(path).existsSync()) return null;
    final name = '$folder/${files.length}${p.extension(path)}';
    files.add((path, name));
    return name;
  }

  for (final b in library.books) {
    books.add({
      ...b.toJson(),
      'fileName': p.basename(b.path),
      'path': put(b.path, 'books'),
      'cover': put(b.coverPath, 'covers'),
      'customCover': put(b.customCover, 'covers'),
    });
  }
  final index = jsonEncode(books.where((b) => b['path'] != null).toList()), lists = jsonEncode(library.listNames);
  final to = out.path;
  await Isolate.run(() => _zip(to, files, index, lists));
  return out;
}

Future<void> _zip(String to, List<(String, String)> files, String index, String lists) async {
  final zip = ZipFileEncoder()..create(to, level: 0);
  for (final (path, name) in files) {
    await zip.addFile(File(path), name, 0);
  }
  zip.addArchiveFile(ArchiveFile.string('library.json', index));
  zip.addArchiveFile(ArchiveFile.string('lists.json', lists));
  await zip.close();
}

/// A backup's file name; automatic ones sort by name in the order they were made.
String backupName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'EgeBookReader-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}.ebrbackup';
}

final _ours = RegExp(r'^EgeBookReader-\d{4}-\d\d-\d\d-\d{4}\.ebrbackup$');

/// Of the files listed in a backup folder, the backups to delete so that [keep] remain once a new one is added.
/// Only names this app gives are touched, and only at the folder's top.
List<String> staleBackups(List<Map<dynamic, dynamic>> listed, {int keep = 3}) {
  final ours = [for (final f in listed) if (_ours.hasMatch(f['path'] as String)) f]
    ..sort((a, b) => (b['path'] as String).compareTo(a['path'] as String));
  return [for (final f in ours.skip(keep - 1)) f['uri'] as String];
}

/// Whether an automatic backup every [days] days is due, the last one made at [last].
bool backupDue(int days, int last, DateTime now) => days > 0 && now.millisecondsSinceEpoch - last >= days * Duration.millisecondsPerDay;

bool _backingUp = false;

/// Writes a backup into the reader's backup folder if one is due, or at once with [now]. The three newest stay.
/// Never throws and never waits on the screen: a failure goes to the error log and false comes back.
/// Not while books are missing (a new phone not restored yet): a backup of what is left would push out the good ones.
Future<bool> autoBackup({bool now = false}) async {
  final folder = settings.backupFolder;
  if (folder == null || _backingUp || library.missing.isNotEmpty) return false;
  if (!now && !backupDue(settings.backupDays, settings.lastBackup, DateTime.now())) return false;
  _backingUp = true;
  File? file;
  try {
    final listed = await _device.invokeListMethod<Map<dynamic, dynamic>>('listFolder', folder) ?? [];
    file = await writeBackup();
    await _device.invokeMethod('writeToTree', {'tree': folder, 'path': file.path, 'name': p.basename(file.path), 'delete': staleBackups(listed)});
    settings.update((x) => x.lastBackup = DateTime.now().millisecondsSinceEpoch);
    return true;
  } catch (e, stack) {
    logError('Automatic backup: $e', stack);
    return false;
  } finally {
    _backingUp = false;
    await file?.delete().catchError((_) => file!);
  }
}

/// Asks for the backup folder (Android's folder picker, where Google Drive is offered too) and keeps it.
Future<String?> pickBackupFolder() async {
  final uri = await _device.invokeMethod<String>('pickFolder');
  if (uri != null) settings.update((x) => x.backupFolder = uri);
  return uri;
}

/// Restores from the newest backup in [folder] that can be read; how many books came back, or null if none could be.
Future<int?> restoreFromFolder(String folder) async {
  final listed = await _device.invokeListMethod<Map<dynamic, dynamic>>('listFolder', folder) ?? [];
  final found = [for (final f in listed) if ((f['path'] as String).endsWith('.ebrbackup') && !(f['path'] as String).contains('/')) f]
    ..sort((a, b) => (b['modified'] as int).compareTo(a['modified'] as int));
  final cache = (await getApplicationCacheDirectory()).path;
  // one cut short (the app closed while writing it) does not stop an older one from being used
  for (final f in found) {
    final copy = await _device.invokeMethod<String>('copyIn', {'uri': f['uri'], 'to': p.join(cache, 'restore', 'backup.ebrbackup')});
    try {
      return await restoreBackup(copy!);
    } catch (e, stack) {
      logError('Restore from ${f['path']}: $e', stack);
    } finally {
      if (copy != null) await File(copy).delete().catchError((_) => File(copy));
    }
  }
  return null;
}

/// Errors the app met, newest last, kept on the device so the reader can send them if they choose to.
File get errorLog => File(p.join(settings.dir.path, 'errors.log'));

void logError(Object error, StackTrace? stack) {
  try {
    final log = errorLog;
    // ponytail: at 256 KB the older half goes; enough to see what happened lately.
    if (log.existsSync() && log.lengthSync() > 256 * 1024) {
      final text = log.readAsStringSync();
      log.writeAsStringSync(text.substring(text.length ~/ 2));
    }
    log.writeAsStringSync('--- ${DateTime.now().toIso8601String()} · $appVersion\n$error\n${stack ?? ''}\n', mode: FileMode.append);
  } catch (_) {
    // a log that cannot be written must never cause an error of its own
  }
}

/// A copy of the error log saved where the reader chooses; false if there is none or they cancelled.
Future<bool> saveErrorLog() async {
  if (!errorLog.existsSync()) return false;
  final copy = await errorLog.copy(p.join((await getApplicationCacheDirectory()).path, 'EgeBookReader-errors.txt'));
  return saveFileAs(copy);
}

/// Lets the reader choose where a file goes (Android's save dialog) and copies it there. False if they cancelled.
Future<bool> saveFileAs(File file) async =>
    await _device.invokeMethod<bool>('saveDocument', {'path': file.path, 'name': p.basename(file.path)}) ?? false;

/// Adds the books in a backup that the library does not have yet, with their progress, tags, lists and covers.
/// Books already here (same file name and size) are left as they are. A book the library lists without its file
/// (restored onto a new phone) gets its file back, with whichever record was opened last. Returns how many were added.
/// Reading and copying run on another isolate.
Future<int> restoreBackup(String path) async {
  final (index, lists, sizes) = await Isolate.run(() => _readIndex(path));
  if (index == null) throw const FormatException('Bu dosya bir EgeBookReader yedeği değil.');
  final dir = await getApplicationDocumentsDirectory();
  final copies = <(String, String)>[];
  final planned = <String>{};

  /// Where an entry goes under [folder] as [wanted] (or the entry's own name), changed if a file there has it already.
  String? take(String? name, String folder, [String? wanted]) {
    if (name == null || !sizes.containsKey(name)) return null;
    final ext = p.extension(wanted ?? name), stem = p.basenameWithoutExtension(wanted ?? name);
    var to = p.join(dir.path, folder, '$stem$ext');
    for (var n = 2; File(to).existsSync() || planned.contains(to); n++) {
      to = p.join(dir.path, folder, '$stem ($n)$ext');
    }
    planned.add(to);
    copies.add((name, to));
    return to;
  }

  final restored = <Map<String, dynamic>>[], found = <Map<String, dynamic>>[];
  final have = {for (final b in library.books) (p.basename(b.path), File(b.path).lengthSync())};
  final missing = {for (final m in library.missing) p.basename(m['path'] as String): m};
  for (final raw in (jsonDecode(index) as List<dynamic>).cast<Map<String, dynamic>>()) {
    final name = raw['path'] as String, fileName = raw['fileName'] as String? ?? p.basename(name);
    final size = sizes[name] ?? -1;
    final kept = missing[fileName];
    if (kept != null) found.add(kept);
    if (have.contains((fileName, size)) || size < 0) continue;
    final newer = kept != null && (kept['opened'] as int? ?? 0) >= (raw['opened'] as int? ?? 0) ? kept : raw;
    restored.add({
      ...newer,
      'path': take(name, 'books', fileName),
      'cover': take(raw['cover'] as String?, 'covers'),
      'customCover': take(raw['customCover'] as String?, 'covers'),
    });
  }
  await Isolate.run(() => _extract(path, copies));
  library.books.addAll(restored.map(Book.fromJson));
  library.missing.removeWhere(found.toSet().contains);
  for (final name in lists == null ? const [] : (jsonDecode(lists) as List<dynamic>).cast<String>()) {
    if (!library.listNames.contains(name)) library.listNames.add(name);
  }
  library.changed();
  return restored.length;
}

/// A backup's library.json and lists.json, and the size of every entry by name.
(String?, String?, Map<String, int>) _readIndex(String path) {
  final input = InputFileStream(path);
  try {
    final zip = ZipDecoder().decodeStream(input);
    String? text(String name) => zip.files.where((f) => f.name == name).map((f) => utf8.decode(f.content)).firstOrNull;
    return (text('library.json'), text('lists.json'), {for (final f in zip.files) f.name: f.size});
  } finally {
    input.closeSync();
  }
}

void _extract(String path, List<(String, String)> copies) {
  final input = InputFileStream(path);
  try {
    final zip = ZipDecoder().decodeStream(input);
    final byName = {for (final f in zip.files) f.name: f};
    for (final (name, to) in copies) {
      File(to).parent.createSync(recursive: true);
      final output = OutputFileStream(to);
      byName[name]!.writeContent(output);
      output.closeSync();
    }
  } finally {
    input.closeSync();
  }
}
