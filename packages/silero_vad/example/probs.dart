import 'dart:io';
import 'dart:typed_data';

import 'package:silero_vad/silero_vad.dart';

Float32List readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final view = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final size = view.getUint32(offset + 4, Endian.little);
    if (id == 'data') {
      final count = size ~/ 2;
      final out = Float32List(count);
      for (var i = 0; i < count; i++) {
        out[i] = view.getInt16(offset + 8 + i * 2, Endian.little) / 32768.0;
      }
      return out;
    }
    offset += 8 + size + (size & 1);
  }
  throw StateError('no data chunk');
}

void main(List<String> args) {
  final samples = readWav(args[0]);
  final vad = SileroVad();
  final out = StringBuffer();
  final watch = Stopwatch()..start();
  var frames = 0;
  for (var i = 0; i + 512 <= samples.length; i += 512) {
    out.writeln(vad.process(Float32List.sublistView(samples, i, i + 512)));
    frames++;
  }
  watch.stop();
  vad.close();
  File(args[1]).writeAsStringSync(out.toString());
  stderr.writeln('frames $frames in ${watch.elapsedMilliseconds}ms');
}
