import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'diagnostics.dart';
import 'stream.dart';

class AmbientStateEvent {
  const AmbientStateEvent({required this.mode, required this.sub, this.reason});
  final String mode;
  final String sub;
  final String? reason;
}

class _StreamTurn {
  int bytes = 0;
  bool ended = false;
  int? carry;
  int lastPlayed = -1;
  DateTime lastFrame = DateTime.now();
  DateTime lastProgress = DateTime.now();
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
  final Map<(int, int), Future<Uint8List?>> _inflight = {};
  final Map<int, Completer<void>> _wake = {};
  final http.Client _client = http.Client();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _poll;
  bool _closed = false, _running = false;
  int _gen = 0, _failures = 0, _last = 0;
  int? _playingTurn;
  AmbientStream? _duplex;
  final Map<int, _StreamTurn> _streams = {};
  final Set<int> _streamIds = {};
  final Set<int> _streamDead = {};
  Timer? _streamTick;
  bool _ticking = false;
  final Map<int, BytesBuilder> _streamBatch = {};
  final Map<int, int> _streamBatchBytes = {};
  Timer? _streamFlush;

  bool get _busy => _chunks.isNotEmpty || _streams.isNotEmpty;

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
        case 'ambient_speech_start' || 'ambient_speech_chunk' || 'ambient_speech_end' when turn != null && (f['stream'] == true || _streamIds.contains(turn)):
          _streamIds.add(turn);
          _chunks.remove(turn);
        case 'ambient_speech_cancel' when turn != null && _streamIds.contains(turn):
          unawaited(stopStream(turn));
        case 'ambient_speech_start':
          if (turn != null && !_dead(turn)) {
            unawaited(_sink.invokeMethod('warm').catchError((_) {}));
            _chunks.putIfAbsent(turn, () => {});
            _prefetch(turn, 0);
            _play();
          }
        case 'ambient_speech_chunk':
          if (turn != null && !_dead(turn)) {
            final seq = f['seq'] as int;
            if (_consumed[turn]?.contains(seq) != true) _chunks.putIfAbsent(turn, () => {})[seq] = f;
            _wakeTurn(turn);
            _play();
          }
        case 'ambient_speech_end':
          if (turn != null && !_dead(turn)) {
            _ended.add(turn);
            _wakeTurn(turn);
            _play();
          }
        case 'ambient_speech_interrupt':
          unawaited(_interruptAll());
        case 'ambient_speech_cancel':
          if (turn != null) {
            _wakeTurn(turn);
            _cancel(turn, f['after_seq'] as int? ?? -1);
          }
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
        if (_dead(id) || t['stream'] == true || _streamIds.contains(id)) continue;
        final map = _chunks.putIfAbsent(id, () => {});
        for (final c in (t['chunks'] as List? ?? [])) {
          final m = Map<String, dynamic>.from(c as Map);
          final seq = m['seq'] as int;
          if (_consumed[id]?.contains(seq) == true) continue;
          map[seq] = m;
        }
        if (t['ended'] == true) _ended.add(id);
        _wakeTurn(id);
      }
      _play();
    } catch (_) {}
  }

  Future<void> _play() async {
    if (_running || _closed) return;
    _running = true;
    speaking.value = _busy;
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
      speaking.value = _busy;
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
          final tail = ((map[seq]?['text'] as String?) ?? '').trimRight();
          map.remove(seq);
          _consumed.putIfAbsent(turn, () => {}).add(seq);
          if (pcm == null) {
            AmbientDiagnostics.log('voice: chunk $turn/$seq unavailable');
            queuedMax = seq;
            continue;
          }
          if (seq > (_cancelAfter[turn] ?? 1 << 30)) continue;
          await _sink.invokeMethod('enqueue', {'turn': turn, 'seq': seq, 'pcm': pcm, 'silenceMs': tail.isEmpty ? 80 : (RegExp(r'[.!?]["\x27)]*$').hasMatch(tail) ? 80 : RegExp(r'[,;:\u2014]$').hasMatch(tail) ? 40 : 0)});
          queuedMax = seq;
          enqueuedMax = seq;
          queuedMs[seq] = _duration(pcm);
          _prefetch(turn, seq + 1);
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
      await _wait(turn);
    }
  }

  void _finish(int turn) {
    _wake.remove(turn)?.complete();
    _inflight.removeWhere((k, _) => k.$1 == turn);
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

  Future<void> _wait(int turn) =>
      _wake.putIfAbsent(turn, () => Completer<void>()).future.timeout(const Duration(milliseconds: 30), onTimeout: () {});

  void _wakeTurn(int turn) => _wake.remove(turn)?.complete();

  void _prefetch(int turn, int seq) {
    if (_dead(turn)) return;
    final cutoff = _cancelAfter[turn];
    if (cutoff != null && seq > cutoff) return;
    _inflight.putIfAbsent((turn, seq), () => _fetchLoop(turn, seq));
  }

  Future<Uint8List?> _fetch(int turn, int seq) async {
    final pending = _inflight.remove((turn, seq));
    if (pending != null) {
      final bytes = await pending;
      if (bytes != null) return bytes;
    }
    return _fetchLoop(turn, seq);
  }

  Future<Uint8List?> _fetchLoop(int turn, int seq) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      if (_closed || _dead(turn)) return null;
      if (_ended.contains(turn) && _chunks[turn]?.containsKey(seq) != true) return null;
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

  void attach(AmbientStream duplex) {
    _duplex = duplex;
    duplex.onTtsFrame = _onStreamFrame;
    duplex.onTts = _onStreamMessage;
    duplex.onConnection = (_) => _streamChanged();
  }

  void _onStreamMessage(Map<String, dynamic> msg) {
    final turn = (msg['turn'] as num?)?.toInt() ?? 0;
    switch (msg['t']) {
      case 'tts_start':
        if (turn <= 0 || _streamDead.contains(turn)) return;
        _adoptStream(turn);
        unawaited(_sink.invokeMethod('warm').catchError((_) {}));
        _streamChanged();
      case 'tts_end':
        if (turn <= 0 || _streamDead.contains(turn)) return;
        _adoptStream(turn).ended = true;
        _streamChanged();
      case 'tts_stop':
        unawaited(stopStream(turn));
    }
  }

  _StreamTurn _adoptStream(int turn) {
    _streamIds.add(turn);
    if (_chunks.remove(turn) != null) _finished.add(turn);
    return _streams.putIfAbsent(turn, _StreamTurn.new);
  }

  void _onStreamFrame(int turn, Uint8List pcm) {
    if (_closed || turn <= 0 || _streamDead.contains(turn)) return;
    final fresh = !_streams.containsKey(turn);
    final st = _adoptStream(turn);
    if (fresh) _streamChanged();
    var data = pcm;
    final carry = st.carry;
    if (carry != null) {
      data = Uint8List(pcm.length + 1)
        ..[0] = carry
        ..setRange(1, pcm.length + 1, pcm);
      st.carry = null;
    }
    if (data.length.isOdd) {
      st.carry = data.last;
      data = Uint8List.sublistView(data, 0, data.length - 1);
    }
    if (data.isEmpty) return;
    st.bytes += data.length;
    st.lastFrame = DateTime.now();
    final batch = _streamBatch.putIfAbsent(turn, () => BytesBuilder(copy: false));
    batch.add(data);
    final queued = (_streamBatchBytes[turn] ?? 0) + data.length;
    _streamBatchBytes[turn] = queued;
    if (queued >= 4800) {
      _flushStreamFrames();
    } else {
      _streamFlush ??= Timer(const Duration(milliseconds: 100), _flushStreamFrames);
    }
  }

  void _flushStreamFrames() {
    _streamFlush?.cancel();
    _streamFlush = null;
    for (final turn in _streamBatch.keys.toList()) {
      final data = _streamBatch.remove(turn)!.takeBytes();
      _streamBatchBytes.remove(turn);
      if (data.isEmpty) continue;
      unawaited(_sink.invokeMethod('enqueueFrame', {'turn': turn, 'pcm': data}).catchError((Object e) {
        AmbientDiagnostics.log('voice: stream frame failed $e');
      }));
    }
  }

  void _streamChanged() {
    speaking.value = _busy;
    if (_streams.isEmpty) {
      _streamTick?.cancel();
    _streamFlush?.cancel();
    _flushStreamFrames();
      _streamTick = null;
    } else {
      _streamTick ??= Timer.periodic(const Duration(milliseconds: 500), (_) => _tickStream());
    }
  }

  Map<int, int> _playedMap(Map<String, dynamic> pos) => {
        for (final e in ((pos['turns'] as Map?) ?? const {}).entries) (e.key as num).toInt(): (e.value as num).toInt(),
      };

  Future<void> _tickStream() async {
    if (_ticking || _closed) return;
    _ticking = true;
    try {
      Map<String, dynamic> pos = const {};
      try {
        pos = await _sink.invokeMapMethod<String, dynamic>('streamPosition') ?? const {};
      } catch (e) {
        AmbientDiagnostics.log('voice: stream position failed $e');
      }
      final played = _playedMap(pos);
      final heard = pos['turn'] as int? ?? -1;
      final active = pos['active'] == 1;
      final now = DateTime.now();
      final quietLimit = (_duplex?.open ?? false) ? const Duration(seconds: 8) : const Duration(seconds: 3);
      for (final e in _streams.entries.toList()) {
        final turn = e.key, st = e.value;
        if (!identical(_streams[turn], st)) continue;
        final ms = played[turn] ?? 0;
        if (ms != st.lastPlayed) {
          st.lastPlayed = ms;
          st.lastProgress = now;
        }
        final total = st.bytes ~/ 48;
        final caughtUp = ms >= total - 5;
        if (st.ended && (caughtUp || (!active && now.difference(st.lastProgress) > const Duration(milliseconds: 1500)))) {
          _duplex?.ttsPos(turn, caughtUp ? total : ms, true);
          _endStream(turn);
          continue;
        }
        if (!st.ended && caughtUp && !(active && heard == turn) && now.difference(st.lastFrame) > quietLimit) {
          AmbientDiagnostics.log('voice: stream turn $turn stalled at ${ms}ms');
          _duplex?.ttsPos(turn, ms, false);
          _endStream(turn);
          continue;
        }
        if (turn == heard && active) _duplex?.ttsPos(turn, ms, false);
      }
    } finally {
      _ticking = false;
    }
    _streamChanged();
  }

  void _endStream(int turn) {
    _streams.remove(turn);
    _streamDead.add(turn);
    _streamDead.removeWhere((t) => t < turn - 100);
    _streamIds.removeWhere((t) => t < turn - 100);
  }

  Future<void> stopStream([int turn = 0]) async {
    final stopped = turn == 0 ? _streams.keys.toList() : [turn];
    for (final t in stopped) {
      _streamIds.add(t);
      _endStream(t);
    }
    _streamChanged();
    Map<String, dynamic> pos = const {};
    try {
      pos = await _sink.invokeMapMethod<String, dynamic>('stopStream', {'turn': turn, 'fadeMs': 25}) ?? const {};
    } catch (e) {
      AmbientDiagnostics.log('voice: stream stop failed $e');
    }
    final played = _playedMap(pos);
    for (final t in stopped) {
      _duplex?.ttsPos(t, played[t] ?? 0, false);
    }
  }

  Future<void> duck(bool on) async {
    try {
      await _sink.invokeMethod('volume', {'volume': on ? 0.0 : 1.0});
    } catch (_) {}
  }

  Future<void> _interruptAll() async {
    if (_streams.isNotEmpty) await stopStream();
    final turns = <int>{..._chunks.keys};
    final current = _playingTurn;
    if (current != null) turns.add(current);
    _gen++;
    _barged.addAll(turns);
    Map<String, dynamic>? pos;
    try {
      pos = await _sink.invokeMapMethod<String, dynamic>('stop');
    } catch (e) {
      AmbientDiagnostics.log('voice: interrupt stop failed $e');
    }
    final playing = pos?['turn'] as int?;
    for (final t in turns) {
      _finish(t);
    }
    if (playing != null && playing >= 0 && turns.contains(playing)) {
      await _postBarge(playing, pos?['seq'] as int? ?? -1, pos?['played_ms'] as int? ?? 0);
    }
    speaking.value = _busy;
  }

  Future<void> stopNow() async {
    if (_streams.isNotEmpty) await stopStream();
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
    speaking.value = _busy;
  }

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    _poll?.cancel();
    _streamTick?.cancel();
    _streamFlush?.cancel();
    _flushStreamFrames();
    final duplex = _duplex;
    if (duplex != null) {
      duplex.onTtsFrame = null;
      duplex.onTts = null;
      duplex.onConnection = null;
    }
    _client.close();
    await _sub?.cancel();
    await _channel?.sink.close();
    await _sink.invokeMethod('stop').catchError((_) {});
    speaking.dispose();
    state.dispose();
  }
}
