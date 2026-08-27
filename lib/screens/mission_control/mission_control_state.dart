/// Mission Control agent surface.
///
/// The board talks to a single daemon-managed "Mission Control" session. The
/// user is having a freeform conversation with that session; the session
/// itself decides whether to dispatch work, ask a question, or just talk back.
/// All of the data shown on screen — tasks, notifications, recent activity —
/// is a projection of that one session plus the durable Mission Control store.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../api.dart';
import '../../models.dart';

/// One row in the activity feed. The feed is a chat-style log of everything
/// that has happened between the user and the MC session, plus the events
/// emitted by the tasks the session has dispatched.
@immutable
sealed class FeedItem {
  const FeedItem({required this.timestamp, required this.id});
  final DateTime timestamp;
  final String id;
}

class UserMessageItem extends FeedItem {
  const UserMessageItem({
    required super.id,
    required super.timestamp,
    required this.text,
    this.failed = false,
  });
  final String text;
  final bool failed;
}

class AgentTextItem extends FeedItem {
  const AgentTextItem({
    required super.id,
    required super.timestamp,
    required this.text,
  });
  final String text;
}

class TaskEventItem extends FeedItem {
  const TaskEventItem({
    required super.id,
    required super.timestamp,
    required this.task,
    required this.kind,
  });
  final MissionControlTask task;

  /// `queued` | `dispatched` | `working` | `done` | `blocked` | `failed`
  final String kind;
}

class QuestionItem extends FeedItem {
  const QuestionItem({
    required super.id,
    required super.timestamp,
    required this.question,
    required this.taskId,
  });
  final String question;
  final String? taskId;
}

class SystemNoteItem extends FeedItem {
  const SystemNoteItem({
    required super.id,
    required super.timestamp,
    required this.text,
  });
  final String text;
}

/// Derived state of the MC agent. Drives the live header copy and pulse color.
enum AgentState { idle, working, asking, error }

@immutable
class AgentSnapshot {
  const AgentSnapshot({
    required this.state,
    required this.detail,
    this.activeCount = 0,
    this.blockedCount = 0,
    this.unreadNotifications = 0,
  });
  final AgentState state;
  final String detail;
  final int activeCount;
  final int blockedCount;
  final int unreadNotifications;

  AgentSnapshot copy() => AgentSnapshot(
        state: state,
        detail: detail,
        activeCount: activeCount,
        blockedCount: blockedCount,
        unreadNotifications: unreadNotifications,
      );
}

