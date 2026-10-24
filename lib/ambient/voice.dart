import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
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
  final Map<int, Set<int>> _received = {};
  final Set<int> _ended = {};
  final Set<int> _barged = {};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _closed = false, _running = false;
  final http.Client _client = http.Client();
  final Set<int> _finished = {};
  final Map<int, Set<int>> _consumed = {};
  final Map<int, DateTime> _idleSince = {};
  Timer? _poll;
  int _failures = 0, _last = 0;
  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(baseUrl).replace(path: path, queryParameters: {'token': token, ...?query});
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
    } catch (_) { _reconnect(); }
  }
  void _reconnect() {
    if (_closed || _retry?.isActive == true) return;
    _sub?.cancel();
    _retry = Timer(Duration(milliseconds: (500 * (1 << _failures.clamp(0, 5))).clamp(500, 15000)), () { _failures++; _connect(); });
  }
  void _frame(dynamic raw) {
    try {
      final f = jsonDecode(raw as String) as Map<String, dynamic>;
      if (f['device'] != device) return;
      final turn = f['turn'] as int?;
      switch (f['kind']) {
        case 'ambient_state': state.value = AmbientStateEvent(mode: f['mode'] as String? ?? '', sub: f['sub'] as String? ?? '', reason: f['reason'] as String?); break;
        case 'ambient_speech_start': if (turn != null) { _chunks.putIfAbsent(turn, () => {}); _received.putIfAbsent(turn, () => {}); _play(); } break;
        case 'ambient_speech_chunk': if (turn != null && !_barged.contains(turn)) { final seq = f['seq'] as int; _received.putIfAbsent(turn, () => {}).add(seq); _chunks.putIfAbsent(turn, () => {})[seq] = f; _play(); } break;
        case 'ambient_speech_end': if (turn != null) { _ended.add(turn); _play(); } break;
        case 'ambient_speech_cancel': if (turn != null) _cancel(turn, f['after_seq'] as int? ?? -1); break;
      }
    } catch (_) {}
  }
  Future<void> _catchUp() async {
    try {
      final floor = _chunks.isEmpty ? _last : (_chunks.keys.reduce((a, b) => a < b ? a : b) - 1);
      final r = await _client.get(_uri('/ambient/turns', {'after': '$floor', 'device': device}));
      if (r.statusCode != 200) return;
      for (final t in (jsonDecode(r.body)['turns'] as List)) {
        final id = t['id'] as int;
        _last = id > _last ? id : _last;
        if (_finished.contains(id) || _barged.contains(id)) continue;
        _chunks.putIfAbsent(id, () => {});
        _received.putIfAbsent(id, () => {});
        for (final c in (t['chunks'] as List? ?? [])) { final m = Map<String, dynamic>.from(c as Map); final seq = m['seq'] as int; if (_consumed[id]?.contains(seq) == true) continue; _chunks[id]![seq] = m; _received[id]!.add(seq); }
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
        final turn = _chunks.keys.reduce((a, b) => a < b ? a : b);
        if (_barged.contains(turn)) { _finish(turn); continue; }
        final map = _chunks[turn]!;
        final keys = map.keys.toList()..sort();
        if (keys.isEmpty) {
          if (_ended.contains(turn)) {
            final pos = await _position();
            if ((pos['seq'] as int? ?? -1) >= 0) await _played(turn, pos['seq'] as int, pos['played_ms'] as int? ?? 0, true);
            _finish(turn);
            continue;
          }
          final since = _idleSince.putIfAbsent(turn, () => DateTime.now());
          final newer = _chunks.keys.any((k) => k > turn);
          if (newer || DateTime.now().difference(since) > const Duration(seconds: 8)) {
            AmbientDiagnostics.log('voice: dropping stalled turn $turn');
            _finish(turn);
            continue;
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
          continue;
        }
        _idleSince.remove(turn);
        final seq = keys.first;
        final pcm = await _fetch(turn, seq);
        map.remove(seq);
        _consumed.putIfAbsent(turn, () => {}).add(seq);
        if (pcm == null) AmbientDiagnostics.log('voice: chunk $turn/$seq unavailable');
        if (pcm == null) continue;
        try {
          await _sink.invokeMethod('enqueue', {'turn': turn, 'seq': seq, 'pcm': pcm, 'silenceMs': 80});
          AmbientDiagnostics.log('voice: enqueued $turn/$seq ${pcm.length}B');
          final next = map.keys.toList()..sort();
          if (next.isNotEmpty) unawaited(_pumpAhead(turn));
          final target = seq;
          Map<String, dynamic> pos = const {};
          while (!_closed) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            pos = await _position();
            if ((pos['seq'] as int? ?? -1) >= target) break;
          }
          final playedSeq = pos['seq'] as int? ?? -1;
          if (playedSeq >= seq) await _played(turn, seq, _duration(pcm), false);
        } catch (e) { AmbientDiagnostics.log('voice: playback error $e'); }
        if (map.isEmpty && _ended.contains(turn)) {
          Map<String, dynamic> pos;
          do { await Future<void>.delayed(const Duration(milliseconds: 20)); pos = await _position(); }
          while (!_closed && (pos['seq'] as int? ?? -1) < seq);
          await _played(turn, seq, pos['played_ms'] as int? ?? _duration(pcm), true);
          _finish(turn);
        }
      }
    } finally {
      _running = false;
      if (_chunks.isEmpty) {
        speaking.value = false;
      } else if (!_closed) {
        unawaited(_play());
      }
    }
  }
  void _finish(int turn) { _chunks.remove(turn); _finished.add(turn); _idleSince.remove(turn); }
  int _duration(Uint8List pcm) => pcm.length * 1000 ~/ 48000;
  Future<Map<String, dynamic>> _position() async => await _sink.invokeMapMethod<String, dynamic>('position') ?? const {};
  Future<Uint8List?> _fetch(int turn, int seq) async {
    for (var attempt = 0; attempt < 30; attempt++) {
      try { final r = await _client.get(_uri('/ambient/turns/$turn/chunks/$seq')); if (r.statusCode == 200) return r.bodyBytes; } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }
  Future<void> _pumpAhead(int turn) async {
    final map = _chunks[turn];
    if (map == null || map.isEmpty) return;
    final seq = (map.keys.toList()..sort()).first;
    try {
      final r = await _client.get(_uri('/ambient/turns/$turn/chunks/$seq'));
      if (r.statusCode != 200) return;
      map.remove(seq);
      _consumed.putIfAbsent(turn, () => {}).add(seq);
      await _sink.invokeMethod('enqueue', {'turn': turn, 'seq': seq, 'pcm': r.bodyBytes, 'silenceMs': 80});
    } catch (_) {}
  }
  Future<void> _played(int id, int seq, int ms, bool complete) async { try { await _client.post(_uri('/ambient/turns/played'), headers: {'content-type':'application/json'}, body: jsonEncode({'id':id,'seq':seq,'played_ms':ms,'complete':complete})); } catch (_) {} }
  Future<void> _cancel(int turn, int after) async {
    final m = _chunks[turn];
    m?.removeWhere((seq, _) => seq > after);
    try {
      final pos = await _position();
      final seq = pos['seq'] as int? ?? -1;
      final ms = pos['played_ms'] as int? ?? 0;
      if (seq >= 0 && seq > after) {
        await _client.post(_uri('/ambient/barge'), headers: {'content-type': 'application/json'}, body: jsonEncode({'turn': turn, 'seq': seq, 'played_ms': ms}));
      }
      await _sink.invokeMethod('cancelAfter', {'turn': turn, 'seq': after, 'fadeMs': 50});
    } catch (_) {}
  }
  Future<void> duck(bool on) async { try { await _sink.invokeMethod('volume', {'volume': on ? 0.3 : 1.0}); } catch (_) {} }
  Future<void> stopNow() async {
    final turn = _chunks.isEmpty ? null : _chunks.keys.reduce((a,b) => a < b ? a : b);
    final pos = await _sink.invokeMapMethod<String, dynamic>('stop');
    if (turn != null) {
      final seq = pos?['seq'] as int? ?? -1;
      final ms = pos?['played_ms'] as int? ?? 0;
      _barged.add(turn);
      _finish(turn);
      try { await _client.post(_uri('/ambient/barge'), headers: {'content-type':'application/json'}, body: jsonEncode({'turn':turn,'seq':seq,'played_ms':ms})); } catch (_) {}
    }
    speaking.value = false;
  }
  Future<void> dispose() async { _closed = true; _retry?.cancel(); _poll?.cancel(); _client.close(); await _sub?.cancel(); await _channel?.sink.close(); await _sink.invokeMethod('stop').catchError((_) {}); speaking.dispose(); state.dispose(); }
}
