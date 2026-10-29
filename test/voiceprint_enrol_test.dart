import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/voiceprint_enrol.dart';

Uint8List tone(double seconds, double amp) {
  final n = (seconds * 16000).round();
  final d = ByteData(n * 2);
  for (var i = 0; i < n; i++) {
    d.setInt16(i * 2, (amp * math.sin(i * 0.3)).round(), Endian.little);
  }
  return d.buffer.asUint8List();
}

void main() {
  test('silence has no voiced time', () {
    expect(voicedDuration(Uint8List(32000)), Duration.zero);
  });

  test('loud audio counts fully', () {
    expect(voicedDuration(tone(2, 6000)), const Duration(seconds: 2));
  });

  test('quiet noise stays under the threshold', () {
    expect(voicedDuration(tone(3, 200)), Duration.zero);
  });

  test('only voiced stretches count', () {
    final b = BytesBuilder()
      ..add(tone(1, 6000))
      ..add(Uint8List(32000))
      ..add(tone(0.5, 6000));
    expect(voicedDuration(b.toBytes()), const Duration(milliseconds: 1500));
  });

  test('level rises with loudness', () {
    expect(pcmLevel(Uint8List(640)), 0);
    expect(pcmLevel(tone(0.1, 8000)), greaterThan(pcmLevel(tone(0.1, 500))));
  });
}
