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

  int nextHandle() => ++_handle;

  Future<WebSocket?> _socket() {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) return Future.value(ws);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
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
      return ws;
    } catch (_) {
      return null;
    }
  }

  void _onMessage(dynamic data) {
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
    }
  }

  void _lost(WebSocket ws) {
    if (identical(_ws, ws)) _ws = null;
    final pending = _waiting.values.toList();
    _waiting.clear();
    for (final c in pending) {
      c.complete(StreamDone(0, 'connection lost'));
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
    if (ws != null && ws.readyState == WebSocket.open) _send(ws, jsonEncode({'t': 'stat', ...values}));
  }

  void skip(int seq) {
    final ws = _ws;
    if (ws != null && ws.readyState == WebSocket.open) _send(ws, jsonEncode({'t': 'skip', 'seq': seq}));
  }

  void close() {
    _closed = true;
    final ws = _ws;
    _ws = null;
    try {
      ws?.close();
    } catch (_) {}
  }
}
