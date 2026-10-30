import 'dart:collection';
import 'dart:typed_data';

class SpeechGate {
  SpeechGate({
    required this.onOpen,
    required this.onFrame,
    required this.onClose,
    this.threshold = 0.5,
    this.offThreshold = 0.35,
    this.preRollFrames = 31,
    this.quietFrames = 312,
  });

  static const frameMs = 32;

  final void Function(DateTime startedAt, List<Uint8List> preRoll) onOpen;
  final void Function(Uint8List frame) onFrame;
  final void Function() onClose;
  final double threshold;
  final double offThreshold;
  final int preRollFrames;
  final int quietFrames;
  bool keepOpen = false;

  final Queue<Uint8List> _preRoll = Queue();
  bool _open = false;
  int _quiet = 0;
  bool _speaking = false;

  bool get open => _open;
  bool get speaking => _speaking;

  void addFrame(Uint8List frame, double probability) {
    if (probability >= threshold) {
      _speaking = true;
    } else if (probability < offThreshold) {
      _speaking = false;
    }
    if (!_open) {
      if (probability >= threshold || keepOpen) {
        _open = true;
        _quiet = 0;
        final started = DateTime.now().subtract(Duration(milliseconds: (_preRoll.length + 1) * frameMs));
        final roll = _preRoll.toList()..add(frame);
        _preRoll.clear();
        onOpen(started, roll);
      } else {
        _preRoll.addLast(frame);
        while (_preRoll.length > preRollFrames) {
          _preRoll.removeFirst();
        }
      }
      return;
    }
    onFrame(frame);
    if (probability >= offThreshold || keepOpen) {
      _quiet = 0;
    } else if (++_quiet >= quietFrames) {
      close();
    }
  }

  void close() {
    if (!_open) return;
    _open = false;
    _quiet = 0;
    _speaking = false;
    onClose();
  }

  void abandon() {
    _preRoll.clear();
    close();
  }
}
