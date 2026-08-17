import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../api.dart';
import '../models.dart';
import '../notifications.dart';
import '../platform.dart';
import '../theme.dart';
import '../transcript.dart';
import '../panel.dart';
import '../widgets.dart';
import 'editor.dart';
import 'files.dart';
import 'processes.dart';
import 'git.dart';
import 'lanes.dart';

String formatCheckpointDate(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final daysAgo = today.difference(day).inDays;
  final hour = parsed.hour == 0
      ? 12
      : (parsed.hour > 12 ? parsed.hour - 12 : parsed.hour);
  final minute = parsed.minute.toString().padLeft(2, '0');
  final meridiem = parsed.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $meridiem';

  if (daysAgo == 0) return 'Today · $time';
  if (daysAgo == 1) return 'Yesterday · $time';
  if (daysAgo >= 0 && daysAgo < 7) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[parsed.weekday - 1]} · $time';
  }
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  return '$date · $time';
}

class SessionScreen extends StatefulWidget {
  final DaemonClient client;
  final String sessionId;
  final String title;
  final String? profile;

  /// True when shown as the main pane of the desktop shell (hides its own
  /// back/home chrome — navigation lives in the sidebar).
  final bool embedded;

  /// When embedded in a narrow desktop shell, opens the collapsed sidebar drawer.
  final VoidCallback? onMenu;

  /// When set, opening a file from the Files browser opens it as a shell tab
  /// instead of pushing an editor route.
  final void Function(String path, String name)? onOpenFileTab;

  /// Open a forked conversation (new tab / replace). Shell provides this so
  /// fork can jump straight into the branch.
  final void Function(String id, String title, String? profile)? onOpenSession;

  /// Publishes live usage data to the macOS shell status rail.
  final void Function(HarnessState? state, bool running)? onMacStatus;

  /// Gives the macOS shell access to session actions after this state mounts,
  /// allowing the shell chrome to replace the duplicate in-session title bar.
  final void Function(
          VoidCallback stop, void Function(String action) performAction)?
      onMacControls;

  /// Desktop PageView keeps every tab mounted. Only the visible session should
  /// accept file drops — otherwise every keep-alive DropTarget ingests the same
  /// file and the composer chips leak across tabs.
  final bool acceptDrops;

