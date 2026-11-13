import 'dart:io';

import 'package:egebookreader/balloons.dart';
import 'package:flutter_test/flutter_test.dart';

// Reads and translates the sample pages with the real models, on this computer. Runs only when told where they are:
//   EBR_MODELS=<folder laid out like the app's models/> EBR_ONNXRUNTIME=<libonnxruntime.dylib> flutter test test/balloons_models_test.dart
void main() {
  final models = Platform.environment['EBR_MODELS'];
  testWidgets('balloons on real pages', (tester) async {
    await tester.runAsync(() async {
      final reader = BalloonReader(models);
      Future<void> page(String path, String from, String to) async {
        final clock = Stopwatch()..start();
        final found = await reader.read(File(path).readAsBytesSync(), from, to);
        // ignore: avoid_print
        print('$path $from→$to, ${clock.elapsedMilliseconds} ms');
        for (final b in found) {
          // ignore: avoid_print
          print('  ${b.rect.topLeft.dx.toStringAsFixed(2)},${b.rect.topLeft.dy.toStringAsFixed(2)}  ${b.original}  →  ${b.translated}');
        }
        expect(found, isNotEmpty);
      }

      await page('assets/onboarding/compare-manga-orig.jpg', 'en', 'tr');
      if (Platform.environment['EBR_JA_PAGE'] case final ja?) await page(ja, 'ja', 'tr');
      reader.close();
    });
  }, skip: models == null);
}
