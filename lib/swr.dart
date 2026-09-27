import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

typedef DeviceEventFrame = Map<String, dynamic>;
typedef SwrTrigger = bool Function(DeviceEventFrame event);

class DeviceEventHub {
  DeviceEventHub(WebSocketChannel Function() open) : _open = open;

  DeviceEventHub.local() : _open = null;

  static const reconnected = '_reconnected';

  final WebSocketChannel Function()? _open;
  late final StreamController<DeviceEventFrame> _controller =
      StreamController<DeviceEventFrame>.broadcast(
          onListen: _connect, onCancel: _close);
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  int _attempt = 0;

  Stream<DeviceEventFrame> get stream => _controller.stream;

  void add(DeviceEventFrame event) => _controller.add(event);

  void _connect() {
    final open = _open;
    if (open == null) return;
    _retry?.cancel();
    try {
      final channel = open();
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

class SwrEntry<T> extends ChangeNotifier {
  T? data;
  Object? error;
  DateTime? updatedAt;
  Future<T>? _inFlight;

  bool get validating => _inFlight != null;

  bool isFresh(Duration window) {
    final at = updatedAt;
    return at != null && DateTime.now().difference(at) < window;
  }

  Future<T?> revalidate(Future<T> Function() fetch,
      {bool force = false, Duration dedupe = Duration.zero}) {
    final running = _inFlight;
    if (running != null) return running;
    if (!force && isFresh(dedupe)) return Future.value(data);
    final pending = fetch();
    _inFlight = pending;
    notifyListeners();
    return pending.then<T?>((value) {
      data = value;
      error = null;
      updatedAt = DateTime.now();
      return value;
    }, onError: (Object e) {
      error = e;
      return data;
    }).whenComplete(() {
      if (identical(_inFlight, pending)) _inFlight = null;
      notifyListeners();
    });
  }

  void mutate(T value) {
    data = value;
    error = null;
    updatedAt = DateTime.now();
    notifyListeners();
  }
}

class SwrCache {
  final Map<String, SwrEntry<dynamic>> _entries = {};

  SwrEntry<T> entry<T>(String key) =>
      _entries.putIfAbsent(key, () => SwrEntry<T>()) as SwrEntry<T>;

  void invalidate(String prefix) {
    for (final e in _entries.entries) {
      if (e.key.startsWith(prefix)) e.value.updatedAt = null;
    }
  }
}

class Revalidator with WidgetsBindingObserver {
  Revalidator({
    required DaemonClient client,
    required void Function({required bool force}) onRevalidate,
    SwrTrigger? on,
    Duration debounce = const Duration(milliseconds: 300),
  })  : _onRevalidate = onRevalidate,
        _debounceDelay = debounce {
    if (on != null) {
      _events = client.deviceEvents.stream.listen((event) {
        if (event['kind'] == DeviceEventHub.reconnected || on(event)) {
          _schedule();
        }
      });
    }
    WidgetsBinding.instance.addObserver(this);
  }

  final void Function({required bool force}) _onRevalidate;
  final Duration _debounceDelay;
  StreamSubscription<DeviceEventFrame>? _events;
  Timer? _debounce;
  bool _disposed = false;

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      if (!_disposed) _onRevalidate(force: true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) {
      _onRevalidate(force: false);
    }
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _events?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

class Swr<T> {
  Swr({
    required DaemonClient client,
    required String key,
    required Future<T> Function() fetch,
    SwrTrigger? revalidateOn,
    VoidCallback? onChange,
    this.dedupe = const Duration(seconds: 2),
    Duration debounce = const Duration(milliseconds: 300),
  })  : _fetch = fetch,
        _onChange = onChange,
        entry = client.swr.entry<T>(key) {
    if (onChange != null) entry.addListener(onChange);
    _triggers = Revalidator(
      client: client,
      on: revalidateOn,
      debounce: debounce,
      onRevalidate: ({required bool force}) => revalidate(force: force),
    );
    scheduleMicrotask(() {
      if (!_disposed) revalidate();
    });
  }

  static bool coordination(DeviceEventFrame e) =>
      e['kind'] == 'coordination_event';

  static bool sessionStatus(DeviceEventFrame e) =>
      (e['status'] as String?)?.isNotEmpty == true;

  final SwrEntry<T> entry;
  final Duration dedupe;
  final Future<T> Function() _fetch;
  final VoidCallback? _onChange;
  late final Revalidator _triggers;
  bool _disposed = false;

  T? get data => entry.data;
  Object? get error => entry.error;
  bool get validating => entry.validating;
  bool get loading => entry.data == null && entry.error == null;

  Future<T?> revalidate({bool force = false}) =>
      entry.revalidate(_fetch, force: force, dedupe: dedupe);

  Future<T?> refresh() => revalidate(force: true);

  void mutate(T value) => entry.mutate(value);

  void dispose() {
    _disposed = true;
    _triggers.dispose();
    final onChange = _onChange;
    if (onChange != null) entry.removeListener(onChange);
  }
}
