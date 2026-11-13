import 'dart:math';
import 'dart:typed_data';

import 'package:egebookreader/natural.dart';
import 'package:egebookreader/trnorm.dart';
import 'package:egebookreader/voiceclone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Turkish text is spelled out as it is read', () {
    expect(numberToWords(1923), 'bin dokuz yüz yirmi üç');
    expect(numberToWords(2000000), 'iki milyon');
    expect(ordinalToWords(21), 'yirmi birinci');
    expect(normalizeTurkish('%2,5 arttı.'), 'yüzde iki buçuk arttı.');
    expect(normalizeTurkish('Saat 15:30\'da geldi.'), 'Saat on beş otuzda geldi.');
    expect(normalizeTurkish('XIX. yüzyılda'), 'on dokuzuncu yüzyılda');
    expect(normalizeTurkish('Prof. Dr. Ayşe'), 'profesör doktor Ayşe');
    expect(normalizeTurkish('-5 °C'), 'eksi beş derece');
  });

  test('random numbers follow torch.manual_seed and torch.randn', () {
    // torch.manual_seed(7); torch.randn(20) begins -0.82013, 0.39563, 0.89891
    final x = TorchRandn(7).randn(32);
    expect(x[0], closeTo(-0.82013, 1e-5));
    expect(x[1], closeTo(0.39563, 1e-5));
    expect(x[2], closeTo(0.89891, 1e-5));
  });

  test('durations and frames line up with the symbols', () {
    final ids = [1, 10, 10, 3, 12, 2];
    final logd = Float32List.fromList([for (var i = 0; i < ids.length; i++) log(4.0)]);
    final d = antaliaDurations(logd, ids, 1);
    expect(d[2], 5); // a doubled letter is held 1.3 times as long: 4 * 1.3 = 5.2
    expect(d.where((v) => v == 4).length, 5);
    final f = frameIndex([1, 2, 2]);
    expect(f, [0, 1, 1, 2, 2, 2]); // 5 frames rounded up to 6, the last holds the last symbol
  });

  test('Ahenk text is cut into short pieces with pauses', () {
    final chunks = ahenkChunks('${'Bir iki üç dört beş altı. ' * 20}Son.', 1);
    expect(chunks.length, greaterThan(1));
    for (final (text, pause) in chunks) {
      expect(text.length, lessThanOrEqualTo(180));
      expect(pause, greaterThanOrEqualTo(0));
    }
  });

  test('resampling keeps a tone and its length', () {
    const n = 44100;
    final x = Float32List.fromList([for (var i = 0; i < n; i++) sin(2 * pi * 440 * i / 44100)]);
    final y = resample(x, 44100, 22050);
    expect(y.length, 22050);
    var err = 0.0;
    for (var i = 1000; i < 21000; i++) {
      err = max(err, (y[i] - sin(2 * pi * 440 * i / 22050)).abs());
    }
    expect(err, lessThan(0.01));
  });

  test('long audio is cut at a quiet spot into pieces of at most 8 s', () {
    const rate = 22050;
    final x = Float32List.fromList([for (var i = 0; i < 20 * rate; i++) (i ~/ rate) == 6 ? 0.0 : sin(i / 7)]);
    final cuts = cutPoints(x);
    expect(cuts.first, 0);
    expect(cuts.last, x.length);
    for (var i = 0; i + 1 < cuts.length; i++) {
      expect(cuts[i + 1] - cuts[i], lessThanOrEqualTo(8 * rate));
    }
    expect(cuts[1] ~/ rate, 6); // inside the silent second
  });
}