  const SessionScreen(
      {super.key,
      required this.client,
      required this.sessionId,
      required this.title,
      this.profile,
      this.embedded = false,
      this.onMenu,
      this.onOpenFileTab,
      this.onOpenSession,
      this.onMacStatus,
      this.onMacControls,
      this.acceptDrops = true});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionActionPanel extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onClose;
  const _SessionActionPanel(
      {required this.title, required this.child, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface1,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(children: [
              Expanded(
                  child: Text(title,
                      style: sans(16,
                          weight: FontWeight.w600, color: AppColors.fg1))),
              IconBtn('x',
                  size: 34, iconSize: 18, tooltip: 'Close', onTap: onClose),
            ]),
          ),
          Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ]),
      ),
    );
  }
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  // Outbound payloads queued while the socket is down; flushed in order on the
  // next healthy frame (silently dropping sends lost user messages/approvals).
  final List<String> _outbox = [];
  // The open-session suppression key THIS screen registered. Session switches
  // mount the new screen before disposing the old one, so dispose must only
  // clear the registration if it still owns it.
  static String _registeredOpenKey = '';
  late final String _openKey;
  HarnessState? _state;
  // Live token/thinking stream from attach `wire: stream` frames — NOT part of
  // HarnessState. Must never be applied via fromJson (that wiped events empty).
  String _liveText = '';
  String _liveThinking = '';
  bool _liveTextVisible = false;
  String? _connError;
  String? _modelLabel;
  String? _currentProfile;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription<Amplitude>? _amplitudeSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  Timer? _recordingTimer;
  bool _isRecording = false;
  bool _isPlayingRecording = false;
  bool _sendingAudio = false;
  bool _sendingMessage = false;
  String? _recordingPath;
  Duration _recordingElapsed = Duration.zero;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  final List<double> _waveform = [];
  // Held while status == running — not sent until the run ends (TUI/desktop parity).
  // Cancel drops locally only; these never hit the daemon's pending_inputs.
  final List<String> _queued = [];
  // Queue nonces at the moment the user queues a message, so every later
  // delivery path (flush, steer, dispose) remains idempotent across reconnects.
  final List<String> _queuedNonce = [];
  // Messages sent to the daemon but not yet echoed back as events — shown
  // optimistically (faint) so they don't vanish during the round-trip.
  final List<String> _pending = [];
  // Nonce per pending message for dedup: _pendingNonce[i] is the nonce for _pending[i].
  // On reconnect resend, the same nonce is reused so the server drops duplicates.
  final List<String> _pendingNonce = [];
  // user_input/steer count observed when each pending item was enqueued. Lets us
  // retire by "echoes advanced past this baseline" even when a snapshot arrives
  // with the same total as the previous local frame (no delta edge).
  final List<int> _pendingEchoBaseline = [];
  // Monotonic counter for unique nonce IDs.
  int _nonceCounter = 0;
  String _nextNonce() =>
      '${++_nonceCounter}-${DateTime.now().microsecondsSinceEpoch}';

  // How many user turns (typed or steered) the daemon has echoed into the event
  // log — the FIFO baseline for retiring optimistic bubbles (see the socket
  // handler; count-based, not text-based, so daemon-side trimming can't strand one).
  static int _userEchoCount(List<Map<String, dynamic>> events) => events
      .where((e) => e['kind'] == 'user_input' || e['kind'] == 'steer')
      .length;

  static String _normEchoText(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ');

  void _trackPending(String msg, String nonce) {
    _pending.add(msg);
    _pendingNonce.add(nonce);
    _pendingEchoBaseline
        .add(_userEchoCount(_state?.events ?? const <Map<String, dynamic>>[]));
  }

  void _clearPendingAll() {
    _pending.clear();
    _pendingNonce.clear();
    _pendingEchoBaseline.clear();
  }

  void _popPendingFront() {
    if (_pending.isEmpty) return;
    _pending.removeAt(0);
    if (_pendingNonce.isNotEmpty) _pendingNonce.removeAt(0);
    if (_pendingEchoBaseline.isNotEmpty) _pendingEchoBaseline.removeAt(0);
  }

  void _removePendingAt(int i) {
    if (i < 0 || i >= _pending.length) return;
    _pending.removeAt(i);
    if (i < _pendingNonce.length) _pendingNonce.removeAt(i);
    if (i < _pendingEchoBaseline.length) _pendingEchoBaseline.removeAt(i);
  }

  /// Drop optimistic bubbles that the authoritative event log already contains.
  /// Runs on every snapshot/delta — count-based retirement alone misses cases
  /// where the echo is present but the local prev→next count edge is zero
  /// (e.g. late snapshot after a missed delta, or reconnect race).
  void _retirePendingAlreadyEchoed(List<Map<String, dynamic>> events) {
    if (_pending.isEmpty) return;
    final echoed = <String>{};
    for (final e in events) {
      final kind = e['kind'];
      if (kind != 'user_input' && kind != 'steer') continue;
      final t = e['text'];
      if (t is String && t.trim().isNotEmpty) echoed.add(_normEchoText(t));
    }
    if (echoed.isEmpty) return;
    var i = 0;
    while (i < _pending.length) {
      if (echoed.contains(_normEchoText(_pending[i]))) {
        _removePendingAt(i);
      } else {
        i++;
      }
    }
  }

  /// Retire FIFO items whose baseline echo count has been surpassed.
  void _retirePendingByBaseline(int nextEchoes) {
    while (_pending.isNotEmpty) {
      final base =
          _pendingEchoBaseline.isNotEmpty ? _pendingEchoBaseline.first : -1;
      if (nextEchoes <= base) break;
      _popPendingFront();
    }
  }

  // Big-paste interception: a paste arrives as ONE controller change, so an
  // insertion this large can't be typing — pull it out of the field and attach
  // it as a text file instead (through the same _ingest pipeline as any file).
  static const _pasteAttachChars = 1000;
  static const _pasteAttachLines = 15;
  String _lastInput = '';
  bool _restoringInput = false;
  int _pasteN = 0;

  void _interceptBigPaste() {
    if (_restoringInput) return;
    final prev = _lastInput;
    final now = _input.text;
    if (now.length - prev.length < _pasteAttachChars) {
      // Also catch shorter-but-many-line pastes cheaply.
      if (now.length <= prev.length || !now.contains('\n')) {
        _lastInput = now;
        return;
      }
    }
    // Single-change diff: common prefix + suffix bound the inserted span.
    var p = 0;
    while (p < prev.length && p < now.length && prev[p] == now[p]) {
      p++;
    }
    var s = 0;
    while (s < prev.length - p &&
        s < now.length - p &&
        prev[prev.length - 1 - s] == now[now.length - 1 - s]) {
      s++;
    }
    final inserted = now.substring(p, now.length - s);
    final lines = '\n'.allMatches(inserted).length + 1;
    if (inserted.length < _pasteAttachChars && lines < _pasteAttachLines) {
      _lastInput = now;
      return;
    }
    // Restore the field to what it was without the pasted wall, cursor at the seam.
    _restoringInput = true;
    _input.value = TextEditingValue(
      text: prev,
      selection: TextSelection.collapsed(offset: p.clamp(0, prev.length)),
    );
    _restoringInput = false;
    _lastInput = prev;
    final name = 'paste-${++_pasteN}.txt';
    _ingest([
      (
        name: name,
        localPath: null,
        readBytes: () async => Uint8List.fromList(utf8.encode(inserted))
      )
    ]);
    _toast('Pasted text attached ($lines lines)');
  }

  // Pending attachments (images + files, up to 5): each uploads to the daemon
  // and is referenced in the next message. Images → read_image, files → read.
  final List<_Attachment> _attachments = [];
  int _attachmentGeneration = 0;
  bool _draggingFiles = false;
  bool get _anyUploading => _attachments.any((a) => a.uploading);
  static const int _maxAttachments = 5;
  bool _transcriptDirty = true;
  List<Widget>? _transcriptCache;
  final List<_UserMark> _userMarks = [];
  final Map<String, GlobalKey> _userMarkKeys = {};
  // Stream frame throttle: store the latest pending stream payload and flush
  // at most every 50ms to avoid rebuilding the full widget tree on every token.
  String _pendingLiveText = '';
  String _pendingLiveThinking = '';
  bool _pendingLiveTextVisible = false;
  Timer? _streamFlushTimer;
  // Auto-reconnect: backoff timer + attempt counter; _closed stops retries on leave.
  Timer? _reconnectTimer;
  Timer? _connectionWatchdog;
  int _reconnectAttempt = 0;
  bool _closed = false;
  // A message can silently die on a socket that looks alive (dropped network, no
  // onError/onDone) — it sits in _pending, shown as "sending", forever. Guard:
  // (1) a fresh connection resends anything still unacked against the authoritative
  // snapshot; (2) a watchdog forces a resync if _pending doesn't clear in time.
  bool _freshConn = false;
  Timer? _ackTimer;

  // An approve/deny/answer decision can die on a dead socket exactly like a
  // message — but it isn't in _pending, so the approval bar hangs at "Sending…"
  // forever. Track the last decision until the run leaves waiting_for_input;
  // resend it on reconnect and force a resync if it doesn't resolve.
  Map<String, dynamic>? _pendingDecision;
  Timer? _decisionTimer;

  // Force a fresh snapshot when an optimistic message hasn't been echoed in time —
  // the reconnect path then resends whatever the server truly never received.
  void _armAckWatchdog() {
    _ackTimer?.cancel();
    if (_closed || _pending.isEmpty) return;
    _ackTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted || _closed || _pending.isEmpty) return;
      final ch = _channel;
      if (ch != null) {
        _resync(ch); // tear down → fresh snapshot → unacked _pending resend
      }
    });
  }

  // Send an approve/deny/answer and hold it until the run acknowledges it (leaves
  // waiting_for_input). If it doesn't in time, the decision was lost — resync and
  // resend so the approval bar can't hang at "Sending…".
  void _sendDecision(Map<String, dynamic> m) {
    final k = m['kind'];
    final outbound = Map<String, dynamic>.from(m);
    if (k == 'approve' || k == 'approve_all' || k == 'deny' || k == 'answer') {
      // Decisions can be retried across reconnects too; give the retry the same
      // idempotency key instead of sending an untracked frame.
      outbound['nonce'] ??= _nextNonce();
      _pendingDecision = outbound;
      _decisionTimer?.cancel();
      _decisionTimer = Timer(const Duration(seconds: 6), () {
        if (!mounted || _closed || _pendingDecision == null) return;
        if (_state?.status == 'waiting_for_input') {
          final ch = _channel;
          if (ch != null) _resync(ch); // fresh snapshot → decision resend below
        }
      });
    }
    _send(outbound);
  }

  late String _title;
  // Tracks the last status so we can detect running → paused and flush _queued.
  String? _prevStatus;

  @override
  void initState() {
    super.initState();
    _title = widget.title;
    _lastInput = _input.text;
    _input.addListener(_interceptBigPaste);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onMacControls
            ?.call(() => _send({'kind': 'interrupt'}), _performMacAction);
      }
    });
    _playerStateSub = _audioPlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlayingRecording = state == PlayerState.playing;
        if (state == PlayerState.completed) {
          _isPlayingRecording = false;
          _playbackPosition = _playbackDuration;
        }
      });
    });
    _positionSub = _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) setState(() => _playbackPosition = position);
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) setState(() => _playbackDuration = duration);
    });
    _connect();
    _loadModel();
    _openKey = '${widget.client.baseUrl}|${widget.sessionId}';
    _registeredOpenKey = _openKey;
    reportOpenSession(_openKey);
  }

  @override
  void didUpdateWidget(covariant SessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId == widget.sessionId &&
        oldWidget.client.baseUrl == widget.client.baseUrl) {
      return;
    }
    // PageView normally keys each session, but a parent may reuse this State
    // while switching tabs. Never carry composer/upload state across sessions.
    // Invalidate completions from an upload started by the previous session.
    _attachmentGeneration++;
    if (mounted) {
      setState(() => _attachments.clear());
    } else {
      _attachments.clear();
    }
    _queued.clear();
    _queuedNonce.clear();
    _clearPendingAll();
    _input.clear();
    _lastInput = '';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Reconnect on resume ONLY if the socket actually died while backgrounded
    // (_scheduleReconnect nulls _channel). Unconditionally reconnecting tore
    // down a healthy socket and forced a full-snapshot reload + scroll jump
    // after even a momentary backgrounding. If the OS silently killed the
    // socket without an event, the next write fails → onError → reconnect.
    if (state == AppLifecycleState.resumed && !_closed) {
      if (_channel == null) {
        _reconnectAttempt = 0;
        _connect();
        // Re-sync the model label from the daemon after a real reconnect: it may
        // have changed while backgrounded (from the TUI or another device).
        _loadModel();
      }
      // Backgrounding cleared the suppression key (so notifications fire while
      // away); restore it — this session is visible again.
      _registeredOpenKey = _openKey;
      reportOpenSession(_openKey);
    }
  }

  Future<void> _loadModel() async {
    try {
      final cfg = await widget.client.getConfig();

      // Resolve which profile this session is on, most authoritative first:
      //   1. an in-session pick the user just made (optimistic, same screen);
      //   2. the daemon's live per-session override — the source of truth; it's
      //      persisted server-side and survives remount/resume/daemon restart;
      //   3. only if the daemon is unreachable, the value the session list
      //      handed us (which goes stale after a switch — that staleness is
      //      exactly what used to snap the header back to the global default).
      // A session with no override resolves to null → the global active profile
      // below. Reading the server, not the list cache, is what keeps a
      // per-chat model sticky when you leave and come back to the window.
      String? wanted = _currentProfile;
      if (wanted == null) {
        try {
          final list = await widget.client.sessions();
          var found = false;
          for (final s in list) {
            if (s.id == widget.sessionId) {
              wanted = s.profile; // null here means "uses the global default"
              found = true;
              break;
            }
          }
          if (!found) wanted = widget.profile;
        } catch (_) {
          wanted = widget.profile;
        }
      }

      ModelProfile? p;
      if (wanted != null) {
        for (final m in cfg.profiles) {
          if (m.name == wanted) {
            p = m;
            break;
          }
        }
      }
      if (p == null) {
        for (final m in cfg.profiles) {
          if (m.active) {
            p = m;
            break;
          }
        }
      }
      if (mounted) {
        setState(() {
          _modelLabel = p?.name;
        });
      }
    } catch (_) {}
  }

  void _connect() {
    if (_closed) return;
    _reconnectTimer?.cancel();
    _bannerTimer
        ?.cancel(); // suppress "Reconnecting…" if we reconnect before 60s
    // Fully detach the old socket first: cancel its subscription so its onDone
    // can't fire _scheduleReconnect against the NEW channel — that cascade
    // orphaned healthy sockets and double-applied every delta.
    _sub?.cancel();
    _sub = null;
    _connectionWatchdog?.cancel();
    _channel?.sink.close();
    if (mounted) setState(() => _connError = null);
    final ch = widget.client.attach(widget.sessionId);
    _channel = ch;
    _connectionWatchdog?.cancel();
    _connectionWatchdog = Timer(const Duration(seconds: 12), () {
      if (!_closed && identical(ch, _channel)) {
        _resync(ch);
      }
    });
    _sub = ch.stream.listen(
      (msg) {
        if (!identical(ch, _channel)) return; // stale socket — ignore
        _connectionWatchdog?.cancel();
        _connectionWatchdog = null;
        // Any frame means a healthy socket — reset backoff + clear the banner.
        if (_reconnectAttempt != 0 || _connError != null) {
          _reconnectAttempt = 0;
          if (mounted) setState(() => _connError = null);
        }
        // Flush sends queued while the socket was down, in order.
        if (_outbox.isNotEmpty) {
          for (final p in _outbox) {
            ch.sink.add(p);
          }
          _outbox.clear();
        }
        try {
          // web_socket_channel can deliver either a String or binary bytes for
          // the same text frame depending on platform/proxy. Casting only to
          // String throws, the catch resyncs forever, and the canvas stays empty.
          final raw = switch (msg) {
            final String s => s,
            final Uint8List b => utf8.decode(b, allowMalformed: true),
            final List<int> b => utf8.decode(b, allowMalformed: true),
            _ => '',
          };
          if (raw.isEmpty) return;
          final decoded = jsonDecode(raw);
          if (decoded is! Map) return;
          final j = decoded.cast<String, dynamic>();
          if (!mounted) return;
          // Only snapshot/delta carry HarnessState. Stream frames are live
          // token/thinking updates with no events — applying them via
          // fromJson wiped the transcript to empty until the next real state
          // frame (often only after a TUI-side persist).
          final wire = j['wire'] as String? ?? 'snapshot';
          if (wire == 'stream') {
            final text = (j['text'] as String?) ?? '';
            final thinking = (j['thinking'] as String?) ?? '';
            final visible = j['text_visible'] == true;
            if (!mounted) return;
            // Ignore non-empty stream while the run is idle/stopped — a late
            // frame after commit would re-show thinking/answer next to the
            // durable AssistantText (duplicate bubble + sticky reasoning).
            final status = _state?.status;
            final liveOk = status == null ||
                status == 'running' ||
                status == 'waiting_for_input' ||
                (text.isEmpty && thinking.isEmpty);
            if (!liveOk) {
              if (_liveText.isNotEmpty ||
                  _liveThinking.isNotEmpty ||
                  _liveTextVisible) {
                setState(() {
                  _liveText = '';
                  _liveThinking = '';
                  _liveTextVisible = false;
                });
              }
              return;
            }
            // Throttle stream frames: store latest payload and flush at most
            // every 50ms to avoid rebuilding the full widget tree on every token.
            _pendingLiveText = text;
            _pendingLiveThinking = thinking;
            _pendingLiveTextVisible = visible;
            if (_streamFlushTimer?.isActive ?? false) return;
            _streamFlushTimer =
                Timer(const Duration(milliseconds: 50), _flushStreamFrame);
            return;
          }
          if (wire != 'snapshot' && wire != 'delta') return;
          final cur = _state;
          final next = (wire == 'delta' && cur != null)
              ? cur.applyDelta(j)
              : HarnessState.fromJson(j);
          // Drift check: our event log must line up with the server's count — a
          // mismatch (dropped/bad frame) resyncs via reconnect, since a fresh
          // socket's first frame is always a full snapshot.
          final ec = j['event_count'];
          if (wire == 'delta' && ec is int && next.events.length != ec) {
            _resync(ch);
            return;
          }
          // A reversed transcript is anchored at offset 0 (latest). No initial
          // jump is needed; preserve whether the user has scrolled into history.
          final follow = _stickToBottom;
          // Auto-submit queued messages only when the run lands on IDLE. Flushing
          // on any running→non-running edge also fired into waiting_for_input,
          // where the queued text would "answer" the agent's own question. So
          // flush on ANY running→not-running edge EXCEPT waiting_for_input —
          // that covers idle (finished) AND interrupted (user paused/stopped the
          // run), which previously left the queue stranded.
          // Sent as a BURST of individual messages: the first opens the turn and
          // the rest fold in as steers before the first model call — the agent
          // sees the full set up front, while each message keeps its own frame
          // (and its own attachments) instead of being joined into one blob.
          if (_prevStatus == 'running' &&
              next.status != 'running' &&
              next.status != 'waiting_for_input' &&
              _queued.isNotEmpty) {
            for (var i = 0; i < _queued.length; i++) {
              final m = _queued[i];
              final nonce =
                  i < _queuedNonce.length ? _queuedNonce[i] : _nextNonce();
              _send({'kind': 'user_message', 'value': m, 'nonce': nonce},
                  tracked: true);
              _trackPending(m, nonce);
            }
            _queued.clear();
            _queuedNonce.clear();
          }
          _prevStatus = next.status;
          // A pending approval/answer is acknowledged the moment the run leaves
          // waiting_for_input — clear it so its watchdog can't fire a needless
          // resync (and so a resent decision isn't double-applied).
          if (next.status != 'waiting_for_input' && _pendingDecision != null) {
            _pendingDecision = null;
            _decisionTimer?.cancel();
          }
          // Retire optimistic bubbles once the daemon has echoed them:
          // 1) FIFO by echo-count delta (prev→next) when we have prior state
          // 2) by per-item baseline (covers missed delta / same-count snapshot)
          // 3) by normalized text match against the authoritative event log
          //    (every frame — not only snapshots — so stuck faint bubbles clear)
          final prevEchoes = cur == null ? null : _userEchoCount(cur.events);
          final nextEchoes = _userEchoCount(next.events);
          if (prevEchoes != null) {
            var retired = (nextEchoes - prevEchoes).clamp(0, _pending.length);
            while (retired-- > 0) {
              _popPendingFront();
            }
          } else if (wire != 'delta') {
            // first-ever snapshot: nothing optimistic predates it
            _clearPendingAll();
          }
          if (_pending.isNotEmpty) {
            _retirePendingByBaseline(nextEchoes);
            _retirePendingAlreadyEchoed(next.events);
          }
          // First full snapshot after a (re)connect is authoritative: anything
          // still in _pending was never received by the server — resend it with
          // the same nonce so the server deduplicates if it DID land.
          if (_freshConn && wire != 'delta') {
            _freshConn = false;
            for (var i = 0; i < _pending.length; i++) {
              final m = _pending[i];
              final nonce = i < _pendingNonce.length ? _pendingNonce[i] : null;
              final msg = nonce != null
                  ? {'kind': 'user_message', 'value': m, 'nonce': nonce}
                  : {'kind': 'user_message', 'value': m};
              try {
                ch.sink.add(jsonEncode(msg));
              } catch (_) {
                _outbox.add(jsonEncode(msg));
              }
            }
            // A decision still pending while the snapshot STILL shows the run
            // waiting means it never landed — resend it. (If it had landed, the
            // status/clear above already dropped it, so no double-approve.)
            if (_pendingDecision != null &&
                next.status == 'waiting_for_input') {
              final payload = jsonEncode(_pendingDecision);
              try {
                ch.sink.add(payload);
              } catch (_) {
                _outbox.add(payload);
              }
            }
          }
          // Only rebuild the transcript widget list when events actually
          // changed — status-only deltas waste a full transcript rebuild.
          final eventsChanged = cur == null ||
              identical(next.events, cur.events) ||
              next.events.length != cur.events.length ||
              (next.events.isNotEmpty &&
                  cur.events.isNotEmpty &&
                  next.events.last != cur.events.last);
          if (eventsChanged) _transcriptDirty = true;
          setState(() {
            _state = next;
            _title = next.title ?? widget.title;
            // Snapshot/delta commit durable events; drop the live answer so it
            // doesn't double-render against AssistantText once it lands.
            // Do not cancel the stream flush or wipe thinking on tool deltas —
            // those frames arrive between thinking tokens and made the thought
            // look truncated / frozen.
            if (wire == 'snapshot' || wire == 'delta') {
              _liveText = '';
              _liveTextVisible = false;
              if (next.status != 'running') {
                _liveThinking = '';
                _pendingLiveThinking = '';
                _streamFlushTimer?.cancel();
                _streamFlushTimer = null;
              }
            }
          });
          widget.onMacStatus?.call(next, next.status == 'running');
          widget.onMacControls
              ?.call(() => _send({'kind': 'interrupt'}), _performMacAction);
          // Re-arm (or cancel) the ack watchdog against the new _pending state.
          _armAckWatchdog();
          if (follow) _scheduleBottom();
        } catch (_) {
          // A frame we couldn't apply would silently corrupt the transcript —
          // resync instead of swallowing it.
          _resync(ch);
        }
      },
      onError: (_) => _scheduleReconnect(ch),
      onDone: () => _scheduleReconnect(ch),
      cancelOnError: true,
    );
  }

  // Tear down this socket and rejoin — the fresh connection opens with a full
  // snapshot, which reconciles any local drift.
  void _resync(WebSocketChannel ch) {
    if (!identical(ch, _channel)) return;
    ch.sink.close();
    _scheduleReconnect(ch);
  }

  // Reconnect with exponential backoff (1,2,4,8,15,30s). Deduped so onError+onDone
  // don't double-schedule; reset to 0 on any healthy frame or app-resume. Only the
  // CURRENT channel may schedule — a detached socket's late onDone is ignored.
  // The "Reconnecting…" banner is suppressed for the first 60s to avoid flicker
  // on brief network hiccups (WiFi→cellular, backgrounding, etc.).
  Timer? _bannerTimer;
  void _scheduleReconnect(WebSocketChannel ch) {
    if (_closed) return;
    if (!identical(ch, _channel)) return; // stale socket
    if (_reconnectTimer?.isActive ?? false) return; // already pending
    _channel = null;
    const steps = [1, 2, 4, 8, 15, 30];
    final delay = steps[_reconnectAttempt.clamp(0, steps.length - 1)];
    _reconnectAttempt++;
    // Delay the banner by 60s so brief disconnects don't flash a warning.
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 60), () {
      if (mounted && !_closed && _channel == null) {
        setState(() => _connError = 'Reconnecting…');
      }
    });
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      if (!_closed) _connect();
    });
  }

  // Stream frames may be a full buffer or a tailed snippet (`…\\n\\n` + last
  // N chars). Never shrink what we already show while the run is live.
  String _mergeLiveThinking(String prev, String next) {
    var incoming = next;
    if (incoming.startsWith('…')) {
      incoming = incoming.replaceFirst(RegExp(r'^…+\s*'), '');
    }
    if (incoming.isEmpty) return prev;
    if (prev.isEmpty) return incoming;
    if (incoming == prev) return prev;
    if (incoming.startsWith(prev)) return incoming;
    if (prev.startsWith(incoming)) return prev;
    if (incoming.contains(prev) && incoming.length >= prev.length) {
      return incoming;
    }
    if (prev.endsWith(incoming) || prev.contains(incoming)) return prev;
    // Overlapping tail/head (tailed snapshots) — grow instead of mash.
    final maxOverlap =
        prev.length < incoming.length ? prev.length : incoming.length;
    for (var n = maxOverlap; n >= 24; n--) {
      if (prev.endsWith(incoming.substring(0, n))) {
        return prev + incoming.substring(n);
      }
    }
    // New thought signature: replace the previous snapshot instead of appending.
    return incoming;
  }

  String? _latestCompactionDetail(List<Map<String, dynamic>> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e['type'] != 'system_decision') continue;
      final step = e['step']?.toString() ?? '';
      if (step == 'history_compaction_pass' ||
          step == 'history_compaction_skipped') {
        final r = e['reasoning']?.toString().trim() ?? '';
        return r.isEmpty ? null : r;
      }
    }
    return null;
  }

  // Throttled stream frame flush — called by the 50ms timer.
  void _flushStreamFrame() {
    if (_closed || !mounted) return;
    final text = _pendingLiveText;
    final thinking = _mergeLiveThinking(_liveThinking, _pendingLiveThinking);
    final visible = _pendingLiveTextVisible;
    setState(() {
      _liveText = text;
      _liveThinking = thinking;
      _liveTextVisible = visible;
    });
    if (_stickToBottom && (text.isNotEmpty || thinking.isNotEmpty)) {
      _scheduleBottom();
    }
  }

  // Whether to keep pinning to the latest message. Only the USER's own scrolling
  // flips this (see the NotificationListener) — content growth never does, so a
  // streaming reply keeps reaching the true bottom instead of falling behind.
  bool _stickToBottom = true;

  // In a reversed list, offset 0 is the latest message.
  bool _atBottom() {
    if (!_scroll.hasClients) return true;
    return _scroll.position.pixels <= 80;
  }

  // Update the stick flag from a user-driven scroll (drag or settle).
  bool _onScroll(ScrollNotification n) {
    final was = _stickToBottom;
    if (n is ScrollUpdateNotification && n.dragDetails != null) {
      _stickToBottom = _atBottom();
    } else if (n is ScrollEndNotification) {
      _stickToBottom = _atBottom();
    }
    // Repaint only on the pinned/unpinned EDGE — it toggles the floating
    // "jump to latest" button over the transcript.
    if (was != _stickToBottom && mounted) setState(() {});
    return false;
  }

  void _scheduleBottom({bool settle = false, bool smooth = false}) {
    if (!_scroll.hasClients) return;
    if (smooth) {
      _scroll.animateTo(0,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else if (_scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
  }

  // Send now, or queue for the reconnect flush — never silently drop.
  // For user messages (tracked in _pending), do NOT also add to _outbox:
  // _freshConn resend handles recovery, so adding to both would double-send.
  void _send(Map<String, dynamic> m, {bool tracked = false}) {
    final payload = jsonEncode(m);
    final ch = _channel;
    if (ch == null) {
      if (!tracked) _outbox.add(payload); // untracked messages use outbox
      return;
    }
    try {
      ch.sink.add(payload);
    } catch (_) {
      if (!tracked) _outbox.add(payload);
      _scheduleReconnect(ch);
    }
  }

  Future<void> _sendMessage() async {
    // The composer can be triggered by both the send button and keyboard submit;
    // serialize the entire async path so a rapid double tap cannot create two
    // distinct nonces and two server turns.
    if (_sendingMessage) return;
    _sendingMessage = true;
    try {
      await _sendMessageOnce();
    } finally {
      _sendingMessage = false;
    }
  }

  Future<void> _sendMessageOnce() async {
    // Audio can be sent directly from the composer: stop the live take, upload
    // it through the normal attachment path, then continue with the same send.
    if (_sendingAudio) return;
    if (_isRecording || _recordingPath != null) {
      _sendingAudio = true;
      if (mounted) setState(() {});
      try {
        if (_isRecording) await _stopRecording();
        if (_recordingPath != null && !await _confirmRecording()) return;
      } finally {
        _sendingAudio = false;
        if (mounted) setState(() {});
      }
    }
    // An upload still in flight would be silently DROPPED (only remotePath'd
    // attachments ship, then the list is cleared). The send button disables via
    // canSend, but keyboard submit bypassed it — guard here, the single choke point.
    if (_anyUploading) return;
    final t = _input.text.trim();
    final ready = _attachments.where((a) => a.remotePath != null).toList();
    if (t.isEmpty && ready.isEmpty) return;
    final running = _state?.status == 'running';
    // Reference each upload by its exact path so the agent reads it this turn.
    final markers = ready
        .map((a) => a.isImage
            ? '[attached image — call read_image on this exact path to view it: ${a.remotePath}]'
            : '[attached file — read it at this exact path: ${a.remotePath}]')
        .join('\n');
    final msg = markers.isEmpty ? t : (t.isEmpty ? markers : '$t\n\n$markers');
    final nonce = _nextNonce();
    setState(() {
      if (running) {
        // Queue by default — flushes when the run pauses. Reserve the nonce now
        // so a reconnect or screen disposal cannot turn one message into two.
        _queued.add(msg);
        _queuedNonce.add(nonce);
      } else {
        _send({'kind': 'user_message', 'value': msg, 'nonce': nonce},
            tracked: true);
        _trackPending(msg, nonce); // faint bubble until daemon echoes it
      }
      _attachments.clear();
    });
    _input.clear();
    _armAckWatchdog(); // recover if this send silently dies on a dead socket
    // Sending is an explicit action — re-pin and jump to the bottom.
    _stickToBottom = true;
    _scheduleBottom();
  }

  bool _isImageName(String n) {
    final l = n.toLowerCase();
    return const [
      '.png',
      '.jpg',
      '.jpeg',
      '.gif',
      '.webp',
      '.bmp',
      '.heic',
      '.heif'
    ].any(l.endsWith);
  }

  // `+` tapped: desktop opens a file picker directly; mobile shows a small
  // Camera / Photos / Files sheet.
  Future<void> _onAttachTap() async {
    if (_maxAttachments - _attachments.length <= 0) {
      _toast('Up to $_maxAttachments attachments.');
      return;
    }
    if (!kMobile) {
      _pickFiles();
      return;
    }
    final choice = await showAppSheet<String>(context,
        title: 'Add context',
        child: Row(children: [
          _ctxOption('camera', 'Camera', 'camera'),
          const SizedBox(width: 10),
          _ctxOption('image', 'Photos', 'photos'),
          const SizedBox(width: 10),
          _ctxOption('file', 'Files', 'files'),
        ]));
    if (choice == 'camera') {
      _pickCamera();
    } else if (choice == 'photos') {
      _pickPhotos();
    } else if (choice == 'files') {
      _pickFiles();
    }
  }

  Future<void> _onMicTap() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  static const _maxRecordingDuration = Duration(minutes: 3);

  Future<void> _startRecording() async {
    if (!kCanRecord) return;
    // Flip the UI first so the tap feels instant; permission + encoder
    // setup still happen before audio is captured.
    if (mounted) {
      setState(() {
        _isRecording = true;
        _recordingElapsed = Duration.zero;
        _waveform
          ..clear()
          ..add(0.08);
      });
    }
    final granted = kMobile
        ? (await Permission.microphone.request()).isGranted
        : await _recorder.hasPermission();
    if (!granted) {
      if (mounted) setState(() => _isRecording = false);
      _toast(kMobile
          ? 'Microphone permission is required.'
          : 'Microphone permission is required by macOS.');
      if (kMobile) {
        final status = await Permission.microphone.status;
        if (status.isPermanentlyDenied) await openAppSettings();
      }
      return;
    }
    try {
      // Starting a new take replaces an unconfirmed take only after the user
      // explicitly chose to record again.
      if (_recordingPath != null) await _discardRecording();
      final tempDir = await getTemporaryDirectory();
      final path =
          '${tempDir.path}/snippet-voice-${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!await _recorder.isRecording()) {
        if (mounted) setState(() => _isRecording = false);
        _toast('Could not start recording.');
        return;
      }
      _amplitudeSub?.cancel();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 120))
          .listen((a) {
        final level = ((a.current + 60) / 60).clamp(0.04, 1.0).toDouble();
        if (!mounted) return;
        setState(() {
          _waveform.add(level);
          // Keep a denser rolling waveform so the bars stay close together
          // when the strip spans the full composer width.
          if (_waveform.length > 180) _waveform.removeAt(0);
        });
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        final next = _recordingElapsed + const Duration(seconds: 1);
        if (next >= _maxRecordingDuration) {
          setState(() => _recordingElapsed = _maxRecordingDuration);
          unawaited(_stopRecording());
          _toast('Recording stopped at the 3-minute limit.');
        } else {
          setState(() => _recordingElapsed = next);
        }
      });
      if (mounted) setState(() => _recordingPath = path);
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      _toast('Could not start recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    if (mounted) setState(() => _isRecording = false);
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      final stoppedPath = await _recorder.stop();
      final path = stoppedPath ?? _recordingPath;
      if (path == null) {
        _toast('No recording was captured.');
        return;
      }
      final file = File(path);
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        await _discardRecording();
        _toast('The recording was empty.');
        return;
      }
      if (mounted) setState(() => _recordingPath = path);
    } catch (e) {
      _toast('Could not finish recording: $e');
    }
  }

  Future<void> _toggleRecordingPlayback() async {
    final path = _recordingPath;
    if (path == null || _isRecording) return;
    try {
      if (_isPlayingRecording) {
        await _audioPlayer.pause();
      } else if (_audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
      } else {
        await _audioPlayer.play(DeviceFileSource(path));
      }
    } catch (e) {
      _toast('Could not play recording: $e');
    }
  }

  bool _confirmingRecording = false;
  Future<bool> _confirmRecording() async {
    final path = _recordingPath;
    if (path == null || _isRecording || _confirmingRecording) return false;
    _confirmingRecording = true;
    // Clear path IMMEDIATELY (synchronously) to prevent a second concurrent
    // call from the recording panel's confirm button racing through the guard.
    _recordingPath = null;
    try {
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) {
        await _discardRecording();
        _toast('The recording was empty.');
        return false;
      }
      await _ingest([
        (
          name: 'voice-${DateTime.now().microsecondsSinceEpoch}.m4a',
          localPath: path,
          readBytes: () async => bytes,
        )
      ]);
      await _audioPlayer.stop();
      final file = File(path);
      if (await file.exists()) await file.delete();
      if (mounted)
        setState(() {
          _waveform.clear();
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
          _isPlayingRecording = false;
        });
      return true;
    } catch (e) {
      _toast('Could not attach recording: $e');
      return false;
    } finally {
      _confirmingRecording = false;
    }
  }

  Future<void> _discardRecording() async {
    final path = _recordingPath;
    _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    try {
      await _audioPlayer.stop();
    } catch (_) {}
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _isRecording = false;
        _recordingPath = null;
        _recordingElapsed = Duration.zero;
        _playbackPosition = Duration.zero;
        _playbackDuration = Duration.zero;
        _waveform.clear();
        _isPlayingRecording = false;
      });
    }
  }

  String _audioTime(Duration d) {
    final seconds = d.inSeconds.clamp(0, 5999);
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Widget _recordingPanel() {
    final reviewing = !_isRecording && _recordingPath != null;
    final position = reviewing ? _playbackPosition : _recordingElapsed;
    final samples = List<double>.of(_waveform);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Row(children: [
        IconBtn(
          reviewing ? (_isPlayingRecording ? 'pause' : 'play') : 'stop',
          size: 36,
          iconSize: 19,
          active: _isRecording || _isPlayingRecording,
          tooltip: _isRecording
              ? 'Stop and review'
              : (_isPlayingRecording ? 'Pause' : 'Play recording'),
          onTap: _isRecording ? _stopRecording : _toggleRecordingPlayback,
        ),
        const SizedBox(width: 8),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 34,
              child: CustomPaint(painter: _WaveformPainter(samples)),
            ),
            const SizedBox(height: 3),
            Row(children: [
              Text(_isRecording ? 'Recording' : 'Voice note',
                  style: sans(11,
                      color: _isRecording ? AppColors.accent : AppColors.fg3)),
              const Spacer(),
              Text(_audioTime(position), style: mono(11, color: AppColors.fg3)),
            ]),
          ]),
        ),
        const SizedBox(width: 6),
        if (reviewing) ...[
          IconBtn('trash',
              size: 36,
              iconSize: 18,
              tooltip: 'Discard recording',
              onTap: _discardRecording),
          const SizedBox(width: 2),
          IconBtn('check',
              size: 36,
              iconSize: 19,
              active: true,
              tooltip: 'Use recording',
              onTap: _confirmRecording),
        ],
      ]),
    );
  }

  Widget _ctxOption(String icon, String label, String value) {
    return Expanded(
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.md),
          onTap: () => Navigator.pop(context, value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(children: [
              AppIcon(icon, size: 22, color: AppColors.fg2),
              const SizedBox(height: 8),
              Text(label, style: sans(12, color: AppColors.fg1)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFiles() async {
    List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(type: FileType.any);
    } catch (e) {
      _toast('$e');
      return;
    }
    if (files.isEmpty) return;
    await _ingest(files
        .map((f) => (
              name: f.name,
              localPath: f.path,
              readBytes: f.readAsBytes,
            ))
        .toList());
  }

  Future<void> _pickPhotos() async {
    final xs =
        await ImagePicker().pickMultiImage(imageQuality: 85, maxWidth: 2200);
    if (xs.isEmpty) return;
    await _ingest(xs
        .map((x) => (name: x.name, localPath: x.path, readBytes: x.readAsBytes))
        .toList());
  }

  Future<void> _pickCamera() async {
    final x = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 85, maxWidth: 2200);
    if (x == null) return;
    await _ingest(
        [(name: x.name, localPath: x.path, readBytes: x.readAsBytes)]);
  }

  // Create attachment chips for the picked items (capped to 10 total) and upload each.
  Future<void> _ingest(
      List<
              ({
                String name,
                String? localPath,
                Future<Uint8List> Function() readBytes
              })>
          picked) async {
    final remaining = _maxAttachments - _attachments.length;
    if (remaining <= 0) return;
    var items = picked;
    if (items.length > remaining) {
      items = items.take(remaining).toList();
      _toast('Added $remaining (max $_maxAttachments).');
    }
    final entries = items
        .map((p) => _Attachment(
            name: p.name,
            isImage: _isImageName(p.name),
            isAudio: isAudioAttachmentPath(p.name),
            localPath: p.localPath))
        .toList();
    if (entries.isEmpty) return;
    setState(() => _attachments.addAll(entries));
    final generation = _attachmentGeneration;
    for (var i = 0; i < entries.length; i++) {
      final p = items[i];
      final a = entries[i];
      try {
        final bytes = await p.readBytes();
        final path = await widget.client.uploadFile(bytes, name: p.name);
        if (!mounted || generation != _attachmentGeneration) return;
        setState(() {
          a.remotePath = path;
          a.uploading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() => _attachments.remove(a));
        _toast('upload failed: ${p.name}');
      }
    }
  }

  // Held messages were never sent to the daemon — drop them locally only.
  // (Daemon `drop_queued` is only for inputs already in pending_inputs.)
  void _cancelQueuedAt(int i) => setState(() {
        if (i >= 0 && i < _queued.length) {
          _queued.removeAt(i);
          if (i < _queuedNonce.length) _queuedNonce.removeAt(i);
        }
      });

  // Steer: send a queued message immediately while the agent is still running.
  void _steerQueuedAt(int i) {
    if (i < 0 || i >= _queued.length) return;
    final msg = _queued.removeAt(i);
    // Preserve the nonce reserved when the message was created. Reassigning a
    // new nonce here misaligns every later queued item after a steer/cancel.
    final nonce =
        i < _queuedNonce.length ? _queuedNonce.removeAt(i) : _nextNonce();
    _send({'kind': 'user_message', 'value': msg, 'nonce': nonce},
        tracked: true);
    setState(() {
      _trackPending(msg, nonce);
    });
    _armAckWatchdog();
  }

  // Clean text for a held/pending message (markers stripped). Attachments
  // surface as AttachmentPill beside the text — same as a real Bubble.
  String _queuedText(String m) => hideAttachmentMarkers(m);

  (int audio, int images, int files) _queuedAttachCounts(String m) {
    final matches =
        RegExp(r'\[attached (image|file) —([^\]]*)\]').allMatches(m);
    final audio =
        matches.where((x) => isAudioAttachmentPath(x.group(2) ?? '')).length;
    final images = matches.where((x) => x.group(1) == 'image').length;
    return (audio, images, matches.length - images - audio);
  }

  void _toast(String m) {
    if (mounted) toast(context, m);
  }

  Future<void> _disposeRecorder() async {
    try {
      if (_isRecording) await _recorder.cancel();
    } catch (_) {}
    final pendingPath = _recordingPath;
    if (pendingPath != null) {
      try {
        final file = File(pendingPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    try {
      if (kCanRecord) {
        await _recorder.dispose();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _closed = true;
    _reconnectTimer?.cancel();
    _connectionWatchdog?.cancel();
    _ackTimer?.cancel();
    _decisionTimer?.cancel();
    _streamFlushTimer?.cancel();
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Only clear the suppression key if this screen still owns it — on a session
    // switch the NEW screen registers before this dispose runs, and clobbering
    // its key made notifications fire for the session being viewed.
    if (_registeredOpenKey == _openKey) {
      _registeredOpenKey = '';
      reportOpenSession('');
    }
    // Flush anything still queued so leaving the chat doesn't lose it — the daemon
    // queues it server-side (pending_inputs) and applies it on the next turn. Give
    // the frames a moment to flush before tearing the socket down.
    final ch = _channel;
    if ((_queued.isNotEmpty || _outbox.isNotEmpty) && ch != null) {
      for (final p in _outbox) {
        ch.sink.add(p);
      }
      _outbox.clear();
      for (var i = 0; i < _queued.length; i++) {
        final m = _queued[i];
        final nonce = i < _queuedNonce.length ? _queuedNonce[i] : _nextNonce();
        ch.sink.add(jsonEncode({
          'kind': 'user_message',
          'value': m,
          'nonce': nonce,
        }));
      }
      _queued.clear();
      _queuedNonce.clear();
      Future.delayed(const Duration(milliseconds: 300), () => ch.sink.close());
    } else {
      ch?.sink.close();
    }
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    _amplitudeSub?.cancel();
    _recordingTimer?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    unawaited(_audioPlayer.dispose());
    unawaited(_disposeRecorder());
    super.dispose();
  }

  bool _pendingApproval(List<Map<String, dynamic>> events) =>
      _pendingApprovalTotal(events) > 0;

  // How many tool calls this batch is awaiting approval (0 = none pending). Drives
  // whether "Approve all" is shown — it only makes sense with more than one.
  int _pendingApprovalTotal(List<Map<String, dynamic>> events) {
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      final k = e['kind'];
      if (k == 'approval_request') return (e['total'] as num?)?.toInt() ?? 1;
      if (k == 'tool_result' || k == 'assistant_text') return 0;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // Depend on Theme so this rebuilds when the user switches palettes.
    Theme.of(context);
    final s = _state;
    final status = s?.status ?? 'connecting';
    final running = status == 'running';
    final waiting = status == 'waiting_for_input';
    final events = s?.events ?? const [];
    if (_transcriptDirty || _transcriptCache == null) {
      _transcriptCache = _transcript(events);
      _transcriptDirty = false;
    }
    final items = _transcriptCache!;
    final scaffold = Scaffold(
      backgroundColor: readingBg,
      body: SafeArea(
        bottom: false,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (kMobile)
            _mobileHeader(s, running, waiting)
          else if (!kMacOS)
            _desktopBar(s, running),
          // Desktop keeps the detailed chip strip.
          if (!kMobile && !kMacOS) _statusStrip(s, running),
          if (_connError != null) _disconnectedBanner(),
          if (s?.goal?.ongoing == true)
            _centerWide(Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: _GoalCard(
                goal: s!.goal!,
                onCancel: _cancelGoal,
              ),
            )),
          Expanded(
            child: Stack(children: [
              s == null
                  ? Center(
                      child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.fg3)))
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onScroll,
                      child: Builder(builder: (context) {
                        final timeline = <Widget>[
                          if (items.isEmpty && !running)
                            const EmptyState(
                                icon: 'terminal',
                                title: 'Session ready',
                                body: 'Send a task to get started.'),
                          ...items,
                          // Optimistic bubbles for messages sent but not yet echoed.
                          for (var pi = 0; pi < _pending.length; pi++)
                            Opacity(
                                key: ValueKey(
                                    'pending-$pi-${_pending[pi].hashCode}'),
                                opacity: 0.5,
                                child: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Bubble(
                                        mine: true,
                                        text: _pending[pi],
                                        selectable: false))),
                          if (_liveTextVisible && _liveText.trim().isNotEmpty)
                            Padding(
                              key: const ValueKey('live-text'),
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Bubble(
                                  mine: false,
                                  text: _liveText.trim(),
                                  selectable: false),
                            ),
                          if (s.compacting) ...[
                            const SizedBox(height: 10),
                            _CompactingStatus(
                              detail: _latestCompactionDetail(events),
                            ),
                          ] else if (running) ...[
                            const SizedBox(height: 10),
                            _ChurningStatus(thinking: _liveThinking),
                          ],
                          if (_queued.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            for (var qi = 0; qi < _queued.length; qi++)
                              KeyedSubtree(
                                key: ValueKey(
                                    'queued-$qi-${_queued[qi].hashCode}'),
                                child: _QueuedBubble(
                                  text: _queuedText(_queued[qi]),
                                  audio: _queuedAttachCounts(_queued[qi]).$1,
                                  images: _queuedAttachCounts(_queued[qi]).$2,
                                  files: _queuedAttachCounts(_queued[qi]).$3,
                                  onCancel: () => _cancelQueuedAt(qi),
                                  onSteer: () => _steerQueuedAt(qi),
                                ),
                              ),
                          ],
                        ];
                        return ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                          itemCount: timeline.length,
                          itemBuilder: (context, index) => _centerWide(
                            RepaintBoundary(
                              child: timeline[timeline.length - 1 - index],
                            ),
                          ),
                        );
                      })),
              // Floating "jump to latest": scrolling up unpins auto-follow, and a
              // streaming reply then grows silently — give a one-tap way back.
              if (!kMobile && _userMarks.length >= 2)
                Positioned(
                  top: 10,
                  right: 6,
                  bottom: 10,
                  child: _MessageJumpRail(
                    marks: List<_UserMark>.from(_userMarks),
                    onJump: _jumpToUserMark,
                  ),
                ),
              if (!_stickToBottom && s != null)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: Material(
                    color: AppColors.surface1,
                    shape: const CircleBorder(),
                    elevation: 0,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        _stickToBottom = true;
                        setState(() {});
                        _scheduleBottom(settle: true, smooth: true);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: AppIcon('chevron-down',
                            size: 16, color: AppColors.fg3),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          // The question/approval bars are PINNED here (not inside the scroll
          // list) so a "needs input" request is always visible — buried at the
          // bottom of a scrolled-up transcript it read as "the agent is stuck".
          if (waiting && _pendingApproval(events))
            _centerWide(Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: _ApprovalBar(
                  onSend: _sendDecision,
                  showApproveAll: _pendingApprovalTotal(events) > 1),
            ))
          else if (waiting && s?.pendingQuestion != null)
            _centerWide(Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: _QuestionBar(
                  question: s!.pendingQuestion!, onSend: _sendDecision),
            )),
          if (!(waiting &&
              (_pendingApproval(events) || s?.pendingQuestion != null)))
            _centerWide(_inputBar(running)),
        ]),
      ),
    );
    return kMacOS
        ? DropTarget(
            enable: widget.acceptDrops,
            onDragEntered: (_) {
              if (!widget.acceptDrops) return;
              setState(() => _draggingFiles = true);
            },
            onDragExited: (_) {
              if (!widget.acceptDrops) return;
              setState(() => _draggingFiles = false);
            },
            onDragDone: _ingestDroppedFiles,
            child: scaffold,
          )
        : scaffold;
  }

  void _jumpToUserMark(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    _stickToBottom = false;
    if (mounted) setState(() {});
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.18,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _renameCurrent() async {
    final title = await promptText(context,
        title: 'Rename session',
        initial: _title,
        hint: 'New title',
        saveLabel: 'Rename');
    if (title == null) return;
    try {
      await widget.client.renameSession(widget.sessionId, title);
      if (mounted) setState(() => _title = title);
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  // On desktop, keep chat content to a comfortable reading width (centered),
  // rather than stretching across the whole pane.
  Widget _centerWide(Widget child) => widget.embedded
      ? Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820), child: child))
      : child;

  // Mobile chat header: a back button that returns to the session list, the
  // title with a live status dot, and a compact subtitle folding in the key
  // facts (status · model · context · approval) — so there's no separate,
  // cramped desktop toolbar + scrolling chip strip on a phone.
  Widget _mobileHeader(HarnessState? s, bool running, bool waiting) {
    final compacting = s?.compacting ?? false;
    final statusWord = compacting
        ? 'Compacting history…'
        : (waiting ? 'Needs input' : (running ? 'Running' : 'Idle'));
    // Keep the model selector in the composer, where it is always visible.
    final facts = <String>[statusWord];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      decoration: BoxDecoration(color: readingBg),
      child: Row(children: [
        Expanded(
          child: InkWell(
            onTap: () => _openActions(s),
            borderRadius: BorderRadius.circular(R.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_title.isEmpty ? 'session' : _title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(17,
                            weight: FontWeight.w600, color: AppColors.fg1)),
                    const SizedBox(height: 3),
                    Text(facts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ]),
            ),
          ),
        ),
        if (running)
          IconBtn('stop',
              tooltip: 'Stop', onTap: () => _send({'kind': 'interrupt'})),
      ]),
    );
  }

  // macOS keeps this row focused on the active session title. Workspace
  // context and Git actions live in the clickable repository bar above.
  Widget _desktopBar(HarnessState? s, bool running) {
    final mac = kMacOS;
    final title = _title.isEmpty ? 'session' : _title;
    return Container(
      height: mac ? 42 : 50,
      padding: EdgeInsets.symmetric(horizontal: mac ? 16 : 8),
      decoration: BoxDecoration(
        color: mac ? AppColors.surface1 : readingBg,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (!mac && widget.onMenu != null) ...[
          IconBtn('sidebar',
              size: 30, iconSize: 16, tooltip: 'Sidebar', onTap: widget.onMenu),
          const SizedBox(width: 4),
        ] else if (!mac)
          const SizedBox(width: 2),
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(mac ? 13.5 : 16.5,
                  weight: FontWeight.w500, color: AppColors.fg1)),
        ),
        if (mac && running)
          IconBtn('stop',
              size: 30,
              iconSize: 15,
              tooltip: 'Stop',
              onTap: () => _send({'kind': 'interrupt'})),
        if (mac)
          IconBtn('more-horizontal',
              size: 30,
              iconSize: 17,
              tooltip: 'More',
              onTap: () => _openActions(s)),
        if (!mac && running)
          IconBtn('stop',
              size: 32,
              iconSize: 16,
              tooltip: 'Stop',
              onTap: () => _send({'kind': 'interrupt'})),
        if (!mac) _menu(s),
      ]),
    );
  }

  Widget _menu(HarnessState? s) {
    final view = View.of(context);
    final desktop =
        view.physicalSize.width / view.devicePixelRatio >= kDesktopBreakpoint;
    if (!desktop) {
      return IconBtn('more-vertical',
          tooltip: 'Actions', onTap: () => _openActions(s));
    }
    return PopupMenuButton<VoidCallback>(
      color: AppColors.surface1,
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 260),
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.md),
          side: BorderSide(color: AppColors.border2)),
      icon: AppIcon('more-vertical', color: AppColors.fg2),
      tooltip: 'Actions',
      onSelected: (fn) => fn(),
      itemBuilder: (_) => _actionItems(s),
    );
  }

  // Set an autonomous /goal: the agent drives toward it on its own until it's
  // done, you cancel, or it's rate-limited. Sent as a LoopInput over the socket.
  Future<void> _setGoal() async {
    final text = await promptText(context,
        title: 'Set an autonomous goal',
        hint: 'What should the agent work toward on its own?',
        saveLabel: 'Set goal');
    final t = text?.trim();
    if (t == null || t.isEmpty) return;
    _send({'kind': 'set_goal', 'value': t});
    _toast('Goal set — the agent will drive toward it');
  }

  void _cancelGoal() {
    _send({'kind': 'cancel_goal'});
    _toast('Cancelling the goal');
  }

  void _performMacAction(String action) {
    final s = _state;
    switch (action) {
      case 'rename':
        _renameCurrent();
        return;
      case 'model':
        _switchModel(context);
        return;
      case 'approval':
        final manual = (s?.approvalMode ?? 'auto') == 'manual';
        _send({'kind': 'set_mode', 'value': manual ? 'auto' : 'manual'});
        _toast(manual ? 'Approval: auto' : 'Approval: ask');
        return;
      case 'goal':
        if (s?.goal?.ongoing ?? false) {
          _cancelGoal();
        } else {
          _setGoal();
        }
        return;
      case 'lanes':
        _showLanes();
        return;
      case 'files':
        final ws = s?.workspace ?? '';
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
        return;
      case 'command':
        _showExec();
        return;
      case 'processes':
        presentScreen(context,
            builder: (_, close) => ProcessesScreen(
                client: widget.client,
                sessionId: widget.sessionId,
                onClose: close));
        return;
      case 'compact':
        _send({'kind': 'compact'});
        _toast('Compacting history');
        return;
      case 'checkpoints':
        _showCheckpoints();
        return;
      case 'usage':
        _showUsage();
        return;
    }
  }

  List<PopupMenuEntry<VoidCallback>> _actionItems(HarnessState? s) {
    final manual = (s?.approvalMode ?? 'auto') == 'manual';
    final ws = s?.workspace ?? '';
    PopupMenuItem<VoidCallback> item(String icon, String label, VoidCallback fn,
            {String? value}) =>
        PopupMenuItem<VoidCallback>(
          value: fn,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(children: [
            AppIcon(icon, size: 14, color: AppColors.fg2),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label, style: sans(12.5, color: AppColors.fg1))),
            if (value != null)
              Text(value, style: mono(11, color: AppColors.fg4)),
          ]),
        );
    return [
      item('edit', 'Rename session', _renameCurrent),
      item('shield', 'Approval mode', () {
        _send({'kind': 'set_mode', 'value': manual ? 'auto' : 'manual'});
        _toast(manual ? 'Approval: auto' : 'Approval: ask');
      }, value: manual ? 'Ask' : 'Auto'),
      (s?.goal?.ongoing ?? false)
          ? item('zap', 'Cancel goal', _cancelGoal,
              value: s!.goal!.paused ? 'paused' : 'running')
          : item('zap', 'Set goal', _setGoal),
      if ((s?.lanes.isNotEmpty ?? false))
        item('layers', 'Lanes', _showLanes,
            value: '${s!.lanes.where((l) => l.running).length} running'),
      const PopupMenuDivider(),
      item(
          'git-branch',
          'Git',
          () => presentScreen(context,
              builder: (_, close) => GitScreen(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  onClose: close))),
      item('folder', 'Browse', () {
        final name = lastPathSegment(ws, ifEmpty: 'Files');
        presentScreen(context,
            builder: (_, close) => FileExplorer(
                client: widget.client,
                title: name,
                start: ws.isEmpty ? null : ws,
                onClose: close,
                onOpenFile: widget.onOpenFileTab));
      }),
      item('terminal', 'Run command', _showExec),
      item(
          'list',
          'Processes',
          () => presentScreen(context,
              builder: (_, close) => ProcessesScreen(
                  client: widget.client,
                  sessionId: widget.sessionId,
                  onClose: close))),
      const PopupMenuDivider(),
      item('minimize', 'Compact history', () {
        _send({'kind': 'compact'});
        _toast('Compacting history');
      }),
      item('history', 'Checkpoints', _showCheckpoints),
      item('activity', 'Usage', _showUsage),
    ];
  }

  void _openActions(HarnessState? s) {
    final manual = (s?.approvalMode ?? 'auto') == 'manual';
    final ws = s?.workspace ?? '';
    void run(VoidCallback f) {
      Navigator.pop(context);
      f();
    }

    showAppSheet(context,
        title: 'Actions',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionLabel('Session'),
            _actionTile('edit', 'Rename session',
                onTap: () => run(_renameCurrent)),
            if (!kMacOS)
              _actionTile('shield', 'Approval mode',
                  value: manual ? 'Ask' : 'Auto',
                  onTap: () => run(() {
                        _send({
                          'kind': 'set_mode',
                          'value': manual ? 'auto' : 'manual'
                        });
                        _toast(manual ? 'Approval: auto' : 'Approval: ask');
                      })),
            if (!kMacOS)
              (s?.goal?.ongoing ?? false)
                  ? _actionTile('zap', 'Cancel goal',
                      value: s!.goal!.paused ? 'paused' : 'running',
                      onTap: () => run(_cancelGoal))
                  : _actionTile('zap', 'Set goal', onTap: () => run(_setGoal)),
            if (!kMacOS && (s?.lanes.isNotEmpty ?? false))
              _actionTile('layers', 'Lanes',
                  value: '${s!.lanes.where((l) => l.running).length} running',
                  onTap: () => run(_showLanes)),
            const SizedBox(height: 12),
            const SectionLabel('Workspace'),
            if (!kMacOS)
              _actionTile('git-branch', 'Git',
                  onTap: () => run(() => presentScreen(context,
                      builder: (_, close) => GitScreen(
                          client: widget.client,
                          sessionId: widget.sessionId,
                          onClose: close)))),
            _actionTile('folder', 'Open files',
                onTap: () => run(() {
                      final name = lastPathSegment(ws, ifEmpty: 'Files');
                      presentScreen(context,
                          builder: (_, close) => FileExplorer(
                              client: widget.client,
                              title: name,
                              start: ws.isEmpty ? null : ws,
                              onClose: close,
                              onOpenFile: widget.onOpenFileTab));
                    })),
            _actionTile('terminal', 'Run command', onTap: () => run(_showExec)),
            _actionTile('list', 'Processes',
                onTap: () => run(() => presentScreen(context,
                    builder: (_, close) => ProcessesScreen(
                        client: widget.client,
                        sessionId: widget.sessionId,
                        onClose: close)))),
            const SizedBox(height: 12),
            const SectionLabel('History'),
            _actionTile('minimize', 'Compact history',
                onTap: () => run(() {
                      _send({'kind': 'compact'});
                      _toast('Compacting history');
                    })),
            _actionTile('history', 'Checkpoints',
                onTap: () => run(_showCheckpoints)),
            _actionTile('activity', 'Usage', onTap: () => run(_showUsage)),
            const SizedBox(height: 4),
          ],
        ));
  }

  Widget _actionTile(String icon, String label,
      {String? value, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(R.sm)),
                child: AppIcon(icon, size: 15, color: AppColors.fg2),
              ),
              const SizedBox(width: 11),
              Expanded(
                  child: Text(label, style: sans(13, color: AppColors.fg1))),
              if (value != null)
                Text(value, style: mono(11, color: AppColors.fg3)),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _statusChips(HarnessState? s, bool running) {
    final chips = <Widget>[
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                color: running ? AppColors.run : AppColors.fg2,
                shape: BoxShape.circle)),
        const SizedBox(width: 7),
        Text(
            s?.compacting == true
                ? 'Compacting'
                : (running ? 'Running' : 'Idle'),
            style: sans(12.5,
                weight: FontWeight.w600,
                color: s?.compacting == true
                    ? AppColors.accent
                    : (running ? AppColors.run : AppColors.fg2))),
      ]),
    ];
    if (s != null && s.workspace.isNotEmpty) {
      chips.add(_StatMeta(
          icon: 'folder',
          label: lastPathSegment(s.workspace, ifEmpty: s.workspace)));
    }
    if (s != null) {
      if (s.contextWindow > 0 && s.lastPromptTokens > 0) {
        chips.add(_StatMeta(
            icon: 'activity',
            label:
                '${(s.lastPromptTokens / s.contextWindow * 100).clamp(0, 999).round()}% ctx'));
      }
      if (s.totalTokens > 0) {
        chips.add(_StatMeta(icon: 'zap', label: '${fmtSi(s.totalTokens)} tok'));
      }
      chips.add(_StatMeta(
          icon: 'shield',
          label: s.approvalMode == 'auto' ? 'Auto-approve' : 'Ask',
          tone: s.approvalMode == 'auto' ? 'accent' : 'default'));
      // Show for any provider that reported limits.
      final rp = s.ratePrimary;
      if (rp != null) {
        chips.add(_StatMeta(
            icon: 'clipboard',
            label:
                '${rateWindowLabel(rp.windowMinutes)} · ${rp.leftPercent.round()}%',
            tone: 'run'));
      }
    }
    return chips;
  }

  Widget _statusStrip(HarnessState? s, bool running) {
    final chips = _statusChips(s, running);
    return Container(
      height: 44,
      decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border(bottom: BorderSide(color: AppColors.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            chips[i]
          ],
        ]),
      ),
    );
  }

  Widget _disconnectedBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
          color: AppColors.dangerBg,
          border: Border(
              bottom:
                  BorderSide(color: AppColors.danger.withValues(alpha: 0.25)))),
      child: Row(children: [
        AppIcon('wifi-off', size: 15, color: AppColors.danger),
        const SizedBox(width: 9),
        Expanded(
            child: Text(
                _outbox.isEmpty
                    ? (_connError ?? 'Disconnected')
                    : '${_connError ?? 'Disconnected'} · ${_outbox.length} message${_outbox.length == 1 ? '' : 's'} will send on reconnect',
                style: sans(12, height: 1.3, color: AppColors.fg1))),
        GestureDetector(
          onTap: () {
            _reconnectAttempt = 0;
            _connect();
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('refresh', size: 13, color: AppColors.danger),
            const SizedBox(width: 5),
            Text('Retry now',
                style:
                    sans(12, weight: FontWeight.w600, color: AppColors.danger)),
          ]),
        ),
      ]),
    );
  }

  // Live send-enabled check — read at tap/submit time and inside the
  // ValueListenableBuilder below, so typing never has to setState the screen.
  bool get _canSend =>
      (_isRecording ||
          _recordingPath != null ||
          _input.text.trim().isNotEmpty ||
          _attachments.any((a) => a.remotePath != null)) &&
      !_anyUploading &&
      !_sendingAudio;

  Future<void> _ingestDroppedFiles(DropDoneDetails details) async {
    if (!kMacOS || !widget.acceptDrops) return;
    setState(() => _draggingFiles = false);
    final files = details.files.whereType<DropItemFile>().map((item) {
      final bookmark = item.extraAppleBookmark;
      return (
        name: item.name,
        localPath: item.path,
        readBytes: () async {
          var accessed = false;
          try {
            if (bookmark != null && bookmark.isNotEmpty) {
              accessed = await DesktopDrop.instance
                  .startAccessingSecurityScopedResource(bookmark: bookmark);
            }
            return await item.readAsBytes();
          } finally {
            if (accessed) {
              await DesktopDrop.instance
                  .stopAccessingSecurityScopedResource(bookmark: bookmark!);
            }
          }
        },
      );
    }).toList();
    await _ingest(files);
  }

  Widget _inputBar(bool running) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 8, 20, 10 + MediaQuery.of(context).padding.bottom),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_attachments.isNotEmpty) _attachmentBar(),
            if (_isRecording || _recordingPath != null) _recordingPanel(),
            Container(
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(R.card),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.fromLTRB(18, 20, 12, 14),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.enter): () {
                          if (!kMobile && _canSend) _sendMessage();
                        },
                        const SingleActivator(LogicalKeyboardKey.enter,
                            meta: true): () {
                          if (_canSend) _sendMessage();
                        },
                        const SingleActivator(LogicalKeyboardKey.enter,
                            control: true): () {
                          if (_canSend) _sendMessage();
                        },
                      },
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 8,
                        cursorColor: AppColors.fg1,
                        onSubmitted: (_) => _sendMessage(),
                        style: sans(16, height: 1.45, color: AppColors.fg1),
                        decoration: InputDecoration(
                          isCollapsed: true,
                          contentPadding:
                              const EdgeInsets.fromLTRB(2, 4, 8, 14),
                          border: InputBorder.none,
                          hintText: 'Ask anything',
                          hintStyle:
                              sans(16, height: 1.45, color: AppColors.fg4),
                        ),
                      ),
                    ),
                    Row(children: [
                      GestureDetector(
                        onTap: _onAttachTap,
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child:
                                AppIcon('plus', size: 18, color: AppColors.fg3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Builder(builder: (chipCtx) {
                        return GestureDetector(
                          onTap: () => _switchModel(chipCtx),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(R.sm),
                            ),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              AppIcon('sparkles',
                                  size: 11, color: AppColors.fg2),
                              const SizedBox(width: 4),
                              Text(_modelLabel ?? 'Auto',
                                  style: sans(11.5, color: AppColors.fg2)),
                              const SizedBox(width: 1),
                              AppIcon('chevron-down',
                                  size: 10, color: AppColors.fg4),
                            ]),
                          ),
                        );
                      }),
                      const Spacer(),
                      if (kCanRecord)
                        GestureDetector(
                          onTap: _onMicTap,
                          child: SizedBox(
                            width: 48,
                            height: 44,
                            child: Center(
                              child: AppIcon(_isRecording ? 'mic-off' : 'mic',
                                  size: 22,
                                  color: _isRecording
                                      ? AppColors.danger
                                      : AppColors.fg3),
                            ),
                          ),
                        ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _input,
                        builder: (_, __, ___) {
                          final queue = running && _canSend;
                          final stop = running && !queue;
                          return _SendBtn(
                              enabled: stop || _canSend,
                              running: stop,
                              onTap: stop
                                  ? () => _send({'kind': 'interrupt'})
                                  : (_canSend ? _sendMessage : null));
                        },
                      ),
                    ]),
                  ]),
            ),
          ]),
    );
  }

  // Composer attachment row: image thumbnails + file chips, each with its own ✕.
  Widget _attachmentBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _attachments.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => _attachmentTile(_attachments[i]),
        ),
      ),
    );
  }

  Widget _attachmentTile(_Attachment a) {
    final thumb = a.isImage && a.localPath != null;
    final isAudio = a.isAudio;
    final body = thumb
        ? ClipRRect(
            borderRadius: BorderRadius.circular(R.sm),
            child: Image.file(File(a.localPath!),
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                cacheWidth: 72,
                cacheHeight: 72),
          )
        : Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: isAudio ? AppColors.accentBg : AppColors.surface2,
              borderRadius: BorderRadius.circular(R.sm),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(isAudio ? 'mic' : (a.isImage ? 'image' : 'file'),
                  size: 12, color: isAudio ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(10,
                        color: isAudio ? AppColors.accent : AppColors.fg2)),
              ),
            ]),
          );
    return Stack(children: [
      body,
      if (a.uploading)
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(R.sm)),
            alignment: Alignment.center,
            child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.fg2)),
          ),
        ),
      Positioned(
        top: 3,
        right: 3,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _attachments.remove(a)),
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: const BoxDecoration(
                color: Colors.black87, shape: BoxShape.circle),
            child: AppIcon('x', size: 11, color: AppColors.fg1),
          ),
        ),
      ),
    ]);
  }

  // ---- event → widget (pairs tool_call with its tool_result) ----
  List<Widget> _transcript(List<Map<String, dynamic>> events) {
    _userMarks.clear();
    final seen = <String>{};
    final out = <Widget>[];
    Map<String, dynamic>? pending;
    final run = <Widget>[]; // consecutive dense tool rows
    String? runStartKey;
    String? pendingKey;
    final eventOccurrences = <String, int>{};
    final laneRowsShown = <String>{}; // spawn cards already emitted (by id)

    String eventKey(Map<String, dynamic> event) {
      // Event indexes shift when the daemon compacts history. Use the event
      // payload plus its occurrence among identical events so Flutter keeps a
      // message's State/SelectionArea attached to that message after compaction.
      final fingerprint = jsonEncode(event);
      final occurrence = eventOccurrences.update(
        fingerprint,
        (count) => count + 1,
        ifAbsent: () => 0,
      );
      return 'transcript-event-${fingerprint.hashCode}-$occurrence';
    }

    void addEvent(String key, Widget child) {
      out.add(KeyedSubtree(
        key: ValueKey(key),
        child: child,
      ));
    }

    void addToolRow(Widget child, String key) {
      runStartKey ??= key;
      run.add(child);
    }

    void flushPending(String fallbackKey) {
      final p = pending;
      if (p != null) {
        final name = _s(p['tool_name']);
        addToolRow(DenseToolRow(tool: name, args: p['arguments']),
            pendingKey ?? fallbackKey);
        pending = null;
        pendingKey = null;
      }
    }

    void endTools(String fallbackKey) {
      flushPending(fallbackKey);
      if (run.isEmpty) return;
      final start = runStartKey ?? fallbackKey;
      final running = run.any((w) => w is DenseToolRow && w.pending);
      out.add(KeyedSubtree(
        key: ValueKey('transcript-tools-$start'),
        child: ToolRun(List.of(run), running: running),
      ));
      run.clear();
      runStartKey = null;
    }

    LaneInfo? liveLane(String id) {
      for (final l in _state?.lanes ?? const <LaneInfo>[]) {
        if (l.id == id) return l;
      }
      return null;
    }

    for (final e in events) {
      final key = eventKey(e);
      final k = e['kind'] as String? ?? '';
      switch (k) {
        case 'tool_call':
          flushPending(key);
          // Meta-tools render via their own events (note → note, ask_user →
          // user_question, delegate_task → lane_spawned). Skip their generic tool
          // lines so they don't double up.
          if (_isMetaTool(_s(e['tool_name']))) break;
          pending = e;
          pendingKey = key;
        case 'tool_result':
          {
            final p = pending;
            if (p != null) {
              addToolRow(
                  DenseToolRow(
                      tool: _s(p['tool_name']),
                      args: p['arguments'],
                      result: e['result']),
                  pendingKey ?? key);
              pending = null;
              pendingKey = null;
            } else {
              final name = _s(e['tool_name']);
              if (_isMetaTool(name)) break;
              addToolRow(DenseToolRow(tool: name, result: e['result']), key);
            }
          }
        case 'user_input':
        case 'steer':
          endTools(key);
          final markKey = _userMarkKeys.putIfAbsent(key, GlobalKey.new);
          final preview = hideAttachmentMarkers(_s(e['text'])).trim();
          if (preview.isNotEmpty) {
            _userMarks.add(_UserMark(key: markKey, preview: preview));
            seen.add(key);
          }
          addEvent(
              key,
              KeyedSubtree(
                key: markKey,
                child: Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 20),
                    child: Bubble(mine: true, text: _s(e['text']))),
              ));
        case 'assistant_text':
          endTools(key);
          addEvent(
              key,
              Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Bubble(mine: false, text: _s(e['text']))));
        case 'model_error':
          endTools(key);
          addEvent(key, NoteLine(_s(e['message']), error: true));
        case 'invalid_tool_call':
          endTools(key);
          addEvent(
              key,
              NoteLine('invalid ${_s(e['tool_name'])}: ${_s(e['error'])}',
                  error: true));
        case 'note':
          endTools(key);
          final entry = _s(e['entry']);
          addEvent(key, _NoteLine(entry));
        case 'system_decision':
          endTools(key);
          // Don't render "interrupted" decisions — just noise in the chat.
          if (_s(e['step']) == 'interrupted') break;
          addEvent(key,
              SystemRow(step: _s(e['step']), reasoning: _s(e['reasoning'])));
        case 'file_presented':
          endTools(key);
          addEvent(key, _presentedFileCard(_s(e['path']), _s(e['caption'])));
        case 'lane_spawned':
          endTools(key);
          final id = _s(e['id']);
          final title = _s(e['title']);
          // Dedup by ID AND title — the same lane can be spawned with
          // different IDs on reconnect (resume), producing visual duplicates.
          if (!laneRowsShown.contains(id) &&
              !laneRowsShown.contains('t:$title')) {
            laneRowsShown.add(id);
            laneRowsShown.add('t:$title');
            addEvent(
                key,
                LaneNotice(
                  title: title,
                  live: () => liveLane(id),
                  onOpen: _showLanes,
                ));
          }
        case 'lane_completed':
          endTools(key);
          final id = _s(e['id']);
          // The spawn card already tracks this lane live — only render a card
          // here if the spawn row is gone (e.g. compacted away).
          if (!laneRowsShown.contains(id)) {
            addEvent(
                key,
                LaneNotice(
                  title: _s(e['title']),
                  live: () => liveLane(id),
                  onOpen: _showLanes,
                  summary: _s(e['summary']),
                ));
          }
        case 'user_question':
          endTools(key);
          final qd = e['questions'];
          final qs = (qd is Map ? qd['questions'] : null) as List?;
          final txt = (qs != null && qs.isNotEmpty && qs.first is Map)
              ? _s((qs.first as Map)['text'])
              : '';
          if (txt.isNotEmpty) {
            addEvent(
                key,
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppIcon('corner-down-right',
                            size: 15, color: AppColors.run),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(txt,
                                style: sans(13.5,
                                    height: 1.45,
                                    weight: FontWeight.w500,
                                    color: AppColors.fg2))),
                      ]),
                ));
          }
        case 'approval_request':
          break; // shown by the approval bar
        default:
          break;
      }
    }
    endTools('transcript-end');
    _userMarkKeys.removeWhere((k, _) => !seen.contains(k));
    return out;
  }

  /// A file the agent handed over (`present_file`): open in the editor, or
  /// download to the device.
  Widget _presentedFileCard(String path, String caption) {
    final name = path.split('/').last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: AppColors.accentBg,
                borderRadius: BorderRadius.circular(R.sm)),
            child: AppIcon('file', size: 16, color: AppColors.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (widget.onOpenFileTab != null) {
                  widget.onOpenFileTab!(path, name);
                } else {
                  presentScreen(
                    context,
                    builder: (_, close) => EditorScreen(
                        client: widget.client,
                        path: path,
                        name: name,
                        onClose: close),
                  );
                }
              },
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(13, color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Text(caption.isNotEmpty ? caption : path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11.5, color: AppColors.fg3)),
                  ]),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            onPressed: () async {
              try {
                toast(context, 'Downloading $name…');
                final msg = await downloadRemoteFileWithCancel(
                    context, widget.client,
                    path: path, name: name);
                if (msg != null && mounted) toast(context, msg);
              } catch (e) {
                if (mounted) toast(context, '$e', danger: true);
              }
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              foregroundColor: AppColors.accentFg,
              backgroundColor: AppColors.accent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(R.sm)),
            ),
            child: Text('Download',
                style: sans(12,
                    weight: FontWeight.w600, color: AppColors.accentFg)),
          ),
        ]),
      ),
    );
  }

  String _s(dynamic v) => v?.toString() ?? '';

  // Meta-tools have dedicated event rendering, so their generic tool lines are skipped.
  bool _isMetaTool(String n) =>
      n == 'note' ||
      n == 'ask_user' ||
      n == 'delegate_task' ||
      n == 'complete_goal' ||
      n == 'monitor' ||
      n == 'present_file';

  Future<void> _switchModel([BuildContext? anchor]) async {
    ServerConfig cfg;
    try {
      cfg = await widget.client.getConfig();
    } catch (e) {
      _toast('$e');
      return;
    }
    if (!mounted) return;
    if (cfg.profiles.isEmpty) {
      _toast('No model profiles');
      return;
    }
    final box = (anchor ?? context).findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    RelativeRect position;
    if (box != null && overlay != null) {
      final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
      final menuW = math.min(280.0, overlay.size.width - 24);
      final left = origin.dx.clamp(12.0, overlay.size.width - menuW - 12);
      // Sit just above the chip. A tiny top inset (16) used to pin the menu
      // to the status bar on phones.
      position = RelativeRect.fromLTRB(
        left,
        origin.dy - 8,
        overlay.size.width - left - menuW,
        overlay.size.height - origin.dy + 8,
      );
    } else {
      position = const RelativeRect.fromLTRB(16, 80, 16, 80);
    }
    final current = _modelLabel;
    final picked = await showMenu<String>(
      context: context,
      position: position,
      color: AppColors.surface1,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.md),
        side: BorderSide(color: AppColors.border2),
      ),
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      items: [
        for (final p in cfg.profiles)
          PopupMenuItem<String>(
            value: p.name,
            height: 48,
            child: Row(children: [
              AppIcon('sparkles',
                  size: 14,
                  color: p.name == current ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13,
                            weight: FontWeight.w500,
                            color: p.name == current
                                ? AppColors.accent
                                : AppColors.fg1)),
                    Text('${p.provider} · ${p.model}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11, color: AppColors.fg4)),
                  ],
                ),
              ),
            ]),
          ),
      ],
    );
    if (picked == null || picked == current) return;
    try {
      await widget.client.setSessionModel(widget.sessionId, picked);
      _toast('Switched to $picked');
      if (mounted) {
        _currentProfile = picked;
        _loadModel();
        _connect();
      }
    } catch (e) {
      _toast('$e');
    }
  }

  void _showExec() {
    final ctrl = TextEditingController();
    String output = '';
    bool busy = false;
    showAppSheet(context, title: 'Run command', child: StatefulBuilder(
      builder: (ctx, setSheet) {
        Future<void> run() async {
          final cmd = ctrl.text.trim();
          if (cmd.isEmpty || busy) return;
          setSheet(() {
            busy = true;
            output = '';
          });
          try {
            final r = await widget.client.exec(widget.sessionId, cmd);
            final so = (r['stdout'] ?? '').toString();
            final se = (r['stderr'] ?? '').toString();
            output = [
              if (so.isNotEmpty) so,
              if (se.isNotEmpty) se,
              'exit ${r['exit_code']}',
            ].join('\n');
          } catch (e) {
            output = '$e';
          }
          if (!ctx.mounted) return; // sheet dismissed mid-command
          setSheet(() => busy = false);
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Runs in the session workspace.',
              style: sans(11.5, color: AppColors.fg3)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: AppField(
                    controller: ctrl,
                    mono: true,
                    icon: 'terminal',
                    hint: 'ls -la',
                    onSubmitted: (_) => run())),
            const SizedBox(width: 8),
            Btn(busy ? '\u2026' : 'Run', disabled: busy, onTap: run),
          ]),
          if (output.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.md)),
              child: SelectableText(output,
                  style: mono(11.5, height: 1.5, color: AppColors.fg1)),
            ),
          ],
        ]);
      },
      // Free the controller when the sheet closes (it leaked one per open).
    )).whenComplete(ctrl.dispose);
  }

  void _showLanes() {
    if ((_state?.lanes ?? const <LaneInfo>[]).isEmpty) return;
    presentScreen(
      context,
      builder: (_, close) => LanesScreen(
        liveLanes: () => _state?.lanes ?? const <LaneInfo>[],
        onClose: close,
      ),
    );
  }

  Widget _usageBody(HarnessState s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (s.contextWindow > 0) ...[
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Context window',
              style: sans(12.5, weight: FontWeight.w500, color: AppColors.fg2)),
          Text('${fmtSi(s.lastPromptTokens)} / ${fmtSi(s.contextWindow)}',
              style: mono(11.5, color: AppColors.fg3)),
        ]),
        const SizedBox(height: 9),
        Progress(pct: s.lastPromptTokens / s.contextWindow * 100, height: 9),
        const SizedBox(height: 7),
        Text('${(s.lastPromptTokens / s.contextWindow * 100).round()}% used',
            style: mono(11, color: AppColors.accent)),
        const SizedBox(height: 18),
      ],
      const SectionLabel('Tokens'),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child: StatTile(label: '↑ Input', value: fmtSi(s.promptTokens))),
        const SizedBox(width: 8),
        Expanded(
            child:
                StatTile(label: '↓ Output', value: fmtSi(s.completionTokens))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
            child:
                StatTile(label: '↻ Cached', value: fmtSi(s.cacheReadTokens))),
        const SizedBox(width: 8),
        Expanded(
            child: StatTile(
                label: 'Total', value: fmtSi(s.totalTokens), accent: true)),
      ]),
      if (s.ratePrimary != null || s.rateSecondary != null) ...[
        const SizedBox(height: 18),
        const SectionLabel('Rate limits · remaining'),
        const SizedBox(height: 8),
        for (final w in [s.ratePrimary, s.rateSecondary])
          if (w != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Builder(builder: (_) {
                final rem = w.leftPercent;
                final color = rem < 20
                    ? AppColors.danger
                    : rem < 50
                        ? AppColors.run
                        : AppColors.ok;
                final reset = rateResetLabel(w.resetsAt);
                return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(rateWindowLabel(w.windowMinutes),
                                style: sans(12, color: AppColors.fg2)),
                            Text('${rem.round()}% left',
                                style: mono(11, color: color)),
                          ]),
                      const SizedBox(height: 6),
                      Progress(pct: rem, color: color, height: 6),
                      if (reset != null) ...[
                        const SizedBox(height: 5),
                        Text(reset, style: mono(10.5, color: AppColors.fg4)),
                      ],
                    ]);
              }),
            ),
      ],
    ]);
  }

  void _showUsage() {
    final s = _state;
    if (s == null) return;
    final body = _usageBody(s);
    if (kMobile) {
      showAppSheet(context, title: 'Usage', child: body);
    } else {
      presentScreen(context,
          builder: (_, close) =>
              _SessionActionPanel(title: 'Usage', onClose: close, child: body));
    }
  }

  void _showCheckpoints() {
    final s = _state;
    if (s == null) return;
    final cps = s.checkpoints.reversed.toList();
    final content = Column(children: [
      if (cps.isEmpty)
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text('No checkpoints yet.',
                style: sans(12.5, color: AppColors.fg3))),
      ...cps.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              padding: const EdgeInsets.all(13),
              onTap: () => _confirmRewind(c),
              child: Row(children: [
                Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(9)),
                    child: AppIcon('history', size: 17, color: AppColors.fg3)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.label.isEmpty ? c.id : c.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13,
                                weight: FontWeight.w500,
                                height: 1.2,
                                color: AppColors.fg1)),
                        const SizedBox(height: 3),
                        Text(formatCheckpointDate(c.createdAt),
                            style: mono(11, color: AppColors.fg3)),
                      ]),
                ),
                IconBtn('git-branch',
                    size: 32,
                    iconSize: 16,
                    tooltip: 'Fork from here',
                    onTap: () => _confirmFork(c)),
              ]),
            ),
          )),
    ]);
    if (kMobile) {
      showAppSheet(context, title: 'Checkpoints', child: content);
    } else {
      presentScreen(context,
          builder: (_, close) => _SessionActionPanel(
              title: 'Checkpoints', onClose: close, child: content));
    }
  }

  Future<void> _confirmRewind(Checkpoint c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.card),
            side: BorderSide(color: AppColors.border2)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Restore workspace?',
                    style: sans(15,
                        weight: FontWeight.w600, color: AppColors.fg1)),
                const SizedBox(height: 6),
                Text(
                    'This rolls the workspace back to “${c.label.isEmpty ? c.id : c.label}”. Changes after this point are discarded.',
                    style: sans(12.5, height: 1.5, color: AppColors.fg3)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: Btn('Cancel',
                          variant: BtnVariant.ghost,
                          onTap: () => Navigator.pop(context, false))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Btn('Restore',
                          onTap: () => Navigator.pop(context, true))),
                ]),
              ]),
        ),
      ),
    );
    if (ok != true) return;
    if (mounted) Navigator.pop(context); // close the sheet
    try {
      await widget.client.rewind(widget.sessionId, c.id);
      _toast('Workspace restored');
    } catch (e) {
      _toast('$e');
    }
  }

  // Kept temporarily for compatibility with any in-flight route callbacks; the
  // user-facing fork entry now lives only inside Checkpoints.
  // ignore: unused_element
  void _showForkPoints() {
    final s = _state;
    if (s == null) return;
    final cps = s.checkpoints.reversed.toList();
    showAppSheet(context,
        title: 'Fork conversation',
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              'Creates a new session with history up to the point you pick. '
              'This chat is left unchanged. Workspace files are shared.',
              style: sans(12.5, height: 1.45, color: AppColors.fg3),
            ),
          ),
          if (cps.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                      'No checkpoints yet — you can still fork the full history.',
                      style: sans(12.5, color: AppColors.fg3)),
                  const SizedBox(height: 12),
                  Btn('Fork full history', onTap: () => _confirmFork(null)),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                padding: const EdgeInsets.all(13),
                onTap: () => _confirmFork(null),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: AppIcon('git-branch',
                        size: 17, color: AppColors.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Full history',
                            style: sans(13,
                                weight: FontWeight.w500, color: AppColors.fg1)),
                        const SizedBox(height: 3),
                        Text('Branch everything so far',
                            style: mono(11, color: AppColors.fg3)),
                      ],
                    ),
                  ),
                  AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                ]),
              ),
            ),
            ...cps.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: const EdgeInsets.all(13),
                    onTap: () => _confirmFork(c),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.surface2,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: AppIcon('git-branch',
                            size: 17, color: AppColors.fg3),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.label.isEmpty ? c.id : c.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13,
                                    weight: FontWeight.w500,
                                    height: 1.2,
                                    color: AppColors.fg1)),
                            const SizedBox(height: 3),
                            Text(formatCheckpointDate(c.createdAt),
                                style: mono(11, color: AppColors.fg3)),
                          ],
                        ),
                      ),
                      AppIcon('chevron-right', size: 16, color: AppColors.fg4),
                    ]),
                  ),
                )),
          ],
        ]));
  }

  Future<void> _confirmFork(Checkpoint? c) async {
    final label =
        c == null ? 'full history' : (c.label.isEmpty ? c.id : c.label);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(R.card),
            side: BorderSide(color: AppColors.border2)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fork conversation?',
                    style: sans(15,
                        weight: FontWeight.w600, color: AppColors.fg1)),
                const SizedBox(height: 6),
                Text(
                    'Opens a new session branched at “$label”. '
                    'This chat stays as-is. Files on disk are shared.',
                    style: sans(12.5, height: 1.5, color: AppColors.fg3)),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: Btn('Cancel',
                          variant: BtnVariant.ghost,
                          onTap: () => Navigator.pop(context, false))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Btn('Fork',
                          onTap: () => Navigator.pop(context, true))),
                ]),
              ]),
        ),
      ),
    );
    if (ok != true) return;
    if (mounted) Navigator.pop(context); // close the sheet
    try {
      final result = await widget.client.forkSession(
        widget.sessionId,
        checkpoint: c?.id,
        eventIndex: c == null && (_state?.events.isNotEmpty ?? false)
            ? _state!.events.length - 1
            : null,
      );
      final id = result['id']?.toString() ?? '';
      final title = result['title']?.toString() ?? 'fork';
      if (id.isEmpty) {
        _toast('Fork created but no session id returned');
        return;
      }
      final open = widget.onOpenSession;
      if (open != null) {
        open(id, title, widget.profile);
      } else {
        _toast('Forked → $title');
      }
    } catch (e) {
      _toast('$e');
    }
  }
}

