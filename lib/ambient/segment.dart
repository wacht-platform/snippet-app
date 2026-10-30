import 'dart:typed_data';

class AmbientSegment {
  AmbientSegment(this.startedAt, this.pcm);
  final DateTime startedAt;
  final Uint8List pcm;

  Duration get duration =>
      Duration(milliseconds: pcm.length ~/ 2 * 1000 ~/ 16000);
}
