import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../api.dart';
import '../desktop_pick.dart';
import '../models.dart';
import '../notifications.dart';
import '../platform.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../tool_sheet.dart';
import '../tool_views.dart';
import '../transcript.dart';
import '../term.dart';
import '../panel.dart';
import '../share_inbound.dart';
import '../widgets.dart';
import '../media_views.dart';
import 'agent_messaging.dart';
import 'package:xterm/xterm.dart';
import 'editor.dart';
import 'files.dart';
import 'processes.dart';
import 'git.dart';
import 'lanes.dart';
import 'recurring.dart';
import 'session_panels.dart';
import 'session_coordination_cards.dart';
import 'mission_control/mission_control_state.dart'
    show
        isDedicatedMcSession,
        parseMissionEnvelope,
        parseBoardMessage,
        parseDirectMessage,
        parseCoordinationReply,
        parseAssignmentEnvelope;
import 'mission_control/task_board_screen.dart';

part 'session_socket.dart';
part 'session_appbar.dart';
part 'session_recorder.dart';
part 'session_composer.dart';
part 'session_transcript.dart';
part 'session_term.dart';
part 'session_approval.dart';

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

  /// Shows a tool batch in the desktop shell's side pane.
  final void Function(ValueListenable<ToolBatch> batch)? onOpenToolBatch;

  /// Open a forked conversation (new tab / replace). Shell provides this so
  /// fork can jump straight into the branch.
  final void Function(String id, String title, String? profile)? onOpenSession;

  /// Publishes live usage data to the macOS shell status rail.
  final void Function(HarnessState? state, bool running)? onMacStatus;

  /// Gives the macOS shell access to session actions after this state mounts,
  /// allowing the shell chrome to replace the duplicate in-session title bar.
  final void Function(VoidCallback stop,
          void Function(String action, [String? extra]) performAction)?
      onMacControls;

  /// Publishes this session's terminals to the shell as a render host. Called
  /// only when the terminal set or focus changes, never on output.
  ///
  /// The shell owns WHERE a terminal renders; the session owns its lifecycle
  /// (it is the only side holding the pty). See [TerminalHost].
  final void Function(TerminalHost host, bool open)? onTerminalHost;

  /// Desktop: open Scheduled as a right-pane READOUT instead of the drawer.
  ///
  /// The shell owns the panes, so a session cannot open one itself. Scheduled
  /// is a property of the conversation it governs, so it belongs beside the
  /// chat — the same treatment Tasks, Lanes and Checkpoints get. Null on mobile,
  /// where there are no panes and the drawer is the right shape for a phone.
  final VoidCallback? onOpenScheduled;

  /// Desktop PageView keeps every tab mounted. Only the visible session should
  /// accept file drops — otherwise every keep-alive DropTarget ingests the same
  /// file and the composer chips leak across tabs.
  final bool acceptDrops;

  /// Android share / "Ask Snippet" payload to attach + send once the session
  /// is connected. Consumed by the first visible session that matches.
  final SharedInbound? inboundShare;

  /// Called once the share has been consumed so the host can drop it —
  /// otherwise remounting this session (mobile tab switch) re-sends it.
  final VoidCallback? onShareConsumed;

  /// Title changed (agent rename or user rename) — shell uses this to keep
  /// tabs, the session list, and the status bar in sync.
  final void Function(String title)? onTitle;

  /// True only while this mobile session is the visible phone surface. The shell
  /// keeps its session mounted behind Chats for the return animation, but an
  /// inactive session must never intercept Android back from the Chats home.
  final bool mobileActive;

  const SessionScreen(
      {super.key,
      required this.client,
      required this.sessionId,
      required this.title,
      this.profile,
      this.embedded = false,
      this.onMenu,
      this.onOpenFileTab,
      this.onOpenToolBatch,
      this.onOpenSession,
      this.onMacStatus,
      this.onMacControls,
      this.onTerminalHost,
      this.onOpenScheduled,
      this.acceptDrops = true,
      this.inboundShare,
      this.onShareConsumed,
      this.mobileActive = true,
      this.onTitle});
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
                      style: TS.sectionTitle())),
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

