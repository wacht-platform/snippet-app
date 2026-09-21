import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'term.dart' show ClearScrollTerminal;
import 'package:xterm/xterm.dart';

/// One daemon-wide shell.
class GlobalShell {
  GlobalShell(this.id, {required this.title})
      : terminal = ClearScrollTerminal();
  final String id;

  /// Mutable so the user can rename it from its tab.
  String title;
  final Terminal terminal;
  int cols = 80;
  int rows = 24;
  bool alive = false;
  bool live = false;
}

/// Daemon-WIDE interactive shells, independent of any session.
///
/// A shell belongs to the machine, not to a conversation: switching or closing a
/// session must not kill it. The session-scoped ptys still exist (a session's own
/// shell follows its workspace), but these do not — they live on `/shells`, a
/// socket the daemon serves without requiring a live session.
///
/// Lifecycle is explicit and owned here: `create`/`close` are the only ways a
/// shell appears or disappears. A dropped socket never destroys a pty, so a
/// reconnect re-lists what exists and reattaches.
class ShellsController extends ChangeNotifier {
  final List<GlobalShell> _shells = [];
  List<GlobalShell> get shells => List.unmodifiable(_shells);

  DaemonClient? _client;
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnect;
  bool _closed = false;

  /// A socket object exists before the WebSocket handshake is ready. Do not
  /// throw away `new` during that gap: it is exactly what left a freshly-created
  /// shell as an empty tab after a daemon restart.
  bool _ready = false;
  final List<Map<String, dynamic>> _pendingFrames = [];

  /// The focused shell id, so a pane strip can show the selection.
  String? _focusId;
  String? get focusId => _focusId;

  set focusId(String? id) {
    if (_focusId == id) return;
    _focusId = id;
    notifyListeners();
  }

