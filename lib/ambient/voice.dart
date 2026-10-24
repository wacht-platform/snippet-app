import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'diagnostics.dart';

class AmbientStateEvent {
  const AmbientStateEvent({required this.mode, required this.sub, this.reason});
  final String mode;
  final String sub;
  final String? reason;
}

class AmbientVoice {
  AmbientVoice({required this.baseUrl, required this.token, required this.device});
  final String baseUrl;
  final String token;
  final String device;
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  final ValueNotifier<AmbientStateEvent?> state = ValueNotifier(null);
  static const MethodChannel _sink = MethodChannel('snippet/ambient_audio');

  final Map<int, Map<int, Map<String, dynamic>>> _chunks = {};
  final Set<int> _ended = {};
  final Set<int> _barged = {};
  final Set<int> _finished = {};
  final Map<int, Set<int>> _consumed = {};
  final Map<int, int> _cancelAfter = {};
  final http.Client _client = http.Client();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _poll;
  bool _closed = false, _running = false;
  int _gen = 0, _failures = 0, _last = 0;
  int? _playingTurn;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse(baseUrl).replace(path: path, queryParameters: {'token': token, ...?query});
  bool _dead(int turn) => _finished.contains(turn) || _barged.contains(turn);
  int _duration(Uint8List pcm) => pcm.length * 1000 ~/ 48000;

  Future<void> start() async {
    _poll = Timer.periodic(const Duration(milliseconds: 2000), (_) => _catchUp());
    _connect();
  }

  void _connect() {
    if (_closed) return;
    final base = Uri.parse(baseUrl);
    final u = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/events', queryParameters: {'token': token});
    try {
      final c = WebSocketChannel.connect(u);
      _channel = c;
      _sub = c.stream.listen(_frame, onError: (_) => _reconnect(), onDone: _reconnect);
      _failures = 0;
      _catchUp();
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_closed || _retry?.isActive == true) return;
    _sub?.cancel();
    _retry = Timer(Duration(milliseconds: (500 * (1 << _failures.clamp(0, 5))).clamp(500, 15000)), () {
      _failures++;
      _connect();
    });
  }

  void _frame(dynamic raw) {
    try {
      final f = jsonDecode(raw as String) as Map<String, dynamic>;
      if (f['device'] != device) return;
      final turn = f['turn'] as int?;
      switch (f['kind']) {
        case 'ambient_state':
          state.value = AmbientStateEvent(mode: f['mode'] as String? ?? '', sub: f['sub'] as String? ?? '', reason: f['reason'] as String?);
        case 'ambient_speech_start':
          if (turn != null && !_dead(turn)) {
            unawaited(_sink.invokeMethod('warm').catchError((_) {}));
            _chunks.putIfAbsent(turn, () => {});
            _play();
          }
        case 'ambient_speech_chunk':
          if (turn != null && !_dead(turn)) {
            final seq = f['seq'] as int;
            if (_consumed[turn]?.contains(seq) != true) _chunks.putIfAbsent(turn, () => {})[seq] = f;
            _play();
          }
        case 'ambient_speech_end':
          if (turn != null && !_dead(turn)) {
            _ended.add(turn);
            _play();
          }
        case 'ambient_speech_cancel':
          if (turn != null) _cancel(turn, f['after_seq'] as int? ?? -1);
      }
    } catch (e) {
      AmbientDiagnostics.log('voice: bad frame $e');
    }
  }

  Future<void> _catchUp() async {
    try {
      final floor = _chunks.isEmpty ? _last : (_chunks.keys.reduce(min) - 1);
      final r = await _client.get(_uri('/ambient/turns', {'after': '$floor', 'device': device}));
      if (r.statusCode != 200) return;
      for (final t in (jsonDecode(r.body)['turns'] as List)) {
        final id = t['id'] as int;
        _last = max(_last, id);
        if (_dead(id)) continue;
        final map = _chunks.putIfAbsent(id, () => {});
        for (final c in (t['chunks'] as List? ?? [])) {
          final m = Map<String, dynamic>.from(c as Map);
          final seq = m['seq'] as int;
          if (_consumed[id]?.contains(seq) == true) continue;
          map[seq] = m;
        }
        if (t['ended'] == true) _ended.add(id);
      }
      _play();
    } catch (_) {}
  }