class _StatMeta extends StatelessWidget {
  final String icon, label, tone;
  const _StatMeta(
      {required this.icon, required this.label, this.tone = 'default'});
  @override
  Widget build(BuildContext context) {
    final c = tone == 'accent'
        ? AppColors.accent
        : tone == 'run'
            ? AppColors.run
            : AppColors.fg2;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppIcon(icon, size: 14, color: tone == 'default' ? AppColors.fg4 : c),
      const SizedBox(width: 6),
      Text(label, style: mono(12.5, color: c)),
    ]);
  }
}

class _CompactingStatus extends StatefulWidget {
  final String? detail;
  const _CompactingStatus({this.detail});
  @override
  State<_CompactingStatus> createState() => _CompactingStatusState();
}

class _CompactingStatusState extends State<_CompactingStatus> {
  late final DateTime _started = DateTime.now();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final d = DateTime.now().difference(_started);
    final total = d.inMilliseconds / 1000;
    final m = total ~/ 60;
    final s = total - m * 60;
    return m > 0
        ? '${m}m ${s.toStringAsFixed(1)}s'
        : '${s.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final detail = widget.detail?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
                width: 16,
                child: Center(child: BrailleSpinner(color: AppColors.accent))),
            const SizedBox(width: 8),
            Flexible(
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: 'Compacting',
                    style: sans(13,
                        weight: FontWeight.w600, color: AppColors.accent)),
                TextSpan(
                    text: ' $_elapsed',
                    style: sans(13,
                        color: AppColors.accent.withValues(alpha: 0.72))),
              ])),
            ),
          ]),
          if (detail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 6),
              child: Text(detail,
                  style: sans(13, height: 1.4, color: AppColors.fg3)),
            ),
        ],
      ),
    );
  }
}

