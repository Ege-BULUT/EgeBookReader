import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

typedef _P = Pointer<Void>;

/// Unpacks every picture of a RAR or 7z archive into [to], on its own isolate.
/// Entry names are flattened with their folders kept in the name, so pages sort in reading order and nothing can land outside [to].
Future<void> extractArchive(String from, String to) => Isolate.run(() {
      final lib = DynamicLibrary.open('libebr_archive.so');
      final open = lib.lookupFunction<_P Function(), _P Function()>('archive_read_new');
      final rar = lib.lookupFunction<Int Function(_P), int Function(_P)>('archive_read_support_format_rar');
      final rar5 = lib.lookupFunction<Int Function(_P), int Function(_P)>('archive_read_support_format_rar5');
      final sevenZip = lib.lookupFunction<Int Function(_P), int Function(_P)>('archive_read_support_format_7zip');
      final openFile = lib.lookupFunction<Int Function(_P, Pointer<Utf8>, Size), int Function(_P, Pointer<Utf8>, int)>('archive_read_open_filename');
      final next = lib.lookupFunction<Int Function(_P, Pointer<_P>), int Function(_P, Pointer<_P>)>('archive_read_next_header');
      final name = lib.lookupFunction<Pointer<Utf8> Function(_P), Pointer<Utf8> Function(_P)>('archive_entry_pathname_utf8');
      final read = lib.lookupFunction<LongLong Function(_P, Pointer<Uint8>, Size), int Function(_P, Pointer<Uint8>, int)>('archive_read_data');
      final free = lib.lookupFunction<Int Function(_P), int Function(_P)>('archive_read_free');

      final a = open();
      rar(a);
      rar5(a);
      sevenZip(a);
      final entry = calloc<_P>();
      final path = from.toNativeUtf8();
      const chunk = 1 << 18;
      final buffer = calloc<Uint8>(chunk);
      try {
        if (openFile(a, path, 1 << 16) != 0) throw const FormatException('Bu çizgi roman arşivi açılamadı.');
        var number = 0;
        for (var status = next(a, entry); status == 0 || status == -20; status = next(a, entry)) {
          final raw = name(entry.value);
          if (raw == nullptr) continue;
          final entryName = raw.toDartString();
          if (!RegExp(r'\.(jpe?g|png|webp|gif|bmp)$', caseSensitive: false).hasMatch(entryName)) continue;
          final flat = entryName.replaceAll(RegExp(r'[\\/]'), '_').replaceAll('..', '_');
          final out = File(p.join(to, flat)).openSync(mode: FileMode.write);
          try {
            for (var n = read(a, buffer, chunk); n != 0; n = read(a, buffer, chunk)) {
              if (n < 0) throw const FormatException('Bu çizgi roman arşivi okunamadı. Parola korumalı olabilir.');
              out.writeFromSync(buffer.asTypedList(n));
            }
          } finally {
            out.closeSync();
          }
          number++;
        }
        if (number == 0) throw const FormatException('Bu çizgi roman arşivinde görsel bulunamadı.');
      } finally {
        free(a);
        calloc.free(entry);
        calloc.free(path);
        calloc.free(buffer);
      }
    });