  Future<void> _play() async {
    if (_running || _closed) return;
    _running = true;
    speaking.value = _chunks.isNotEmpty;
    try {
      while (!_closed && _chunks.isNotEmpty) {
        final turn = _chunks.keys.reduce(min);
        if (_dead(turn)) {
          _finish(turn);
          continue;
        }
        _playingTurn = turn;
        try {
          await _playTurn(turn);
        } catch (e) {
          AmbientDiagnostics.log('voice: turn $turn failed: $e');
          _finish(turn);
        }
        _playingTurn = null;
        if (_chunks.containsKey(turn) && !_dead(turn)) await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    } finally {
      _running = false;
      _playingTurn = null;
      speaking.value = _chunks.isNotEmpty;
    }
  }

  Future<void> _playTurn(int turn) async {
    final gen = _gen;
    var queuedMax = -1;
    var enqueuedMax = -1;
    var ackedMax = -1;
    final queuedMs = <int, int>{};
    var lastProgress = DateTime.now();
    DateTime? gapSince;
    bool stale() => _closed || gen != _gen || _dead(turn);

    while (!stale()) {
      final map = _chunks[turn];
      if (map == null) return;
      final cutoff = _cancelAfter[turn];
      if (cutoff != null) {
        map.removeWhere((s, _) => s > cutoff);
        if (queuedMax > cutoff) queuedMax = cutoff;
        if (enqueuedMax > cutoff) enqueuedMax = cutoff;
        queuedMs.removeWhere((sq, _) => sq > cutoff);
        _ended.add(turn);
      }
      final next = map.keys.where((s) => s > queuedMax).toList()..sort();
      if (next.isNotEmpty) {
        final seq = next.first;
        final gapExpired = gapSince != null && DateTime.now().difference(gapSince) > const Duration(seconds: 2);
        if (seq == queuedMax + 1 || gapExpired) {
          gapSince = null;
          final pcm = await _fetch(turn, seq);
          if (stale()) return;
          map.remove(seq);
          _consumed.putIfAbsent(turn, () => {}).add(seq);
          if (pcm == null) {
            AmbientDiagnostics.log('voice: chunk $turn/$seq unavailable');
            queuedMax = seq;
            continue;
          }
          if (seq > (_cancelAfter[turn] ?? 1 << 30)) continue;
          await _sink.invokeMethod('enqueue', {'turn': turn, 'seq': seq, 'pcm': pcm, 'silenceMs': 80});
          queuedMax = seq;
          enqueuedMax = seq;
          queuedMs[seq] = _duration(pcm);
          lastProgress = DateTime.now();
          AmbientDiagnostics.log('voice: enqueued $turn/$seq ${pcm.length}B');
          continue;
        }
        gapSince ??= DateTime.now();
      }

      final pos = await _position();
      if (stale()) return;
      final posTurn = pos['turn'] as int? ?? -1;
      final playedSeq = posTurn == turn ? (pos['seq'] as int? ?? -1) : (posTurn > turn ? enqueuedMax : -1);
      final idle = posTurn == turn && pos['active'] == 0;
      while (ackedMax < playedSeq && ackedMax < enqueuedMax) {
        ackedMax++;
        final ms = queuedMs[ackedMax];
        if (ms != null) await _played(turn, ackedMax, ms, false);
        lastProgress = DateTime.now();
      }
      final done = map.isEmpty && _ended.contains(turn);
      if (done && (enqueuedMax < 0 || playedSeq >= enqueuedMax || idle)) {
        if (enqueuedMax >= 0) await _played(turn, max(ackedMax, min(playedSeq, enqueuedMax)), pos['played_ms'] as int? ?? queuedMs[enqueuedMax] ?? 0, true);
        _finish(turn);
        return;
      }
      if (map.isEmpty && !_ended.contains(turn) && playedSeq >= enqueuedMax && _chunks.entries.any((e) => e.key > turn && e.value.isNotEmpty)) {
        AmbientDiagnostics.log('voice: dropping unfinished turn $turn');
        _finish(turn);
        return;
      }
      var remaining = 0;
      queuedMs.forEach((s, ms) {
        if (s > playedSeq) remaining += ms;
      });
      if (DateTime.now().difference(lastProgress) > Duration(milliseconds: remaining + 6000)) {
        AmbientDiagnostics.log('voice: turn $turn stalled');
        await _played(turn, max(ackedMax, -1), 0, true);
        _finish(turn);
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  void _finish(int turn) {
    _chunks.remove(turn);
    _finished.add(turn);
    final old = turn - 100;
    _finished.removeWhere((t) => t < old);
    _ended.removeWhere((t) => t < old);
    _barged.removeWhere((t) => t < old);
    _consumed.removeWhere((t, _) => t < old);
    _cancelAfter.removeWhere((t, _) => t < old);
  }

  Future<Map<String, dynamic>> _position() async {
    try {
      return await _sink.invokeMapMethod<String, dynamic>('position') ?? const {};
    } catch (e) {
      AmbientDiagnostics.log('voice: position failed $e');
      return const {};
    }
  }

  Future<Uint8List?> _fetch(int turn, int seq) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (_closed || _dead(turn)) return null;
      try {
        final r = await _client.get(_uri('/ambient/turns/$turn/chunks/$seq'));
        if (r.statusCode == 200) return r.bodyBytes;
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _played(int id, int seq, int ms, bool complete) async {
    try {
      await _client.post(_uri('/ambient/turns/played'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'id': id, 'seq': seq, 'played_ms': ms, 'complete': complete}));
    } catch (e) {
      AmbientDiagnostics.log('voice: played ack failed $e');
    }
  }

  Future<void> _postBarge(int turn, int seq, int ms) async {
    try {
      await _client.post(_uri('/ambient/barge'),
          headers: {'content-type': 'application/json'}, body: jsonEncode({'turn': turn, 'seq': seq, 'played_ms': ms}));
    } catch (e) {
      AmbientDiagnostics.log('voice: barge post failed $e');
    }
  }

  Future<void> _cancel(int turn, int after) async {
    if (_dead(turn)) return;
    if (!_chunks.containsKey(turn)) {
      _finished.add(turn);
      return;
    }
    _cancelAfter[turn] = after;
    _chunks[turn]?.removeWhere((seq, _) => seq > after);
    _ended.add(turn);
    try {
      final pos = await _position();
      if ((pos['turn'] as int? ?? -1) == turn && (pos['seq'] as int? ?? -1) > after) {
        await _postBarge(turn, pos['seq'] as int, pos['played_ms'] as int? ?? 0);
      }
      await _sink.invokeMethod('cancelAfter', {'turn': turn, 'seq': after, 'fadeMs': 50});
    } catch (e) {
      AmbientDiagnostics.log('voice: cancel failed $e');
    }
    _play();
  }

  Future<void> duck(bool on) async {
    try {
      await _sink.invokeMethod('volume', {'volume': on ? 0.0 : 1.0});
    } catch (_) {}
  }

  Future<void> stopNow() async {
    final turn = _playingTurn ?? (_chunks.isEmpty ? null : _chunks.keys.reduce(min));
    _gen++;
    if (turn != null) _barged.add(turn);
    Map<String, dynamic>? pos;
    try {
      pos = await _sink.invokeMapMethod<String, dynamic>('stop');
    } catch (e) {
      AmbientDiagnostics.log('voice: stop failed $e');
    }
    if (turn != null) {
      final same = (pos?['turn'] as int? ?? -1) == turn;
      _finish(turn);
      await _postBarge(turn, same ? (pos?['seq'] as int? ?? -1) : -1, same ? (pos?['played_ms'] as int? ?? 0) : 0);
    }
    speaking.value = _chunks.isNotEmpty;
  }

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    _poll?.cancel();
    _client.close();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _sink.invokeMethod('stop').catchError((_) {});
    speaking.dispose();
    state.dispose();
  }
}
