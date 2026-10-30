import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:silero_vad/silero_vad.dart';

import '../platform.dart';
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
  SpeechGate? _gate;
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  bool _running = false;
  bool _mediaOn = false;
  bool _playOn = false;
  Timer? _pollTimer;
  bool _polling = false;
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
        speaking: (defaultTargetPlatform == TargetPlatform.android ||
                defaultTargetPlatform == TargetPlatform.macOS)
            ? (_gate?.speaking ?? false)
            : (_playOn ? _ducked : (_gate?.speaking ?? false)),
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
    uploader.displaced.addListener(_onDisplaced);
    await uploader.start();
    await AmbientDiagnostics.log('loading detector');
    _vad = SileroVad();
    await AmbientDiagnostics.log('detector loaded, opening microphone');
    _gate = SpeechGate(
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
    Stream<Uint8List> stream;
    if (kMacOS) {
      stream = const EventChannel('snippet/macos_aec_mic')
          .receiveBroadcastStream()
          .where((event) => event is Uint8List)
          .cast<Uint8List>();
    } else {
      stream = await _recorder.startStream(RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          audioInterruption: AudioInterruptionMode.none,
          echoCancel: true,
          noiseSuppress: true,
          androidConfig: const AndroidRecordConfig(
              audioSource: AndroidAudioSource.voiceCommunication)));
    }
    _running = true;
    _error = null;
    _sub = stream.listen(_onAudio, onError: (Object e) {
      _error = AmbientDiagnostics.redact('$e');
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
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        const Duration(milliseconds: 500), (_) => _pollAudioState());
    unawaited(_voice!.start());
    _status.add(current);
  }

  void _onDisplaced() {
    if (uploader.displaced.value) unawaited(stop());
  }

  Future<void> _pollAudioState() async {
    if (_polling) return;
    _polling = true;
    try {
      if (_voice?.speaking.value != true) {
        final media = await _audio.mediaActive();
        if (media != _mediaOn) {
          _mediaOn = media;
          uploader.flag('media', media);
        }
      }
      final call = await _audio.inCall();
      if (call != _callOn) {
        _callOn = call;
        unawaited(AmbientDiagnostics.log(call
            ? 'call started: listening paused'
            : 'call ended: listening resumed'));
      }
    } catch (_) {
    } finally {
      _polling = false;
    }
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
    final gate = _gate;
    if (vad == null || gate == null) return;
    if (AmbientHold.active || _callOn) {
      _heldBytes += bytes.length;
      gate.abandon();
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
            'The microphone is only sending silence. Check the input device and that microphone access is allowed for this app.';
        unawaited(AmbientDiagnostics.log('microphone silent for 3s'));
      } else if (_silentFrames == 0 &&
          _error != null &&
          _error!.startsWith('The microphone is only sending silence')) {
        _error = null;
      }
      final rms = energy / samples.length;
      if (rms > 0.0004 && _probability < 0.3) _loudQuiet++;
      gate.addFrame(frame, _probability);
      final voiced = _probability >= threshold;
      if (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        _duckCheck(voiced);
      } else if (_playOn) {
        if (_echoRms == 0) {
          _echoRms = rms > 0.0002 ? rms : 0.0008;
        } else if (!voiced || rms <= _echoRms * 2.2) {
          _echoRms = _echoRms * 0.90 + rms * 0.10;
        }
        final bargeVoiced = voiced && rms > _echoRms * 2.8 && rms > 0.003;
        _duckCheck(bargeVoiced);
      } else {
        _echoRms = 0;
        _duckCheck(false);
      }
      offset += chunkBytes;
    }
    if (offset < buffer.length) {
      _pending.add(Uint8List.sublistView(buffer, offset));
    }
  }

  void _onAmbientState() {
    _gate?.keepOpen = _voice?.state.value?.mode == 'active';
  }

  int _loud = 0;
  double _echoRms = 0;
  bool _ducked = false;
  Timer? _unduck;

  void _duckCheck(bool voiced) {
    final voice = _voice;
    if (voice == null || !voice.speaking.value) {
      _loud = 0;
      return;
    }
    _loud = voiced ? _loud + 1 : 0;
    if (_loud >= 3) {
      if (!_ducked) {
        _ducked = true;
        unawaited(voice.duck(true));
      }
      _unduck?.cancel();
      _unduck = Timer(const Duration(milliseconds: 700), _restoreVolume);
    }
    unawaited(voice.localSpeech(voiced,
        canPause: defaultTargetPlatform == TargetPlatform.macOS && _loud >= 5));
  }

  void _restoreVolume() {
    _unduck?.cancel();
    if (!_ducked) return;
    _ducked = false;
    unawaited(_voice?.duck(false));
  }

  void _onSpeaking() {
    final on = _voice?.speaking.value ?? false;
    if (!on) {
      _echoRms = 0;
      _restoreVolume();
    }
    if (on == _playOn) return;
    _playOn = on;
    uploader.flag('play', on);
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    _pollTimer?.cancel();
    uploader.displaced.removeListener(_onDisplaced);
    _callOn = false;
    _statTimer?.cancel();
    await _sub?.cancel();
    if (!kMacOS) {
      await _recorder.stop();
    }
    _gate?.close();
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
