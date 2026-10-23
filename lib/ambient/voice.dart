import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'diagnostics.dart';

class AmbientVoice {
  AmbientVoice({
    required this.baseUrl,
    required this.token,
    required this.device,
    required this.onSpeaking,
  });

  final String baseUrl;
  final String token;
  final String device;
  final void Function(bool speaking) onSpeaking;

  final AudioPlayer _player = AudioPlayer();
  final List<Map<String, dynamic>> _queue = [];
  final Set<int> _seen = {};
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _closed = false;
  bool _playing = false;
  int _failures = 0;
  int _last = 0;
  DateTime? _connectedAt;

  Future<void> start() async {
    _connect();
  }

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(baseUrl)
      .replace(path: path, queryParameters: {'token': token, ...?query});

  void _connect() {
    if (_closed) return;
    final base = Uri.parse(baseUrl);
    final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/events',
        queryParameters: {'token': token});
    try {
      final channel = IOWebSocketChannel.connect(uri,
          connectTimeout: const Duration(seconds: 10),
          pingInterval: const Duration(seconds: 45));
      _channel = channel;
      _sub = channel.stream.listen(_onFrame, onError: (_) => _reconnect(), onDone: _reconnect);
      _connectedAt = DateTime.now();
      unawaited(_catchUp());
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_closed) return;
    _sub?.cancel();
    _channel = null;
    final alive = _connectedAt == null ? Duration.zero : DateTime.now().difference(_connectedAt!);
    _connectedAt = null;
    _failures = alive > const Duration(seconds: 30) ? 1 : _failures + 1;
    _retry?.cancel();
    final base = (2 << (_failures.clamp(0, 5))).clamp(2, 60);
    _retry = Timer(Duration(milliseconds: base * 1000 + Random().nextInt(1000)), _connect);
  }

  Future<void> _catchUp() async {
    try {
      final response = await http.get(_uri('/ambient/turns', {'after': '$_last', 'device': device}));
      if (response.statusCode != 200) return;
      final turns = (jsonDecode(response.body) as Map<String, dynamic>)['turns'] as List? ?? [];
      for (final t in turns) {
        _accept((t as Map).cast<String, dynamic>());
      }
    } catch (_) {}
  }

  void _onFrame(dynamic raw) {
    try {
      final frame = jsonDecode(raw as String);
      if (frame is Map && frame['kind'] == 'ambient_speech' && frame['device'] == device) {
        _accept(frame.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  void _accept(Map<String, dynamic> turn) {
    final id = (turn['id'] as num?)?.toInt() ?? 0;
    if (id == 0 || !_seen.add(id)) return;
    if (id > _last) _last = id;
    _queue.add(turn);
    unawaited(_play());
  }

  Future<bool> _playServerAudio(int id) async {
    try {
      final response = await http
          .get(_uri('/ambient/turns/$id/audio'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200 || response.bodyBytes.isEmpty) return false;
      final finished = _player.onPlayerComplete.first;
      await _player.play(BytesSource(response.bodyBytes, mimeType: 'audio/wav'));
      await finished.timeout(const Duration(seconds: 90));
      return true;
    } catch (e) {
      await AmbientDiagnostics.log('server audio failed: $e');
      try {
        await _player.stop();
      } catch (_) {}
      return false;
    }
  }

  Future<void> _play() async {
    if (_playing) return;
    _playing = true;
    onSpeaking(true);
    try {
      while (_queue.isNotEmpty && !_closed) {
        final turn = _queue.removeAt(0);
        if (turn['audio'] == true) {
          await _playServerAudio((turn['id'] as num).toInt());
        }
        unawaited(http
            .post(_uri('/ambient/turns/played'),
                headers: {'content-type': 'application/json'},
                body: jsonEncode({'id': turn['id']}))
            .catchError((Object _) => http.Response('', 500)));
      }
      await Future<void>.delayed(const Duration(milliseconds: 450));
    } finally {
      _playing = false;
      onSpeaking(false);
    }
  }

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _channel?.sink.close();
    _queue.clear();
    try {
      await _player.dispose();
    } catch (_) {}
  }
}
