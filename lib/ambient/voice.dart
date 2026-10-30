import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'diagnostics.dart';
import 'sink.dart';
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
  bool locallyPaused = false;
  DateTime? pauseStarted;
  DateTime? speechEndedAt;
  Timer? pauseTimer;
  int pauseGeneration = 0;
}

class AmbientVoice {
  AmbientVoice(
      {required this.baseUrl, required this.token, required this.device});
  final String baseUrl;
  final String token;
  final String device;
  final ValueNotifier<bool> speaking = ValueNotifier(false);
  final ValueNotifier<AmbientStateEvent?> state = ValueNotifier(null);
  final AmbientSink _sink = AmbientSink();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _closed = false;
  int _failures = 0;
  AmbientStream? _duplex;
  final Map<int, _StreamTurn> _streams = {};
  final Set<int> _streamDead = {};
  Timer? _streamTick;
  bool _ticking = false;

  bool get _busy => _streams.isNotEmpty;

  Future<void> start() async {
    _connect();
  }

  void _connect() {
    if (_closed) return;
    final base = Uri.parse(baseUrl);
    final u = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/events',
        queryParameters: {'token': token});
    try {
      final c = WebSocketChannel.connect(u);
      _channel = c;
      _sub = c.stream
          .listen(_frame, onError: (_) => _reconnect(), onDone: _reconnect);
      c.ready.then((_) {
        if (identical(_channel, c)) _failures = 0;
      }, onError: (_) {});
    } catch (_) {
      _reconnect();
    }
  }

  void _reconnect() {
    if (_closed || _retry?.isActive == true) return;
    _sub?.cancel();
    _retry = Timer(
        Duration(
            milliseconds:
                (500 * (1 << _failures.clamp(0, 5))).clamp(500, 15000)), () {
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
          state.value = AmbientStateEvent(
              mode: f['mode'] as String? ?? '',
              sub: f['sub'] as String? ?? '',
              reason: f['reason'] as String?);
        case 'ambient_speech_cancel' when turn != null:
          unawaited(stopStream(turn));
        case 'ambient_speech_interrupt':
          unawaited(stopStream());
      }
    } catch (e) {
      AmbientDiagnostics.log('voice: bad frame $e');
    }
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
        unawaited(_sink.warm().catchError((_) {}));
        _streamChanged();
      case 'tts_end':
        if (turn <= 0 || _streamDead.contains(turn)) return;
        _adoptStream(turn).ended = true;
        _streamChanged();
      case 'tts_stop':
        unawaited(stopStream(turn));
    }
  }

  _StreamTurn _adoptStream(int turn) =>
      _streams.putIfAbsent(turn, _StreamTurn.new);

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
    unawaited(_sink.enqueueFrame(turn, data).then((_) {
      if (_streamDead.contains(turn)) unawaited(_sink.stopStream(turn));
    }).catchError((Object e) {
      AmbientDiagnostics.log('voice: stream frame failed $e');
    }));
  }

  void _streamChanged() {
    speaking.value = _busy;
    if (_streams.isEmpty) {
      _streamTick?.cancel();
      _streamTick = null;
    } else {
      _streamTick ??= Timer.periodic(
          const Duration(milliseconds: 500), (_) => _tickStream());
    }
  }

  Map<int, int> _playedMap(Map<String, dynamic> pos) => {
        for (final e in ((pos['turns'] as Map?) ?? const {}).entries)
          (e.key as num).toInt(): (e.value as num).toInt(),
      };

  Future<void> _tickStream() async {
    if (_ticking || _closed) return;
    _ticking = true;
    try {
      Map<String, dynamic> pos = const {};
      try {
        pos = await _sink.streamPosition();
      } catch (e) {
        AmbientDiagnostics.log('voice: stream position failed $e');
      }
      final played = _playedMap(pos);
      final heard = pos['turn'] as int? ?? -1;
      final active = pos['active'] == 1;
      final now = DateTime.now();
      final quietLimit = (_duplex?.open ?? false)
          ? const Duration(seconds: 8)
          : const Duration(seconds: 3);
      for (final e in _streams.entries.toList()) {
        final turn = e.key, st = e.value;
        if (!identical(_streams[turn], st)) continue;
        final ms = played[turn] ?? 0;
        if (st.locallyPaused) {
          st.lastPlayed = ms;
          st.lastProgress = now;
          continue;
        }
        if (ms != st.lastPlayed) {
          st.lastPlayed = ms;
          st.lastProgress = now;
        }
        final total = st.bytes ~/ 48;
        final caughtUp = ms >= total - 5;
        if (st.ended &&
            (caughtUp ||
                (!active &&
                    now.difference(st.lastProgress) >
                        const Duration(milliseconds: 1500)))) {
          _duplex?.ttsPos(turn, caughtUp ? total : ms, true);
          _endStream(turn);
          continue;
        }
        if (!st.ended &&
            caughtUp &&
            !(active && heard == turn) &&
            now.difference(st.lastFrame) > quietLimit) {
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
  }

  Future<void> localSpeech(bool voiced, {bool canPause = false}) async {
    for (final entry in _streams.entries.toList()) {
      final st = entry.value;
      if (voiced) {
        st.speechEndedAt = null;
        st.pauseTimer?.cancel();
        if (canPause && !st.locallyPaused) {
          st.locallyPaused = true;
          st.pauseStarted = DateTime.now();
          st.pauseGeneration++;
          final generation = st.pauseGeneration;
          Timer(const Duration(seconds: 3),
              () => _resumeLocal(st, entry.key, generation));
          await _sink.pauseTts();
          unawaited(AmbientDiagnostics.log(
              'voice: local TTS pause turn ${entry.key}'));
        }
      } else if (st.locallyPaused && st.speechEndedAt == null) {
        st.speechEndedAt = DateTime.now();
        final generation = st.pauseGeneration;
        st.pauseTimer = Timer(const Duration(milliseconds: 900),
            () => _resumeLocal(st, entry.key, generation));
      }
    }
  }

  Future<void> _resumeLocal(_StreamTurn st, int turn, int generation) async {
    if (!st.locallyPaused ||
        st.pauseGeneration != generation ||
        _streamDead.contains(turn)) return;
    if (st.speechEndedAt == null &&
        DateTime.now().difference(st.pauseStarted!) <
            const Duration(seconds: 3)) return;
    final elapsed = DateTime.now()
        .difference(st.pauseStarted ?? DateTime.now())
        .inMilliseconds;
    st.locallyPaused = false;
    st.pauseTimer?.cancel();
    await _sink.resumeTts();
    await _sink.volume(1);
    unawaited(AmbientDiagnostics.log(
        'voice: local TTS resume turn $turn after ${elapsed}ms'));
  }

  Future<void> stopStream([int turn = 0]) async {
    final stopped = turn == 0 ? _streams.keys.toList() : [turn];
    for (final t in stopped) {
      final st = _streams[t];
      if (st?.locallyPaused == true) {
        final elapsed = DateTime.now()
            .difference(st!.pauseStarted ?? DateTime.now())
            .inMilliseconds;
        unawaited(AmbientDiagnostics.log(
            'voice: server TTS stop turn $t after ${elapsed}ms local pause'));
      }
      st?.pauseGeneration++;
      st?.pauseTimer?.cancel();
      st?.locallyPaused = false;
      _endStream(t);
    }
    _streamChanged();
    Map<String, dynamic> pos = const {};
    try {
      pos = await _sink.stopStream(turn, fadeMs: 25);
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
      await _sink.volume(on ? 0.25 : 1.0);
    } catch (_) {}
  }

  Future<void> stopNow() => stopStream();

  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    _streamTick?.cancel();
    final duplex = _duplex;
    if (duplex != null) {
      duplex.onTtsFrame = null;
      duplex.onTts = null;
      duplex.onConnection = null;
    }
    await _sub?.cancel();
    await _channel?.sink.close();
    await _sink.stop().catchError((_) => const <String, dynamic>{});
    speaking.dispose();
    state.dispose();
  }
}