class _ChurningStatus extends StatefulWidget {
  final String thinking;
  const _ChurningStatus({this.thinking = ''});
  @override
  State<_ChurningStatus> createState() => _ChurningStatusState();
}

class _ChurningStatusState extends State<_ChurningStatus> {
  static const _verbs = [
    'Churning',
    'Pondering',
    'Rummaging',
    'Noodling',
    'Tinkering',
    'Scheming',
    'Weaving',
    'Sifting',
    'Puttering',
    'Brewing',
    'Fiddling',
    'Mulling',
    'Foraging',
    'Juggling',
    'Unraveling',
    'Conjuring',
    'Whittling',
    'Riffling',
    'Plotting',
    'Kneading',
  ];

  late final DateTime _started = DateTime.now();
  late final math.Random _rng = math.Random();
  Timer? _tick;
  Timer? _swap;
  late String _verb = _verbs[_rng.nextInt(_verbs.length)];
  bool _open = true;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) setState(() {});
    });
    _scheduleSwap();
  }

  void _scheduleSwap() {
    final wait = Duration(milliseconds: 2800 + _rng.nextInt(4200));
    _swap?.cancel();
    _swap = Timer(wait, () {
      if (!mounted) return;
      String next;
      do {
        next = _verbs[_rng.nextInt(_verbs.length)];
      } while (next == _verb && _verbs.length > 1);
      setState(() => _verb = next);
      _scheduleSwap();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _swap?.cancel();
    super.dispose();
  }

  String get _elapsed {
    final d = DateTime.now().difference(_started);
    final total = d.inMilliseconds / 1000;
    final m = total ~/ 60;
    final s = total - m * 60;
    return m > 0
        ? '${m}m ${s.toStringAsFixed(1)}s'
        : '${s.toStringAsFixed(1)}s';
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final thought = widget.thinking.trim();
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                thought.isEmpty ? null : () => setState(() => _open = !_open),
            child: Row(
              children: [
                SizedBox(
                    width: 16,
                    child:
                        Center(child: BrailleSpinner(color: AppColors.accent))),
                const SizedBox(width: 8),
                Flexible(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: _verb,
                        style: sans(13,
                            weight: FontWeight.w600, color: AppColors.accent)),
                    TextSpan(
                        text: ' $_elapsed',
                        style: sans(13,
                            color: AppColors.accent.withValues(alpha: 0.72))),
                  ])),
                ),
                if (thought.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  AppIcon(_open ? 'chevron-down' : 'chevron-right',
                      size: 13, color: AppColors.accent.withValues(alpha: 0.7)),
                ],
              ],
            ),
          ),
          if (_open && thought.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 8),
              child: ThinkingMarkdown(data: thought),
            ),
        ],
      ),
    );
  }
}