bool isDedicatedMcSession(String? id) {
  if (id == null || id.isEmpty) return false;
  final normalized = id.replaceAll(r'\', '/').trim();
  return normalized == 'mission-control' ||
      normalized == 'mission-control/session.json';
}

/// True for the dedicated MC home — by session id or the exact tab title
/// leftover from when MC was listed as a regular chat.
bool isMissionControlTab({String? sessionId, String? title}) {
  if (isDedicatedMcSession(sessionId)) return true;
  return title?.trim() == 'Mission Control';
}

bool isMissionControlListRow(SessionInfo session) {
  return isMissionControlTab(sessionId: session.id, title: session.title);
}

/// `/attach` may deliver text as a String or as UTF-8 bytes.
String decodeAttachPayload(dynamic raw) {
  return switch (raw) {
    final String s => s,
    final Uint8List b => utf8.decode(b, allowMalformed: true),
    final List<int> b => utf8.decode(b, allowMalformed: true),
    _ => '',
  };
}

class MissionEnvelope {
  const MissionEnvelope({
    required this.isReport,
    required this.taskId,
    required this.title,
    required this.status,
    required this.summary,
  });
  final bool isReport;
  final String taskId;
  final String title;
  final String status;
  final String summary;

  String get eventKind {
    if (!isReport) return 'queued';
    return switch (status) {
      'done' || 'completed' => 'done',
      'failed' || 'cancelled' => 'failed',
      'blocked' => 'blocked',
      'in_progress' || 'working' => 'working',
      _ => 'done',
    };
  }
}

MissionEnvelope? parseMissionEnvelope(String text) {
  final t = text.trim();
  final isReport = t.contains('[mission_task_report]');
  final isTask = t.contains('[mission_control_task]');
  if (!isReport && !isTask) return null;
  String field(String name) {
    final match =
        RegExp(r'^' + name + r':\s*(.*)$', multiLine: true).firstMatch(t);
    return match?.group(1)?.trim() ?? '';
  }

  return MissionEnvelope(
    isReport: isReport,
    taskId: field('task_id'),
    title: field('title'),
    status: isReport ? field('status') : 'pending',
    summary: isReport ? field('summary') : field('scope'),
  );
}

/// Project harness events into the Mission Control chat feed.
List<FeedItem> feedItemsFromEvents(List<Map<String, dynamic>> events) {
  final out = <FeedItem>[];
  final now = DateTime.now();
  for (var i = 0; i < events.length; i++) {
    final e = events[i];
    final kind = e['kind'] as String? ?? '';
    switch (kind) {
      case 'user_input':
      case 'steer':
        final text = (e['text'] ?? '').toString().trim();
        if (text.isEmpty) break;
        final envelope = parseMissionEnvelope(text);
        if (envelope != null) {
          out.add(TaskEventItem(
            id: 'h-t-$i',
            timestamp: now,
            task: MissionControlTask.fromJson({
              'id': envelope.taskId,
              'title': envelope.title,
              'description': envelope.summary,
              'status': envelope.isReport ? envelope.status : 'pending',
            }),
            kind: envelope.eventKind,
          ));
          break;
        }
        out.add(UserMessageItem(id: 'h-u-$i', timestamp: now, text: text));
      case 'assistant_text':
        final text = (e['text'] ?? '').toString().trim();
        if (text.isEmpty) break;
        out.add(AgentTextItem(id: 'h-a-$i', timestamp: now, text: text));
      case 'user_question':
        final q = missionControlQuestionText(e);
        if (q.isEmpty) break;
        out.add(QuestionItem(
          id: 'h-q-$i',
          timestamp: now,
          question: q,
          taskId: e['task_id'] as String?,
        ));
      case 'model_error':
        final msg = (e['message'] ?? '').toString().trim();
        if (msg.isEmpty) break;
        out.add(SystemNoteItem(id: 'h-e-$i', timestamp: now, text: msg));
      default:
        break;
    }
  }
  return out;
}

String missionControlQuestionText(Map<String, dynamic> e) {
  final questions = e['questions'];
  if (questions is List && questions.isNotEmpty) {
    final first = questions.first;
    if (first is Map) {
      return (first['prompt'] ?? first['question'] ?? first['text'] ?? '')
          .toString()
          .trim();
    }
    return first.toString().trim();
  }
  return (e['text'] ?? e['question'] ?? '').toString().trim();
}

/// Shared state for the Mission Control screen. Owns polling, the WebSocket
/// connection to the MC session, and the activity feed. Mobile and desktop
/// layouts both consume this — they only differ in chrome.
class MissionControlState extends ChangeNotifier with WidgetsBindingObserver {
  MissionControlState({
    required this.client,
    this.mcSessionId,
    Duration pollInterval = const Duration(seconds: 20),
  }) : _pollInterval = pollInterval;

  final DaemonClient client;
  String? mcSessionId;
  final Duration _pollInterval;

  MissionControlOverview? overview;
  List<MissionControlTask> tasks = const [];
  List<ManagedSession> sessions = const [];

  final List<FeedItem> _feed = [];
  List<FeedItem> get feed => List.unmodifiable(_feed);

  String? fatalError;
  String? staleError;
  bool loading = true;
  bool sending = false;
  int _feedGeneration = 0;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  Timer? _hydrateTimer;
  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  String? _pendingUserNonce;
  DateTime? _pendingUserSentAt;
  String? _pendingUserText;
  HarnessState? _harness;
  bool _foreground = true;
  bool _closed = false;

  AgentSnapshot agent = const AgentSnapshot(
    state: AgentState.idle,
    detail: '',
  );

  /// Read-only views.
  List<MissionControlTask> get activeTasks =>
      tasks.where((task) => task.isActive).toList();
  List<MissionControlTask> get unresolvedBlocked =>
      tasks.where((task) => task.status == 'blocked').toList();
  int get unresolvedNotificationCount => tasks.fold<int>(
        0,
        (sum, task) =>
            sum + task.notifications.where((n) => n.delivered == false).length,
      );

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
    _startPoll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_foreground) {
        _foreground = true;
        _startPoll();
      }
      if (_ws == null) _connectWs();
      _refresh(silent: true);
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _foreground = false;
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _startPoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (!_foreground || mcSessionId == null) return;
      _refresh(silent: true);
    });
  }

  Future<void> _bootstrap() async {
    mcSessionId = 'mission-control';
    loading = true;
    fatalError = null;
    notifyListeners();
    _hydrateTimer?.cancel();
    _hydrateTimer = Timer(const Duration(seconds: 12), () {
      if (_closed || !loading) return;
      fatalError = 'Could not load the conversation.';
      loading = false;
      notifyListeners();
    });
    unawaited(_openThenAttach());
    unawaited(_refresh(silent: true));
  }

  Future<void> _openThenAttach() async {
    await _ensureOpen();
    if (_closed) return;
    _connectWs();
  }

  Future<void> _ensureOpen() async {
    try {
      final opened = await client.mcOpen().timeout(const Duration(seconds: 8));
      if (_closed || opened.isEmpty) return;
      if (opened != mcSessionId) mcSessionId = opened;
    } catch (_) {}
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _hydrateTimer?.cancel();
    _detachWs();
    super.dispose();
  }

  /// Public refresh entry point. Used by widgets that need to nudge the state
  /// (e.g. after a user action) without going through the periodic timer.
  Future<void> refresh({bool silent = true}) => _refresh(silent: silent);

  Future<void> _refresh({bool silent = false}) async {
    if (silent && !_foreground) return;
    if (!silent) fatalError = null;
    try {
      final results = await Future.wait([
        client.mcOverview(),
        client.mcTasks(archived: false),
        client.mcSessions(archived: false),
      ]).timeout(const Duration(seconds: 8));
      overview = results[0] as MissionControlOverview;
      tasks = (results[1] as List<MissionControlTask>);
      sessions = (results[2] as List<ManagedSession>);
      _reconcileFeed();
      _recomputeAgent();
      staleError = null;
    } catch (e) {
      staleError = '$e';
    } finally {
      if (!_closed) notifyListeners();
    }
  }

  void _detachWs() {
    _wsSub?.cancel();
    _wsSub = null;
    _ws?.sink.close();
    _ws = null;
  }

  void _connectWs() {
    if (_closed) return;
    final id = mcSessionId;
    if (id == null || id.isEmpty) return;
    _reconnectTimer?.cancel();
    _detachWs();
    try {
      final ch = client.attach(id);
      _ws = ch;
      _wsSub = ch.stream.listen(
        (raw) {
          if (!identical(ch, _ws)) return;
          _onWsEvent(raw);
        },
        onError: (_) {
          if (!identical(ch, _ws)) return;
          _reconnectLater();
        },
        onDone: () {
          if (!identical(ch, _ws)) return;
          _reconnectLater();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _reconnectLater();
    }
  }

  void _reconnectLater() {
    _detachWs();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 2), () {
      if (_closed) return;
      _connectWs();
    });
  }

  void _onWsEvent(dynamic raw) {
    Map<String, dynamic>? frame;
    try {
      final payload = decodeAttachPayload(raw);
      if (payload.isEmpty) return;
      final decoded = jsonDecode(payload);
      if (decoded is Map) frame = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    if (frame == null) return;
    final wire = frame['wire'] as String? ?? 'snapshot';
    if (wire == 'snapshot' || wire == 'delta') {
      _applyHarnessFrame(frame, wire == 'delta');
      return;
    }
    if (wire == 'stream') {
      if (_harness?.status == 'running') {
        agent = agent.copy().copyWith(
              state: AgentState.working,
              detail: 'Thinking…',
            );
        notifyListeners();
      }
      return;
    }
    final kind = frame['kind'] as String?;
    if (kind == 'user_message_ack') {
      final nonce = frame['nonce'] as String?;
      if (nonce != null && nonce == _pendingUserNonce) {
        _pendingUserNonce = null;
        _pendingUserSentAt = null;
        _pendingUserText = null;
        sending = false;
        notifyListeners();
      }
    }
  }

  void _applyHarnessFrame(Map<String, dynamic> frame, bool delta) {
    final cur = _harness;
    _harness = (delta && cur != null)
        ? cur.applyDelta(frame)
        : HarnessState.fromJson(frame);
    _rebuildTranscript();
    _hydrateTimer?.cancel();
    _hydrateTimer = null;
    loading = false;
    fatalError = null;
    if (_harness?.status == 'running') {
      agent = agent.copy().copyWith(
            state: AgentState.working,
            detail: 'Thinking…',
          );
    } else {
      _recomputeAgent();
    }
    notifyListeners();
  }

  @visibleForTesting
  void applyHarnessFrameForTest(Map<String, dynamic> frame,
      {bool delta = false}) {
    _applyHarnessFrame(frame, delta);
  }

  void _rebuildTranscript() {
    final events = _harness?.events ?? const <Map<String, dynamic>>[];
    final chat = feedItemsFromEvents(events);
    final tasksOnly = _feed.whereType<TaskEventItem>().toList();
    _feed
      ..clear()
      ..addAll(chat)
      ..addAll(tasksOnly);
    _reconcileFeed();
    if (_pendingUserText != null) {
      final pending = _pendingUserText!.trim();
      final echoed = chat.whereType<UserMessageItem>().any(
            (m) => m.text.trim() == pending,
          );
      if (echoed) {
        _pendingUserNonce = null;
        _pendingUserSentAt = null;
        _pendingUserText = null;
        sending = false;
      } else {
        _feed.add(UserMessageItem(
          id: 'u-${_pendingUserNonce ?? 'pending'}',
          timestamp: _pendingUserSentAt ?? DateTime.now(),
          text: _pendingUserText!,
        ));
      }
    }
  }

  /// Reconcile tasks that already exist on disk into the feed. New tasks
  /// appear as `queued` events; status transitions appear as their own kind.
  void _reconcileFeed() {
    final known = <String, _FeedTaskKey>{};
    for (final item in _feed) {
      if (item is TaskEventItem) known[item.task.id] = _FeedTaskKey(item);
    }
    for (final task in tasks) {
      final existing = known[task.id];
      if (existing == null) {
        _feed.add(TaskEventItem(
          id: 't-${task.id}-$_feedGeneration',
          timestamp: DateTime.fromMillisecondsSinceEpoch(task.createdAt * 1000),
          task: task,
          kind: _eventKindFor(task.status),
        ));
      } else {
        final newKind = _eventKindFor(task.status);
        if (existing.item.kind != newKind) {
          _feed.add(TaskEventItem(
            id: 't-${task.id}-${_feedGeneration++}-$newKind',
            timestamp: DateTime.now(),
            task: task,
            kind: newKind,
          ));
        }
      }
    }
  }

  String _eventKindFor(String status) {
    switch (status) {
      case 'pending':
        return 'queued';
      case 'in_progress':
        return 'working';
      case 'done':
      case 'completed':
        return 'done';
      case 'blocked':
        return 'blocked';
      case 'failed':
      case 'cancelled':
        return 'failed';
      default:
        return 'queued';
    }
  }

  void _recomputeAgent() {
    final blocked = unresolvedBlocked;
    final inFlight = tasks.where((t) => t.status == 'in_progress').toList();
    final unread = unresolvedNotificationCount;
    if (sending || _pendingUserNonce != null) {
      agent = agent.copy().copyWith(
            state: AgentState.working,
            detail: 'Working on your request…',
            activeCount: inFlight.length,
            blockedCount: blocked.length,
            unreadNotifications: unread,
          );
    } else if (blocked.isNotEmpty) {
      agent = agent.copy().copyWith(
            state: AgentState.asking,
            detail:
                '${blocked.length} task${blocked.length == 1 ? '' : 's'} blocked — needs your input',
            activeCount: inFlight.length,
            blockedCount: blocked.length,
            unreadNotifications: unread,
          );
    } else if (inFlight.isNotEmpty) {
      final t = inFlight.first;
      agent = agent.copy().copyWith(
            state: AgentState.working,
            detail: 'Working on “${t.title}”',
            activeCount: inFlight.length,
            blockedCount: 0,
            unreadNotifications: unread,
          );
    } else {
      agent = agent.copy().copyWith(
            state: AgentState.idle,
            detail: '',
            activeCount: 0,
            blockedCount: 0,
            unreadNotifications: unread,
          );
    }
  }

  /// Send a freeform user message to the MC session. The message appears in
  /// the feed immediately as an optimistic row; the WebSocket ack flips the
  /// state from `sending` to `live`.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || sending) return;
    if (mcSessionId == null || mcSessionId!.isEmpty) {
      fatalError = 'Mission Control is still connecting.';
      notifyListeners();
      return;
    }
    final nonce = 'mc-${DateTime.now().microsecondsSinceEpoch}';
    _pendingUserNonce = nonce;
    _pendingUserText = trimmed;
    _pendingUserSentAt = DateTime.now();
    sending = true;
    _feed.add(UserMessageItem(
      id: 'u-$nonce',
      timestamp: _pendingUserSentAt!,
      text: trimmed,
    ));
    _recomputeAgent();
    notifyListeners();
    try {
      final ch = _ws;
      if (ch == null) {
        _connectWs();
        throw StateError('Reconnecting — try again in a moment.');
      }
      ch.sink.add(jsonEncode({
        'kind': 'user_message',
        'value': trimmed,
        'nonce': nonce,
      }));
    } catch (e) {
      _pendingUserNonce = null;
      _pendingUserText = null;
      _pendingUserSentAt = null;
      sending = false;
      // Mark the optimistic row as failed.
      final idx = _feed.lastIndexWhere(
        (item) => item is UserMessageItem && item.id == 'u-$nonce',
      );
      if (idx != -1) {
        final original = _feed[idx] as UserMessageItem;
        _feed[idx] = UserMessageItem(
          id: original.id,
          timestamp: original.timestamp,
          text: original.text,
          failed: true,
        );
      }
      fatalError = 'Could not send: $e';
      notifyListeners();
    }
  }
}

class _FeedTaskKey {
  _FeedTaskKey(this.item);
  final TaskEventItem item;
}

extension on AgentSnapshot {
  AgentSnapshot copyWith({
    AgentState? state,
    String? detail,
    int? activeCount,
    int? blockedCount,
    int? unreadNotifications,
  }) =>
      AgentSnapshot(
        state: state ?? this.state,
        detail: detail ?? this.detail,
        activeCount: activeCount ?? this.activeCount,
        blockedCount: blockedCount ?? this.blockedCount,
        unreadNotifications: unreadNotifications ?? this.unreadNotifications,
      );
}
