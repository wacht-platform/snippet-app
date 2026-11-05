import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:record/record.dart';

import '../platform.dart';
import 'macos_mic.dart';
import 'wav.dart';

/// macOS notes are WAV: they come from the shared mic stream, not a file encoder.
String get voiceNoteExtension => kMacOS ? 'wav' : 'm4a';

class AmbientHold {
  static int _count = 0;
  static DateTime? _remoteUntil;

  static bool get local => _count > 0;

  static bool get active {
    if (_count > 0) return true;
    final until = _remoteUntil;
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _remoteUntil = null;
      return false;
    }
    return true;
  }

  static void _add() {
    _count++;
    if (_count == 1) _publish(true);
  }

  static void _drop() {
    if (_count == 0) return;
    _count--;
    if (_count == 0) _publish(false);
  }

  static void publishCurrent() => _publish(local);

  static void _publish(bool on) {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      FlutterForegroundTask.sendDataToTask({'ambient_hold': on});
    } catch (_) {}
  }

  static bool receive(Object data) {
    if (data is! Map || !data.containsKey('ambient_hold')) return false;
    _remoteUntil = data['ambient_hold'] == true
        ? DateTime.now().add(const Duration(minutes: 15))
        : null;
    return true;
  }
}

class HeldRecorder extends AudioRecorder {
  bool _held = false;
  StreamSubscription<Uint8List>? _micSub;
  BytesBuilder? _pcm;
  String? _micPath;
  Object? _micError;
  int _micPeak = 0;
  double _micLevel = -160;

  void _on() {
    if (_held) return;
    _held = true;
    AmbientHold._add();
  }

  void _off() {
    if (!_held) return;
    _held = false;
    AmbientHold._drop();
  }

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    _on();
    if (kMacOS) {
      // AVCaptureAudioFileOutput can yield no file beside ambient's
      // voice-processing engine, and it drops its errors.
      await _closeMic();
      _pcm = BytesBuilder(copy: false);
      _micPath = path;
      _micError = null;
      _micPeak = 0;
      _micLevel = -160;
      _micSub = MacosMic.stream
          .listen(_onMic, onError: (Object e) => _micError = e);
      return;
    }
    try {
      await super.start(config, path: path);
    } catch (_) {
      _off();
      rethrow;
    }
  }

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    _on();
    try {
      return await super.startStream(config);
    } catch (_) {
      _off();
      rethrow;
    }
  }

  @override
  Future<String?> stop() async {
    if (kMacOS) return _stopMic();
    try {
      return await super.stop();
    } finally {
      _off();
    }
  }

  @override
  Future<void> cancel() async {
    if (kMacOS) {
      await _closeMic();
      _off();
      return;
    }
    try {
      await super.cancel();
    } finally {
      _off();
    }
  }

  @override
  Future<void> dispose() async {
    await _closeMic();
    try {
      await super.dispose();
    } finally {
      _off();
    }
  }

  @override
  Future<bool> isRecording() async =>
      kMacOS ? _micSub != null : await super.isRecording();

  @override
  Stream<Amplitude> onAmplitudeChanged(Duration interval) => kMacOS
      ? Stream.periodic(
          interval, (_) => Amplitude(current: _micLevel, max: _micLevel))
      : super.onAmplitudeChanged(interval);

  void _onMic(Uint8List chunk) {
    _pcm?.add(chunk);
    final data = ByteData.sublistView(chunk);
    final samples = data.lengthInBytes ~/ 2;
    if (samples == 0) return;
    var energy = 0.0;
    for (var i = 0; i < samples; i++) {
      final s = data.getInt16(i * 2, Endian.little);
      energy += s * s;
      if (s.abs() > _micPeak) _micPeak = s.abs();
    }
    final rms = math.sqrt(energy / samples) / 32768;
    _micLevel = rms <= 0 ? -160 : 20 * math.log(rms) / math.ln10;
  }

  Future<String?> _stopMic() async {
    final path = _micPath;
    final pcm = _pcm?.takeBytes();
    final error = _micError;
    final peak = _micPeak;
    await _closeMic();
    _off();
    if (path == null) return null;
    if (error != null) throw error;
    if (pcm == null || pcm.isEmpty || peak == 0) {
      throw 'the microphone sent no audio. Check the input device and '
          'microphone access in System Settings.';
    }
    await File(path).writeAsBytes(pcm16ToWav(pcm), flush: true);
    return path;
  }

  Future<void> _closeMic() async {
    final sub = _micSub;
    _micSub = null;
    _pcm = null;
    _micPath = null;
    await sub?.cancel();
  }
}