/// A message sent mid-run, shown right-aligned + dimmed with a cancel (✕) until
/// the daemon applies it (then it's replaced by the real bubble).
/// A run of consecutive tool calls, grouped under a left rule. The "N steps"
/// header toggles the group collapsed/expanded.

class _QueuedBubble extends StatelessWidget {
  final String text;
  final int audio, images, files;
  final VoidCallback onCancel;
  final VoidCallback? onSteer;
  const _QueuedBubble({
    required this.text,
    required this.audio,
    required this.images,
    required this.files,
    required this.onCancel,
    this.onSteer,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 5,
              height: 5,
              decoration:
                  BoxDecoration(color: AppColors.fg4, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          Text('QUEUED', style: sans(10, color: AppColors.fg4, spacing: 0.8)),
          const Spacer(),
          if (onSteer != null)
            GestureDetector(
              onTap: onSteer,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accentBg,
                  borderRadius: BorderRadius.circular(R.sm),
                ),
                child: Text('Steer', style: sans(11, color: AppColors.accent)),
              ),
            ),
          if (onSteer != null) const SizedBox(width: 6),
          IconBtn('x',
              size: 26, iconSize: 14, tooltip: 'Cancel', onTap: onCancel),
        ]),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 3),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(text,
                style: sans(13.5, height: 1.5, color: AppColors.fg3)),
          ),
        ],
        if (images + files + audio > 0) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: AttachmentPill(audio: audio, images: images, files: files),
          ),
        ],
      ]),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final GoalInfo goal;
  final VoidCallback onCancel;
  const _GoalCard({required this.goal, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final paused = goal.paused;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: paused ? AppColors.surface3 : AppColors.accentBg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: AppIcon('goal',
              size: 15, color: paused ? AppColors.fg3 : AppColors.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(paused ? 'Goal paused' : 'Working toward goal',
                  style: sans(12.5,
                      weight: FontWeight.w600, color: AppColors.fg1)),
              const SizedBox(width: 7),
              Text('${goal.autonomousTurns} turns',
                  style: mono(10, color: AppColors.fg4)),
            ]),
            if (goal.text.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(goal.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11.5, height: 1.35, color: AppColors.fg3)),
            ],
          ]),
        ),
        IconBtn('x',
            size: 30, iconSize: 14, tooltip: 'Cancel goal', onTap: onCancel),
      ]),
    );
  }
}

