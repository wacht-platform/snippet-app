import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'sink.dart';

const int _rate = 24000;
const int _ahead = 7200;
const int _slice = 4800;
const Duration _idleRelease = Duration(seconds: 30);

abstract class PcmOut {
  void write(Uint8List pcm);
  int head();
  void volume(double v);
  void close();
}

/// macOS hardware-AEC playback output (`AVAudioPlayerNode` on the shared
/// `AVAudioEngine` with `setVoiceProcessingEnabled(true)`), so macOS cancels
/// speaker output from the microphone at the OS audio-unit level.
class MacosAecOut implements PcmOut {
  MacosAecOut(this._volume) {
    _c.invokeMethod<void>('resetPlayer', {'volume': _volume}).catchError((_) {});
  }

  static const MethodChannel _c = MethodChannel('snippet/macos_aec');
  double _volume;
  int _writtenFrames = 0;
  int _playedFrames = 0;
  DateTime? _lastSyncAt;
  bool _closed = false;

  @override
  void write(Uint8List pcm) {
    if (_closed || pcm.isEmpty) return;
    final frames = pcm.length ~/ 2;
    _writtenFrames += frames;
    _lastSyncAt ??= DateTime.now();
    _c.invokeMethod<int>('writeTts', {'pcm': pcm, 'volume': _volume}).then((nativeHead) {
      if (_closed || nativeHead == null) return;
      _playedFrames = nativeHead;
      _lastSyncAt = DateTime.now();
    }).catchError((_) {});
  }

  @override
  int head() {
    if (_closed) return _playedFrames;
    final syncAt = _lastSyncAt;
    if (syncAt == null) return _playedFrames;
    final elapsedUs = DateTime.now().difference(syncAt).inMicroseconds;
    final est = _playedFrames + (elapsedUs * _rate ~/ 1000000);
    return est.clamp(0, _writtenFrames);
  }

  @override
  void volume(double v) {
    _volume = v;
    _c.invokeMethod<void>('setVolume', {'volume': v}).catchError((_) {});
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _c.invokeMethod<void>('stopTts').catchError((_) {});
  }
}

class SoloudOut implements PcmOut {
  SoloudOut(this._volume)
      : _src = SoLoud.instance.setBufferStream(
          bufferingTimeNeeds: 0.001,
          sampleRate: _rate,
          channels: Channels.mono,
          format: BufferType.s16le,
        );
  final AudioSource _src;
  double _volume;
  SoundHandle? _handle;
  int _last = 0;

  @override
  void write(Uint8List pcm) {
    SoLoud.instance.addAudioDataStream(_src, pcm);
    _handle ??= SoLoud.instance.play(_src, volume: _volume);
  }

  @override
  int head() {
    final h = _handle;
    if (h == null) return _last;
    try {
      _last = SoLoud.instance.getPosition(h).inMicroseconds * _rate ~/ 1000000;
    } catch (_) {}
    return _last;
  }

  @override
  void volume(double v) {
    _volume = v;
    final h = _handle;
    if (h == null) return;
    try {
      SoLoud.instance.setVolume(h, v);
    } catch (_) {}
  }

  @override
  void close() {
    final h = _handle;
    if (h != null) unawaited(SoLoud.instance.stop(h).catchError((_) {}));
    unawaited(SoLoud.instance.disposeSource(_src).catchError((_) {}));
  }
}

class _Chunk {
  _Chunk(this.turn, this.seq, this.pcm, this.silenceFrames, [this.stream = false]);
  final int turn, seq, silenceFrames;
  final Uint8List pcm;
  final bool stream;
}

class _Boundary {
  _Boundary(this.turn, this.seq, this.start, this.audioEnd, this.stream);
  final int turn, seq, start;
  final bool stream;
  int audioEnd;
}

class _Session {
  _Session(this.out);
  final PcmOut out;
  final Queue<_Chunk> queue = Queue();
  final List<_Boundary> written = [];
  int framesWritten = 0;
  bool stopping = false;
  Uint8List? cur;
  int curOff = 0;
  int curSilence = 0;
  DateTime? idleSince;
  Timer? timer;
}

class DesktopSink implements AmbientSink {
  DesktopSink({this.openOut});
  final PcmOut Function(double volume)? openOut;

  _Session? _sink;
  Future<_Session>? _creating;
  Map<String, dynamic> _lastPos = _idlePos();
  Map<String, dynamic> _lastStream = _idleStream();
  double _volume = 1;
  final Map<int, int> _streamBase = {};
  final Set<int> _streamStopped = {};

