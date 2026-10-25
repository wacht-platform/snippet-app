import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class StreamDone {
  StreamDone(this.code, this.status);
  final int code;
  final String status;
}

class AmbientStream {
  AmbientStream({required this.baseUrl, required this.token, required this.device});

  final String baseUrl;
  final String token;
  final String device;

  WebSocket? _ws;
  Future<WebSocket?>? _connecting;
  final Map<int, Completer<StreamDone>> _waiting = {};
  int _handle = 0;
  bool _closed = false;
  bool _keep = false;
  int _failures = 0;
  Timer? _retry;
  DateTime? _connectedAt;
  DateTime? _lastMicFrameAt;
  int _micFrameSeq = 0;
  int _maxMicGapMs = 0;
  void Function(int turn, Uint8List pcm)? onTtsFrame;
  void Function(Map<String, dynamic> msg)? onTts;
  void Function(bool open)? onConnection;

  bool get open => _ws?.readyState == WebSocket.open;

  int nextHandle() => ++_handle;

  Future<WebSocket?> _socket() {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) return Future.value(ws);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  void keepAlive() {
    _keep = true;
    unawaited(_socket());
  }

  void _scheduleRetry() {
    if (!_keep || _closed || _retry?.isActive == true) return;
    _retry = Timer(Duration(milliseconds: (500 * (1 << _failures.clamp(0, 5))).clamp(500, 15000)), () {
      _failures++;
      unawaited(_socket());
    });
  }

  Future<WebSocket?> _connect() async {
    if (_closed) return null;
    try {
      final base = Uri.parse(baseUrl);
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/ambient/stream',
        queryParameters: {'token': token, 'device': device},
      );
      final ws = await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 8));
      ws.pingInterval = const Duration(seconds: 20);
      ws.listen(
        (data) => _onMessage(data),
        onDone: () => _lost(ws),
        onError: (Object _) => _lost(ws),
        cancelOnError: true,
      );
      _ws = ws;
      _connectedAt = DateTime.now();
      _lastMicFrameAt = null;
      _micFrameSeq = 0;
      _maxMicGapMs = 0;
      _failures = 0;
      _send(ws, jsonEncode({'t': 'caps', 'tts_stream': 1}));
      onConnection?.call(true);
      return ws;
    } catch (_) {
      _scheduleRetry();
      return null;
    }
  }

  void _onMessage(dynamic data) {
    if (data is List<int>) {
      if (data.length < 6) return;
      final bytes = data is Uint8List ? data : Uint8List.fromList(data);
      final turn = ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.little);
      onTtsFrame?.call(turn, Uint8List.sublistView(bytes, 4));
      return;
    }
    if (data is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(data) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final t = msg['t'];
    if (t == 'done' || t == 'err') {
      final h = (msg['h'] as num?)?.toInt() ?? 0;
      _waiting.remove(h)?.complete(StreamDone((msg['code'] as num?)?.toInt() ?? 0, '${msg['status'] ?? ''}'));
    } else if (t == 'tts_start' || t == 'tts_end' || t == 'tts_stop') {
      onTts?.call(msg);
    }
  }

  void _lost(WebSocket ws) {
    if (identical(_ws, ws)) _ws = null;
    final pending = _waiting.values.toList();
    _waiting.clear();
    for (final c in pending) {
      c.complete(StreamDone(0, 'connection lost'));
    }
    if (_ws == null) {
      onConnection?.call(false);
      _scheduleRetry();
    }
  }

  void _send(WebSocket ws, Object data) {
    try {
      ws.add(data);
    } catch (_) {}
  }

  Future<bool> start(int h, String id, int seq, DateTime startedAt, {bool continued = false, bool backlog = false, bool live = false}) async {
    final ws = await _socket();
    if (ws == null) return false;
    _send(ws, jsonEncode({
      't': 'start',
      'h': h,
      'id': id,
      'seq': seq,
      'started_at': startedAt.toUtc().toIso8601String(),
      'continued': continued,
      if (backlog) 'backlog': true,
      if (live) 'live': true,
    }));
    return true;
  }

  void chunk(int h, Uint8List pcm) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open || pcm.isEmpty) return;
    final out = Uint8List(4 + pcm.length);
    ByteData.sublistView(out).setUint32(0, h, Endian.little);
    out.setRange(4, out.length, pcm);
    final now = DateTime.now();
    final previous = _lastMicFrameAt;
    if (previous != null) {
      final gap = now.difference(previous).inMilliseconds;
      if (gap > _maxMicGapMs) _maxMicGapMs = gap;
    }
    _lastMicFrameAt = now;
    _micFrameSeq++;
    _send(ws, out);
  }

  Future<StreamDone> end(int h, String id, {required int durationMs, required int bytes, bool media = false, bool duringPlayback = false}) {
    final ws = _ws;
    if (ws == null || ws.readyState != WebSocket.open) return Future.value(StreamDone(0, 'connection lost'));
    final done = Completer<StreamDone>();
    _waiting[h] = done;
    _send(ws, jsonEncode({
      't': 'end',
      'h': h,
      'id': id,
      'duration_ms': durationMs,
      'bytes': bytes,
      'media': media,
      'during_playback': duringPlayback,
    }));
    return done.future.timeout(const Duration(seconds: 40), onTimeout: () {
      _waiting.remove(h);
      return StreamDone(0, 'timeout');
    });
  }

  void abort(int h) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) _send(ws, jsonEncode({'t': 'abort', 'h': h}));
  }

  void stat(Map<String, Object> values) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) {
      _send(ws, jsonEncode({
        't': 'stat',
        ...values,
        'mic_frame_seq': _micFrameSeq,
        'mic_send_elapsed_ms': DateTime.now().difference(_connectedAt ?? DateTime.now()).inMilliseconds,
        'mic_max_gap_ms': _maxMicGapMs,
      }));
      _maxMicGapMs = 0;
    }
  }

  void ttsPos(int turn, int ms, bool done) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) _send(ws, jsonEncode({'t': 'tts_pos', 'turn': turn, 'ms': ms, 'done': done}));
  }

  void skip(int seq) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) _send(ws, jsonEncode({'t': 'skip', 'seq': seq}));
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    final ws = _ws;
    _ws = null;
    try {
      ws?.close();
    } catch (_) {}
  }
}
