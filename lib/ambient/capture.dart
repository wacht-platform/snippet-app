import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:silero_vad/silero_vad.dart';

import 'hold.dart';

import 'diagnostics.dart';
import 'gate.dart';
import 'sink.dart';
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
  SpeechGate? _segmenter;
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  bool _running = false;
  bool _mediaOn = false;
  bool _playOn = false;
  Timer? _mediaTimer;
  Timer? _callTimer;
  bool _callOn = false;
  final AmbientSink _audio = AmbientSink();
  AmbientVoice? _voice;
  final ValueNotifier<AmbientVoice?> voiceListenable = ValueNotifier(null);
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
        error: uploader.displaced.value
            ? null
            : (_error ?? uploader.lastError.value),
        displaced: uploader.displaced.value,
        assistantSpeaking: _voice?.speaking.value ?? false,
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
    _segmenter = SpeechGate(
      threshold: threshold,
      offThreshold: threshold - 0.15,
      onOpen: (startedAt, preRoll) {
        _segments++;
        uploader.gateOpen(startedAt, preRoll);
        uploader.flag('media', _mediaOn);
        uploader.flag('play', _playOn);
      },
      onFrame: uploader.gateFrame,
      onClose: uploader.gateClose,
    );
    final stream = await _recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.none,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: const AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication)));
    _running = true;
    _error = null;
    _sub = stream.listen(_onAudio, onError: (Object e) {
      _error = '$e';
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!_status.isClosed) _status.add(current);
    });
    _statTimer?.cancel();
    _statTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      uploader.stat({
        'frames': _frames,
        'speech': _speechFrames,
        'loud_low_vad': _loudQuiet,
        'held_ms': _heldBytes ~/ 32,
        'build': 12,
        'segments': _segments,
        'threshold': threshold,
        'peak': double.parse(_peak.toStringAsFixed(4))
      });
      _peak = 0;
      _frames = 0;
      _speechFrames = 0;
      _loudQuiet = 0;
    });
    _voice = AmbientVoice(
      baseUrl: uploader.baseUrl,
      token: uploader.token,
      device: uploader.device,
    );
    _voice!.attach(uploader.stream);
    voiceListenable.value = _voice;
    _voice!.state.addListener(_onAmbientState);
    _voice!.speaking.addListener(_onSpeaking);
    _mediaTimer?.cancel();
    _mediaTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_voice?.speaking.value == true) return;
      try {
        final on = await _audio.mediaActive();
        if (on != _mediaOn) {
          _mediaOn = on;
          uploader.flag('media', on);
        }
      } catch (_) {}
    });
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final on = await _audio.inCall();
        if (on != _callOn) {
          _callOn = on;
          unawaited(AmbientDiagnostics.log(on
              ? 'call started: listening paused'
              : 'call ended: listening resumed'));
        }
      } catch (_) {}
    });
    unawaited(_voice!.start());
    _status.add(current);
  }

  Timer? _statTimer;
  int _frames = 0;
  int _speechFrames = 0;
  int _loudQuiet = 0;
  int _heldBytes = 0;
  int _silentFrames = 0;
  double _peak = 0;

  void _onAudio(Uint8List bytes) {
    final vad = _vad;
    final segmenter = _segmenter;
    if (vad == null || segmenter == null) return;
    if (AmbientHold.active || _callOn) {
      _heldBytes += bytes.length;
      segmenter.abandon();
      _pending.takeBytes();
      return;
    }
    _pending.add(bytes);
    const chunkBytes = SileroVad.chunkSamples * 2;
    final buffer = _pending.takeBytes();
    var offset = 0;
    while (buffer.length - offset >= chunkBytes) {
      final frame =
          Uint8List.fromList(buffer.sublist(offset, offset + chunkBytes));
      final view = ByteData.sublistView(frame);
      final samples = Float32List(SileroVad.chunkSamples);
      for (var i = 0; i < samples.length; i++) {
        samples[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
      }
      _probability = vad.process(samples);
      _frames++;
      if (_probability >= threshold) _speechFrames++;
      var energy = 0.0;
      var peak = 0.0;
      for (final x in samples) {
        energy += x * x;
        if (x.abs() > peak) peak = x.abs();
      }
      if (peak > _peak) _peak = peak;
      _silentFrames = peak == 0 ? _silentFrames + 1 : 0;
      if (_silentFrames == 94) {
        _error =
            'The microphone is only sending silence. Allow microphone access for this app (on a Mac: System Settings, Privacy & Security, Microphone; when launched with flutter run, allow the terminal app).';
        unawaited(AmbientDiagnostics.log('microphone silent for 3s'));
      } else if (_silentFrames == 0 &&
          _error != null &&
          _error!.startsWith('The microphone is only sending silence')) {
        _error = null;
      }
      if (energy / samples.length > 0.0004 && _probability < 0.3) _loudQuiet++;
      segmenter.addFrame(frame, _probability);
      _duckCheck(_probability >= threshold);
      offset += chunkBytes;
    }
    if (offset < buffer.length) {
      _pending.add(Uint8List.sublistView(buffer, offset));
    }
  }

  void _onAmbientState() {
    _segmenter?.keepOpen = _voice?.state.value?.mode == 'active';
  }

  int _loud = 0;
  bool _ducked = false;
  Timer? _unduck;

  void _duckCheck(bool voiced) {
    final voice = _voice;
    if (voice == null || !voice.speaking.value) {
      _loud = 0;
      return;
    }
    _loud = voiced ? _loud + 1 : 0;
    if (_loud >= 3 && !_ducked) {
      _ducked = true;
      unawaited(voice.duck(true));
      _unduck?.cancel();
      _unduck = Timer(const Duration(milliseconds: 1500), _restoreVolume);
    }
  }

  void _restoreVolume() {
    _unduck?.cancel();
    if (!_ducked) return;
    _ducked = false;
    unawaited(_voice?.duck(false));
  }

  void _onSpeaking() {
    final on = _voice?.speaking.value ?? false;
    if (!on) _restoreVolume();
    if (on == _playOn) return;
    _playOn = on;
    uploader.flag('play', on);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    _mediaTimer?.cancel();
    _callTimer?.cancel();
    _callOn = false;
    _statTimer?.cancel();
    await _sub?.cancel();
    await _recorder.stop();
    _segmenter?.close();
    unawaited(_audio.leave().catchError((_) {}));
    _vad?.close();
    _vad = null;
    _status.add(current);
  }

  Future<void> dispose() async {
    await _voice?.dispose();
    _voice = null;
    voiceListenable.value = null;
    voiceListenable.dispose();
    await stop();
    uploader.close();
    await _recorder.dispose();
    await _status.close();
  }
}
