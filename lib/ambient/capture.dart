import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
  bool _duringPlayback = false;
  DateTime? _mediaAt;
  DateTime? _playbackAt;
  Timer? _mediaTimer;
  static const MethodChannel _audio = MethodChannel('snippet/ambient_audio');
  bool _ducked = false;
  DateTime? _speechSince;
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
        error: uploader.displaced.value ? null : (_error ?? uploader.lastError.value),
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
    _segmenter = SpeechSegmenter(
      threshold: threshold,
      offThreshold: threshold - 0.15,
      onSpeechStart: (startedAt) {
        final seq = uploader.reserveSequence();
        return seq;
      },
      onDiscard: (seq) {
        uploader.liveAbort(seq);
        unawaited(seq.then(uploader.skip));
      },
      onLiveStart: uploader.liveStart,
      onLiveChunk: uploader.liveChunk,
      onSegment: (segment) {
        _segments++;
        final seen = _mediaAt;
        final media = seen != null && seen.isAfter(segment.startedAt.subtract(const Duration(seconds: 1)));
        final heard = _playbackAt;
        final overlap = heard != null && heard.isAfter(segment.startedAt.subtract(const Duration(milliseconds: 1500)));
        unawaited(uploader.enqueue(segment.copyWith(duringPlayback: _duringPlayback || overlap, media: media)));
      },
    );
    final stream = await _recorder.startStream(RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.none,
        echoCancel: true,
        noiseSuppress: true,
        androidConfig: const AndroidRecordConfig(audioSource: AndroidAudioSource.voiceCommunication)));
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
    );
    voiceListenable.value = _voice;
    _mediaTimer?.cancel();
    _mediaTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_voice?.speaking.value == true) return;
      try {
        if (await _audio.invokeMethod<bool>('mediaActive') == true) _mediaAt = DateTime.now();
      } catch (_) {}
    });
    unawaited(_voice!.start());
    _status.add(current);
  }

  void _onAudio(Uint8List bytes) {
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
      _handleBargeIn(segmenter.speaking);
      offset += chunkBytes;
    }
    if (offset < buffer.length) {
      _pending.add(Uint8List.sublistView(buffer, offset));
    }
  }

  void _handleBargeIn(bool voiceActive) {
    final voice = _voice;
    if (voice != null && voice.speaking.value) _playbackAt = DateTime.now();
    if (voice == null || !voice.speaking.value) {
      _speechSince = null;
      _duringPlayback = false;
      if (_ducked && voice != null) { _ducked = false; unawaited(voice.duck(false)); }
      return;
    }
    if (!voiceActive) {
      _speechSince = null;
      if (_ducked) { _ducked = false; unawaited(voice.duck(false)); }
      _duringPlayback = false;
      return;
    }
    _duringPlayback = true;
    if (_probability < 0.9) {
      _speechSince = null;
      return;
    }
    final since = _speechSince ??= DateTime.now();
    final elapsed = DateTime.now().difference(since);
    if (elapsed >= const Duration(milliseconds: 450) && !_ducked) { _ducked = true; unawaited(voice.duck(true)); }
    if (elapsed >= const Duration(milliseconds: 900)) { _speechSince = null; unawaited(voice.stopNow()); }
  }

  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _ticker?.cancel();
    _mediaTimer?.cancel();
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
    voiceListenable.value = null;
    voiceListenable.dispose();
    await stop();
    uploader.close();
    await _recorder.dispose();
    await _status.close();
  }
}