class _ApprovalBar extends StatefulWidget {
  final void Function(Map<String, dynamic>) onSend;
  final bool showApproveAll; // only when >1 tool is pending this batch
  const _ApprovalBar({required this.onSend, this.showApproveAll = false});
  @override
  State<_ApprovalBar> createState() => _ApprovalBarState();
}

class _ApprovalBarState extends State<_ApprovalBar> {
  // Disable after the first tap — the bar stays on screen until the next frame
  // flips status, so an impatient double-tap fired the decision twice.
  bool _sent = false;

  void _decide(Map<String, dynamic> m) {
    if (_sent) return;
    setState(() => _sent = true);
    widget.onSend(m);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_sent ? 'Decision sending…' : 'Tool Approval',
            style: sans(14, weight: FontWeight.w600, color: AppColors.fg1)),
        const SizedBox(height: 4),
        Text(
            widget.showApproveAll
                ? 'Several actions are waiting'
                : 'Approve this action to continue',
            style: sans(12, color: AppColors.fg3)),
        const SizedBox(height: 12),
        Opacity(
          opacity: _sent ? 0.5 : 1,
          child: Row(children: [
            Expanded(
                child: Btn('Approve',
                    small: true,
                    icon: 'check',
                    onTap: _sent ? null : () => _decide({'kind': 'approve'}))),
            const SizedBox(width: 8),
            if (widget.showApproveAll) ...[
              Expanded(
                  child: Btn('Approve all',
                      small: true,
                      variant: BtnVariant.secondary,
                      icon: 'check-check',
                      onTap: _sent
                          ? null
                          : () => _decide({'kind': 'approve_all'}))),
              const SizedBox(width: 8),
            ],
            Btn('Deny',
                small: true,
                variant: BtnVariant.ghost,
                onTap: _sent ? null : () => _decide({'kind': 'deny'})),
          ]),
        ),
      ]),
    );
  }
}