String _registeredOpenKey = '';
const int _maxAttachments = 5;

int _userEchoCount(List<Map<String, dynamic>> events) => events
    .where((e) => e['kind'] == 'user_input' || e['kind'] == 'steer')
    .length;

String _normEchoText(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

String? _inboxAgentId(String sessionId) {
  const prefix = 'inbox-';
  if (!sessionId.startsWith(prefix)) {
    return null;
  }
  final id = sessionId.substring(prefix.length);
  return id.isEmpty ? null : id;
}

class _SessionScreenState extends State<SessionScreen>
    with WidgetsBindingObserver {
  void _setState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final List<String> _outbox = [];
  Timer? _bannerTimer;
  bool _confirmingRecording = false;
  SharedInbound? _consumedShare;
  late final String _openKey;
  HarnessState? _state;
  String _liveText = '';
  String _liveThinking = '';
  bool _liveTextVisible = false;
  final ValueNotifier<_LiveFrame> _liveFrame =
      ValueNotifier(const _LiveFrame());
  String? _connError;
  bool _termOpen = false;
  bool _draggingFiles = false;
  final List<_LiveTerm> _terms = [];
  int _termFocus = 0;
  int _termSeq = 0;

  /// Width of the desktop terminal split pane. Height is not tracked: the pane
  /// is full-height beside the chat.
  double _termWidth = 420;
  int _modelLoadGeneration = 0;
  String? _modelLabel;
  String? _currentProfile;

  /// When set, the composer sends a DIRECT MESSAGE to this agent instead of a
  /// turn in the current session. Null means ordinary chat input.
  String? _recipientAgentId;
  String? _recipientAgentName;

  /// Agent ids pinned to THIS session from the directory, so the composer shows
  /// who can be reached here without re-reading the whole directory.
  final Set<String> _sessionAgentIds = {};

  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();

  /// Owns the mobile end-drawer so the actions panel can close it directly.
  /// `Navigator.pop` does NOT close a drawer, so the closer must be this key.
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _composerCardKey = GlobalKey();
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
  Uint8List? _recordingBytes;
  Duration _recordingElapsed = Duration.zero;
  final ValueNotifier<int> _recorderTick = ValueNotifier(0);
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  final List<double> _waveform = [];
  // Queue frames already sent but not yet in `state.queuedInputs` (the daemon
  // parks them until the in-flight step ends). Shown immediately so the
  // composer doesn't sit empty for a whole tool call.
  final List<QueuedInput> _optimisticQueued = [];
  // Queue IDs hidden after a local cancel/steer until the daemon confirms them.
  final Set<String> _queueHidden = {};
  int? _hoveredQueuedIndex;
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
    Iterable<String> attachmentPaths(String text) => RegExp(
          r'\[attached (?:image|file) —[^\]]*exact path(?: to view it)?: ([^\]]+)\]',
        )
            .allMatches(text)
            .map((m) => m.group(1)?.trim() ?? '')
            .where((path) => path.isNotEmpty);
    final echoed = <String>{};
    final echoedAttachments = <String>{};
    for (final e in events) {
      final kind = e['kind'];
      if (kind != 'user_input' && kind != 'steer') continue;
      final t = e['text'];
      if (t is String && t.trim().isNotEmpty) {
        echoed.add(_normEchoText(t));
        for (final path in attachmentPaths(t)) {
          echoedAttachments.add(path);
        }
      }
    }
    if (echoed.isEmpty) return;
    bool attachmentEchoed(String pending) {
      final paths = attachmentPaths(pending).toList();
      return paths.isNotEmpty && paths.every(echoedAttachments.contains);
    }

    var i = 0;
    while (i < _pending.length) {
      if (echoed.contains(_normEchoText(_pending[i])) ||
          attachmentEchoed(_pending[i])) {
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
  // insertion this large can't be typing. It leaves the field and becomes a
  // pasted-text card, sent inline; only a paste too big for the agent's context
  // is uploaded as a file instead.
  static const _pasteCardChars = 600;
  static const _pasteCardLines = 8;
  static const _pasteFileChars = 30000;
  String _lastInput = '';
  bool _restoringInput = false;
  int _pasteN = 0;

  void _interceptBigPaste() {
    if (_closed || _restoringInput) return;
    final prev = _lastInput;
    final now = _input.text;
    if (now.length - prev.length < _pasteCardChars) {
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
    if (inserted.length < _pasteCardChars && lines < _pasteCardLines) {
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
    if (inserted.length <= _pasteFileChars) {
      setState(() => _attachments.add(_Attachment.pasted(inserted)));
      return;
    }
    final name = 'paste-${++_pasteN}.txt';
    _ingest([
      (
        name: name,
        localPath: null,
        readBytes: () async => Uint8List.fromList(utf8.encode(inserted))
      )
    ]);
    _toast('Long paste attached as a file ($lines lines)');
  }

  // Pending attachments (images + files, up to 5): each uploads to the daemon
  // and is referenced in the next message. Images → view_image, files → bash.
  final List<_Attachment> _attachments = [];
  int _attachmentGeneration = 0;
  bool get _anyUploading => _attachments.any((a) => a.uploading);
  final Map<String, bool> _toolRunOpen = {};
  final Map<String, ValueNotifier<ToolBatch>> _toolBatches = {};
  final Set<String> _openToolRows = {};
  bool _transcriptDirty = true;
  List<Widget>? _transcriptCache;

  /// Coordination events concerning this session's agent, shown inline in the
  /// conversation: a direct message arriving for it, or work dispatched out of
  /// it. Kept separate from `_state.events` because these are DEVICE events —
  /// they belong to the agent and the coordination plane, not to this session's
  /// transcript, and folding them in would put them in the model's history.
  final List<Map<String, dynamic>> _agentEvents = [];
  StreamSubscription<dynamic>? _agentEventsSub;
  int _transcriptStart = 0;
  bool _loadingOlderTranscript = false;
  final Set<int> _requestedFullEvents = {};

  void _requestFullEvent(int index) {
    if (!_requestedFullEvents.add(index)) return;
    scheduleMicrotask(() {
      if (_closed || !mounted) return;
      _send({'kind': 'event', 'index': index});
    });
  }

  Future<void> _loadOlderTranscript() async {
    if (_state == null || _transcriptStart == 0 || _loadingOlderTranscript) {
      return;
    }
    setState(() => _loadingOlderTranscript = true);
    _send({
      'kind': 'history',
      'before': _transcriptStart,
    });
  }

  // Stream frame throttle: store the latest pending stream payload and flush
  // at most every 50ms to avoid rebuilding the full widget tree on every token.
  String _pendingLiveText = '';
  String _pendingLiveThinking = '';
  bool _pendingLiveTextVisible = false;
  Timer? _streamFlushTimer;
  Future<void>? _decodeQueue;
  // Auto-reconnect: backoff timer + attempt counter; _closed stops retries on leave.
  Timer? _reconnectTimer;
  Timer? _connectionWatchdog;
  int _reconnectAttempt = 0;
  int _lastAttachRevision = 0;
  bool _closed = false;
  // A message can silently die on a socket that looks alive (dropped network, no
  // onError/onDone) — it sits in _pending, shown as "sending", forever. Guard:
  // (1) a fresh connection resends anything still unacked against the authoritative
  // snapshot; (2) a watchdog forces a resync if _pending doesn't clear in time.
  bool _freshConn = false;

  /// Hidden / backgrounded: no attach socket. Background watching is the
  /// per-instance `/events` notify path, not a live transcript attach.
  bool _parked = false;
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

  @override
  void initState() {
    super.initState();
    _title = _isMissionControl ? 'Mission Control' : widget.title;
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
      if (!mounted) return;
      _playbackPosition = position;
      _recorderTick.value++;
    });
    _durationSub = _audioPlayer.onDurationChanged.listen((duration) {
      if (!mounted) return;
      _playbackDuration = duration;
      _recorderTick.value++;
    });
    if (!widget.acceptDrops && _state != null) _parked = true;
    _startSession();
    _startAgentEvents();
    _loadModel();
    modelsRevision.addListener(_loadModel);
    unawaited(widget.client.getConfig());
    _openKey = '${widget.client.baseUrl}|${widget.sessionId}';
    _registeredOpenKey = _openKey;
    reportOpenSession(_openKey);
    if (widget.inboundShare != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumeInboundShare(widget.inboundShare!);
      });
    }
  }

  bool get _isMissionControl => isDedicatedMcSession(widget.sessionId);

  /// Watch the device event stream for coordination activity about THIS session:
  /// work dispatched into it, and — when this session is an agent's inbox —
  /// messages arriving for that agent.
  ///
  /// These are DEVICE events, not transcript events, so they are kept out of
  /// `_state.events`: folding them in would put coordination chatter into the
  /// model's history, which is not what happened in the conversation.
  void _startAgentEvents() {
    _agentEventsSub?.cancel();
    _agentEventsSub = widget.client.events().stream.listen((raw) {
      if (!mounted || _closed) return;
      final Map<String, dynamic> frame;
      try {
        final decoded = jsonDecode(raw as String);
        if (decoded is! Map) return;
        frame = decoded.cast<String, dynamic>();
      } catch (_) {
        return;
      }
      final entry = _agentEventFor(frame);
      if (entry == null) return;
      setState(() {
        _agentEvents.add(entry);
        _transcriptDirty = true;
      });
    }, onError: (_) {});
  }

  /// Map one coordination frame to an inline row, or null when it does not
  /// concern this session.
  Map<String, dynamic>? _agentEventFor(Map<String, dynamic> frame) {
    final kind = frame['kind']?.toString() ?? '';
    if (kind == 'dispatch') {
      // Dispatches name their target session, so this is an exact match.
      if (frame['session']?.toString() != widget.sessionId) return null;
      return {
        'event': 'dispatch',
        'agent': frame['agent']?.toString() ?? '',
        'assignment': frame['assignment']?.toString() ?? '',
        'profile': frame['profile']?.toString(),
      };
    }
    if (kind == 'direct_message') {
      // A message concerns this session only when this session IS that agent's
      // inbox. The binding is in the session id, so it needs no round trip.
      final agent = _inboxAgentId(widget.sessionId);
      if (agent == null) return null;
      if (frame['to']?.toString() != 'agent:$agent') return null;
      return {
        'event': 'direct_message',
        'from': frame['from']?.toString() ?? '',
        'thread': frame['thread_id']?.toString() ?? '',
      };
    }
    return null;
  }

  /// One inline coordination row.
  Widget _agentEventRow(Map<String, dynamic> e, int index) {
    final kind = e['event']?.toString() ?? '';
    if (kind == 'dispatch') {
      final agent = e['agent']?.toString() ?? '';
      final profile = e['profile']?.toString();
      return KeyedSubtree(
        key: ValueKey('agent-dispatch-$index-${e['assignment']}'),
        child: AgentEventRow(
          icon: 'send',
          label: agent.isEmpty
              ? 'Work dispatched here'
              : 'Work dispatched to $agent',
          detail: profile == null || profile.isEmpty
              ? 'from Mission Control'
              : 'from Mission Control · profile $profile',
        ),
      );
    }
    final from = e['from']?.toString() ?? '';
    return KeyedSubtree(
      key: ValueKey('agent-message-$index-${e['thread']}'),
      child: AgentEventRow(
        icon: 'message',
        label: 'Message from ${from.isEmpty ? 'an agent' : from}',
        detail: 'Direct message — open the agent to read and reply',
        accent: true,
      ),
    );
  }

  Future<void> _startSession() async {
    if (_isMissionControl) {
      try {
        await widget.client.mcOpen().timeout(const Duration(seconds: 8));
      } catch (_) {}
      if (!mounted || _closed) return;
    }
    _connect();
  }

  @override
  void didUpdateWidget(covariant SessionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameSession = oldWidget.sessionId == widget.sessionId &&
        oldWidget.client.baseUrl == widget.client.baseUrl;
    if (_isMissionControl && _title != 'Mission Control') {
      _title = 'Mission Control';
    }
    if (sameSession && widget.acceptDrops != oldWidget.acceptDrops) {
      if (widget.acceptDrops) {
        _unpark();
      } else {
        _park();
      }
    }
    if (widget.acceptDrops && (_channel == null || _parked)) {
      _unpark();
    }
    if (!sameSession) {
      _parked = !widget.acceptDrops;
      _title = _isMissionControl ? 'Mission Control' : widget.title;
      // PageView normally keys each session, but a parent may reuse this State
      // while switching tabs. Never carry composer/upload state across sessions.
      // Invalidate completions from an upload started by the previous session.
      _attachmentGeneration++;
      if (mounted) {
        setState(() => _attachments.clear());
      } else {
        _attachments.clear();
      }
      _optimisticQueued.clear();
      _queueHidden.clear();
      _clearPendingAll();
      _input.clear();
      _lastInput = '';
      _consumedShare = null;
      _state = null;
      _openKey = '${widget.client.baseUrl}|${widget.sessionId}';
      _registeredOpenKey = _openKey;
      reportOpenSession(_openKey);
      unawaited(_startSession());
    }
    if (widget.inboundShare != null &&
        widget.inboundShare != oldWidget.inboundShare) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _consumeInboundShare(widget.inboundShare!);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      // Drop the live attach while backgrounded. The per-instance `/events`
      // watcher is what notifies — not a transcript socket per open chat.
      _park();
      return;
    }
    if (state == AppLifecycleState.resumed && !_closed) {
      if (widget.acceptDrops) {
        _unpark();
        _loadModel();
      }
      _registeredOpenKey = _openKey;
      reportOpenSession(_openKey);
    }
  }

  Future<void> _loadModel() async {
    final generation = ++_modelLoadGeneration;
    try {
      final cfg = await widget.client.getConfig();
      if (!mounted || generation != _modelLoadGeneration) return;

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

      InferenceProfile? p;
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

      if (!mounted || generation != _modelLoadGeneration) return;
      if (mounted) {
        setState(() => _modelLabel = p?.name);
      }
    } catch (_) {}
  }

  void _publishTitle(String title) {
    if (_isMissionControl) return;
    if (title == _title) {
      widget.onTitle?.call(title);
      return;
    }
    _title = title;
    widget.onTitle?.call(title);
  }

  void _park() {
    if (_parked) return;
    _parked = true;
    // Android can restore the activity with the previous EditableText still
    // focused after a bottom-swipe app switch. Release the focus before the
    // route is resized again so the IME cannot remain visually stuck on resume.
    _inputFocus.unfocus();
    SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    _reconnectTimer?.cancel();
    _bannerTimer?.cancel();
    _connectionWatchdog?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _unpark() {
    if (!_parked) return;
    _parked = false;
    if (_closed) return;
    _reconnectAttempt = 0;
    _connect();
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
    // User scrolling only updates pinning; history pages are not fetched from
    // scroll notifications because changing the list extent during a gesture
    // causes the viewport and thumb to jump.
    // Repaint only on the pinned/unpinned EDGE — it toggles the floating
    // "jump to latest" button over the transcript.
    if (was != _stickToBottom && mounted) setState(() {});
    return false;
  }

  void _scheduleBottom({bool settle = false, bool smooth = false}) {
    if (!_scroll.hasClients) return;
    if (smooth) {
      _scroll.animateTo(0, duration: Motion.base, curve: Motion.enter);
    } else if (_scroll.offset != 0) {
      _scroll.jumpTo(0);
    }
  }

  // Send now, or queue for the reconnect flush — never silently drop.
  // For user messages (tracked in _pending), do NOT also add to _outbox:
  // _freshConn resend handles recovery, so adding to both would double-send.
  @override
  void deactivate() {
    // Close IME while the TextField is still mounted. Parent dispose() runs
    // after the child EditableText is already gone, which is too late to stop
    // a pending Android selection snapshot from hitting a disposed controller.
    _inputFocus.unfocus();
    super.deactivate();
  }

  @override
  void dispose() {
    _closed = true;
    _agentEventsSub?.cancel();
    modelsRevision.removeListener(_loadModel);
    _input.removeListener(_interceptBigPaste);
    for (final batch in _toolBatches.values) {
      batch.dispose();
    }
    _inputFocus.unfocus();
    _reconnectTimer?.cancel();
    _bannerTimer?.cancel();
    _connectionWatchdog?.cancel();
    _ackTimer?.cancel();
    _decisionTimer?.cancel();
    _streamFlushTimer?.cancel();
    _liveFrame.dispose();
    _recorderTick.dispose();
    _sub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // Only clear the suppression key if this screen still owns it — on a session
    // switch the NEW screen registers before this dispose runs, and clobbering
    // its key made notifications fire for the session being viewed.
    if (_registeredOpenKey == _openKey) {
      _registeredOpenKey = '';
      reportOpenSession('');
    }
    // Held messages already live on the daemon. Flush only the reconnect outbox.
    final ch = _channel;
    if (_outbox.isNotEmpty && ch != null) {
      for (final p in _outbox) {
        ch.sink.add(p);
      }
      _outbox.clear();
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
    final allEvents = s?.events ?? const [];
    final events = allEvents;
    if (_transcriptDirty || _transcriptCache == null) {
      _transcriptCache = _transcript(events);
      _transcriptDirty = false;
    }
    final items = _transcriptCache!;
    // The mobile end-drawer is the ONLY host for the action list on a phone, so
    // the scaffold needs a key (Navigator.pop cannot close a drawer) and the
    // drawer itself. Desktop keeps the pull-up sheet.
    final useDrawer = kMobile && widget.onMenu != null;
    final scaffold = Scaffold(
      key: useDrawer ? _scaffoldKey : null,
      endDrawer: useDrawer ? _actionsDrawer(s) : null,
      // Tap-only: the default edge drag competes with transcript gestures.
      endDrawerEnableOpenDragGesture: false,
      backgroundColor: readingBg,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Stack(children: [
          Positioned.fill(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  // The bottom chrome is NON-FLEX, so Flutter lays it out at its
                  // natural height BEFORE the transcript's Expanded claims what
                  // is left. A question or approval card carrying a long
                  // agent-authored body could therefore exceed the pane outright
                  // and push its own actions off the bottom edge — which is why a
                  // big question was impossible to answer. Measuring the pane
                  // here is what lets the cards be capped and scroll instead.
                  child: LayoutBuilder(builder: (context, pane) {
                    final barsCap = pane.maxHeight * 0.6;
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (kMobile)
                            _mobileHeader(s)
                          else if (!kMacOS)
                            _desktopBar(s, running),
                          // Desktop keeps the detailed chip strip.
                          if (!kMobile && !kMacOS) _statusStrip(s, running),
                          if (_connError != null) _disconnectedBanner(),
                          Expanded(
                            child: Stack(children: [
                              s == null
                                  ? Center(child: DelayedSpinner(size: 22))
                                  : NotificationListener<ScrollNotification>(
                                      onNotification: _onScroll,
                                      child: Builder(builder: (context) {
                                        final timeline = <Widget>[
                                          if (items.isEmpty && !running)
                                            const EmptyState(
                                                icon: 'terminal',
                                                title: 'Session ready',
                                                body:
                                                    'Send a task to get started.'),
                                          if (_transcriptStart > 0 &&
                                              items.isNotEmpty)
                                            Padding(
                                              key: const ValueKey(
                                                  'load-earlier'),
                                              padding: const EdgeInsets.only(
                                                  bottom: S.s12),
                                              child: Center(
                                                child: _loadingOlderTranscript
                                                    ? const SizedBox(
                                                        height: 28,
                                                        child: Center(
                                                            child: Spinner(
                                                                size: 14)))
                                                    : TextAction(
                                                        'Show earlier messages',
                                                        icon: 'history',
                                                        onTap:
                                                            _loadOlderTranscript),
                                              ),
                                            ),
                                          ...items,
                                          // Optimistic bubbles for messages sent but not yet echoed.
                                          for (var pi = 0;
                                              pi < _pending.length;
                                              pi++)
                                            Opacity(
                                                key: ValueKey(
                                                    'pending-$pi-${_pending[pi].hashCode}'),
                                                opacity: 0.5,
                                                child: Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            bottom: 12),
                                                    child: Bubble(
                                                        mine: true,
                                                        text: _pending[pi],
                                                        selectable: false,
                                                        client: widget.client))),
                                          _LiveStreamRow(
                                            key: const ValueKey(
                                                'live-stream-row'),
                                            frame: _liveFrame,
                                            running: running,
                                            compacting: s.compacting,
                                            startedAt: s.turnStartedAt,
                                            hasVisibleAction:
                                                _turnHasVisibleAction(events),
                                            compactionDetail:
                                                _latestCompactionDetail(events),
                                          ),
                                        ];
                                        return ScrollConfiguration(
                                          behavior:
                                              ScrollConfiguration.of(context)
                                                  .copyWith(scrollbars: false),
                                          child: ListView.builder(
                                            controller: _scroll,
                                            reverse: true,
                                            scrollCacheExtent:
                                                ScrollCacheExtent.pixels(400),
                                            padding: EdgeInsets.fromLTRB(
                                                kMobile ? M.gutter : 20,
                                                16,
                                                kMobile ? M.gutter : 20,
                                                24),
                                            itemCount: timeline.length,
                                            itemBuilder: (context, index) {
                                              final child = timeline[
                                                  timeline.length - 1 - index];
                                              return KeyedSubtree(
                                                key: child.key ??
                                                    ValueKey('timeline-$index'),
                                                child: _centerWide(
                                                  RepaintBoundary(child: child),
                                                ),
                                              );
                                            },
                                          ),
                                        );
                                      })),
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
                                        _scheduleBottom(
                                            settle: true, smooth: true);
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
                            _centerWide(ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: barsCap),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    kMobile
                                        ? M.gutter
                                        : (widget.embedded ? 0 : 20),
                                    6,
                                    kMobile
                                        ? M.gutter
                                        : (widget.embedded ? 0 : 20),
                                    0),
                                child: ApprovalBar(
                                    events: events,
                                    onSend: _sendDecision,
                                    showApproveAll:
                                        _pendingApprovalTotal(events) > 1),
                              ),
                            )),
                          if (waiting && s?.pendingQuestion != null)
                            _centerWide(ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: barsCap),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(
                                    kMobile
                                        ? M.gutter
                                        : (widget.embedded ? 0 : 20),
                                    6,
                                    kMobile
                                        ? M.gutter
                                        : (widget.embedded ? 0 : 20),
                                    0),
                                child: QuestionBar(
                                    question: s!.pendingQuestion!,
                                    onSend: _sendDecision),
                              ),
                            )),
                          if (!(waiting && s?.pendingQuestion != null))
                            _centerWide(_inputBar(running)),
                        ]);
                  }),
                ),
                // Desktop, standalone: the terminal is a second pane BESIDE the
                // chat. When embedded, the SHELL owns this pane instead — a
                // terminal must survive switching sessions, which a session-local
                // pane cannot do, so the session only renders it when it is the
                // outermost desktop surface.
                if (_termOpen &&
                    _terms.isNotEmpty &&
                    !kMobile &&
                    !widget.embedded)
                  _desktopTermPane(),
              ],
            ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: Motion.fast,
              reverseDuration: Motion.quick,
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.025, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: kMobile && _termOpen && _terms.isNotEmpty
                  ? KeyedSubtree(
                      key: const ValueKey('mobile-terminal'),
                      child: _mobileTermTab(),
                    )
                  : const SizedBox(key: ValueKey('mobile-chat')),
            ),
          ),
        ]),
      ),
    );
    final guardedScaffold = DaemonScope(
      client: widget.client,
      onOpenFile: widget.onOpenFileTab,
      onOpenTools: widget.onOpenToolBatch,
      child: scaffold,
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
            child: guardedScaffold,
          )
        : guardedScaffold;
  }
}
