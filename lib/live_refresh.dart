import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

typedef DeviceEventFrame = Map<String, dynamic>;

class DeviceEventHub {
  DeviceEventHub(this._open);

  static const reconnected = '_reconnected';

  final WebSocketChannel Function() _open;
  late final StreamController<DeviceEventFrame> _controller =
      StreamController<DeviceEventFrame>.broadcast(
          onListen: _connect, onCancel: _close);
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;

  Stream<DeviceEventFrame> get stream => _controller.stream;

  void _connect() {
    _retry?.cancel();
    try {
      final channel = _open();
      _channel = channel;
      _sub = channel.stream.listen(
        (raw) {
          try {
            final frame = jsonDecode(raw as String);
            if (frame is Map) {
              _attempt = 0;
              _controller.add(frame.cast<String, dynamic>());
            }
          } catch (_) {}
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    _sub = null;
    _channel = null;
    if (!_controller.hasListener) return;
    _retry?.cancel();
    final seconds = math.min(30, 1 << math.min(_attempt++, 5));
    _retry = Timer(Duration(seconds: seconds), () {
      if (!_controller.hasListener) return;
      _connect();
      _controller.add({'kind': reconnected});
    });
  }

  void _close() {
    _retry?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _sub = null;
    _channel = null;
    _attempt = 0;
  }
}

class LiveRefresh {
  LiveRefresh({
    required DaemonClient client,
    required bool Function(DeviceEventFrame event) when,
    required void Function() refresh,
    Duration backstop = const Duration(seconds: 60),
    Duration debounce = const Duration(milliseconds: 300),
  })  : _refresh = refresh,
        _debounceDelay = debounce {
    _sub = client.deviceEvents.stream.listen((event) {
      if (event['kind'] == DeviceEventHub.reconnected || when(event)) {
        _schedule();
      }
    });
    _backstop = Timer.periodic(backstop, (_) => _refresh());
  }

  static bool coordination(DeviceEventFrame e) =>
      e['kind'] == 'coordination_event';

  static bool sessionStatus(DeviceEventFrame e) =>
      (e['status'] as String?)?.isNotEmpty == true;

  final void Function() _refresh;
  final Duration _debounceDelay;
  late final StreamSubscription<DeviceEventFrame> _sub;
  late final Timer _backstop;
  Timer? _debounce;

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, _refresh);
  }

  void dispose() {
    _debounce?.cancel();
    _backstop.cancel();
    _sub.cancel();
  }
}
