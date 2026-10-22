import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as so;

Float32List readWav(String path) {
  final b = File(path).readAsBytesSync();
  final n = (b.length - 44) ~/ 2;
  final out = Float32List(n);
  final d = ByteData.sublistView(b, 44);
  for (var i = 0; i < n; i++) {
    out[i] = d.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}

void main(List<String> args) {
  so.initBindings();
  final config = so.VadModelConfig(
    sileroVad: so.SileroVadModelConfig(
        model: args[0],
        threshold: 0.5,
        minSilenceDuration: 0.5,
        minSpeechDuration: 0.25,
        windowSize: 512),
    sampleRate: 16000,
    numThreads: 1,
    debug: false,
  );
  final vad = so.VoiceActivityDetector(config: config, bufferSizeInSeconds: 30);
  final samples = readWav(args[1]);
  final total = samples.length / 16000;
  final sw = Stopwatch()..start();
  var segments = 0;
  var speech = 0.0;
  const window = 512;
  for (var i = 0; i + window <= samples.length; i += window) {
    vad.acceptWaveform(Float32List.sublistView(samples, i, i + window));
    while (!vad.isEmpty()) {
      final s = vad.front();
      segments++;
      speech += s.samples.length / 16000;
      vad.pop();
    }
  }
  vad.flush();
  while (!vad.isEmpty()) {
    final s = vad.front();
    segments++;
    speech += s.samples.length / 16000;
    vad.pop();
  }
  sw.stop();
  vad.free();
  print('audio ${total.toStringAsFixed(1)}s, speech ${speech.toStringAsFixed(1)}s '
      '(${(100 * speech / total).toStringAsFixed(0)}%), segments $segments, '
      'took ${sw.elapsedMilliseconds}ms, RTF ${(sw.elapsedMilliseconds / 1000 / total).toStringAsFixed(4)}');
}