  static Map<String, dynamic> _idlePos() => {'seq': -1, 'played_ms': 0, 'turn': -1, 'active': 0};
  static Map<String, dynamic> _idleStream() => {'turn': -1, 'played_ms': 0, 'active': 0, 'turns': <int, int>{}};

  Future<_Session> _ensure() {
    final s = _sink;
    if (s != null) return Future.value(s);
    return _creating ??= _create().whenComplete(() => _creating = null);
  }

  Future<_Session> _create() async {
    final open = openOut;
    PcmOut out;
    if (open != null) {
      out = open(_volume);
    } else if (Platform.isMacOS) {
      out = MacosAecOut(_volume);
    } else {
      if (!SoLoud.instance.isInitialized) await SoLoud.instance.init();
      out = SoloudOut(_volume);
    }
    _lastPos = _idlePos();
    final s = _Session(out);
    s.timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _pump(s));
    _sink = s;
    return s;
  }

  int _head(_Session s) {
    final h = s.out.head();
    if (s.queue.isEmpty && s.cur == null && s.curSilence == 0 && s.framesWritten - h < 120) return s.framesWritten;
    return h;
  }

  void _pump(_Session s) {
    if (s.stopping || !identical(_sink, s)) return;
    final head = _head(s);
    while (s.framesWritten - head < _ahead) {
      final cur = s.cur;
      if (cur == null) {
        if (s.curSilence > 0) {
          final n = s.curSilence;
          s.curSilence = 0;
          s.out.write(Uint8List(n * 2));
          s.framesWritten += n;
          continue;
        }
        if (s.queue.isEmpty) break;
        final item = s.queue.removeFirst();
        if (item.stream && _streamStopped.contains(item.turn)) continue;
        final pcm = item.pcm.length.isEven ? item.pcm : Uint8List.sublistView(item.pcm, 0, item.pcm.length - 1);
        final frames = pcm.length ~/ 2;
        final last = s.written.isEmpty ? null : s.written.last;
        if (item.stream && last != null && last.stream && last.turn == item.turn && last.audioEnd == s.framesWritten) {
          last.audioEnd = s.framesWritten + frames;
        } else {
          s.written.add(_Boundary(item.turn, item.seq, s.framesWritten, s.framesWritten + frames, item.stream));
        }
        s.cur = pcm;
        s.curOff = 0;
        s.curSilence = item.silenceFrames;
        continue;
      }
      final n = (cur.length - s.curOff) < _slice * 2 ? cur.length - s.curOff : _slice * 2;
      s.out.write(Uint8List.sublistView(cur, s.curOff, s.curOff + n));
      s.curOff += n;
      s.framesWritten += n ~/ 2;
      if (s.curOff >= cur.length) s.cur = null;
    }
    if (s.queue.isEmpty && s.cur == null && s.curSilence == 0 && head >= s.framesWritten) {
      final since = s.idleSince ??= DateTime.now();
      if (DateTime.now().difference(since) >= _idleRelease) {
        _lastPos = {..._positionOf(s), 'active': 0};
        _release(s);
      }
    } else {
      s.idleSince = null;
    }
  }

  Map<String, dynamic> _positionOf(_Session s) {
    final head = _head(s);
    var lastSeq = -1, lastTurn = -1, ms = 0;
    for (final b in s.written) {
      if (b.stream) continue;
      if (head < b.start) break;
      lastTurn = b.turn;
      if (head >= b.audioEnd) {
        lastSeq = b.seq;
        ms = (b.audioEnd - b.start) * 1000 ~/ _rate;
      } else {
        lastSeq = b.seq - 1;
        ms = (head - b.start) * 1000 ~/ _rate;
      }
    }
    return {'seq': lastSeq, 'played_ms': ms, 'turn': lastTurn, 'active': 1};
  }

  Map<int, int> _streamPlayed(_Session s) {
    final head = _head(s);
    final out = <int, int>{};
    for (final b in s.written) {
      if (!b.stream) continue;
      final played = (head - b.start).clamp(0, b.audioEnd - b.start);
      out[b.turn] = (out[b.turn] ?? 0) + played;
    }
    return out;
  }

  Map<String, dynamic> _streamStats(_Session s) {
    final head = _head(s);
    var heard = -1;
    var pending = s.queue.any((c) => c.stream);
    for (final b in s.written) {
      if (!b.stream) continue;
      if (head >= b.start) heard = b.turn;
      if (head < b.audioEnd) pending = true;
    }
    final turns = <int, int>{};
    _streamBase.forEach((turn, frames) => turns[turn] = frames * 1000 ~/ _rate);
    _streamPlayed(s).forEach((turn, frames) => turns[turn] = ((_streamBase[turn] ?? 0) + frames) * 1000 ~/ _rate);
    if (heard < 0) heard = (_lastStream['turn'] as int?) ?? -1;
    return {'turn': heard, 'played_ms': turns[heard] ?? 0, 'active': pending ? 1 : 0, 'turns': turns};
  }

  void _trim() {
    final all = [..._streamBase.keys, ..._streamStopped];
    if (all.isEmpty) return;
    final newest = all.reduce((a, b) => a > b ? a : b);
    _streamBase.removeWhere((k, _) => k < newest - 50);
    _streamStopped.removeWhere((k) => k < newest - 50);
  }

  void _release(_Session s) {
    if (identical(_sink, s)) {
      _lastStream = {..._streamStats(s), 'active': 0};
      _streamPlayed(s).forEach((turn, frames) => _streamBase[turn] = (_streamBase[turn] ?? 0) + frames);
      _trim();
      _sink = null;
    }
    s.stopping = true;
    s.queue.clear();
    s.timer?.cancel();
    try {
      s.out.close();
    } catch (_) {}
  }

  Future<void> _fade(_Session s, int fadeMs) async {
    const steps = 5;
    final start = _volume;
    final each = Duration(milliseconds: (fadeMs ~/ steps).clamp(1, 1 << 30));
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(each);
      try {
        s.out.volume(start * (1 - i / steps));
      } catch (_) {
        break;
      }
    }
  }

  @override
  Future<void> warm() async {
    if (_sink == null) await _ensure();
  }

  @override
  Future<void> enqueue(int turn, int seq, Uint8List pcm, int silenceMs) async {
    final s = await _ensure();
    s.queue.add(_Chunk(turn, seq, pcm, _rate * silenceMs ~/ 1000));
  }

  @override
  Future<void> enqueueFrame(int turn, Uint8List pcm) async {
    if (pcm.length < 2) return;
    if (_streamStopped.contains(turn)) return;
    final s = await _ensure();
    if (_streamStopped.contains(turn)) return;
    s.queue.add(_Chunk(turn, -1, pcm, 0, true));
  }

  @override
  Future<Map<String, dynamic>> position() async {
    final s = _sink;
    return s == null ? _lastPos : _positionOf(s);
  }

  @override
  Future<Map<String, dynamic>> streamPosition() async {
    final s = _sink;
    return s == null ? _lastStream : _streamStats(s);
  }

  @override
  Future<Map<String, dynamic>> stopStream(int turn, {int fadeMs = 25}) async {
    if (turn != 0) {
      _streamStopped.add(turn);
    } else {
      _streamStopped.addAll(_streamBase.keys);
      final cur = _sink;
      if (cur != null) {
        for (final b in cur.written) {
          if (b.stream) _streamStopped.add(b.turn);
        }
        for (final c in cur.queue) {
          if (c.stream) _streamStopped.add(c.turn);
        }
      }
    }
    final s = _sink;
    if (s == null) return _lastStream;
    s.queue.clear();
    s.cur = null;
    s.curSilence = 0;
    await _fade(s, fadeMs);
    if (identical(_sink, s)) {
      final p = _streamStats(s);
      _lastPos = {..._positionOf(s), 'active': 0};
      _release(s);
      return {...p, 'active': 0};
    }
    return _lastStream;
  }

  @override
  Future<void> cancelAfter(int turn, int seq, {int fadeMs = 50}) async {
    final s = _sink;
    if (s == null) return;
    final keep = s.queue.where((c) => c.turn != turn || c.seq <= seq).toList();
    s.queue
      ..clear()
      ..addAll(keep);
    if (!s.written.any((b) => b.turn == turn && b.seq > seq)) return;
    unawaited(() async {
      await _fade(s, fadeMs);
      if (identical(_sink, s)) {
        _lastPos = {..._positionOf(s), 'active': 0};
        _release(s);
      }
    }());
  }

  @override
  Future<void> volume(double volume) async {
    _volume = volume;
    _sink?.out.volume(volume);
  }

  @override
  Future<Map<String, dynamic>> stop() async {
    final s = _sink;
    if (s == null) return _lastPos;
    final pos = _positionOf(s);
    _lastPos = {...pos, 'active': 0};
    _release(s);
    return pos;
  }

  @override
  Future<bool> mediaActive() async => false;
  @override
  Future<bool> inCall() async => false;
  @override
  Future<void> leave() async {}
}
