import 'dart:collection';
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

class SpeechSegmenter {
  SpeechSegmenter({
    required this.onSegment,
    required this.onSpeechStart,
    this.onDiscard,
    this.threshold = 0.5,
    this.offThreshold = 0.35,
    this.preRollFrames = 10,
    this.minSpeechFrames = 8,
    this.endSilenceFrames = 20,
    this.maxFrames = 1875,
  });

  static const frameMs = 32;

  final void Function(AmbientSegment segment) onSegment;
  final Future<int> Function(DateTime startedAt) onSpeechStart;
  final void Function(Future<int> seq)? onDiscard;
  final double threshold;
  final double offThreshold;
  final int preRollFrames;
  final int minSpeechFrames;
  final int endSilenceFrames;
  final int maxFrames;

  final Queue<Uint8List> _preRoll = Queue();
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  bool _active = false;
  int _frames = 0;
  int _speechFrames = 0;
  int _silentFrames = 0;
  DateTime _startedAt = DateTime.now();
  bool _continued = false;
  Future<int>? _seq;
  Uint8List? _pendingTail;
  DateTime? _pendingTailStartedAt;

  bool get speaking => _active;

  void addFrame(Uint8List frame, double probability) {
    if (!_active) {
      if (_pendingTail != null) {
        if (probability >= offThreshold) {
          _beginContinued(frame);
        } else {
          _preRoll.addLast(_pendingTail!);
          _preRoll.addLast(frame);
          while (_preRoll.length > preRollFrames) {
            _preRoll.removeFirst();
          }
          _pendingTail = null;
          _pendingTailStartedAt = null;
          if (probability >= threshold) _begin(frame);
        }
      } else if (probability >= threshold) {
        _begin(frame);
      } else {
        _preRoll.addLast(frame);
        while (_preRoll.length > preRollFrames) {
          _preRoll.removeFirst();
        }
      }
      return;
    }
    _buffer.add(frame);
    _frames++;
    if (probability >= threshold) _speechFrames++;
    if (probability >= offThreshold) {
      _silentFrames = 0;
    } else {
      _silentFrames++;
    }
    if (_silentFrames >= endSilenceFrames) {
      _finish();
    } else if (_frames >= maxFrames) {
      final frames = _buffer.takeBytes();
      const tailBytes = 10 * 512 * 2;
      final first = Uint8List.fromList(frames.sublist(0, frames.length - tailBytes));
      final tail = Uint8List.fromList(frames.sublist(frames.length - tailBytes));
      final wasContinued = _continued;
      _active = false;
      _continued = true;
      if (_speechFrames >= minSpeechFrames) onSegment(AmbientSegment(_startedAt, first, continued: wasContinued, seq: _seq));
      _pendingTail = tail;
      _pendingTailStartedAt = _startedAt.add(Duration(milliseconds: first.length ~/ 2 * 1000 ~/ 16000));
    }
  }

  void flush() {
    if (_active) _finish();
    _preRoll.clear();
  }

  void _begin(Uint8List frame) {
    _startedAt = DateTime.now()
        .subtract(Duration(milliseconds: (_preRoll.length + 1) * frameMs));
    for (final past in _preRoll) {
      _buffer.add(past);
    }
    _frames = _preRoll.length + 1;
    _preRoll.clear();
    _buffer.add(frame);
    _speechFrames = 1;
    _silentFrames = 0;
    _active = true;
    _continued = false;
    _seq = onSpeechStart(_startedAt);
  }

  void _beginContinued(Uint8List frame) {
    _startedAt = _pendingTailStartedAt ?? DateTime.now();
    _buffer.add(_pendingTail!);
    _buffer.add(frame);
    _pendingTail = null;
    _pendingTailStartedAt = null;
    _frames = 11;
    _speechFrames = 1;
    _silentFrames = 0;
    _active = true;
    _continued = true;
    _seq = onSpeechStart(_startedAt);
  }

  void _finish() {
    final bytes = _buffer.takeBytes();
    final enough = _speechFrames >= minSpeechFrames;
    _active = false;
    _frames = 0;
    _speechFrames = 0;
    _silentFrames = 0;
    if (enough && bytes.isNotEmpty) {
      onSegment(AmbientSegment(_startedAt, bytes, continued: _continued, seq: _seq));
    } else if (_seq != null) {
      onDiscard?.call(_seq!);
    }
  }
}