class _NoteLine extends StatefulWidget {
  final String text;
  const _NoteLine(this.text);
  @override
  State<_NoteLine> createState() => _NoteLineState();
}

class _NoteLineState extends State<_NoteLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    final long = text.split('\n').length > 3 || text.length > 220;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: long ? () => setState(() => _open = !_open) : null,
          borderRadius: BorderRadius.circular(R.md),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MarkdownBody(
                  data: text,
                  selectable: false,
                  styleSheet: markdownStyle(context),
                  builders: {'pre': PreBlockBuilder()},
                ),
                if (long) ...[
                  const SizedBox(height: 4),
                  Text(
                    _open ? 'collapse' : 'expand',
                    style: mono(10.5, color: AppColors.fg4),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders an `ask_user` pending question (status waiting_for_input) and sends the
/// answer back as a LoopInput::Answer. Handles free_text / single_choice / yes_no /
/// confirm answer kinds.
class _QuestionBar extends StatefulWidget {
  final Map<String, dynamic> question; // {questions:[...], context}
  final void Function(Map<String, dynamic>) onSend;
  const _QuestionBar({required this.question, required this.onSend});
  @override
  State<_QuestionBar> createState() => _QuestionBarState();
}

class _QuestionBarState extends State<_QuestionBar> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _choice = {};
  final Set<String> _skipped = {};
  final Set<String> _freeText = {};
  // One answer per ask — the bar lingers until the next frame flips status,
  // so an eager second tap double-submitted the answer.
  bool _sent = false;
  int _step = 0;

  Map<String, dynamic>? get _currentQuestion => _questions.isEmpty
      ? null
      : _questions[_step.clamp(0, _questions.length - 1)];

  List<Map<String, dynamic>> get _questions =>
      ((widget.question['questions'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  String _kind(Map<String, dynamic> q) =>
      (q['answer_kind'] is Map ? q['answer_kind']['kind'] : null)?.toString() ??
      'free_text';

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _ready {
    final q = _currentQuestion;
    if (q == null) return false;
    final id = q['id'].toString();
    if (_skipped.contains(id)) return true;
    final textMode = _kind(q) == 'free_text' || _freeText.contains(id);
    return textMode
        ? (_text[id]?.text.trim().isNotEmpty ?? false)
        : (_choice[id]?.isNotEmpty ?? false);
  }

  String _answerFor(Map<String, dynamic> q) {
    final id = q['id'].toString();
    if (_skipped.contains(id)) return 'user skipped the question';
    final textMode = _kind(q) == 'free_text' || _freeText.contains(id);
    return textMode ? (_text[id]?.text.trim() ?? '') : (_choice[id] ?? '');
  }

  void _submit() {
    if (_questions.isEmpty || !_ready || _sent) return;
    if (_step < _questions.length - 1) {
      setState(() => _step++);
      return;
    }
    setState(() => _sent = true);
    final parts =
        _questions.map((q) => '${q['text']}\n→ ${_answerFor(q)}').toList();
    widget.onSend({'kind': 'answer', 'value': parts.join('\n\n')});
  }

  void _skip() {
    final q = _currentQuestion;
    if (q == null || _sent) return;
    _skipped.add(q['id'].toString());
    _freeText.remove(q['id'].toString());
    _choice.remove(q['id'].toString());
    if (_step < _questions.length - 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _toggleFreeText() {
    final q = _currentQuestion;
    if (q == null || _sent) return;
    final id = q['id'].toString();
    setState(() {
      _skipped.remove(id);
      _freeText.contains(id) ? _freeText.remove(id) : _freeText.add(id);
    });
  }

  Widget _freeTextToggle(String id) => InkWell(
        onTap: _sent ? null : _toggleFreeText,
        borderRadius: BorderRadius.circular(R.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(_freeText.contains(id) ? 'check' : 'edit',
                size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(
                _freeText.contains(id)
                    ? 'Writing a response'
                    : 'Write your own answer',
                style: sans(12, color: AppColors.accent)),
          ]),
        ),
      );

  Widget _skipButton() => TextButton(
        onPressed: _sent ? null : _skip,
        style: TextButton.styleFrom(
            foregroundColor: AppColors.fg3,
            padding: const EdgeInsets.symmetric(horizontal: 8)),
        child: Text('Skip', style: sans(12, color: AppColors.fg3)),
      );

  Widget _chip(String label, bool sel, VoidCallback onTap) => Material(
        color: sel ? AppColors.accentBg : AppColors.surface2,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(99),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(label,
                style: sans(13,
                    weight: FontWeight.w600,
                    color: sel ? AppColors.accent : AppColors.fg2)),
          ),
        ),
      );

  // Full-width selectable row for single-choice options (labels are sentences).
  // Selected reads as a quiet accent tint + border + check, not a solid orange slab.
  Widget _choiceRow(String label, bool sel, VoidCallback onTap) => Material(
        color: sel ? AppColors.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      style: sans(14,
                          height: 1.4,
                          weight: FontWeight.w500,
                          color: sel ? AppColors.fg1 : AppColors.fg2))),
              if (sel) ...[
                const SizedBox(width: 10),
                AppIcon('check', size: 16, color: AppColors.accent)
              ],
            ]),
          ),
        ),
      );

  List<Widget> _inputFor(Map<String, dynamic> q) {
    final id = q['id'].toString();
    final k = _kind(q);
    final opts =
        k == 'confirm' ? const ['Confirm', 'Cancel'] : const ['Yes', 'No'];
    final vals =
        k == 'confirm' ? const ['confirm', 'cancel'] : const ['yes', 'no'];
    final choices =
        ((q['answer_kind']?['choices'] as List?) ?? const []).map((e) {
      if (e is Map) {
        final label = '${e['label'] ?? ''}'.trim();
        final value = '${e['value'] ?? ''}'.trim();
        final v = value.isEmpty ? label : value;
        return (value: v, label: label.isEmpty ? v : label);
      }
      final s = '$e';
      return (value: s, label: s);
    }).toList();
    _text.putIfAbsent(id, () => TextEditingController());
    return [
      if (k == 'single_choice')
        ...choices.map((c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _choiceRow(
                  c.label,
                  _choice[id] == c.value,
                  () => setState(() {
                        _choice[id] = c.value;
                        _freeText.remove(id);
                      })),
            )),
      if (k == 'yes_no' || k == 'confirm')
        Wrap(spacing: 8, children: [
          for (var i = 0; i < opts.length; i++)
            _chip(opts[i], _choice[id] == vals[i],
                () => setState(() => _choice[id] = vals[i])),
        ]),
      if (k == 'single_choice' || k == 'yes_no' || k == 'confirm')
        _freeTextToggle(id),
      if (k == 'free_text' || _freeText.contains(id))
        AppField(
            controller: _text[id]!,
            hint: 'Write your answer',
            maxLines: 4,
            onSubmitted: (_) => _submit()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ctx = widget.question['context']?.toString();
    final total = _questions.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_sent ? 'Sending…' : 'Question',
            style: sans(14, weight: FontWeight.w600, color: AppColors.fg1)),
        if (total > 1)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('${_step + 1} of $total',
                style: sans(12, color: AppColors.fg4)),
          ),
        if (ctx != null && ctx.isNotEmpty && ctx != 'null') ...[
          const SizedBox(height: 12),
          Text(ctx, style: sans(13, height: 1.45, color: AppColors.fg2)),
        ],
        ...() {
          final q = _currentQuestion;
          if (q == null) return <Widget>[];
          return <Widget>[
            const SizedBox(height: 12),
            Text(q['text']?.toString() ?? '',
                style: sans(14, height: 1.45, color: AppColors.fg1)),
            const SizedBox(height: 10),
            ..._inputFor(q),
          ];
        }(),
        const SizedBox(height: 12),
        Row(children: [
          _skipButton(),
          if (_step > 0) ...[
            const SizedBox(width: 4),
            Btn('Back',
                small: true,
                variant: BtnVariant.ghost,
                onTap: _sent ? null : () => setState(() => _step--)),
          ],
          const Spacer(),
          Btn(_sent ? 'Sending…' : (_step < total - 1 ? 'Continue' : 'Submit'),
              small: true,
              disabled: !_ready || _sent,
              onTap: (_ready && !_sent) ? _submit : null),
        ]),
      ]),
    );
  }
}

