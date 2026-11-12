import 'dart:convert';
import 'dart:io';

import 'package:egebookreader/incoming.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _Cache extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Cache(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationCachePath() async => dir;
}

void main() {
  test('the Wi-Fi page is only at its secret path, takes uploads, and refuses paths out of its folder', () async {
    final cache = Directory.systemTemp.createTempSync('wifi');
    PathProviderPlatform.instance = _Cache(cache.path);
    final t = WifiTransfer();
    await t.start();
    final base = 'http://127.0.0.1:${t.server!.port}';
    final token = (t.address ?? '/x/').split('/').reversed.elementAt(1);
    final client = HttpClient();
    Future<int> call(String method, String path, [String body = '']) async {
      final r = await client.openUrl(method, Uri.parse('$base$path'));
      r.followRedirects = false;
      r.write(body);
      final res = await r.close();
      await res.drain<void>();
      return res.statusCode;
    }

    expect(await call('GET', '/'), 404);
    expect(await call('GET', '/wrong/'), 404);
    if (t.address != null) {
      expect(await call('GET', '/$token/'), 200);
      expect(await call('GET', '/$token'), 302);
      expect(await call('PUT', '/$token/upload?path=${Uri.encodeQueryComponent('../../evil.txt')}', 'x'), 400);
      expect(await call('PUT', '/$token/upload?path=${Uri.encodeQueryComponent('/etc/evil.txt')}', 'x'), 400);
      expect(await call('PUT', '/$token/upload?path=${Uri.encodeQueryComponent('Calibre/A/B (1)/b.txt')}', 'hello'), 200);
      final got = cache.listSync(recursive: true).whereType<File>().toList();
      expect(got.map((f) => utf8.decode(f.readAsBytesSync())), ['hello']);
      expect(got.single.path, startsWith(cache.path));
      expect(t.status.value, contains('1'));
    }
    await t.stop();
    client.close();
    cache.deleteSync(recursive: true);
  });
}
