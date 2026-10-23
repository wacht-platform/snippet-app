import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:silero_vad/silero_vad.dart';

import 'diagnostics.dart';
import 'segmenter.dart';
import 'uploader.dart';
import 'voice.dart';

class AmbientStatus {
  const AmbientStatus({
    this.running = false,
    this.speaking = false,
    this.probability = 0,
    this.segments = 0,
    this.pending = 0,
    this.error,
    this.displaced = false,
    this.assistantSpeaking = false,
  });

  final bool assistantSpeaking;
  final bool displaced;
  final bool running;
  final bool speaking;
  final double probability;
  final int segments;
  final int pending;
  final String? error;

  Map<String, Object?> toMap() => {
        'running': running,
        'speaking': speaking,
        'probability': probability,
        'segments': segments,
        'pending': pending,
        'error': error,
        'displaced': displaced,
        'assistantSpeaking': assistantSpeaking,
      };

  factory AmbientStatus.fromMap(Map<Object?, Object?> map) => AmbientStatus(
        running: map['running'] == true,
        speaking: map['speaking'] == true,
        probability: (map['probability'] as num?)?.toDouble() ?? 0,
        segments: (map['segments'] as num?)?.toInt() ?? 0,
        pending: (map['pending'] as num?)?.toInt() ?? 0,
        error: map['error'] as String?,
        displaced: map['displaced'] == true,
        assistantSpeaking: map['assistantSpeaking'] == true,
      );
}

class AmbientCapture {
  AmbientCapture(this.uploader, {this.threshold = 0.5});

  final AmbientUploader uploader;
  final double threshold;
  final StreamController<AmbientStatus> _status = StreamController.broadcast();
  final AudioRecorder _recorder = AudioRecorder();
  final BytesBuilder _pending = BytesBuilder(copy: false);

  SileroVad? _vad;
  SpeechSegmenter? _segmenter;
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  bool _running = false;
  bool _muted = false;
  AmbientVoice? _voice;
  double _probability = 0;
  int _segments = 0;
  String? _error;

  Stream<AmbientStatus> get status => _status.stream;
  bool get running => _running;

  AmbientStatus get current => AmbientStatus(
        running: _running,
        speaking: _segmenter?.speaking ?? false,
        probability: _probability,
        segments: _segments,
        pending: uploader.pending.value,
        error: uploader.displaced.value ? null : (_error ?? uploader.lastError.value),
        displaced: uploader.displaced.value,
        assistantSpeaking: _muted,
      );

  Future<void> start() async {
    if (_running) return;
    await AmbientDiagnostics.log('uploader starting');
    uploader.displaced.addListener(() {
      if (uploader.displaced.value) unawaited(stop());
    });
    await uploader.start();
    await AmbientDiagnostics.log('loading detector');
    _vad = SileroVad();
    await AmbientDiagnostics.log('detector loaded, opening microphone');
    _segmenter = SpeechSegmenter(
      threshold: threshold,
      offThreshold: threshold - 0.15,
      onSegment: (segment) {
        _segments++;
        unawaited(uploader.enqueue(segment));
      },
    );
    final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.none));
    _running = true;
    _error = null;
    _sub = stream.listen(_onAudio, onError: (Object e) {
      _error = '$e';
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_status.isClosed) _status.add(current);
    });
    _voice = AmbientVoice(
      baseUrl: uploader.baseUrl,
      token: uploader.token,
      device: uploader.device,
      onSpeaking: _setMuted,
    );
    unawaited(_voice!.start());
    _status.add(current);
  }

  void _setMuted(bool muted) {
    if (_muted == muted) return;
    _muted = muted;
    if (muted) {
      _segmenter?.flush();
      _pending.clear();
    }
    if (!_status.isClosed) _status.add(current);
  }

  void _onAudio(Uint8List bytes) {
    if (_muted) return;
    final vad = _vad;
    final segmenter = _segmenter;
    if (vad == null || segmenter == null) return;
    _pending.add(bytes);
    const chunkBytes = SileroVad.chunkSamples * 2;
    final buffer = _pending.takeBytes();
    var offset = 0;
    while (buffer.length - offset >= chunkBytes) {
      final frame = Uint8List.fromList(buffer.sublist(offset, offset + chunkBytes));
      final view = ByteData.sublistView(frame);
      final samples = Float32List(SileroVad.chunkSamples);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
      }
      _probability = vad.process(samples);
      segmenter.addFrame(frame, _probability);
      offset += chunkBytes;
    }
    if (offset < buffer.length) {
      _pending.add(Uint8List.sublistView(buffer, offset));
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    await _sub?.cancel();
    await _recorder.stop();
    _segmenter?.flush();
    _vad?.close();
    _vad = null;
    _status.add(current);
  }

  Future<void> dispose() async {
    await _voice?.dispose();
    _voice = null;
    await stop();
    uploader.close();
    await _recorder.dispose();
    await _status.close();
  }
}
