import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sink_desktop.dart';

abstract class AmbientSink {
  factory AmbientSink() {
    if (kIsWeb) return _NullSink();
    if (Platform.isAndroid) return _ChannelSink();
    return DesktopSink();
  }

  Future<void> warm();
  Future<void> enqueue(int turn, int seq, Uint8List pcm, int silenceMs);
  Future<void> enqueueFrame(int turn, Uint8List pcm);
  Future<Map<String, dynamic>> position();
  Future<Map<String, dynamic>> streamPosition();
  Future<Map<String, dynamic>> stopStream(int turn, {int fadeMs = 25});
  Future<void> cancelAfter(int turn, int seq, {int fadeMs = 50});
  Future<void> volume(double volume);
  Future<Map<String, dynamic>> stop();
  Future<bool> mediaActive();
  Future<bool> inCall();
  Future<void> leave();
}

class _ChannelSink implements AmbientSink {
  static const MethodChannel _c = MethodChannel('snippet/ambient_audio');

  Future<Map<String, dynamic>> _map(String m, [Object? args]) async =>
      await _c.invokeMapMethod<String, dynamic>(m, args) ?? const {};

  @override
  Future<void> warm() => _c.invokeMethod('warm');
  @override
  Future<void> enqueue(int turn, int seq, Uint8List pcm, int silenceMs) =>
      _c.invokeMethod('enqueue', {'turn': turn, 'seq': seq, 'pcm': pcm, 'silenceMs': silenceMs});
  @override
  Future<void> enqueueFrame(int turn, Uint8List pcm) => _c.invokeMethod('enqueueFrame', {'turn': turn, 'pcm': pcm});
  @override
  Future<Map<String, dynamic>> position() => _map('position');
  @override
  Future<Map<String, dynamic>> streamPosition() => _map('streamPosition');
  @override
  Future<Map<String, dynamic>> stopStream(int turn, {int fadeMs = 25}) => _map('stopStream', {'turn': turn, 'fadeMs': fadeMs});
  @override
  Future<void> cancelAfter(int turn, int seq, {int fadeMs = 50}) =>
      _c.invokeMethod('cancelAfter', {'turn': turn, 'seq': seq, 'fadeMs': fadeMs});
  @override
  Future<void> volume(double volume) => _c.invokeMethod('volume', {'volume': volume});
  @override
  Future<Map<String, dynamic>> stop() => _map('stop');
  @override
  Future<bool> mediaActive() async => await _c.invokeMethod<bool>('mediaActive') == true;
  @override
  Future<bool> inCall() async => await _c.invokeMethod<bool>('inCall') == true;
  @override
  Future<void> leave() => _c.invokeMethod('leave');
}

class _NullSink implements AmbientSink {
  static const Map<String, dynamic> _pos = {'seq': -1, 'played_ms': 0, 'turn': -1, 'active': 0};
  static const Map<String, dynamic> _stream = {'turn': -1, 'played_ms': 0, 'active': 0, 'turns': <int, int>{}};

  @override
  Future<void> warm() async {}
  @override
  Future<void> enqueue(int turn, int seq, Uint8List pcm, int silenceMs) async {}
  @override
  Future<void> enqueueFrame(int turn, Uint8List pcm) async {}
  @override
  Future<Map<String, dynamic>> position() async => _pos;
  @override
  Future<Map<String, dynamic>> streamPosition() async => _stream;
  @override
  Future<Map<String, dynamic>> stopStream(int turn, {int fadeMs = 25}) async => _stream;
  @override
  Future<void> cancelAfter(int turn, int seq, {int fadeMs = 50}) async {}
  @override
  Future<void> volume(double volume) async {}
  @override
  Future<Map<String, dynamic>> stop() async => _pos;
  @override
  Future<bool> mediaActive() async => false;
  @override
  Future<bool> inCall() async => false;
  @override
  Future<void> leave() async {}
}
