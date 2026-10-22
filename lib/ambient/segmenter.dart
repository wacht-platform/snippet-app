import 'dart:collection';
import 'dart:typed_data';

class AmbientSegment {
  AmbientSegment(this.startedAt, this.pcm);
  final DateTime startedAt;
  final Uint8List pcm;

  Duration get duration => Duration(milliseconds: pcm.length ~/ 2 * 1000 ~/ 16000);
}

class SpeechSegmenter {
  SpeechSegmenter({
    required this.onSegment,
    this.threshold = 0.5,
    this.offThreshold = 0.35,
    this.preRollFrames = 10,
    this.minSpeechFrames = 8,
    this.endSilenceFrames = 16,
    this.maxFrames = 1875,
  });

  static const frameMs = 32;

  final void Function(AmbientSegment segment) onSegment;
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

  bool get speaking => _active;

  void addFrame(Uint8List frame, double probability) {
    if (!_active) {
      if (probability >= threshold) {
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
      final keepGoing = probability >= offThreshold;
      _finish();
      if (keepGoing) _beginEmpty();
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
  }

  void _beginEmpty() {
    _startedAt = DateTime.now();
    _frames = 0;
    _speechFrames = 1;
    _silentFrames = 0;
    _active = true;
  }

  void _finish() {
    final bytes = _buffer.takeBytes();
    final enough = _speechFrames >= minSpeechFrames;
    _active = false;
    _frames = 0;
    _speechFrames = 0;
    _silentFrames = 0;
    if (enough && bytes.isNotEmpty) {
      onSegment(AmbientSegment(_startedAt, bytes));
    }
  }
}