  GlobalShell? byId(String id) {
    for (final s in _shells) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Point the controller at a machine. A different client tears the socket down
  /// and reconnects, because shells belong to that machine's daemon.
  void setClient(DaemonClient? c) {
    if (identical(c, _client)) return;
    _client = c;
    _teardown();
    if (c == null) {
      // No machine: the tabs are stale, so drop them rather than render rows
      // that can never connect.
      _shells.clear();
      notifyListeners();
      return;
    }
    _connect();
  }

  void _teardown() {
    _ready = false;
    _reconnect?.cancel();
    _reconnect = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _connect() {
    final c = _client;
    if (c == null || _closed) return;
    _teardown();
    try {
      final ch = c.attachShells();
      _channel = ch;
      _sub = ch.stream.listen(
        (msg) => _onFrame(msg),
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 2), _connect);
  }

  void _onFrame(dynamic msg) {
    if (msg is! String) return;
    Map<String, dynamic> j;
    try {
      j = jsonDecode(msg) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (j['wire'] != 'term') return;
    final op = j['op'] as String? ?? '';

    switch (op) {
      case 'list':
        // A list is the server's handshake. Retain optimistic `new` ids while
        // applying it: clearing one between the hello and its acknowledgement
        // was the cause of a blank, stuck terminal after daemon restart.
        _ready = true;
        final queued = List<Map<String, dynamic>>.from(_pendingFrames);
        final pendingNewIds = <String>{
          for (final frame in queued)
            if (frame['op'] == 'new' && frame['id'] is String)
              frame['id'] as String,
        };
        _pendingFrames.clear();
        // Reconnect: adopt what the daemon already has, so a dropped socket does
        // not make live shells vanish from the strip.
        final listed = (j['shells'] as List?) ?? const [];
        final live = <String>{...pendingNewIds};
        var changed = false;
        for (final raw in listed) {
          if (raw is! Map) continue;
          final id = raw['id'] as String? ?? '';
          if (id.isEmpty) continue;
          live.add(id);
          if (byId(id) == null) {
            _shells.add(GlobalShell(id, title: 'shell $id'));
            changed = true;
          }
        }
        // Drop anything the daemon no longer has.
        final before = _shells.length;
        _shells.removeWhere((s) => !live.contains(s.id));
        if (_shells.length != before) changed = true;
        _sort();
        if (focusId != null && byId(focusId!) == null) _focusId = null;
        for (final frame in queued) {
          _send(frame);
        }
        if (changed || queued.isNotEmpty) notifyListeners();
        return;

      case 'out':
        final id = j['id'] as String? ?? '';
        if (id.isEmpty) return;
        final raw = j['data'] as String?;
        final bytes =
            (raw == null || raw.isEmpty) ? Uint8List(0) : base64Decode(raw);
        final cols = (j['cols'] as num?)?.toInt();
        final rows = (j['rows'] as num?)?.toInt();

        // A shell the client has not seen yet (created elsewhere, or a `new`
        // whose id we sent): adopt it rather than dropping its output.
        var s = byId(id);
        if (s == null) {
          s = GlobalShell(id, title: 'shell $id');
          _shells.add(s);
          _sort();
        }
        s.alive = j['alive'] == true;
        if (bytes.isNotEmpty) {
          s.terminal.write(utf8.decode(bytes, allowMalformed: true));
          s.live = true;
        }
        if (cols != null) s.cols = cols;
        if (rows != null) s.rows = rows;
        // An exited shell keeps its tab (and its scrollback) so the output is
        // still readable; only an explicit close removes it.
        notifyListeners();
        return;
    }
  }

  void _sort() {
    _shells.sort((a, b) {
      final na = int.tryParse(a.id) ?? 0;
      final nb = int.tryParse(b.id) ?? 0;
      return na.compareTo(nb);
    });
  }

  void _send(Map<String, dynamic> m) {
    final ch = _channel;
    // WebSocketChannel.connect returns before the protocol handshake completes.
    // Queue lifecycle/input frames until the daemon's `list` hello confirms this
    // particular socket is ready; otherwise pressing + immediately after a
    // restart creates an optimistic tab but never a pty.
    if (ch == null || !_ready) {
      _pendingFrames.add(m);
      return;
    }
    try {
      ch.sink.add(jsonEncode(m));
    } catch (_) {
      // Socket already gone; retain the request for the reconnect rather than
      // leaving an optimistic terminal tab forever blank.
      _pendingFrames.add(m);
    }
  }

  /// Mint an id the daemon will honour.
  ///
  /// Client-minted rather than server-allocated: the daemon echoes the id on
  /// every output frame, but a shell that produces no output would otherwise
  /// never tell us what id it got, leaving a tab we cannot address.
  String _nextId() {
    var max = 0;
    for (final s in _shells) {
      final n = int.tryParse(s.id);
      if (n != null && n > max) max = n;
    }
    return '${max + 1}';
  }

  /// Create a shell locally, then let its owning UI insert the optimistic tab.
  /// The daemon acknowledgement will refresh it through the normal listener;
  /// notifying synchronously here would race that insertion and duplicate it.
  GlobalShell create({String? title}) {
    final id = _nextId();
    final s = GlobalShell(id, title: title ?? 'shell $id');
    _shells.add(s);
    _sort();
    _focusId = id;
    _send({'wire': 'term', 'op': 'new', 'id': id, 'cols': 80, 'rows': 24});
    return s;
  }

  /// Destroy a shell. This and [create] are the only lifecycle operations — a
  /// pane closing its view must call neither.
  void close(String id) {
    _send({'wire': 'term', 'op': 'close', 'id': id});
    _shells.removeWhere((s) => s.id == id);
    if (_focusId == id) {
      _focusId = _shells.isEmpty ? null : _shells.first.id;
    }
    notifyListeners();
  }

  void focus(String id) {
    final s = byId(id);
    if (s == null) return;
    focusId = id;
    // Re-open so the daemon resizes/attaches this pane if it was never opened.
    _send({
      'wire': 'term',
      'op': 'open',
      'id': id,
      'cols': s.cols,
      'rows': s.rows,
    });
  }

  void rename(String id, String title) {
    final s = byId(id);
    if (s == null) return;
    final t = title.trim();
    if (t.isEmpty || t == s.title) return;
    s.title = t;
    notifyListeners();
  }

  void write(String id, Uint8List bytes) {
    final s = byId(id);
    if (s == null) return;
    _send({
      'wire': 'term',
      'op': 'in',
      'id': id,
      'data': base64Encode(bytes),
      'cols': s.cols,
      'rows': s.rows,
    });
  }

  void resize(String id, int cols, int rows) {
    final s = byId(id);
    if (s == null) return;
    s.cols = cols;
    s.rows = rows;
    _send({
      'wire': 'term',
      'op': 'resize',
      'id': id,
      'cols': cols,
      'rows': rows,
    });
  }

  /// Render one shell. The controller owns the socket, so it supplies the view
  /// wiring; the shell decides where to place it.
  @override
  void dispose() {
    _closed = true;
    _teardown();
    super.dispose();
  }
}
