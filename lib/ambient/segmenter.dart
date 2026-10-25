import 'dart:typed_data';

class AmbientSegment {
  AmbientSegment(this.startedAt, this.pcm, {this.continued = false, this.duringPlayback = false, this.media = false, this.seq});
  final DateTime startedAt;
  final Uint8List pcm;
  final bool continued;
  final bool duringPlayback;
  final bool media;
  final Future<int>? seq;
  AmbientSegment copyWith({bool? duringPlayback, bool? media, Future<int>? seq}) => AmbientSegment(startedAt, pcm, continued: continued, duringPlayback: duringPlayback ?? this.duringPlayback, media: media ?? this.media, seq: seq ?? this.seq);

  Duration get duration => Duration(milliseconds: pcm.length ~/ 2 * 1000 ~/ 16000);
}