/// Paints the sampled microphone amplitude as a compact live waveform.
class _WaveformPainter extends CustomPainter {
  final List<double> samples;
  const _WaveformPainter(this.samples);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.accent
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (samples.isEmpty) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint..color = AppColors.fg4,
      );
      return;
    }
    final waveformWidth = math.min(size.width, samples.length * 4.0);
    for (var i = 0; i < samples.length; i++) {
      final amplitude = samples[i].clamp(0.04, 1.0).toDouble();
      final half =
          (size.height * 0.45 * amplitude).clamp(2.0, size.height * 0.45);
      final x = i * 4.0 + 2.0;
      if (x > waveformWidth) break;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.samples != samples;
}

/// A pending composer attachment (image, file, or audio) being uploaded.
class _Attachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath; // local source (for image thumbnails)
  String? remotePath; // daemon path once uploaded
  bool uploading = true;
  _Attachment(
      {required this.name,
      required this.isImage,
      required this.isAudio,
      this.localPath});
}

/// Inline circular send button for the composer.
class _SendBtn extends StatelessWidget {
  final bool enabled;
  final bool running;
  final VoidCallback? onTap;
  const _SendBtn({required this.enabled, this.running = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.fg1 : AppColors.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
              child: AppIcon(running ? 'stop' : 'arrow-up',
                  size: running ? 15 : 16,
                  color: enabled ? AppColors.bg : AppColors.fg4)),
        ),
      ),
    );
  }
}

class _UserMark {
  final GlobalKey key;
  final String preview;
  const _UserMark({required this.key, required this.preview});
}

class _MessageJumpRail extends StatefulWidget {
  final List<_UserMark> marks;
  final void Function(GlobalKey key) onJump;
  const _MessageJumpRail({required this.marks, required this.onJump});

  @override
  State<_MessageJumpRail> createState() => _MessageJumpRailState();
}

class _MessageJumpRailState extends State<_MessageJumpRail> {
  int? _hover;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final marks = widget.marks;
    if (marks.length < 2) return const SizedBox.shrink();
    return SizedBox(
      width: 18,
      child: MouseRegion(
        onExit: (_) => setState(() => _hover = null),
        child: LayoutBuilder(builder: (context, c) {
          final n = marks.length;
          const tickH = 2.5;
          const step = 11.0;
          final cluster = (n - 1) * step + tickH;
          final start = ((c.maxHeight - cluster) / 2).clamp(0.0, c.maxHeight);
          return Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < n; i++)
              Positioned(
                top: start + i * step,
                right: 0,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hover = i),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onJump(marks[i].key),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 3, horizontal: 4),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: _hover == i ? 14 : 8,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: _hover == i
                              ? AppColors.accent
                              : AppColors.fg4.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_hover != null)
              Positioned(
                top: (start + _hover! * step - 10)
                    .clamp(0.0, math.max(0.0, c.maxHeight - 36)),
                right: 22,
                child: IgnorePointer(
                  child: Material(
                    color: AppColors.surface1,
                    elevation: 6,
                    borderRadius: BorderRadius.circular(R.sm),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        child: Text(
                          marks[_hover!].preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, height: 1.35, color: AppColors.fg1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}
